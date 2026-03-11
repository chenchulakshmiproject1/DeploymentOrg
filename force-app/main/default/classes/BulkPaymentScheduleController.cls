public with sharing class BulkPaymentScheduleController {
@AuraEnabled(cacheable=true)
    public static DataWrapper fetchDataOnLoad() {

        DataWrapper wrap = new DataWrapper();

        wrap.existingRecords = new List<Payment_Schedule_Master__c>();

        for (Payment_Schedule_Master__c rec : [ SELECT Id, Name, Installment_Code__c, Installment_Sequence__c  FROM Payment_Schedule_Master__c
            ORDER BY CreatedDate DESC
        ]) {
            wrap.existingRecords.add(rec);
        }

        wrap.existingInstallmentCodes = new Set<String>();

        for (Payment_Schedule_Master__c rec : wrap.existingRecords) {
            if (rec.Installment_Code__c != null) {
                wrap.existingInstallmentCodes.add(
                    rec.Installment_Code__c.toLowerCase()
                );
            }
        }

        return wrap;
    }


    @AuraEnabled
    public static String createPaymentSchedules(
        List<String> headers,
        List<List<Object>> data
    ) {
        try {

            List<Payment_Schedule_Master__c> recordsToInsert =
                new List<Payment_Schedule_Master__c>();

            for (List<Object> row : data) {

                if (row == null || row.isEmpty()) continue;

                Payment_Schedule_Master__c rec =
                    new Payment_Schedule_Master__c();

                for (Integer i = 0; i < headers.size(); i++) {

                    String fieldApi = headers[i];
                    Object rawVal = row[i];

                    if (rawVal == null) continue;

                    if (fieldApi == 'Name') {
                        rec.Name = String.valueOf(rawVal);
                    }
                    else if (fieldApi == 'Installment_Code__c') {
                        rec.Installment_Code__c =
                            String.valueOf(rawVal);
                    }
                    else if (fieldApi == 'Installment_Sequence__c') {
                        rec.Installment_Sequence__c =
                            Integer.valueOf(String.valueOf(rawVal));
                    }
                  
                }

                recordsToInsert.add(rec);
            }

            if (!recordsToInsert.isEmpty()) {
                insert recordsToInsert;
            }

            return 'success';

        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }


    /* ================= WRAPPER ================= */
public class DataWrapper {

    @AuraEnabled public List<Payment_Schedule_Master__c> existingRecords {get;set;}
    @AuraEnabled public Set<String> existingInstallmentCodes {get;set;}

}
}