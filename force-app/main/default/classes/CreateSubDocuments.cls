public with sharing class CreateSubDocuments {

@AuraEnabled
public static String generateAndStorePDF(Id oppId){

    try{
        System.debug('oppid---->'+oppId);
        Document__c postSalesDoc = [
            SELECT Id, Document_Id__c
            FROM Document__c
            WHERE Opportunity__c =: oppId
            AND Name = 'Post Sales'
            LIMIT 1
        ];

        if(postSalesDoc == null){
            throw new AuraHandledException('Post Sales folder not found');
        }

        PageReference pageRef = Page.GenerateAllotmentLetterVFPage;
        pageRef.getParameters().put('id', oppId);

        Blob pdfBlob = pageRef.getContentAsPDF();

        String fileName = 'AllotmentLetter_'+System.currentTimeMillis()+'.pdf';

        String base64Data = EncodingUtil.base64Encode(pdfBlob);

        Integer size = pdfBlob.size();

        String contentRange = 'bytes 0-' + (size-1) + '/' + size;

        GoogleDriveAPI.wrapperForResponse res =
        GoogleDriveAPI.uploadFileToGoogleDrive(
            fileName,
            'application/pdf',
            postSalesDoc.Document_Id__c,
            base64Data,
            contentRange,
            postSalesDoc.Id
        );

        return res.subDocUrl;

    }
    catch(Exception e){
        throw new AuraHandledException(e.getMessage());
    }

}


@AuraEnabled
public static void sendAllotmentEmail(Id oppId){

    Opportunity opp = [
        SELECT Id, Name, Email__c
        FROM Opportunity
        WHERE Id = :oppId
        LIMIT 1
    ];

    if(opp.Email__c == null){
        throw new AuraHandledException('Opportunity Email not found');
    }

    // Generate PDF
    PageReference pageRef = Page.GenerateAllotmentLetterVFPage;
    pageRef.getParameters().put('id', oppId);

    Blob pdfBlob = pageRef.getContentAsPDF();

    // Create Email
    Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

    mail.setToAddresses(new String[]{opp.Email__c});
    mail.setSubject('Allotment Letter');
    mail.setPlainTextBody('Please find your allotment letter attached.');

    // Create Attachment
    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
    attachment.setFileName('AllotmentLetter.pdf');
    attachment.setBody(pdfBlob);
    attachment.setContentType('application/pdf');

    mail.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });

    Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });

}

}