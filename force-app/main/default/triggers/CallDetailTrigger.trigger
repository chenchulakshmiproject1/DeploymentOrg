trigger CallDetailTrigger on Call_Detail__c (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        CallDetailTriggerHandler.afterInsert(Trigger.new);
    }
}