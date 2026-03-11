@isTest
public class ContentVersionHandlerTest {

    private static ContentVersion createTestContentVersion() {
        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'TestFile.pdf',
            VersionData = Blob.valueOf('Test Content'),
            IsMajorVersion = true
        );
        insert cv;

        return [SELECT Id, ContentDocumentId, SharingPrivacy FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];
    }

    @isTest
    static void testPublicizeFiles() {
        Test.startTest();
        ContentVersion cv = createTestContentVersion();

        List<ContentVersion> cvList = new List<ContentVersion>{cv};

        ContentVersionHandler handler = new ContentVersionHandler();
        handler.publicizeFiles(cvList);

        System.assertEquals('P', cvList[0].SharingPrivacy, 'File should be made public');
        Test.stopTest();
    }

    @isTest
    static void testCreateConDocLink() {
        Test.startTest();
        ContentVersion cv = createTestContentVersion();

        List<ContentVersion> cvList = new List<ContentVersion>{cv};
        ContentVersionHandler handler = new ContentVersionHandler();
        handler.createConDocLink(cvList);

        List<ContentDistribution> dists = [
            SELECT Id, Name, ContentVersionId
            FROM ContentDistribution
            WHERE ContentVersionId = :cv.Id
        ];
        System.assertEquals(1, dists.size(), 'ContentDistribution should be created');

      
        List<ContentDocumentLink> links = [
            SELECT Id, ContentDocumentId, LinkedEntityId, ShareType
            FROM ContentDocumentLink
            WHERE ContentDocumentId = :cv.ContentDocumentId
        ];
        //System.assertEquals(1, links.size(), 'ContentDocumentLink should be created');
        System.assertEquals('V', links[0].ShareType, 'Share type should be View');
        Test.stopTest();
    }
}