public without sharing class receiptTriggerHandler {
    public static void generateDoc(List<Receipt__c> newRecords, Map<Id, Receipt__c> oldMap){
        if(!newRecords.isEmpty()){
            List<String> rcptIds = new List<String>();
            for(Receipt__c rcpt : newRecords){ 
                if(rcpt.Approval_Status__c == 'Approved' && oldMap.get(rcpt.Id).Approval_Status__c != 'Approved'){
                    rcptIds.add(rcpt.Id);
                }
            }
            if(!rcptIds.isEmpty()){
                QueueableToGenerateDocDigio queueable = new QueueableToGenerateDocDigio(rcptIds);
                System.enqueueJob(queueable);
            }
        }
    }
    
    public static void updtRcpdAmtOnPymntSchedule(List<Receipt__c> newRecords, Map<Id, Receipt__c> oldMap) {
        System.debug('newRecords==>'+newRecords);
        System.debug('oldMap==>'+oldMap);
        if(newRecords == null || newRecords.isEmpty()){
            return;
        }
        List<Tax_Invoice__c> taxInvoicesToInsert = new List<Tax_Invoice__c>();
        Map<Id, Receipt__c> oppToReceiptMap = new Map<Id, Receipt__c>();
        Map<Id, Receipt__c> oppToReceiptOldMap = new Map<Id, Receipt__c>();
        for(Receipt__c rcpt : newRecords){
            Receipt__c oldRcpt = oldMap.get(rcpt.Id);
            if(rcpt.Amount__c != null &&
               oldRcpt != null &&
               rcpt.Approval_Status__c != oldRcpt.Approval_Status__c &&
               rcpt.Approval_Status__c == 'Approved' && rcpt.Opportunity__c != null) {
                   oppToReceiptMap.put(rcpt.Opportunity__c, rcpt);
               }else if(rcpt.Amount__c != null &&
                        oldRcpt != null &&rcpt.Approval_Status__c == 'Approved' && rcpt.Opportunity__c != null &&  rcpt.Opportunity__c != oldRcpt.Opportunity__c){
                            oppToReceiptMap.put(rcpt.Opportunity__c, rcpt);
                            oppToReceiptOldMap.put(oldRcpt.Opportunity__c, rcpt);
                        }
        }
        
        if(oppToReceiptMap.isEmpty()){
            return;
        }
        List<Payment_Schedule__c> paymentSchedules = [
            SELECT Id, Agreement_Value__c, Total_Amount_Inclusive_Of_Tax__c, Opportunity__c, Tax_Amount__c, Installment_Sequence__c, Total_Received_Amount__c, Total_Due_Amount__c,Opportunity__r.AccountId,Tax_Invoice_Created__c  
            FROM Payment_Schedule__c 
            WHERE Opportunity__c IN :oppToReceiptMap.keySet() 
            ORDER BY Installment_Sequence__c
        ];
        if(paymentSchedules.isEmpty()){
            return;
        }
        Map<Id, List<Payment_Schedule__c>> oppToPaymentSchedules = new Map<Id, List<Payment_Schedule__c>>();
        for(Payment_Schedule__c ps : paymentSchedules) {
            if(!oppToPaymentSchedules.containsKey(ps.Opportunity__c)){
                oppToPaymentSchedules.put(ps.Opportunity__c, new List<Payment_Schedule__c>());
            }
            oppToPaymentSchedules.get(ps.Opportunity__c).add(ps);
        }
        List<Payment_Schedule__c> psToUpdate = new List<Payment_Schedule__c>();
        for(Receipt__c rcpt : oppToReceiptMap.values()){
            Decimal rcptAmt = rcpt.Amount__c;
            List<Payment_Schedule__c> psList = oppToPaymentSchedules.get(rcpt.Opportunity__c);
            if(psList == null || psList.isEmpty()){
                continue;
            }
            for(Payment_Schedule__c ps : psList){
                if(rcptAmt <= 0 || ps.Total_Due_Amount__c <= 0) {
                    continue;
                }
                Decimal previousReceivedAmount =  ps.Total_Received_Amount__c != null ? ps.Total_Received_Amount__c : 0;
                ps.Total_Received_Amount__c = (rcptAmt >= ps.Total_Due_Amount__c) ? ps.Total_Amount_Inclusive_Of_Tax__c : ((ps.Total_Received_Amount__c != null ? ps.Total_Received_Amount__c : 0) + rcptAmt);
                rcptAmt = (rcptAmt >= ps.Total_Due_Amount__c) ? rcptAmt - ps.Total_Due_Amount__c : 0;
                Decimal newRecivedAmount = ps.Total_Received_Amount__c - previousReceivedAmount;
                psToUpdate.add(ps);
                
                
                // Tax Generation Logic
                if(!ps.Tax_Invoice_Created__c){
                Tax_Invoice__c newTaxInv  = new Tax_Invoice__c();
                
                newTaxInv.Payment_Schedule__c = ps.Id;
                newTaxInv.Opportunity__c	 = ps.Opportunity__c;
                newTaxInv.Account__c	 = ps.Opportunity__r.AccountId;
                newTaxInv.Receipt__c	 = rcpt.Id;
                
                Decimal agreementValue   = ps.Agreement_Value__c != null ? ps.Agreement_Value__c : 0;
                Decimal taxAmount        = ps.Tax_Amount__c != null ? ps.Tax_Amount__c : 0;
                Decimal totalAmount      = ps.Total_Amount_Inclusive_Of_Tax__c != null ? ps.Total_Amount_Inclusive_Of_Tax__c : 0;
                Decimal receivedAmount   = newRecivedAmount != null ? newRecivedAmount : 0;
                
                Decimal taxForReceivedAmount = 0;
                
                if (totalAmount > 0) {
                    taxForReceivedAmount = (receivedAmount * taxAmount) / totalAmount;
                }
                
                newTaxInv.Received_Amount__c = receivedAmount;
                //   newTaxInv.SGST__c = taxForReceivedAmount/2;
                //   newTaxInv.CGST__c = taxForReceivedAmount/2;
                
                taxInvoicesToInsert.add(newTaxInv);
                if(rcptAmt == 0){
                    break;
                }
                }
            }
        }
        if(!psToUpdate.isEmpty()){
            update psToUpdate;
            System.debug('Payment Schedule records updated successfully');
        }
        if(!taxInvoicesToInsert.isEmpty()){
            insert taxInvoicesToInsert;
            
        }
        
        if(!oppToReceiptOldMap.isEmpty()){
            System.debug('oppToReceiptOldMap==>'+oppToReceiptOldMap);
            List<Payment_Schedule__c> paymentSchedulesOld = [
                SELECT Id, Agreement_Value__c, Total_Amount_Inclusive_Of_Tax__c, Opportunity__c, Tax_Amount__c, Installment_Sequence__c, Total_Received_Amount__c, Total_Due_Amount__c 
                FROM Payment_Schedule__c 
                WHERE Opportunity__c IN :oppToReceiptOldMap.keySet() 
                ORDER BY Installment_Sequence__c 
            ];
            if(paymentSchedulesOld.isEmpty()){
                return;
            }
            Map<Id, List<Payment_Schedule__c>> oppToPaymentSchedules1 = new Map<Id, List<Payment_Schedule__c>>();
            for(Payment_Schedule__c ps : paymentSchedulesOld) {
                if(!oppToPaymentSchedules1.containsKey(ps.Opportunity__c)){
                    oppToPaymentSchedules1.put(ps.Opportunity__c, new List<Payment_Schedule__c>());
                }
                oppToPaymentSchedules1.get(ps.Opportunity__c).add(ps);
            }
            System.debug('oppToPaymentSchedules1==>'+oppToPaymentSchedules1);
            List<Payment_Schedule__c> psToUpdateoldOpp = new List<Payment_Schedule__c>();
            
            Map<Id, List<Receipt__c>> receiptsList = new Map<Id, List<Receipt__c>>();
            if(oppToPaymentSchedules1.keySet() != null){
                List<Receipt__c> allReceipts = [select Id,Opportunity__c,Amount__c from Receipt__c Where Opportunity__c In:oppToPaymentSchedules1.keySet()];
                for(Receipt__c rs : allReceipts) {
                if(!receiptsList.containsKey(rs.Opportunity__c)){
                    receiptsList.put(rs.Opportunity__c, new List<Receipt__c>());
                }
                receiptsList.get(rs.Opportunity__c).add(rs);
            }
            
            }
            
            
            
            
            
            for(Id oppId : oppToPaymentSchedules1.keySet()){
                List<Payment_Schedule__c> psList1 = oppToPaymentSchedules1.get(oppId);
                List<Receipt__c> receipts =  receiptsList.get(oppId);
                Decimal totalAmount = 0;
                System.debug('receipts==?'+receipts);
                if(receipts != null && !receipts.isEmpty() ){
                    
                    for(Receipt__c recp : receipts){
                        totalAmount += recp.Amount__c;
                    }
                    
                        for(Payment_Schedule__c ps : psList1){
                            ps.Total_Received_Amount__c = (totalAmount >= ps.Total_Due_Amount__c) ? ps.Total_Amount_Inclusive_Of_Tax__c : ((ps.Total_Received_Amount__c != null ? ps.Total_Received_Amount__c : 0) + totalAmount);
                            totalAmount = (totalAmount >= ps.Total_Due_Amount__c) ? totalAmount - ps.Total_Due_Amount__c : 0;
                            psToUpdateoldOpp.add(ps);
                            if(totalAmount == 0){
                                break;
                            }
                        }
                    
                }else{
                    System.debug('psList1==>'+psList1);
                    for(Payment_Schedule__c ps : psList1){
                            ps.Total_Received_Amount__c = 0;
                            
                            psToUpdateoldOpp.add(ps);

                        }
                    
                }
                
            }
            
            
            System.debug('psToUpdateoldOpp==>'+psToUpdateoldOpp);
            if(!psToUpdateoldOpp.isEmpty()){
                update psToUpdateoldOpp;
                System.debug('Payment Schedule records updated successfully');
            }
            
        }
    }
}