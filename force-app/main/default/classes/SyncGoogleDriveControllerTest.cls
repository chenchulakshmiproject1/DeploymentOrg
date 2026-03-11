@isTest
public class SyncGoogleDriveControllerTest {

    @isTest
    static void testGetAccessToken() {
        // Create a mock GoogleDriveIntegration__c record
        GoogleDriveIntegration__c driveIntegration = new GoogleDriveIntegration__c(
            Name = 'GDrive',
            Refresh_Token__c = 'mockRefreshToken',
            Client_Id__c = 'mockClientId',
            Client_Secret__c = 'mockClientSecret',
            Redirect_URI__c = 'mockRedirectUri'
        );
        insert driveIntegration;

        // Mock the HTTP response for token request
        Test.setMock(HttpCalloutMock.class, new GoogleDriveAccessTokenMock());

        Test.startTest();
        String token = SyncGoogleDriveController.getAccessToken();
        Test.stopTest();

        System.debug('Access Token: ' + token);
    }

    @isTest
    static void testGetFolderId() {
        // Insert metadata for ObjectPrefixMapping__mdt
        ObjectPrefixMapping__mdt prefixMapping = new ObjectPrefixMapping__mdt(
            DeveloperName = 'TestMapping',
            Prefix__c = '001',
            ObjectName__c = 'Account'
        );
        //insert prefixMapping; // Insert the metadata record

        // Insert an Account record
        Account acc = new Account(Name = 'Test Account' );
        insert acc; // Insert a record with a matching folderId__c field
        Company__c company = new Company__c(Name = 'TestCompany');
        insert company;
        Project__c project = new Project__c(Name = 'TestProject',Company__c = company.Id,FolderId__c = 'wewer' );
        insert project;
        Test.startTest();
        try {
            String folderId = SyncGoogleDriveController.getFolderId(project.Id);
            System.debug('Folder ID: ' + folderId);
        } catch (Exception e) {
            System.debug('Exception caught: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void testGetFilesFromDrive() {
        // Insert metadata for ObjectPrefixMapping__mdt
        ObjectPrefixMapping__mdt prefixMapping = new ObjectPrefixMapping__mdt(
            DeveloperName = 'TestMapping',
            Prefix__c = '001',
            ObjectName__c = 'Account'
        );
       // insert prefixMapping;

        // Insert an Account record
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
         Company__c company = new Company__c(Name = 'TestCompany');
        insert company;
        Project__c project = new Project__c(Name = 'TestProject',Company__c = company.Id,FolderId__c = 'wewer' );
        insert project;
        
        //Tridasa_Marketing__c testMarketing = new Tridasa_Marketing__c(Name__c = 'testMarketing');
        //insert testMarketing;

        // Mock the HTTP response for file listing
        Test.setMock(HttpCalloutMock.class, new GoogleDriveFilesMock());

        Test.startTest();
        String result = SyncGoogleDriveController.getFilesFromDrive('mockFolderId', project.Id);
        Test.stopTest();

        System.debug('Result: ' + result);
    }

    // Mock HTTP Callout for Access Token
    private class GoogleDriveAccessTokenMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"access_token": "mockAccessToken",' +
                        '"expires_in": 3600,' +
                        '"token_type": "Bearer"}');
            return res;
        }
    }

    // Mock HTTP Callout for Files from Drive
    private class GoogleDriveFilesMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setBody('{"files": [' +
                        '{"id": "file1", "name": "Document1.pdf", "webViewLink": "https://drive.google.com/file1"},' +
                        '{"id": "file2", "name": "Document2.pdf", "webViewLink": "https://drive.google.com/file2"}]}');
            return res;
        }
    }
}