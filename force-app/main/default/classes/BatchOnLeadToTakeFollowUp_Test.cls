@isTest
public class BatchOnLeadToTakeFollowUp_Test {
    
    @testSetup
    static void setupTestData() {
        User testUser = [SELECT Id, Email FROM User WHERE IsActive = true LIMIT 1];
        System.debug('testUser.Email ===> ' + testUser.Email);
        Company__c company = new Company__c(Name = 'TestCompany');
        insert company;
        Project__c newProject = new Project__c(Name = 'Test Project', Company__c = company.Id);
        insert newProject;
        
        Lead lead1 = new Lead(
            LastName = 'Lead One',
            Company = 'Test Company 1',
            IsConverted = false,
            Is_User_Assigned__c = true,
            Lead_Assigned_Date_Time__c = Datetime.newInstance(2025, 8, 28, 14, 30, 0), 
            OwnerId = testUser.Id,
            Project__c = newProject.Id
        );
        
        Lead lead2 = new Lead(
            LastName = 'Lead Two',
            Company = 'Test Company 2',
            IsConverted = false,
            Is_User_Assigned__c = true,
            Lead_Assigned_Date_Time__c = DateTime.now().addMinutes(-200),
            OwnerId = testUser.Id,
            Project__c = newProject.Id
        );
        
        Lead lead3 = new Lead(
            LastName = 'Lead Three',
            Company = 'Test Company 3',
            IsConverted = false,
            Is_User_Assigned__c = true,
            Lead_Assigned_Date_Time__c = DateTime.now().addDays(-1),
            OwnerId = testUser.Id,
            Project__c = newProject.Id
        );
        
        insert lead1;
        insert lead2;
        insert lead3;
        
        Task task1 = new Task(
            Subject = 'Take First Follow Up with Customer - Within 4 Hours',
            Status = 'Open',
            WhoId = lead1.Id,
            OwnerId = testUser.Id
        );
        
        Task task2 = new Task(
            Subject = 'CTI Task - Customer Follow-up',
            Status = 'Open',
            Customer_Status__c = 'in progress',
            Agent_Status__c = 'in progress',
            WhoId = lead1.Id,
            OwnerId = testUser.Id
        );
        
        Task task3 = new Task(
            Subject = 'Take First Follow Up with Customer - Within 24 Hours',
            Status = 'Open',
            WhoId = lead2.Id,
            OwnerId = testUser.Id
        );
        
        Task task4 = new Task(
            Subject = 'CTI Task - Follow-up',
            Status = 'Completed',
            Customer_Status__c = 'completed',
            Agent_Status__c = 'completed',
            WhoId = lead3.Id,
            OwnerId = testUser.Id
        );
        
        insert new List<Task>{ task1, task2, task3, task4 };
            
            User_Tracking__c todayTracking = new User_Tracking__c(
                Member__c = testUser.Id,
                Checkin_Datetime__c = Date.today(),
                Checkout_Datetime__c = null
            );
        
        User_Tracking__c previousTracking = new User_Tracking__c(
            Member__c = testUser.Id,
            Checkin_Datetime__c = Date.today().addDays(-1),
            Checkout_Datetime__c = DateTime.now().addDays(-1).addHours(5)
        );
        Test.startTest();
        insert new List<User_Tracking__c>{ todayTracking, previousTracking };
            Test.stopTest();
        
        
    }
    
    @isTest
    static void testBatchExecution() {
        Test.startTest();
        
        BatchOnLeadToTakeFollowUp batch = new BatchOnLeadToTakeFollowUp();
        Database.executeBatch(batch);
        
        Test.stopTest();
        
        List<Task> followUpTasks = [
            SELECT Id, Subject, WhoId, Status
            FROM Task
            WHERE Subject IN ('Take First Follow Up with Customer - Within 24 Hours', 'Take Follow Up with Customer')
        ];
        
        List<Task> updatedTasks = [
            SELECT Id, Subject, Status
            FROM Task
            WHERE Status = 'Completed'
        ];
        
        Integer sentEmails = Limits.getEmailInvocations();
    }
    
    
}