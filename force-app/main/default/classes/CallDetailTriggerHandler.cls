public class CallDetailTriggerHandler {

    public static void afterInsert(List<Call_Detail__c> newList) {
        if (newList == null || newList.isEmpty()) return;

        Set<Id> leadIds = new Set<Id>();
        for (Call_Detail__c cd : newList) {
            if (cd.Lead__c != null) leadIds.add(cd.Lead__c);
        }
        if (leadIds.isEmpty()) return;

        Map<Id, Lead> leadMap = new Map<Id, Lead>([SELECT Id, Status FROM Lead WHERE Id IN :leadIds AND Status = 'Assigned']);
        if (leadMap.isEmpty()) return;

        Map<Id, Integer> existingCounts = new Map<Id, Integer>();
        for (AggregateResult ar : [SELECT Lead__c leadId, COUNT(Id) cnt FROM Call_Detail__c WHERE Lead__c IN :leadMap.keySet() GROUP BY Lead__c]) {
            existingCounts.put((Id) ar.get('leadId'), (Integer) ar.get('cnt'));
        }

        Map<Id, Integer> insertedThisTxnCount = new Map<Id, Integer>();
        for (Call_Detail__c cd : newList) {
            if (cd.Lead__c == null) continue;
            if (!leadMap.containsKey(cd.Lead__c)) continue; 
            insertedThisTxnCount.put(
                cd.Lead__c,
                (insertedThisTxnCount.containsKey(cd.Lead__c) ? insertedThisTxnCount.get(cd.Lead__c) : 0) + 1
            );
        }

        List<Lead> leadsToUpdate = new List<Lead>();
        for (Id leadId : insertedThisTxnCount.keySet()) {
            Integer totalCnt = existingCounts.containsKey(leadId) ? existingCounts.get(leadId) : 0;
            Integer txnCnt   = insertedThisTxnCount.get(leadId);

            if (totalCnt == txnCnt) {
                Lead l = leadMap.get(leadId);
                l.Status = 'Contacted';
                l.Phone_Conversation_Done__c = true;
                leadsToUpdate.add(l);
            }
        }

        if (!leadsToUpdate.isEmpty()) {
            update leadsToUpdate;
        }
    }
}