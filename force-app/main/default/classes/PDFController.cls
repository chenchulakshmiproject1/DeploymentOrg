public with sharing class PDFController {

    /* ---------------- DEMAND LETTER VARIABLES ---------------- */

    public String customerName {get;set;}
    public String mobileNo {get;set;}
    public String subject {get;set;}
    public Decimal totalScheduleAmount {get;set;}
    public String currentUser {get;set;}
    public String bankName {get;set;}
    public String accountNo {get;set;}
    public String ifscCode {get;set;}
    public Date dueDate {get;set;}

    public List<ScheduleWrapper> paymentSchedules {get;set;}

    /* ---------------- STATEMENT VARIABLES ---------------- */

    public String projectName {get;set;}
    public String unitNo {get;set;}
    public String towerCode {get;set;}
    public String customerAddress {get;set;}

    public Decimal totalBilled {get;set;}
    public Decimal totalReceived {get;set;}
    public Decimal totalBalance {get;set;}
    public Decimal totalReceiptAmount {get;set;}

    public List<StatementScheduleWrapper> statementSchedules {get;set;}
    public List<StatementReceiptWrapper> statementReceipts {get;set;}

    /* ---------------- DEMAND LETTER CONSTRUCTOR ---------------- */

    public PDFController(){

        totalScheduleAmount = 0;
        paymentSchedules = new List<ScheduleWrapper>();

        Id oppId = ApexPages.currentPage().getParameters().get('id');

        List<Opportunity> oppList = [
            SELECT Id, Phone__c, Account.Name
            FROM Opportunity
            WHERE Id = :oppId
            LIMIT 1
        ];

        if(!oppList.isEmpty()){

            Opportunity opp = oppList[0];

            customerName = opp.Account != null ? opp.Account.Name : '';
            mobileNo = opp.Phone__c;
            subject = 'Pending Payment Schedules for Constructed Floor';
            currentUser = UserInfo.getName();
        }

        List<Payment_Schedule__c> schedules = [
            SELECT Name, Installment__c, Due_Date__c, Agreement_Value__c, Tax_Amount__c
            FROM Payment_Schedule__c
            WHERE Opportunity__c = :oppId
        ];

        for(Payment_Schedule__c s : schedules){

            ScheduleWrapper w = new ScheduleWrapper();

            w.name = s.Name;
            w.percent = s.Installment__c;
            w.dueDate = s.Due_Date__c;
            w.amount = s.Agreement_Value__c;
            w.tax = s.Tax_Amount__c;

            w.total = (s.Agreement_Value__c == null ? 0 : s.Agreement_Value__c)
                    + (s.Tax_Amount__c == null ? 0 : s.Tax_Amount__c);

            totalScheduleAmount += w.total;

            paymentSchedules.add(w);
        }
        List<SNN_Bank_Details__c> bankDetails = [
        SELECT Name,Bank_Name__c, Account_Number__c, IFSC_Code__c
        FROM SNN_Bank_Details__c
        LIMIT 1
    ];

    if(!bankDetails.isEmpty()){
        bankName = bankDetails[0].Name;
        accountNo = bankDetails[0].Account_Number__c;
        ifscCode = bankDetails[0].IFSC_Code__c;
    }

    dueDate = Date.today().addDays(7);
    }
    
    /* ---------------- STATEMENT OF ACCOUNT METHOD ---------------- */

   public void loadStatementData(){

    statementSchedules = new List<StatementScheduleWrapper>();
    statementReceipts = new List<StatementReceiptWrapper>();

    totalBilled = 0;
    totalReceived = 0;
    totalBalance = 0;
    totalReceiptAmount = 0;

    Id oppId = ApexPages.currentPage().getParameters().get('id');

    /* ---------------- OPPORTUNITY ---------------- */

    Opportunity opp = [
        SELECT Id,
            Account.Name,
            Account.Permanent_Address__Street__s,
            Account.Permanent_Address__City__s,
            Account.Permanent_Address__StateCode__s,
            Account.Permanent_Address__PostalCode__s,
            Project__r.Name,
            Unit__r.Name,
            Unit__r.Floor__r.Blocks__r.Tower_Code__c
        FROM Opportunity
        WHERE Id = :oppId
        LIMIT 1
    ];

    customerName = opp.Account != null ? opp.Account.Name : '';
    projectName = opp.Project__r != null ? opp.Project__r.Name : '';
    unitNo = opp.Unit__r != null ? opp.Unit__r.Name : '';

    towerCode =
        (opp.Unit__r != null &&
         opp.Unit__r.Floor__r != null &&
         opp.Unit__r.Floor__r.Blocks__r != null)
        ? opp.Unit__r.Floor__r.Blocks__r.Tower_Code__c
        : '';

    customerAddress =
        (opp.Account.Permanent_Address__Street__s != null ? opp.Account.Permanent_Address__Street__s + ', ' : '') +
        (opp.Account.Permanent_Address__City__s != null ? opp.Account.Permanent_Address__City__s + ', ' : '') +
        (opp.Account.Permanent_Address__StateCode__s != null ? opp.Account.Permanent_Address__StateCode__s + ', ' : '') +
        (opp.Account.Permanent_Address__PostalCode__s != null ? opp.Account.Permanent_Address__PostalCode__s : '');

    /* ---------------- PAYMENT SCHEDULE ---------------- */

    List<Payment_Schedule__c> schedules = [
        SELECT Id, Name, Agreement_Value__c
        FROM Payment_Schedule__c
        WHERE Opportunity__c = :oppId
    ];

    /* ---------------- DEMAND LETTERS ---------------- */

    List<Demand_Letter__c> demandLetters = [
        SELECT Id,
               Payment_Schedule__c,
               Amount_Balance__c,
               Amount_Received__c,
               Total_Due_Amount__c
        FROM Demand_Letter__c
        WHERE Payment_Schedule__c IN :schedules
    ];

    Map<Id, List<Demand_Letter__c>> demandMap = new Map<Id, List<Demand_Letter__c>>();

    for(Demand_Letter__c dl : demandLetters){

        if(!demandMap.containsKey(dl.Payment_Schedule__c)){
            demandMap.put(dl.Payment_Schedule__c, new List<Demand_Letter__c>());
        }

        demandMap.get(dl.Payment_Schedule__c).add(dl);
    }

    /* ---------------- BUILD SCHEDULE DATA ---------------- */

    for(Payment_Schedule__c p : schedules){

        StatementScheduleWrapper sw = new StatementScheduleWrapper();

        sw.particular = p.Name;
        sw.totalBilled = p.Agreement_Value__c != null ? p.Agreement_Value__c : 0;
        sw.amountReceived = 0;
        sw.amountBalance = 0;

        if(demandMap.containsKey(p.Id)){

            for(Demand_Letter__c dl : demandMap.get(p.Id)){

                sw.amountReceived += dl.Amount_Received__c != null ? dl.Amount_Received__c : 0;
                sw.amountBalance += dl.Total_Due_Amount__c != null ? dl.Total_Due_Amount__c : 0;
            }
        }

        totalBilled += sw.totalBilled;
        totalReceived += sw.amountReceived;
        totalBalance += sw.amountBalance;

        statementSchedules.add(sw);
    }

    /* ---------------- RECEIPTS ---------------- */

    List<Receipt__c> receipts = [
        SELECT Receipt_Number__c,
               Receipt_Date__c,
               Mode_Of_Payment__c,
               Bank__c,
               Amount__c
        FROM Receipt__c
        WHERE Opportunity__c = :oppId
    ];

    for(Receipt__c r : receipts){

        StatementReceiptWrapper rw = new StatementReceiptWrapper();

        rw.receiptNo = r.Receipt_Number__c;
        rw.receiptDate = r.Receipt_Date__c;
        rw.paymentCategory = r.Mode_Of_Payment__c;
        rw.bankName = r.Bank__c;
        rw.amount = r.Amount__c != null ? r.Amount__c : 0;

        totalReceiptAmount += rw.amount;

        statementReceipts.add(rw);
    }
}

    /* ---------------- WRAPPERS ---------------- */

    public class ScheduleWrapper{
        public String name {get;set;}
        public Decimal percent {get;set;}
        public Date dueDate {get;set;}
        public Decimal amount {get;set;}
        public Decimal tax {get;set;}
        public Decimal total {get;set;}
    }

    public class StatementScheduleWrapper{
        public String particular {get;set;}
        public Decimal totalBilled {get;set;}
        public Decimal amountReceived {get;set;}
        public Decimal amountBalance {get;set;}
    }

    public class StatementReceiptWrapper{
        public String receiptNo {get;set;}
        public Date receiptDate {get;set;}
        public String paymentCategory {get;set;}
        public String bankName {get;set;}
        public Decimal amount {get;set;}
    }
    @AuraEnabled
public static String generateStatementAndStore(Id oppId){

    Opportunity opp = [
        SELECT Id,
        (SELECT Id, Document_Id__c FROM Documents__r WHERE Name = 'Post Sales' LIMIT 1)
        FROM Opportunity
        WHERE Id = :oppId
        LIMIT 1
    ];

    Id postSalesDocId;

    if(opp.Documents__r != null && !opp.Documents__r.isEmpty()){
        postSalesDocId = opp.Documents__r[0].Id;
    }

    PageReference pdfPage = Page.StatementOfAccountPDF;
    pdfPage.getParameters().put('id', oppId);

    Blob pdfBody = pdfPage.getContentAsPDF();

    String fileName = 'StatementOfAccount_' + System.now().format('yyyyMMddHHmmss') + '.pdf';

    ContentVersion cv = new ContentVersion();
    cv.Title = fileName;
    cv.PathOnClient = fileName;
    cv.VersionData = pdfBody;
    insert cv;

    ContentVersion insertedCV = [
        SELECT ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
    ];

    ContentDocumentLink cdl = new ContentDocumentLink();
    cdl.ContentDocumentId = insertedCV.ContentDocumentId;

    /* 🔴 LINK TO POST SALES FOLDER */
    if(postSalesDocId != null){
        cdl.LinkedEntityId = postSalesDocId;
    }else{
        cdl.LinkedEntityId = oppId;
    }

    cdl.ShareType = 'V';
    cdl.Visibility = 'AllUsers';

    insert cdl;

    return insertedCV.ContentDocumentId;
}
@AuraEnabled
public static void sendStatementEmail(Id oppId){

    Opportunity opp = [
        SELECT Id, Name, Email__c
        FROM Opportunity
        WHERE Id = :oppId
        LIMIT 1
    ];

    PageReference pdfPage = Page.StatementOfAccountPDF;
    pdfPage.getParameters().put('id', oppId);

    Blob pdfBody = pdfPage.getContentAsPDF();

    Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
    attachment.setFileName('StatementOfAccount.pdf');
    attachment.setBody(pdfBody);
    attachment.setContentType('application/pdf');

    Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();

    email.setToAddresses(new String[] { opp.Email__c });
    email.setSubject('Statement Of Account');
    email.setPlainTextBody('Please find the attached Statement of Account.');

    email.setFileAttachments(new Messaging.EmailFileAttachment[] { attachment });

    Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
}
}