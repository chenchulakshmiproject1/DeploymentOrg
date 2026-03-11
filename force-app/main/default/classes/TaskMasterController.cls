public with sharing class TaskMasterController {
    
    @AuraEnabled
    public static Map<String, Object> createTaskMaster(String taskData) {
        Map<String, Object> response = new Map<String, Object>();
        List<Task_Master__c> tasksToInsert = new List<Task_Master__c>();
        
        try {
            // Parse the incoming data
            Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(taskData);
            
            // Check if it's a bulk creation (has 'tasks' array) or single creation
            if (dataMap.containsKey('tasks')) {
                // Bulk creation
                List<Object> tasksList = (List<Object>) dataMap.get('tasks');
                
                for (Object taskObj : tasksList) {
                    Map<String, Object> taskMap = (Map<String, Object>) taskObj;
                    Task_Master__c taskMaster = createTaskFromMap(taskMap);
                    tasksToInsert.add(taskMaster);
                }
            } else {
                // Single creation (backward compatibility)
                Task_Master__c taskMaster = createTaskFromMap(dataMap);
                tasksToInsert.add(taskMaster);
            }
            
            // Insert all tasks in one DML operation
            if (!tasksToInsert.isEmpty()) {
                insert tasksToInsert;
                
                // Collect IDs manually
                List<String> taskIds = new List<String>();
                for (Task_Master__c task : tasksToInsert) {
                    taskIds.add(task.Id);
                }
                
                response.put('success', true);
                response.put('message', tasksToInsert.size() + ' task(s) created successfully');
                response.put('ids', taskIds);
            } else {
                response.put('success', false);
                response.put('message', 'No tasks to create');
            }
            
        } catch (Exception e) {
            response.put('success', false);
            response.put('message', e.getMessage());
        }
        
        return response;
    }
    
    // Helper method to create Task_Master__c from map
    private static Task_Master__c createTaskFromMap(Map<String, Object> dataMap) {
        Task_Master__c taskMaster = new Task_Master__c();
        
        if (dataMap.containsKey('objectType')) {
            taskMaster.Object_Type__c = (String) dataMap.get('objectType');
        }
        
        if (dataMap.containsKey('taskSubject')) {
            taskMaster.Task_Subject__c = (String) dataMap.get('taskSubject');
        }
        
        if (dataMap.containsKey('stageName')) {
            taskMaster.StageName__c = (String) dataMap.get('stageName');
        }
        
        if (dataMap.containsKey('isActive')) {
            taskMaster.IsActive__c = (Boolean) dataMap.get('isActive');
        }
        
        if (dataMap.containsKey('isCommonTask')) {
            taskMaster.IsCommonTask__c = (Boolean) dataMap.get('isCommonTask');
        }
        
        if (dataMap.containsKey('remarks')) {
            taskMaster.Remarks__c = (String) dataMap.get('remarks');
        }
        
        return taskMaster;
    }
    
    // Delete Task Master records
    @AuraEnabled
    public static Map<String, Object> deleteTaskMaster(List<String> taskIds) {
        Map<String, Object> response = new Map<String, Object>();
        
        try {
            if (taskIds == null || taskIds.isEmpty()) {
                response.put('success', false);
                response.put('message', 'No tasks selected for deletion');
                return response;
            }
            
            List<Task_Master__c> tasksToDelete = [SELECT Id FROM Task_Master__c WHERE Id IN :taskIds];
            
            if (tasksToDelete.isEmpty()) {
                response.put('success', false);
                response.put('message', 'No valid tasks found to delete');
                return response;
            }
            
            delete tasksToDelete;
            
            response.put('success', true);
            response.put('message', tasksToDelete.size() + ' task(s) deleted successfully');
            response.put('deletedCount', tasksToDelete.size());
            
        } catch (Exception e) {
            response.put('success', false);
            response.put('message', 'Error deleting tasks: ' + e.getMessage());
        }
        
        return response;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getActionTypePicklistValues() {
        List<Map<String, String>> options = new List<Map<String, String>>();
        
        // Get picklist values from Action_Type__c field
        Schema.DescribeFieldResult fieldDescribe = Task_Master__c.Action_Type__c.getDescribe();
        List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
        
        for (Schema.PicklistEntry entry : picklistEntries) {
            if (entry.isActive()) {
                Map<String, String> option = new Map<String, String>();
                option.put('label', entry.getLabel());
                option.put('value', entry.getValue());
                options.add(option);
            }
        }
        
        return options;
    }
}