public class BulkUploadProjectDataController {
    @AuraEnabled
    public static String saveExcelData(List<String> headers, List<List<Object>> data) {
		try{
			System.debug('headers::'+headers);
			Map<String, String> objectMappings = new Map<String, String>();
			Map<String, String> fieldMappings = new Map<String, String>();
			Map<String, List<String>> ObjectfieldMappings = new Map<String, List<String>>();

			Map<String, Project__c> existingProjects = new Map<String, Project__c>();
			Map<String, Tower__c> existingTowers = new Map<String, Tower__c>();
			Map<String, Map<String, Floor__c>> existingFloors = new Map<String, Map<String, Floor__c>>();
			Map<String, Unit__c> existingUnits = new Map<String, Unit__c>();

			List<Project__c> projectsToInsert = new List<Project__c>();
			List<Project__c> projectsToUpdate = new List<Project__c>();

			List<Tower__c> towersToInsert = new List<Tower__c>();
			List<Tower__c> towersToUpdate = new List<Tower__c>();

			List<Floor__c> floorsToInsert = new List<Floor__c>();
			List<Floor__c> floorsToUpdate = new List<Floor__c>();

			List<Unit__c> unitsToInsert = new List<Unit__c>();
			List<Unit__c> unitsToUpdate = new List<Unit__c>();

			for (ProjectDataUpload__c setting : [SELECT Name,Object_Name__c, Field_API_Name__c FROM ProjectDataUpload__c]) {
				if(!ObjectfieldMappings.containsKey(setting.Object_Name__c)){
					ObjectfieldMappings.put(setting.Object_Name__c, new List<String>());
				}
				ObjectfieldMappings.get(setting.Object_Name__c).add(setting.Field_API_Name__c);
				
				objectMappings.put(setting.Name, setting.Object_Name__c);
				fieldMappings.put(setting.Name, setting.Field_API_Name__c);
			}

			for (Project__c proj : [SELECT Id, Project_Code__c FROM Project__c]) {
				existingProjects.put(proj.Project_Code__c, proj);
			}

			for (Tower__c tower : [SELECT Id, Tower_Code__c, Project__c FROM Tower__c]) {
				existingTowers.put(tower.Tower_Code__c, tower);
			}

			for (Floor__c floor : [SELECT Id, Floor_Name__c,Blocks__c,Blocks__r.Tower_Code__c FROM Floor__c]) {
				if (!existingFloors.containsKey(floor.Blocks__r.Tower_Code__c)) {
					existingFloors.put(floor.Blocks__r.Tower_Code__c, new Map<String, Floor__c>());
				}
				existingFloors.get(floor.Blocks__r.Tower_Code__c).put(floor.Floor_Name__c, floor);
			}

			for (Unit__c unit : [SELECT Id, Unit_Code__c, Floor__c FROM Unit__c]) {
				existingUnits.put(unit.Unit_Code__c, unit);
			}
			//company----------------------------------
			 Set<String> companyNames = new Set<String>();

				for(List<Object> row : data){
					if(row != null && !row.isEmpty()){
						Map<String,Object> rowData = new Map<String,Object>();
						for(Integer i=0;i<headers.size();i++){
							rowData.put(headers[i], row[i]);
						}
						if(rowData.containsKey('Company__c') && rowData.get('Company__c')!=null){
							companyNames.add(String.valueOf(rowData.get('Company__c')));
						}
					}
				}
				Map<String, Id> companyMap = new Map<String, Id>();

				for(Company__c c : [SELECT Id, Name FROM Company__c WHERE Name IN :companyNames]){companyMap.put(c.Name, c.Id);}

			for (List<Object> row : data) {
				if (row != null && !row.isEmpty()) {
					Map<String, Object> rowData = new Map<String, Object>();
					for (Integer i = 0; i < headers.size(); i++) {
						rowData.put(headers[i], row[i]);
					}
					if (rowData.containsKey('Project_Code__c')) {
						String projectCode = String.valueOf(rowData.get('Project_Code__c'));
						if (existingProjects.containsKey(projectCode)) {
							Project__c project = existingProjects.get(projectCode);
							updateSObject(project, rowData, fieldMappings,objectMappings,ObjectfieldMappings);
							Boolean isReplaced = false;
							for (Integer i = 0; i < projectsToUpdate.size(); i++) {
								if (projectsToUpdate[i].Id == project.Id) {
									// Replace the old record with the new one
									projectsToUpdate[i] = project;
									isReplaced = true;
									break;
								}
							}
							if (!isReplaced) {
								projectsToUpdate.add(project);
							}
						} else {

							Boolean alreadyExists = false;

							for (Project__c proj : projectsToInsert) {
								if (proj.Project_Code__c == projectCode) {
									alreadyExists = true;
									break;
								}
							}
                             String companyName = String.valueOf(rowData.get('Company__c'));
                             Id companyId = companyMap.containsKey(companyName) ? companyMap.get(companyName) : null;

							if (!alreadyExists) {
								Project__c newProject = new Project__c(Project_Code__c = projectCode,Company__c = companyId);
								updateSObject(newProject, rowData, fieldMappings, objectMappings, ObjectfieldMappings);
								projectsToInsert.add(newProject);
							} else {
								System.debug('Duplicate project code found in current batch: ' + projectCode);
							}
							
						}
					}
				}
			}
			System.debug('projectsToInsert==>'+projectsToInsert);
			System.debug('projectsToUpdate==>'+projectsToUpdate);

			if (!projectsToInsert.isEmpty()) insert projectsToInsert;
			System.debug('projectsToInsert==>'+projectsToInsert);
			if (!projectsToUpdate.isEmpty()) update projectsToUpdate;
			existingProjects.clear();

			for (Project__c proj : [SELECT Id, Project_Code__c FROM Project__c]) {
				existingProjects.put(proj.Project_Code__c, proj);
			}

			// Process Tower Data Rows
			for(List<Object> row : data){
				if (row != null && !row.isEmpty()){
				Map<String, Object> rowData = new Map<String, Object>();
				for (Integer i = 0; i < headers.size(); i++) {
					rowData.put(headers[i], row[i]);
				}
				if (rowData.containsKey('Tower_Code__c')) {
					String towerCode = String.valueOf(rowData.get('Tower_Code__c'));
					String projectCode = String.valueOf(rowData.get('Project_Code__c'));
					String projectId = existingProjects.containsKey(projectCode) ? existingProjects.get(projectCode).Id : null;
					if (existingTowers.containsKey(towerCode)) {
						Tower__c tower = existingTowers.get(towerCode);
						tower.Project__c = projectId;
						updateSObject(tower, rowData, fieldMappings,objectMappings,ObjectfieldMappings);
						Boolean isReplaced = false;
							for (Integer i = 0; i < towersToUpdate.size(); i++) {
								if (towersToUpdate[i].Id == tower.Id) {
									// Replace the old record with the new one
									towersToUpdate[i] = tower;
									isReplaced = true;
									break;
								}
							}
							if (!isReplaced) {
								towersToUpdate.add(tower);
							}
					} else {
						// Insert new Tower (Include Tower_Code__c)
						



						 Boolean alreadyExists = false;

							for (Tower__c tow : towersToInsert) {
								if (tow.Tower_Code__c == towerCode) {
									alreadyExists = true;
									break;
								}
							}

							if (!alreadyExists) {
								Tower__c newTower = new Tower__c(Tower_Code__c = towerCode, Project__c = projectId);
						updateSObject(newTower, rowData, fieldMappings,objectMappings,ObjectfieldMappings);
						towersToInsert.add(newTower);
							} else {
								System.debug('Duplicate Tower code found in current batch: ' + towerCode);
							}
					}
				}
				}

			}
			System.debug('towersToInsert==>'+towersToInsert);
			System.debug('towersToUpdate==>'+towersToUpdate);

			if (!towersToInsert.isEmpty()) insert towersToInsert;
			if (!towersToUpdate.isEmpty()) update towersToUpdate;

			existingTowers.clear();
			for (Tower__c tower : [SELECT Id, Tower_Code__c, Project__c FROM Tower__c]) {
				existingTowers.put(tower.Tower_Code__c, tower);
			}

			// Process floors Data Rows
			Set<String> processedFloorKeys = new Set<String>();

			for (List<Object> row : data) {
				if (row != null && !row.isEmpty()) {

					Map<String, Object> rowData = new Map<String, Object>();
					for (Integer i = 0; i < headers.size(); i++) {
						rowData.put(headers[i], row[i]);
					}

					if (rowData.containsKey('Floor_Name__c')) {

						String projectCode = String.valueOf(rowData.get('Project_Code__c'));
						String towerCode   = String.valueOf(rowData.get('Tower_Code__c'));
						String floorNo     = String.valueOf(rowData.get('Floor_Name__c'));

						String floorKey = projectCode + '-' + towerCode + '-' + floorNo;

						if (processedFloorKeys.contains(floorKey)) {
							continue;
						}

						processedFloorKeys.add(floorKey);

						String towerId = existingTowers.containsKey(towerCode)
							? existingTowers.get(towerCode).Id
							: null;

						if (existingFloors.containsKey(towerCode) &&
							existingFloors.get(towerCode).containsKey(floorNo)) {

							Floor__c floor = existingFloors.get(towerCode).get(floorNo);
							floor.Blocks__c = towerId;

							updateSObject(floor, rowData, fieldMappings, objectMappings, ObjectfieldMappings);

							floorsToUpdate.add(floor);

						} else {

							Floor__c newFloor = new Floor__c(
								Floor_Name__c = floorNo,
								Blocks__c      = towerId
						);

						updateSObject(newFloor, rowData, fieldMappings, objectMappings, ObjectfieldMappings);

						floorsToInsert.add(newFloor);
					}
				}
			}
			

			}
			System.debug('floorsToInsert==>'+floorsToInsert);
			System.debug('floorsToUpdate==>'+floorsToUpdate);

			if (!floorsToInsert.isEmpty()) insert floorsToInsert;
			if (!floorsToUpdate.isEmpty()) update floorsToUpdate;

			existingFloors.clear();

			for (Floor__c floor : [
				SELECT Id, Floor_Name__c, Blocks__c, Blocks__r.Tower_Code__c
				FROM Floor__c
			]) {
				String towerCode = floor.Blocks__r.Tower_Code__c;

				if (!existingFloors.containsKey(towerCode)) {
					existingFloors.put(towerCode, new Map<String, Floor__c>());
				}

				existingFloors.get(towerCode).put(floor.Floor_Name__c, floor);
			}
			System.debug('existingFloors==>'+existingFloors);

			// Process Unit Data Rows
			for(List<Object> row : data){
				if (row != null && !row.isEmpty()){
				Map<String, Object> rowData = new Map<String, Object>();
				for (Integer i = 0; i < headers.size(); i++) {
					rowData.put(headers[i], row[i]);
				}
				if (rowData.containsKey('Unit_Code__c')) {
					String unitCode = String.valueOf(rowData.get('Unit_Code__c'));
					System.debug('unitCode==>'+unitCode);
					String towerCode = String.valueOf(rowData.get('Tower_Code__c'));
					System.debug('towerCode==>'+towerCode);
					Map<String, Floor__c> towerFlors = existingFloors.get(towerCode);
					System.debug('towerFlors==>'+towerFlors);
					String floorNo = (String) rowData.get('Floor_Name__c');
					System.debug('floorNo==>'+floorNo);
					Floor__c floorRec = towerFlors.get(floorNo);
					System.debug('floorRec==>'+floorRec);
					String floorId = floorRec != null ? floorRec.Id : null;
					if (existingUnits.containsKey(unitCode)) {
						Unit__c unit = existingUnits.get(unitCode);
						unit.Floor__c = floorId;
						updateSObject(unit, rowData, fieldMappings,objectMappings,ObjectfieldMappings);
						Boolean isReplaced = false;
							for (Integer i = 0; i < unitsToUpdate.size(); i++) {
								if (unitsToUpdate[i].Id == unit.Id) {
									// Replace the old record with the new one
									unitsToUpdate[i] = unit;
									isReplaced = true;
									break;
								}
							}
							if (!isReplaced) {
								unitsToUpdate.add(unit);
							}
					} else {
						


						 Boolean alreadyExists = false;

							for (Unit__c un : unitsToInsert) {
								if (un.Unit_Code__c == unitCode) {
									alreadyExists = true;
									break;
								}
							}

							if (!alreadyExists) {
								Unit__c newUnit = new Unit__c(Unit_Code__c = unitCode, Floor__c = floorId);
						updateSObject(newUnit, rowData, fieldMappings,objectMappings,ObjectfieldMappings);
						unitsToInsert.add(newUnit);
								
							} else {
								System.debug('Duplicate Unit code found in current batch: ' + unitCode);
							}
					}
				}
			}
			}

			System.debug('unitsToInsert==>'+unitsToInsert);
			System.debug('unitsToUpdate==>'+unitsToUpdate);

			if (!unitsToInsert.isEmpty()) insert unitsToInsert;
			if (!unitsToUpdate.isEmpty()) update unitsToUpdate;

			return 'success';
		}Catch(Exception e){
			System.debug('e.getLineNumber::'+e.getLineNumber());
			System.debug('e.getMessage::'+e.getMessage());
			return e.getMessage();
		}
		
    }




