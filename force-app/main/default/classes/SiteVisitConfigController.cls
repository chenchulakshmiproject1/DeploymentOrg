public with sharing class SiteVisitConfigController {
    @AuraEnabled(cacheable=true)
    public static FieldWrapper getFields(){
        FieldWrapper wrap = new FieldWrapper();
       
       List<Site_Visit_Field_Config__c> visitFields =  [SELECT Id,Field_API_Name__c,Field_Label__c,Field_Type__c,Is_Required__c,Is_Visible__c,Section_Name__c,Display_Order__c,Object_API_Name__c FROM Site_Visit_Field_Config__c where Object_API_Name__c='Visit__c' ORDER BY Section_Name__c,Display_Order__c ];
       List<Site_Visit_Field_Config__c> leadFields =  [SELECT Id,Field_API_Name__c,Field_Label__c,Field_Type__c,Is_Required__c,Is_Visible__c,Section_Name__c,Display_Order__c,Object_API_Name__c FROM Site_Visit_Field_Config__c where Object_API_Name__c='Lead' ORDER BY Section_Name__c,Display_Order__c ];
        wrap.visitFields = visitFields;
        wrap.leadFields = leadFields;
        return wrap;
    }
    public class FieldWrapper{
        @AuraEnabled public List<Site_Visit_Field_Config__c> visitFields{get;set;}
        @AuraEnabled public List<Site_Visit_Field_Config__c> leadFields{get;set;}
    }
    @AuraEnabled
    public static  void updateVisibility(Id recordId, Boolean isVisible){
        Site_Visit_Field_Config__c field = new Site_Visit_Field_Config__c(Id=recordId,Is_Visible__c=isVisible);
        try {
            update field;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}