public with sharing class OpportunityStageController {
    
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getStageData() {
        try {
            Map<String, Object> response = new Map<String, Object>();
            
            // 1. Get picklist values from Opportunity__c StageName__c
            List<String> stageNames = getPicklistValues('Opportunity', 'StageName');
            
            // 2. For each stage, get related Task Master records
            List<StageWrapper> stagesWithTasks = new List<StageWrapper>();
            
            // Get all Task Master records in one query (better performance)
            Map<String, List<TaskWrapper>> tasksByStage = getTasksByStage();
            
            // 3. Build stage wrappers with tasks
            for(String stageName : stageNames) {
                StageWrapper stage = new StageWrapper();
                stage.stageName = stageName;
                stage.tasks = tasksByStage.containsKey(stageName) ? 
                              tasksByStage.get(stageName) : 
                              new List<TaskWrapper>();
                stage.selectedCount = 0;
                stage.totalTasks = stage.tasks.size();
                stagesWithTasks.add(stage);
            }
            
            response.put('success', true);
            response.put('stages', stagesWithTasks);
            return response;
            
        } catch(Exception e) {
            throw new AuraHandledException('Error loading stage data: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void saveTaskSelections(List<String> selectedTaskIds) {
        try {
            // This will be implemented later for DML operations
            // For now, just a placeholder
            System.debug('Selected Tasks: ' + selectedTaskIds);
        } catch(Exception e) {
            throw new AuraHandledException('Error saving selections: ' + e.getMessage());
        }
    }
    
    /**
     * Helper method to get picklist values from a field
     */
    private static List<String> getPicklistValues(String objectName, String fieldName) {
        List<String> picklistValues = new List<String>();
        
        Schema.SObjectType targetType = Schema.getGlobalDescribe().get(objectName);
        Schema.DescribeSObjectResult objDescribe = targetType.getDescribe();
        Schema.DescribeFieldResult fieldDescribe = objDescribe.fields.getMap().get(fieldName).getDescribe();
        
        List<Schema.PicklistEntry> picklistEntries = fieldDescribe.getPicklistValues();
        
        for(Schema.PicklistEntry entry : picklistEntries) {
            if(entry.isActive()) {
                picklistValues.add(entry.getValue());
            }
        }
        
        return picklistValues;
    }
    
    /**
     * Helper method to get Task Master records grouped by Stage
     */
    private static Map<String, List<TaskWrapper>> getTasksByStage() {
        Map<String, List<TaskWrapper>> tasksByStage = new Map<String, List<TaskWrapper>>();
        
        // Query Task Master records with Object_Type__c = 'Opportunity'
        List<Task_Master__c> taskMasters = [
            SELECT Id, Name, Task_Subject__c, StageName__c 
            FROM Task_Master__c 
            WHERE Object_Type__c = 'Opportunity' 
            AND StageName__c != null
            ORDER BY CreatedDate
        ];
        
        for(Task_Master__c task : taskMasters) {
            TaskWrapper wrapper = new TaskWrapper();
            wrapper.id = task.Id;
            wrapper.subject = task.Task_Subject__c;
            wrapper.stageName = task.StageName__c;
            wrapper.selected = false;
            
            if(!tasksByStage.containsKey(task.StageName__c)) {
                tasksByStage.put(task.StageName__c, new List<TaskWrapper>());
            }
            tasksByStage.get(task.StageName__c).add(wrapper);
        }
        
        return tasksByStage;
    }
    
    /**
     * Wrapper classes for data structure
     */
    public class StageWrapper {
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public List<TaskWrapper> tasks { get; set; }
        @AuraEnabled public Integer selectedCount { get; set; }
        @AuraEnabled public Integer totalTasks { get; set; }
    }
    
    public class TaskWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String subject { get; set; }
        @AuraEnabled public String stageName { get; set; }
        @AuraEnabled public Boolean selected { get; set; }
    }
}