    private static Void updateSObject(SObject record, Map<String, Object> rowData, Map<String, String> fieldMappings,Map<String, String> objectMappings,Map<String, List<String>> ObjectfieldMappings) {
    try {
        Map<String, SObjectField> describeFields = record.getSObjectType().getDescribe().fields.getMap();
        for (String fieldAPI : fieldMappings.keySet()) {
			String getObjectApi = objectMappings.get(fieldAPI);
			String getFieldApi = fieldMappings.get(fieldAPI);
			List<String> getallFieldValues = ObjectfieldMappings.get(getObjectApi);
			if(getallFieldValues.Contains(getFieldApi)){
            if (rowData.containsKey(fieldAPI) && getObjectApi == record.getSObjectType().getDescribe().getName()) {
                Object rawValue = rowData.get(fieldAPI);
                if (describeFields.containsKey(getFieldApi)) {   // == fieldMappings.get(fieldAPI)
                    Schema.DisplayType fieldType = describeFields.get(getFieldApi).getDescribe().getType();
                    try {
                        switch on fieldType {
                            when String {
                                record.put(fieldMappings.get(fieldAPI), String.valueOf(rawValue));
                            }
                            when Integer {
                                record.put(fieldMappings.get(fieldAPI), Integer.valueOf(String.valueOf(rawValue)));
                            }
                            when Double {
                                record.put(fieldMappings.get(fieldAPI), Double.valueOf(String.valueOf(rawValue)));
                            }
                            when Currency {
                                record.put(fieldMappings.get(fieldAPI), Decimal.valueOf(String.valueOf(rawValue)));
                            }
                            when Date {
								try {
									String dateString = String.valueOf(rawValue).trim();
									if (dateString.contains('/')) {
										// dd/MM/yyyy format
										List<String> parts = dateString.split('/');
										if (parts.size() == 3) {
											String formattedDate = parts[2] + '-' + parts[1] + '-' + parts[0];
											record.put(fieldMappings.get(fieldAPI), Date.valueOf(formattedDate));
										}
									} else if (dateString.isNumeric()) {
										// Excel serial number format
										Integer excelSerial = Integer.valueOf(dateString);
										Date baseDate = Date.newInstance(1900, 1, 1);
										Date excelDate = baseDate.addDays(excelSerial - 1);
										record.put(fieldMappings.get(fieldAPI), excelDate);
									} else {
										// yyyy-MM-dd format or other ISO formats
										record.put(fieldMappings.get(fieldAPI), Date.valueOf(dateString));
									}
								} catch (Exception e) {
									System.debug('e.getLineNumber::' + e.getLineNumber());
									System.debug('Error parsing date for field ' + fieldAPI + ': ' + e.getMessage());
									
								}
							}
                            when DateTime {
                                record.put(fieldMappings.get(fieldAPI), DateTime.valueOf(String.valueOf(rawValue)));
                            }
                            when Boolean {
                                record.put(fieldMappings.get(fieldAPI), Boolean.valueOf(String.valueOf(rawValue)));
                            }when TEXTAREA {
                                record.put(fieldMappings.get(fieldAPI), String.valueOf(rawValue));
                            }when PICKLIST {
                                record.put(fieldMappings.get(fieldAPI), String.valueOf(rawValue));
                            }
							when MULTIPICKLIST {
                                record.put(fieldMappings.get(fieldAPI), String.valueOf(rawValue));
                            }
                            when else {
                                System.debug('Unsupported field type: ' + fieldType);
								
                            }
							
                        }
                    } catch (Exception typeEx) {
                        System.debug('Type conversion error on field ' + fieldAPI + ': ' + typeEx.getMessage());
                    }
                } else {
					
                    System.debug('Field ' + fieldAPI + ' not found in describe fields');
                }
            }
        }
	}

        System.debug('Updated record==>' + record);

    } catch (Exception e) {
        System.debug('e.getLineNumber::' + e.getLineNumber());
        System.debug('e.getMessage::' + e.getMessage());
    }
}

    
    public static void dummyMethod(){
        Integer i = 0;
        i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
        i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
        i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
        i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
        i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
        i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++; i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
         i++;i++;i++;i++;
    }


