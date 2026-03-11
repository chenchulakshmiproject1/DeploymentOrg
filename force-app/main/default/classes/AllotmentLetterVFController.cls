public with sharing class AllotmentLetterVFController {

    public String applicantName {get;set;}
    public String coApplicantName {get;set;}
    public String addressName {get;set;}
    public String pinCodeNumber {get;set;}
    public String emailId {get;set;}
    public String phoneNumber {get;set;}

    public String projectName {get;set;}
    public String blockName {get;set;}
    public String floorName {get;set;}
    public String apartmentNo {get;set;}
    public String apartmentTypeName {get;set;}
    public Decimal saleableAreaName {get;set;}
    public String carParkingDetails {get;set;}

    public Decimal totalFlatCost {get;set;}

    public List<PaymentWrapper> paymentScheduleList {get;set;}

    public class PaymentWrapper{
        public Integer SlNo {get;set;}
        public String installment {get;set;}
        public String sequence {get;set;}
        public Decimal amount {get;set;}
    }

    public AllotmentLetterVFController(){

        Id oppId = ApexPages.currentPage().getParameters().get('id');

        paymentScheduleList = new List<PaymentWrapper>();
        carParkingDetails = '';
        totalFlatCost = 0;

        List<Applicant__c> allApplicants = [
            SELECT Id, Account__r.Name
            FROM Applicant__c
            WHERE Opportunity__c =: oppId
        ];

        String coApplicantNames = '';

        for(Applicant__c applicant : allApplicants){
            if(String.isNotBlank(coApplicantNames)){
                coApplicantNames += ' ; ';
            }
            coApplicantNames += applicant.Account__r.Name;
        }

        coApplicantName = coApplicantNames;

        Opportunity oppDetails = [
            SELECT Id, AccountId,
            Project__r.Name,
            Unit__r.Unit_Name__c,
            Unit__r.Unit_Type__c,
            Unit__r.Super_Built_Up_Area_sq_ft__c,
            Unit__r.Floor__r.Blocks__r.Name,
            Unit__r.Floor__r.Floor_No__c
            FROM Opportunity
            WHERE Id =: oppId
            LIMIT 1
        ];

        Account mainApplicant = [
            SELECT Id, Name, Email__c, Phone, Permanent_Address__c
            FROM Account
            WHERE Id =: oppDetails.AccountId
            LIMIT 1
        ];

        applicantName = mainApplicant.Name;
        emailId = mainApplicant.Email__c;
        phoneNumber = mainApplicant.Phone;

        if(mainApplicant.Permanent_Address__c != null){
            System.Address address = mainApplicant.Permanent_Address__c;

            addressName =
                (address.getStreet() != null ? address.getStreet() + ', ' : '') +
                (address.getCity() != null ? address.getCity() + ', ' : '') +
                (address.getState() != null ? address.getState() + ', ' : '') +
                (address.getCountry() != null ? address.getCountry() + ', ' : '') +
                (address.getPostalCode() != null ? address.getPostalCode() : '');

            pinCodeNumber = address.getPostalCode();
        }

        projectName = oppDetails.Project__r.Name;
        blockName = oppDetails.Unit__r.Floor__r.Blocks__r.Name;
        floorName = String.valueOf(oppDetails.Unit__r.Floor__r.Floor_No__c);
        apartmentNo = oppDetails.Unit__r.Unit_Name__c;
        apartmentTypeName = oppDetails.Unit__r.Unit_Type__c;
        saleableAreaName = oppDetails.Unit__r.Super_Built_Up_Area_sq_ft__c;

        List<Cost_Sheet__c> finalizeCostSheet = [
            SELECT Id
            FROM Cost_Sheet__c
            WHERE finalize_CostSheet__c = TRUE
            AND Opportunity__c =: oppId
            LIMIT 1
        ];

        if(!finalizeCostSheet.isEmpty()){

            List<Pricing_Element__c> carParkingDetailList = [
                SELECT Pricing_Element_Master__r.Name, Quantity__c
                FROM Pricing_Element__c
                WHERE Cost_Sheet__c =: finalizeCostSheet[0].Id
                AND parking_Element__c = TRUE
            ];

            for(Pricing_Element__c cpd : carParkingDetailList){

                carParkingDetails +=
                    cpd.Pricing_Element_Master__r.Name +
                    ' - ' +
                    cpd.Quantity__c +
                    ', ';
            }

            if(carParkingDetails.endsWith(', ')){
                carParkingDetails =
                    carParkingDetails.substring(0, carParkingDetails.length()-2);
            }
        }

        List<Payment_Schedule__c> paymentScheduleRelatedToOpp = [
            SELECT Name, Installment__c, Agreement_Value__c
            FROM Payment_Schedule__c
            WHERE Opportunity__c =: oppId
            ORDER BY Installment_Sequence__c
        ];

        Integer serialNo = 1;

        for(Payment_Schedule__c paymentSchedule : paymentScheduleRelatedToOpp){

            PaymentWrapper pw = new PaymentWrapper();

            pw.SlNo = serialNo;
            pw.installment = paymentSchedule.Name;
            pw.sequence = String.valueOf(paymentSchedule.Installment__c) + '%';
            pw.amount = paymentSchedule.Agreement_Value__c;

            totalFlatCost += paymentSchedule.Agreement_Value__c;

            paymentScheduleList.add(pw);

            serialNo++;
        }

    }

}