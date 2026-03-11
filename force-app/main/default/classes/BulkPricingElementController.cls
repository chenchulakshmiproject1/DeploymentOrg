public with sharing class BulkPricingElementController {
    public class DataWrapper {
        @AuraEnabled public List<String> categories {get;set;}
        @AuraEnabled public List<String> baseUnits {get;set;}
        @AuraEnabled public List<String> conversionUnits {get;set;}
        @AuraEnabled public List<String> parkingTypes {get;set;}
        @AuraEnabled public List<String> existingCodes {get;set;}
        @AuraEnabled public List<Pricing_Element_Master__c> existingRecords {get;set;}
    }

    @AuraEnabled(cacheable=true)
    public static DataWrapper fetchDataOnLoad() {
        DataWrapper wrap = new DataWrapper();
        wrap.categories = new List<String>();
        wrap.baseUnits = new List<String>();
        wrap.conversionUnits = new List<String>();
        wrap.parkingTypes = new List<String>();
        wrap.existingCodes = new List<String>();

        for (Schema.PicklistEntry p :
            Pricing_Element_Master__c.Category__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) wrap.categories.add(p.getLabel());
        }

        for (Schema.PicklistEntry p :
            Pricing_Element_Master__c.Base_Unit__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) wrap.baseUnits.add(p.getLabel());
        }

        for (Schema.PicklistEntry p :
            Pricing_Element_Master__c.Conversion_Unit__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) wrap.conversionUnits.add(p.getLabel());
        }

        for (Schema.PicklistEntry p :
            Pricing_Element_Master__c.Parking_Type__c.getDescribe().getPicklistValues()) {
            if (p.isActive()) wrap.parkingTypes.add(p.getLabel());
        }

        for (Pricing_Element_Master__c p :
            [SELECT Code__c FROM Pricing_Element_Master__c WHERE Code__c != null]) {
            wrap.existingCodes.add(p.Code__c.toLowerCase());
        }
         wrap.existingRecords = [  SELECT Id, Name, Agreement__c, Base_Unit__c, Category__c, Code__c, Conversion_Factor__c, Conversion_Unit__c, Is_Premium_Applicable__c, Remarks__c, Parking_Type__c
                                FROM Pricing_Element_Master__c ORDER BY CreatedDate DESC ];
        return wrap;
    }

    @AuraEnabled
    public static String createPricingElements(String recordsJson) {
        try {
            List<Pricing_Element_Master__c> records =
                (List<Pricing_Element_Master__c>)
                JSON.deserialize(recordsJson, List<Pricing_Element_Master__c>.class);

            if (records.isEmpty()) {
                return 'ERROR: No records to insert';
            }

            insert records;
            return 'SUCCESS';

        } catch (Exception e) {
            throw new AuraHandledException(
                'Insert failed: ' + e.getMessage()
            );
        }
    }
}