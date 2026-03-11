public with sharing class BulkPaymentSchemeController {
    public class DataWrapper {
        @AuraEnabled public Map<String, Id> companyMap;
        @AuraEnabled public Map<String, Id> projectMap;
        @AuraEnabled public Map<String, Id> blockMap;
        @AuraEnabled public Map<String, Id> scheduleMasterMap;
        @AuraEnabled public List<String> installmentTypes;
    }
@AuraEnabled(cacheable=true)
public static List<Payment_Scheme__c> getPaymentSchemes() {
    return [
        SELECT Id, Name, project__c, Company__r.Name, Project__r.Name,Block__r.Name,Token_Amount__c, From_Date__c,To_Date__c FROM Payment_Scheme__c ORDER BY CreatedDate DESC
    ];
}
    @AuraEnabled(cacheable=true)
    public static DataWrapper fetchDataOnLoad() {

        DataWrapper w = new DataWrapper();
        w.companyMap = new Map<String, Id>();
        w.projectMap = new Map<String, Id>();
        w.blockMap = new Map<String, Id>();
        w.scheduleMasterMap = new Map<String, Id>();
        w.installmentTypes = new List<String>();

        for (Company__c c : [SELECT Id, Name FROM Company__c]) {
            w.companyMap.put(c.Name.toLowerCase(), c.Id);
        }

        for (Project__c p : [SELECT Id, Name FROM Project__c]) {
            w.projectMap.put(p.Name.toLowerCase(), p.Id);
        }

        for (Tower__c t : [SELECT Id, Name FROM Tower__c]) {
            w.blockMap.put(t.Name.toLowerCase(), t.Id);
        }

        for (Payment_Schedule_Master__c psm :
            [SELECT Id, Name FROM Payment_Schedule_Master__c]
        ) {
            w.scheduleMasterMap.put(psm.Name.toLowerCase(), psm.Id);
        }

        for (Schema.PicklistEntry pe :
            Payment_Scheme_Installment__c.Type__c
                .getDescribe()
                .getPicklistValues()
        ) {
            if (pe.isActive()) {
                w.installmentTypes.add(pe.getValue());
            }
        }

        return w;
    }

    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) return null;

        List<String> p = dateStr.split('-'); 
        return Date.newInstance(
            Integer.valueOf(p[2]),
            Integer.valueOf(p[1]),
            Integer.valueOf(p[0])
        );
    }

   @AuraEnabled
public static void createPaymentSchemes(String recordsJson) {

    if (String.isBlank(recordsJson)) {
        throw new AuraHandledException('No data received');
    }

    List<Object> payload =
        (List<Object>) JSON.deserializeUntyped(recordsJson);

    Set<String> incomingKeys = new Set<String>();

    /* ---------------- CHECK DUPLICATES IN DB ---------------- */

    for (Object obj : payload) {

        Map<String, Object> s = (Map<String, Object>) obj;

        String uniqueKey =
            String.valueOf(s.get('companyId')) + '|' +
            String.valueOf(s.get('projectId')) + '|' +
            String.valueOf(s.get('blockId')) + '|' +
            ((String) s.get('name')).toLowerCase();

        incomingKeys.add(uniqueKey);
    }

    List<Payment_Scheme__c> existingSchemes = [
        SELECT Id, Company__c, Project__c, Block__c, Name
        FROM Payment_Scheme__c
        WHERE Company__c != null
        AND Project__c != null
        AND Block__c != null
    ];

    Set<String> existingKeys = new Set<String>();

    for (Payment_Scheme__c ps : existingSchemes) {
        existingKeys.add(
            ps.Company__c + '|' +
            ps.Project__c + '|' +
            ps.Block__c + '|' +
            ps.Name.toLowerCase()
        );
    }

    for (String k : incomingKeys) {
        if (existingKeys.contains(k)) {
            throw new AuraHandledException(
                'Duplicate Payment Scheme already exists. ' +
                'Company + Project + Block + Scheme Name must be unique.'
            );
        }
    }

    /* ---------------- INSERT SCHEMES ---------------- */

    List<Payment_Scheme__c> schemes = new List<Payment_Scheme__c>();

    for (Object obj : payload) {

        Map<String, Object> s = (Map<String, Object>) obj;

        schemes.add(new Payment_Scheme__c(
            Name            = (String) s.get('name'),
            Company__c      = (Id) s.get('companyId'),
            Project__c      = (Id) s.get('projectId'),
            Block__c        = (Id) s.get('blockId'),
            Token_Amount__c = (Decimal) s.get('tokenAmount'),
            From_Date__c    = parseDate((String) s.get('fromDate')),
            To_Date__c      = parseDate((String) s.get('toDate'))
        ));
    }

    insert schemes;

    /* ---------------- INSERT INSTALLMENTS (SAFE) ---------------- */

    Map<String, Id> schemeIdByName = new Map<String, Id>();

    for (Payment_Scheme__c ps : schemes) {
        schemeIdByName.put(ps.Name, ps.Id);
    }

    List<Payment_Scheme_Installment__c> installments =
        new List<Payment_Scheme_Installment__c>();

    for (Object obj : payload) {

        Map<String, Object> s = (Map<String, Object>) obj;

        Id schemeId = schemeIdByName.get((String) s.get('name'));

        if (s.containsKey('installments') &&
            s.get('installments') != null) {

            for (Object o : (List<Object>) s.get('installments')) {

                Map<String, Object> row = (Map<String, Object>) o;

                installments.add(new Payment_Scheme_Installment__c(
                    Payment_Scheme__c = schemeId,
                    Payment_Schedule_Master__c =
                        (Id) row.get('scheduleMasterId'),
                    Type__c = (String) row.get('type'),
                    Installment__c = (Decimal) row.get('percentage'),
                    Display_Order__c = (Integer) row.get('displayOrder')
                ));
            }
        }
    }

    if (!installments.isEmpty()) {
        insert installments;
    }
}
}