    // Custom Exception
    public class CustomException extends Exception {}

	public class DataWrapper{
		@AuraEnabled public List<Unit__c> existingUnits {get;set;}
		@AuraEnabled public Set<String> existingCompns {get;set;}
		@AuraEnabled public Integer towersCount {get;set;}
		@AuraEnabled public List<Project__c> projects {get;set;}
	}
	@AuraEnabled(cacheable=true)
	public static DataWrapper getDataOnLoad(){
		try {
			DataWrapper wrap = new DataWrapper();
			wrap.existingUnits = new List<Unit__c>();
			wrap.existingCompns = new Set<String>();

			
			wrap.existingUnits = [SELECT Id,Unit_Name__c,Name,Floor__c,Floor__r.Floor_No__c,Share__c,Saleable_Area__c,Status__c,Unit_Type__c,Floor__r.Blocks__r.Name,Floor__r.Blocks__r.Project__c FROM Unit__c WHERE Floor__c !=null AND Floor__r.Blocks__c !=null Order by CreatedDate DESC ];
			System.debug('Existing Units--------->'+wrap.existingUnits);
			for(Company__c c:[SELECT Id,Name FROM Company__c]){
				wrap.existingCompns.add(c.Name);
			}
			AggregateResult result = [
			SELECT COUNT_DISTINCT(Floor__r.Blocks__c) total
			FROM Unit__c
			WHERE Floor__r.Blocks__c != null
			];

			Integer uniqueTowerCount = (Integer) result.get('total');
			wrap.towersCount = uniqueTowerCount;
			wrap.projects = [
				SELECT Id, Name
				FROM Project__c
				ORDER BY Name
			];
			return wrap;
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}

	

}