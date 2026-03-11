@isTest
public class OpportunityTriggerHandlerTest {
    
    @isTest
    public static void testAfterInsert() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = System.today(),
            AccountId = acc.Id
        );
        insert opp;
        List<Opportunity> oppList = new List<Opportunity>{opp};
            Test.startTest();
        
        
        opportunityTriggerHandler.afterInsert(oppList);
        Test.stopTest();
    }
    
    @isTest
    public static void testApplicantInsert() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            StageName = 'Prospecting',
            CloseDate = System.today(),
            AccountId = acc.Id
        );
        insert opp;
        
        Applicant__c app = new Applicant__c(
            Opportunity__c = opp.Id,
            Account__c = acc.Id
        );
        insert app;
        List<Applicant__c> appList = new List<Applicant__c>{app};
            
            Test.startTest();
        
        
        opportunityTriggerHandler.ApplicantInsert(appList);
        Test.stopTest();
        
    }
}