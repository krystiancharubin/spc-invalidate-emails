global class InvalidateEmails implements SandboxPostCopy {
	global void runApexClass(SandboxContext context){
      System.debug(context.organizationId());
      System.debug(context.sandboxId());
      System.debug(context.sandboxName());

			run();
	}

	static Map<String, Map<String, Object>> objectConditionals = new Map<String, Map<String, Object>>{
		'Lead' => new Map<String, Object>{
			'isConverted' => false
		}
	};

  global static void run(){
		// Map from SObject to List of Email Fields
		Map<String, List<String>> soEmailFieldMap = findEmaiLFields();
		// Invalidate Email fields found on SObjects
		processEmailFields(soEmailFieldMap);
  }

	private static Map<String, List<String>> findEmaiLFields(){
		Map<String, List<String>> soEmailFieldMap = new Map<String, List<String>>();
		// Iterate over all SObjects
    for(SObjectType soType: Schema.getGlobalDescribe().values()){
      DescribeSObjectResult soDescribe = soType.getDescribe();
			// Skip objects we cannot query or update
      if(!soDescribe.isQueryable() || !soDescribe.isUpdateable()) continue;
      String objectTypeName = soDescribe.getName();
			// Iterate over all fields found on a given SObject
      for(SObjectField soField :soDescribe.fields.getMap().values()){
        DescribeFieldResult field = soField.getDescribe();
				// Skip non Email type fields
        if(field.getType() != Schema.DisplayType.EMAIL) continue;
				// Skip emails that cannot be filtered on
				if(!field.isFilterable()) continue;
				// Collect all Email fields found
        if(soEmailFieldMap.containsKey(objectTypeName)){
          soEmailFieldMap.get(objectTypeName).add(field.getName());
        } else {
          soEmailFieldMap.put(objectTypeName, new List<String>{field.getName()});
        }
      }
    }
		return soEmailFieldMap;
	}

	private static void processEmailFields(Map<String, List<String>> soEmailFieldMap){
		// Iterate over the SObject to Email Fields collection
		for(String objectName :soEmailFieldMap.keySet()){
			// Get any specified conditionals
			Map<String, Object> conditionals = new Map<String, Object>();
			if(objectConditionals.containsKey(objectName)) conditionals = objectConditionals.get(objectName);
			// Build a list of all fields that need to be queried
			List<String> emailFields = soEmailFieldMap.get(objectName);
      List<String> fieldList = new List<String>();
			fieldList.addAll(emaiLFields);
			fieldList.addAll(conditionals.keySet());
			// Generate a SOQL query to get records with non null emails
      String soql = getSOQL(objectName, fieldList);
      System.debug(soql);
      List<SObject> records = new List<SObject>();
      // Iterate over queried SObject records
      for(SObject record :Database.query(soql)){
				// Skip records that do not match specified conditons
				if(!checkConditions(record, conditionals)) continue;
				// Iterate over Email fields found on SObject and invalidate values
        for(String field :emailFields){
          String email = (String)record.get(field);
          if(String.isEmpty(email)) continue;
          record.put(field, email.replaceAll('\\W', '_') + '@disabled.diabled');
        }
				records.add(record);
      }
			System.debug(JSON.serializePretty(records));
      update records;
    }
	}

	private static boolean checkConditions(SObject record, Map<String, Object> conditionals){
		for(String field :conditionals.keySet()){
			Object value = record.get(field);
			Object condition = conditionals.get(field);
			if(value != condition) return false;
		}
		return true;
	}

  global static String getSOQL(String objectTypeName, List<String> fieldList){
    List<String> conditionals = new List<String>();
    for(String field :fieldList)  conditionals.add(field + ' != null');
    String soql = 'SELECT {!fieldList} FROM {!objectTypeName} WHERE {!conditionals}';
    return soql
      .replace('{!fieldList}', String.join(fieldList, ','))
      .replace('{!objectTypeName}', objectTypeName)
      .replace('{!conditionals}', String.join(conditionals, ' OR '));
  }
}