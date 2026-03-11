/**
* @File Name : CostSheetCsvController.cls
* @Description :
* @Author :
* @Last Modified By :
* @Last Modified On : January 5, 2026
* @Modification Log :
*==============================================================================
* Ver | Date | Author | Modification
*==============================================================================
* 1.0 | January 5, 2026 |   | Initial Version
**/

public with sharing class CostSheetCsvController {

    @AuraEnabled(cacheable=true)
    public static List<Cost_Sheet_Template__c> getCostSheetTemplates() {
        return [
            SELECT Id, Name,Project__c, Company__r.Name, Project__r.Name,Template_Code__c, Amount__c,  Total_Amount_Inclusive_of_Tax__c,Tax_Amount__c,  Active__c FROM Cost_Sheet_Template__c
            ORDER BY CreatedDate DESC
        ];
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> fetchDataOnLoad() {
        Map<String, Object> result = new Map<String, Object>();

        Map<String, Id> companyMap = new Map<String, Id>();
        for (Company__c c : [SELECT Id, Name FROM Company__c]) {
            companyMap.put(c.Name.toLowerCase(), c.Id);
        }
        result.put('companyMap', companyMap);

        Map<String, Id> projectMap = new Map<String, Id>();
        for (Project__c p : [SELECT Id, Name FROM Project__c]) {
            projectMap.put(p.Name.toLowerCase(), p.Id);
        }
        result.put('projectMap', projectMap);

        Map<String, Id> unitMap = new Map<String, Id>();
        for (Unit__c u : [
            SELECT Id, Unit_Code__c
            FROM Unit__c
            WHERE Status__c = 'Available'
        ]) {
            unitMap.put(u.Unit_Code__c, u.Id);
        }
        result.put('unitMap', unitMap);

        Map<String, Id> pricingElementMap = new Map<String, Id>();
        for (Pricing_Element_Master__c pe : [
            SELECT Id, Name
            FROM Pricing_Element_Master__c
            WHERE Parking_Type__c = null
        ]) {
            pricingElementMap.put(pe.Name, pe.Id);
        }
        result.put('pricingElementMap', pricingElementMap);

        Set<String> existingTemplateCodes = new Set<String>();
        for (Cost_Sheet_Template__c cst : [
            SELECT Template_Code__c
            FROM Cost_Sheet_Template__c
            WHERE Template_Code__c != null
        ]) {
            existingTemplateCodes.add(cst.Template_Code__c.toLowerCase());
        }

        result.put('existingTemplateCodes', existingTemplateCodes);


        Map<String, List<TaxInfo>> taxByTypeMap = new Map<String, List<TaxInfo>>();
        Map<String, TaxInfo> taxDetailsMap = new Map<String, TaxInfo>();
        
        for (Tax_Master__c t : [
            SELECT Id, Name, Tax__c, Tax_Type__c
            FROM Tax_Master__c
            WHERE Active__c = true
        ]) {
            TaxInfo info = new TaxInfo();
            info.id = t.Id;
            info.name = t.Name;
            info.taxPercent = t.Tax__c;
            info.taxType = t.Tax_Type__c;
            
            taxDetailsMap.put(t.Name, info);
            
            if (String.isNotBlank(t.Tax_Type__c)) {
                if (!taxByTypeMap.containsKey(t.Tax_Type__c)) {
                    taxByTypeMap.put(t.Tax_Type__c, new List<TaxInfo>());
                }
                taxByTypeMap.get(t.Tax_Type__c).add(info);
            }
        }
        
        result.put('taxByTypeMap', taxByTypeMap);
        result.put('taxDetailsMap', taxDetailsMap);

        return result;
    }

    @AuraEnabled
    public static void uploadCostSheet(String payloadJson) {
        if (String.isBlank(payloadJson)) {
            throw new AuraHandledException('Payload is empty');
        }

        List<PayloadWrapper> payloads =
    (List<PayloadWrapper>) JSON.deserialize(payloadJson, List<PayloadWrapper>.class);


        for (PayloadWrapper payload : payloads) {

    validateTemplate(payload.template);

    Id templateId = createTemplate(payload.template);

    processUnits(templateId, payload.unitCodes);

    Map<Integer, Id> pricingAssocMap =
        processPricingAssociations(templateId, payload.pricingRows);

    processTaxes(pricingAssocMap, payload.pricingRows);
  }

    }
            private static void validateTemplate(TemplateWrapper t) {
            Integer cnt = [
                SELECT COUNT()
                FROM Cost_Sheet_Template__c
                WHERE Template_Code__c = :t.templateCode
            ];

            if (cnt > 0) {
                throw new AuraHandledException(
                    'Template Code "' + t.templateCode + '" already exists. Template Code must be unique.'
                );
            }
        }       

    private static Id createTemplate(TemplateWrapper t) {
        Cost_Sheet_Template__c cst = new Cost_Sheet_Template__c(
            Company__c       = t.companyId,
            Project__c       = t.projectId,
            Template_Code__c = t.templateCode,
            Name             = t.templateName,
            Active__c        = t.active
        );

        insert cst;
        return cst.Id;
    }

    private static void processUnits(Id templateId, List<String> unitCodes) {
        Set<String> uniqueUnitCodes = new Set<String>(unitCodes);


        Map<String, Unit__c> unitMap = new Map<String, Unit__c>();
        for (Unit__c u : [
            SELECT Id, Unit_Code__c
            FROM Unit__c
            WHERE Unit_Code__c IN :uniqueUnitCodes
              AND Status__c = 'Available'
        ]) {
            unitMap.put(u.Unit_Code__c, u);
        }

        if (unitMap.size() != uniqueUnitCodes.size()) {
            Set<String> missing = new Set<String>(uniqueUnitCodes);
            missing.removeAll(unitMap.keySet());
            throw new AuraHandledException('Invalid/Unavailable Unit Codes: ' + String.join(new List<String>(missing), ', '));
        }

        List<Cost_Unit_Linking__c> links = new List<Cost_Unit_Linking__c>();
        for (Unit__c u : unitMap.values()) {
            links.add(new Cost_Unit_Linking__c(
                Cost_Sheet_Template__c = templateId,
                Unit__c = u.Id
            ));
        }

        insert links;
    }

    private static Map<Integer, Id> processPricingAssociations(
        Id templateId,
        List<PricingRowWrapper> rows
    ) {

        Map<String, Pricing_Element_Master__c> masterMap = new Map<String, Pricing_Element_Master__c>();
        for (Pricing_Element_Master__c pe : [
            SELECT Id, Name
            FROM Pricing_Element_Master__c
            WHERE Parking_Type__c = null
        ]) {
            masterMap.put(pe.Name, pe);
        }

        List<Cost_Pricing_Association__c> records = new List<Cost_Pricing_Association__c>();
        Map<Integer, Id> result = new Map<Integer, Id>();

        for (Integer i = 0; i < rows.size(); i++) {
            PricingRowWrapper r = rows[i];
            
            if (String.isBlank(r.pricingElementAlloc) ||
            !masterMap.containsKey(r.pricingElementAlloc)) {
                throw new AuraHandledException('Invalid Pricing Element: ' + r.pricingElementAlloc);
            }

            Decimal amount = r.quantity * r.rate;

            Cost_Pricing_Association__c rec = new Cost_Pricing_Association__c(
                Cost_Sheet_Template__c    = templateId,
                Pricing_Element_Master__c = masterMap.get(r.pricingElementAlloc).Id,
                Unit__c                   = r.unit,
    
                PE_Type__c                = r.peType,
                Type__c                   = r.type,
                Sequence__c               = r.sequence,
                Quantity__c               = r.quantity,
                Rate__c                   = r.rate,
                Amount__c                 = amount,
                Tax_Amount__c             = 0  
            );

            records.add(rec);
        }

        insert records;

        for (Integer i = 0; i < records.size(); i++) {
            result.put(i, records[i].Id);
        }

        return result;
    }

   private static void processTaxes(
    Map<Integer, Id> pricingAssocMap,
    List<PricingRowWrapper> rows
) {
    Map<String, Tax_Master__c> taxMap = new Map<String, Tax_Master__c>();
    for (Tax_Master__c t : [
        SELECT Id, Name, Tax__c, Tax_Type__c
        FROM Tax_Master__c
        WHERE Active__c = true
    ]) {
        taxMap.put(t.Name, t);
    }

    List<Cost_Sheet_Tax_Linking__c> taxLinks = new List<Cost_Sheet_Tax_Linking__c>();
    Map<Id, Decimal> pricingTaxSums = new Map<Id, Decimal>();

    for (Integer i = 0; i < rows.size(); i++) {
        PricingRowWrapper r = rows[i];
        if (String.isBlank(r.taxName)) continue;

        Id pricingAssocId = pricingAssocMap.get(i);
        Tax_Master__c tm = taxMap.get(r.taxName);

        if (tm == null) {
            throw new AuraHandledException('Invalid Tax: ' + r.taxName);
        }

        if (tm.Tax_Type__c != r.taxType) {
            throw new AuraHandledException(
                'Tax "' + r.taxName + '" is of type "' + tm.Tax_Type__c + '"'
            );
        }

        Decimal appliedPercent =
            (r.appPercent != null && r.appPercent > 0)
            ? r.appPercent
            : tm.Tax__c;

        Decimal baseAmount = r.quantity * r.rate;
        Decimal taxAmount = baseAmount * (appliedPercent / 100);


        taxLinks.add(new Cost_Sheet_Tax_Linking__c(
            Cost_Pricing_Association__c = pricingAssocId,
            Tax_Master__c = tm.Id,
            App__c = appliedPercent,
            Amount__c = taxAmount
        ));

        pricingTaxSums.put(
            pricingAssocId,
            (pricingTaxSums.containsKey(pricingAssocId)
                ? pricingTaxSums.get(pricingAssocId)
                : 0) + taxAmount
        );
    }

    if (!taxLinks.isEmpty()) insert taxLinks;

    List<Cost_Pricing_Association__c> updates = new List<Cost_Pricing_Association__c>();
    for (Id pid : pricingTaxSums.keySet()) {
        updates.add(new Cost_Pricing_Association__c(
            Id = pid,
            Tax_Amount__c = pricingTaxSums.get(pid)
        ));
    }

    if (!updates.isEmpty()) update updates;
}

    public class PayloadWrapper {
        public TemplateWrapper template;
        public List<String> unitCodes;
        public List<PricingRowWrapper> pricingRows;
    }

    public class TemplateWrapper {
        public Id companyId;
        public Id projectId;
        public String templateCode;
        public String templateName;
        public Boolean active;
    }

    public class PricingRowWrapper {
        public String pricingElementMaster;
        public String pricingElementAlloc;
        public String unit;
        public String peType;
        public String peGroup;
        public String type;
        public Integer sequence;
        public Decimal quantity;
        public Decimal rate;
        public String taxType;
        public String taxName;
        public Decimal appPercent;
        public Decimal taxPercent;
    }

    public class TaxInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal taxPercent;
        @AuraEnabled public String taxType;
    }
}