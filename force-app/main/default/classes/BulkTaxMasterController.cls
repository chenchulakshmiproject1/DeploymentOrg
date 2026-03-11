public with sharing class BulkTaxMasterController {

    public class DataWrapper {
        @AuraEnabled public List<String> taxTypes;
        @AuraEnabled public List<String> roundingMethods;
        @AuraEnabled public List<String> existingTaxNames;
    }

    @AuraEnabled(cacheable=true)
    public static List<Tax_Master__c> getTaxMasters() {
        return [
            SELECT Id, Name, Tax_Type__c, Short_Name__c,
                From_Date__c, Taxable__c, Tax__c,
                Rounding_Method__c, Active__c
            FROM Tax_Master__c
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled
    public static DataWrapper fetchDataOnLoad() {
        DataWrapper wrap = new DataWrapper();
        wrap.taxTypes = new List<String>();
        wrap.roundingMethods = new List<String>();
        wrap.existingTaxNames = new List<String>();

        for (Schema.PicklistEntry pe :
            Tax_Master__c.Tax_Type__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                wrap.taxTypes.add(pe.getLabel());
            }
        }

        for (Schema.PicklistEntry pe :
            Tax_Master__c.Rounding_Method__c.getDescribe().getPicklistValues()) {
            if (pe.isActive()) {
                wrap.roundingMethods.add(pe.getLabel());
            }
        }

        for (Tax_Master__c t : [SELECT Name FROM Tax_Master__c]) {
            wrap.existingTaxNames.add(t.Name.toLowerCase());
        }

        return wrap;
    }

@AuraEnabled
public static void createTaxMasters(String recordsJson) {
try{
    List<Tax_Master__c> taxList =
        (List<Tax_Master__c>) JSON.deserialize(
            recordsJson,
            List<Tax_Master__c>.class
        );

    insert taxList; // let Salesforce throw real error
}catch(Exception e){
    throw new AuraHandledException(e.getMessage());
}
}
}