public with sharing class CostSchemeBulkUploadController {

    public class UploadRow {
        @AuraEnabled public Integer rowNumber;
        @AuraEnabled public String paymentSchemeName;
        @AuraEnabled public String costSheetTemplateName;
        @AuraEnabled public String zCode;
        @AuraEnabled public Boolean isValid = true;
        @AuraEnabled public String errorMessage;
    }
    @AuraEnabled(cacheable=true)
    public static List<String> getPaymentSchemes(){
        List<String> names = new List<String>();
        for(Payment_Scheme__c ps : [SELECT Name FROM Payment_Scheme__c]){
            names.add(ps.Name);
        }
        return names;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getCostSheetTemplates(){
        List<String> names = new List<String>();
        for(Cost_Sheet_Template__c cs : [SELECT Name FROM Cost_Sheet_Template__c]){
            names.add(cs.Name);
        }
        return names;
    }
    @AuraEnabled
    public static void processUpload(String rowsJson) {

        List<UploadRow> rows =
            (List<UploadRow>) JSON.deserialize(rowsJson, List<UploadRow>.class);

        if(rows.isEmpty()) return;

        Set<String> psNames = new Set<String>();
        Set<String> csNames = new Set<String>();

        for(UploadRow r : rows){
            psNames.add(r.paymentSchemeName);
            csNames.add(r.costSheetTemplateName);
        }

        Map<String, Payment_Scheme__c> psMap = new Map<String, Payment_Scheme__c>();
        for(Payment_Scheme__c ps : [
            SELECT Id, Name FROM Payment_Scheme__c
            WHERE Name IN :psNames
        ]){
            psMap.put(ps.Name, ps);
        }

        Map<String, Cost_Sheet_Template__c> csMap = new Map<String, Cost_Sheet_Template__c>();
        for(Cost_Sheet_Template__c cs : [
            SELECT Id, Name, Amount__c, Tax_Amount__c
            FROM Cost_Sheet_Template__c
            WHERE Name IN :csNames
        ]){
            csMap.put(cs.Name, cs);
        }

        List<Cost_Scheme_Linking__c> parents = new List<Cost_Scheme_Linking__c>();

        for(UploadRow r : rows){
            parents.add(new Cost_Scheme_Linking__c(
                Payment_Scheme__c = psMap.get(r.paymentSchemeName).Id,
                Cost_Sheet_Template__c = csMap.get(r.costSheetTemplateName).Id
            ));
        }

        insert parents;
    }

    @AuraEnabled(cacheable=true)
    public static List<Cost_Scheme_Linking__c> getCostSchemeLinkings() {
    return [
        SELECT Id, Name, CreatedDate, Payment_Scheme__r.Name,Payment_Scheme__r.Project__c,
        Cost_Sheet_Template__r.Name
        FROM Cost_Scheme_Linking__c
        ORDER BY CreatedDate DESC
    ];
    }
    @AuraEnabled(cacheable=true)
    public static List<Project__c> getProjects() {
        return [SELECT Id, Name FROM Project__c ORDER BY Name];
    }
}