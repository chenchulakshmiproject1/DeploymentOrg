public with sharing class SiteVisitFormLWCController {
     public class leadAndOppWrapper{
        @AuraEnabled public List<Lead> leadList{get;set;}
        @AuraEnabled public List<Opportunity> oppList{get;set;}
        @AuraEnabled public Map<String,List<Visit__c>> oppXvisitMap{get;set;}

    }

    @AuraEnabled
    public static leadAndOppWrapper getLeadRecords(string searchkey){
        try{
            string keyString = '%' +searchkey;
            System.debug('searchkey====>'+searchkey);
            Map<String,List<Visit__c>> oppXvisitMap = new Map<String,List<Visit__c>>();
            List<Lead> leadList = [SELECT Id, FirstName, LeadSource, Lead_Sub_Source__c, Lead_Type__c, LastName, Email, Phone, LastModifiedDate, Pre_Sales_Team_Member__r.Name FROM Lead WHERE (Email LIKE :keyString OR Phone LIKE :keyString) AND isConverted = false ORDER BY LastModifiedDate DESC];
            System.debug('leadList====>'+leadList);
            List<Opportunity> oppList = [SELECT Id, Name, Email__c, Phone__c, LeadSource, Lead_Sub_Source__c, Lead_Type__c, LastModifiedDate, Pre_Sales_Team_Member__r.Name, Sales_Team_Member__r.Name FROM Opportunity WHERE (Email__c LIKE :keyString OR Phone__c LIKE :keyString) ORDER BY LastModifiedDate DESC];
            System.debug('oppList====>'+oppList);
            Set<String> OppIdSet = new Set<String>();
            if(!oppList.isEmpty()){
                for(Opportunity opp :oppList){
                    OppIdSet.add(opp.Id);
                }
            }
            if(!OppIdSet.isEmpty()){
                List<Visit__c> visitList = [SELECT Id, Name, CreatedDate, Opportunity__c, Opportunity__r.Name, Opportunity__r.Sales_Team_Member__r.Name, Opportunity__r.Pre_Sales_Team_Member__r.Name, Opportunity__r.LeadSource, Actual_Visit_Date__c, Sales_Manager__c, Visit_Time__c, Project_Name__c FROM Visit__c WHERE Opportunity__c IN :OppIdSet];
                if(!visitList.isEmpty()){
                    for(Visit__c visit : visitList){
                        if(!oppXvisitMap.containsKey(visit.Opportunity__c)){
                            oppXvisitMap.put(visit.Opportunity__c, new List<Visit__c>());
                        }
                        oppXvisitMap.get(visit.Opportunity__c).add(visit);
                    }
                }
            }
            leadAndOppWrapper wrapper = new leadAndOppWrapper();
            wrapper.leadList = leadList;
            wrapper.oppList = oppList;
            wrapper.oppXvisitMap = oppXvisitMap;
            return wrapper;
        }catch(Exception e){
            return null;
        }
    }

    @AuraEnabled
    public static String updateLeadDetails(Id leadId, Boolean bypassValidation) {
        try {
            List<Lead> leadToUpdate = [SELECT Id, By_Pass_Validations__c,IsConverted  FROM Lead WHERE Id = :leadId and IsConverted  = false LIMIT 1];
            if(!leadToUpdate.isEmpty()){
                leadToUpdate[0].By_Pass_Validations__c = bypassValidation;
                update leadToUpdate;
                
            }
            
            return 'SUCCESS';
        } catch (Exception e) {
            return 'ERROR: ' + e.getMessage();
        }
    }

    public class DataWrapper{
        @AuraEnabled public List<Site_Visit_Field_Config__c> leadVistFields{get;set;}
    }

    @AuraEnabled(cacheable=true)
    public static DataWrapper getFieldsOnLoad(){
        try {
            DataWrapper wrap = new DataWrapper();
            wrap.leadVistFields = [SELECT id,Display_Order__c,Field_API_Name__c,Field_Label__c,Field_Type__c,Is_Required__c,Is_Visible__c,Object_API_Name__c,Section_Name__c FROM Site_Visit_Field_Config__c WHERE (Object_API_Name__c = 'Visit__c' OR Object_API_Name__c = 'Lead' ) AND Is_Visible__c = true  Order by Display_Order__c];
            return wrap;
        } catch (Exception e) {
            System.debug('Error Occured ------>'+e.getMessage()+'at line  number--->'+e.getLineNumber());
            throw new AuraHandledException(e.getMessage());
        }        
    }

    @AuraEnabled
    public static returnPickValsWrapper getPickListLookupDependentValues(List<GetPickValsWrapper> picklistFields,List<GetPickValsWrapper> lookUpFields,List<GetPickValsWrapper> dependentPicklistFields){
        try {

            returnPickValsWrapper returnWrap = new returnPickValsWrapper();

            Map<String,List<PicklistOption>> mapOfIdbyOptions =
                new Map<String,List<PicklistOption>>();

            Map<String,List<PicklistOption>> mapOfIdbyLookupOptions =
                new Map<String,List<PicklistOption>>();

            /* ---------------- DEPENDENT PICKLIST ---------------- */

            Map<String,DependentPicklistWrapper> mapOfIdbyCntrlValbyDependentVal =
        new Map<String,DependentPicklistWrapper>();

            if(dependentPicklistFields != null && dependentPicklistFields.size() > 0){

                for(GetPickValsWrapper wr : dependentPicklistFields){

                    String controllingFieldApi =
                        getControllingFieldApiName(wr.objectapiName, wr.fieldapiName);

                    Schema.SObjectType objType =
                        Schema.getGlobalDescribe().get(wr.objectapiName);

                    Map<String, Schema.SObjectField> fieldMap =
                        objType.getDescribe().fields.getMap();

                    Schema.SObjectField controllingField =
                        fieldMap.get(controllingFieldApi);

                    Schema.SObjectField dependentField =
                        fieldMap.get(wr.fieldapiName);

                    Map<String,List<PicklistOption>> dependentValues =
                        getDependentPicklistOptions(controllingField, dependentField);

                    DependentPicklistWrapper depWrap = new DependentPicklistWrapper();

                    depWrap.controllingField = controllingFieldApi;
                    depWrap.values = dependentValues;

                    mapOfIdbyCntrlValbyDependentVal.put(wr.id, depWrap);
                }

                returnWrap.mapOfIdbyCntrlValbyDependentVal =
                    mapOfIdbyCntrlValbyDependentVal;
            }

            /* ---------------- NORMAL PICKLIST ---------------- */

            if(picklistFields != null && picklistFields.size() > 0){

                for(GetPickValsWrapper wr : picklistFields){

                    Schema.SObjectType objType =
                        Schema.getGlobalDescribe().get(wr.objectapiName);

                    Map<String, Schema.SObjectField> fieldMap =
                        objType.getDescribe().fields.getMap();

                    Schema.SObjectField fieldToken =
                        fieldMap.get(wr.fieldapiName);

                    List<Schema.PicklistEntry> pickVals =
                        fieldToken.getDescribe().getPicklistValues();

                    List<PicklistOption> options = new List<PicklistOption>();

                    for(Schema.PicklistEntry entry : pickVals){

                        if(entry.isActive()){
                            options.add(
                                new PicklistOption(
                                    entry.getLabel(),
                                    entry.getValue()
                                )
                            );
                        }
                    }

                    mapOfIdbyOptions.put(wr.id, options);
                }

                returnWrap.mapOfIdbyOptions = mapOfIdbyOptions;
            }

            /* ---------------- LOOKUP ---------------- */

            if(lookUpFields != null && lookUpFields.size() > 0){

                Map<String,String> configIdToParentObj = new Map<String,String>();
                Set<String> parentObjects = new Set<String>();

                for(GetPickValsWrapper wr : lookUpFields){

                    Schema.SObjectType objType =
                        Schema.getGlobalDescribe().get(wr.objectapiName);

                    Map<String, Schema.SObjectField> fieldMap =
                        objType.getDescribe().fields.getMap();

                    Schema.DescribeFieldResult fieldDescribe =
                        fieldMap.get(wr.fieldapiName).getDescribe();

                    if(fieldDescribe.getType() == Schema.DisplayType.Reference){

                        List<Schema.SObjectType> refObjs =
                            fieldDescribe.getReferenceTo();

                        if(refObjs.size() > 0){

                            String parentObj =
                                refObjs[0].getDescribe().getName();

                            configIdToParentObj.put(wr.id,parentObj);
                            parentObjects.add(parentObj);
                        }
                    }
                }

                Map<String,List<PicklistOption>> parentObjectRecords =
                    new Map<String,List<PicklistOption>>();

                for(String parentObj : parentObjects){

                    List<SObject> records =
                        Database.query('SELECT Id, Name FROM '+parentObj);

                    List<PicklistOption> options = new List<PicklistOption>();

                    for(SObject rec : records){

                        options.add(
                            new PicklistOption(
                                (String)rec.get('Name'),
                                (String)rec.get('Id')
                            )
                        );
                    }

                    parentObjectRecords.put(parentObj, options);
                }

                for(String configId : configIdToParentObj.keySet()){

                    String parentObj = configIdToParentObj.get(configId);

                    mapOfIdbyLookupOptions.put(
                        configId,
                        parentObjectRecords.get(parentObj)
                    );
                }

                returnWrap.mapOfIdbyLookupOptions = mapOfIdbyLookupOptions;
            }
            System.debug('returnWrap--------->'+returnWrap);
            return returnWrap;

        } catch (Exception e) {
            System.debug('Error occured while loading the values---->'+e.getMessage()+' at line number'+e.getLineNumber());
            return null;
            // throw new AuraHandledException(e.getMessage());
        }
    }
    public class GetPickValsWrapper{
        @AuraEnabled public String id{set;get;}
        @AuraEnabled public String objectapiName{set;get;}
        @AuraEnabled public String fieldapiName{set;get;}
    }
    public class returnPickValsWrapper {

        @AuraEnabled
        public Map<String,List<PicklistOption>> mapOfIdbyOptions;

        @AuraEnabled
        public Map<String,List<PicklistOption>> mapOfIdbyLookupOptions;

        @AuraEnabled
        public Map<String,DependentPicklistWrapper> mapOfIdbyCntrlValbyDependentVal;

        public returnPickValsWrapper(){
            mapOfIdbyOptions = new Map<String, List<PicklistOption>>();
            mapOfIdbyLookupOptions = new Map<String, List<PicklistOption>>();
            mapOfIdbyCntrlValbyDependentVal = new Map<String,DependentPicklistWrapper>();
        }
    }
    public class DependentPicklistWrapper {
        @AuraEnabled public String controllingField;
        @AuraEnabled public Map<String,List<PicklistOption>> values;
    }
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String controllingField;

        public PicklistOption(String label,String value){
            this.label = label;
            this.value = value;
        }
    }
    public static Map<String, List<PicklistOption>> getDependentPicklistOptions(Schema.sObjectField controllingField, Schema.sObjectField dependentField) {
        Map<String, List<PicklistOption>> dependentOptionsMap = new Map<String, List<PicklistOption>>();
        List<Schema.PicklistEntry> dependentEntries = dependentField.getDescribe().getPicklistValues();

        for (Schema.PicklistEntry dependentEntry : dependentEntries) {

            if (dependentEntry.isActive()) {

                String jsonString = JSON.serialize(dependentEntry);
                Map<String, Object> entryMap = (Map<String, Object>)JSON.deserializeUntyped(jsonString);

                if (entryMap.containsKey('validFor')) {

                    String validFor = (String)entryMap.get('validFor');

                    List<String> controllingValues = getControllingValuesFromValidFor(
                        controllingField,
                        validFor
                    );

                    for (String controllingValue : controllingValues) {

                        if (!dependentOptionsMap.containsKey(controllingValue)) {
                            dependentOptionsMap.put(controllingValue, new List<PicklistOption>());
                        }

                        dependentOptionsMap.get(controllingValue).add(
                            new PicklistOption(
                                dependentEntry.getLabel(),
                                dependentEntry.getValue()
                            )
                        );
                    }
                }
            }
        }

        return dependentOptionsMap;
    }
    public static String getControllingFieldApiName(String objectApiName, String dependentFieldApiName) {

        Schema.SObjectType objType = Schema.getGlobalDescribe().get(objectApiName);

        if(objType == null){
            return null;
        }

        Map<String, Schema.SObjectField> fieldMap = objType.getDescribe().fields.getMap();

        if(!fieldMap.containsKey(dependentFieldApiName)){
            return null;
        }

        Schema.DescribeFieldResult dependentFieldDescribe =
            fieldMap.get(dependentFieldApiName).getDescribe();

        if(dependentFieldDescribe.isDependentPicklist()){

            Schema.SObjectField controllingFieldToken =
                dependentFieldDescribe.getController();

            if(controllingFieldToken != null){
                return controllingFieldToken.getDescribe().getName();
            }
        }

        return null;
    }
    private static List<String> getControllingValuesFromValidFor(
        Schema.sObjectField controllingField, 
        String validFor
    ) {
        List<String> controllingValues = new List<String>();
        
        if (String.isNotBlank(validFor)) {
            // Get controlling picklist values
            List<Schema.PicklistEntry> controllingEntries = controllingField.getDescribe().getPicklistValues();
            
            // Decode the validFor string
            List<Integer> bits = base64ToBits(validFor);
            
            for (Integer i = 0; i < bits.size(); i++) {
                if (bits[i] == 1 && i < controllingEntries.size()) {
                    controllingValues.add(controllingEntries[i].getValue());
                }
            }
        }
        
        return controllingValues;
    }
    private static List<Integer> base64ToBits(String validFor) {
        if (validFor == null) return new List<Integer>();
        
        List<Integer> bits = new List<Integer>();
        String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        
        for (Integer i = 0; i < validFor.length(); i++) {
            String currentChar = validFor.substring(i, i + 1);
            Integer val = alphabet.indexOf(currentChar);
            
            for (Integer bit = 5; bit >= 0; bit--) {
                bits.add((val & (1 << bit)) != 0 ? 1 : 0);
            }
        }
        
        return bits;
    }

    @AuraEnabled
    public static String createRecordDynamic(String objectName, Map<String,Object> fieldValues){
        try{
            System.debug('objectName--------->'+objectName);
            System.debug('fieldValues------>'+fieldValues);
            if(String.isEmpty(objectName) ||fieldValues==null || fieldValues.isEmpty()){
                return 'please providell  data';
            }
            SObject obj = Schema.getGlobalDescribe().get(objectName).newSObject();
            for(String fieldName : fieldValues.keySet()){
                obj.put(fieldName, fieldValues.get(fieldName));
            }
            insert obj;
            return obj.Id;
        }catch(Exception e){
            System.debug('Error occured while inserting the data --->' +e.getMessage()+' At line number ----> ' +e.getLineNumber());
            return e.getMessage();
        }
    }
    @AuraEnabled
    public static Id convertLeadAndTagOpportunity(Id leadId, Id visitId){

        Database.LeadConvert lc = new Database.LeadConvert();
        lc.setLeadId(leadId);
        lc.setDoNotCreateOpportunity(false);
        lc.setConvertedStatus('Converted'); 

        Database.LeadConvertResult lcr = Database.convertLead(lc);

        if(lcr.isSuccess()){

            Id oppId = lcr.getOpportunityId();

            Visit__c visitRec = new Visit__c(
                Id = visitId,
                Opportunity__c = oppId
            );

            update visitRec;

            return oppId;
        }

        return null;
    }
    @AuraEnabled
    public static string insertVisitRecord(Visit__c visitRecord, string leadId, string oppId){
        try{
            System.debug('visitRecord ===> '+visitRecord);
            System.debug('leadId===>'+leadId);
            System.debug('oppId===>'+oppId);
            List<RecordType> custAccType = [
                SELECT Id 
                FROM RecordType 
                WHERE SObjectType = 'Account' AND DeveloperName = 'Customer'
                LIMIT 1
            ];
            
            List<Lead> leadList = [select Id,FirstName, LastName, MiddleName, Title, Sales_Team_Member__c,OwnerId from Lead Where Id =: leadId Limit 1];
            if((leadId != null || leadId != '') && (oppId == null || oppId == '')){
                System.debug('one Time site Visit...');
                if(leadList[0].Sales_Team_Member__c == null){
                    assignToSalesMember(leadId,'Sales(GRE)');
                }
                
                Database.LeadConvert lc = new database.LeadConvert();
                lc.setLeadId(leadId);
                lc.setConvertedStatus('Converted');
                //Pass the lead convert object to convertlead object so it can be converted.
                Database.LeadConvertResult lcr = Database.convertLead(lc);
                System.debug('lcr====>'+lcr);
                
                //Debug the AccountId, ContactId & OpportunityId after the lead is converted
                system.debug(lcr.getAccountId());
                system.debug(lcr.getContactId());
                system.debug(lcr.getOpportunityId());
                Lead updatedLead = [SELECT Id, ConvertedOpportunityId, ConvertedContactId, ConvertedAccountId, OwnerId,Sales_Team_Member__c,Sales_Team_Member__r.Name,Pre_Sales_Team_Member__c,Pre_Sales_Team_Member__r.Name,Name,Company,Email,Phone,Status,LeadSource,Industry,AnnualRevenue,Rating,CreatedById,CreatedDate  FROM Lead WHERE Id =: leadId];
                if(updatedLead != null && updatedLead.ConvertedAccountId != null) {
                    List<Account> convAcc = [SELECT Id, Name, RecordTypeId FROM Account WHERE Id =: updatedLead.ConvertedAccountId LIMIT 1];
                    convAcc[0].RecordTypeId = custAccType[0].Id;
                    List<String> parts = new List<String>();
                    if (!String.isBlank(leadList[0].Title))        parts.add(leadList[0].Title);
                    if (!String.isBlank(leadList[0].FirstName))    parts.add(leadList[0].FirstName);
                    if (!String.isBlank(leadList[0].MiddleName))   parts.add(leadList[0].MiddleName);
                    if (!String.isBlank(leadList[0].LastName))     parts.add(leadList[0].LastName);
                    convAcc[0].Name = parts.isEmpty() ? '' : String.join(parts, ' ');
                    update convAcc;
                }
                if(updatedLead != null && updatedLead.ConvertedOpportunityId != null){
                    Opportunity newOpp = [SELECT Id, Name, Channel_Partner__c, OwnerId, Email__c, Account.Name, Account.Phone, Phone__c,StageName,CloseDate,Amount,LeadSource,CreatedDate,Owner.Name FROM Opportunity WHERE Id =: updatedLead.ConvertedOpportunityId];
                    visitRecord.Opportunity__c = updatedLead.ConvertedOpportunityId;
                    visitRecord.Channel_Partner__c = newOpp.Channel_Partner__c;
                    visitRecord.Contact__c = updatedLead.ConvertedContactId;
                    newOpp.OwnerId = updatedLead.OwnerId;
                    
                    update newOpp;
                    System.debug('New Opportunity Owner updated: ' + newOpp.OwnerId);
                    // LeadHandler.copyNotesToOpportunity(new List<Lead>{updatedLead});
                    
                    System.debug('updatedLead==>'+updatedLead);
                    
                    if(updatedLead.Pre_Sales_Team_Member__c != null){
                        User preSalesUser = [
                            SELECT Id, Email 
                            FROM User 
                            WHERE Id = :updatedLead.Pre_Sales_Team_Member__c 
                            LIMIT 1
                        ];
                        
                        System.debug('preSalesUser==>'+preSalesUser);
                        
                        EmailTemplate template = [
                            SELECT Id, DeveloperName, Name , Body, HtmlValue,Subject
                            FROM EmailTemplate 
                            WHERE DeveloperName = 'SiteVisitPreSalesTemplate' 
                            LIMIT 1
                        ];
                        System.debug('template==>'+template);
                        String subject = template.Subject;
                        String htmlBody = template.HtmlValue;
                        
                        htmlBody = htmlBody.replace('{!Opportunity.Name}', newOpp.Name);
                        htmlBody = htmlBody.replace('{!Opportunity.StageName}', newOpp.StageName);
                        htmlBody = htmlBody.replace('{!Opportunity.CloseDate}', String.valueOf(newOpp.CloseDate));
                        htmlBody = htmlBody.replace('{!Opportunity.Amount}', (newOpp.Amount != null ? String.valueOf(newOpp.Amount) : 'N/A'));
                        htmlBody = htmlBody.replace('{!Opportunity.LeadSource}', newOpp.LeadSource);
                        htmlBody = htmlBody.replace('{!Opportunity.Account.Name}', newOpp.Account != null ? newOpp.Account.Name : 'N/A');
                        htmlBody = htmlBody.replace('{!Opportunity.Owner.Name}', newOpp.Owner.Name);
                        htmlBody = htmlBody.replace('{!Opportunity.CreatedDate}', String.valueOf(newOpp.CreatedDate));
                        
                        
                        
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setToAddresses(new String[]{preSalesUser.Email});
                        mail.setSubject(subject);
                        mail.setHtmlBody(htmlBody);
                        mail.setSaveAsActivity(false);
                        
                        System.debug('mail===>'+mail);
                        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
                        
                        CustomNotificationType notificationType = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'LeadConvertedToOpportunity' LIMIT 1];
                        System.debug('notificationType :'+ notificationType );
                        
                        Messaging.CustomNotification notification = new Messaging.CustomNotification();
                        notification.setTitle('Lead Assigned');
                        notification.setBody('Lead Converted to Opportunity');
                        notification.setNotificationTypeId(notificationType.Id);
                        notification.setTargetId(updatedLead.Id); 
                        notification.send(new Set<String>{ updatedLead.Pre_Sales_Team_Member__c });
                    }
                    
                    if(newOpp.OwnerId != null){
                        
                        // Query Opportunity
                        Opportunity newOpp1 = [
                            SELECT Id, Name, StageName, CloseDate, Amount, LeadSource, CreatedDate,
                            Account.Name, Owner.Name, Owner.Email, OwnerId
                            FROM Opportunity
                            WHERE Id = :updatedLead.ConvertedOpportunityId
                            LIMIT 1
                        ];
                        
                        // Query Owner (Sales Person)
                        User salesUser = [
                            SELECT Id, Name, Email 
                            FROM User 
                            WHERE Id = :newOpp1.OwnerId
                            LIMIT 1
                        ];
                        
                        EmailTemplate template2 = [
                            SELECT Id, DeveloperName, Name , Body, HtmlValue,Subject
                            FROM EmailTemplate 
                            WHERE DeveloperName = 'OpportunityConvertedSalesEmail' 
                            LIMIT 1
                        ];
                        
                        
                        
                        // Replace placeholders
                        String body = template2.HtmlValue;
                        body = body.replace('{!SalesPersonName}', salesUser.Name);
                        body = body.replace('{!OpportunityName}', newOpp.Name);
                        body = body.replace('{!AccountName}', newOpp.Account != null ? newOpp.Account.Name : 'N/A');
                        body = body.replace('{!StageName}', newOpp.StageName);
                        body = body.replace('{!CloseDate}', newOpp.CloseDate != null ? String.valueOf(newOpp.CloseDate) : 'N/A');
                        body = body.replace('{!Amount}', newOpp.Amount != null ? String.valueOf(newOpp.Amount) : 'N/A');
                        body = body.replace('{!LeadSource}', newOpp.LeadSource != null ? newOpp.LeadSource : 'N/A');
                        body = body.replace('{!CreatedDate}', String.valueOf(newOpp.CreatedDate));
                        body = body.replace('{!OpportunityId}', newOpp.Id);
                        
                        // Send Email
                        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                        mail.setToAddresses(new String[] { salesUser.Email });
                        mail.setSubject('New Opportunity Created - ' + newOpp.Name);
                        mail.setHtmlBody(body);
                        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
                        
                        CustomNotificationType notificationType1 = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'LeadConvertedToOpportunity' LIMIT 1];
                        
                        // Send Notification
                        Messaging.CustomNotification notification = new Messaging.CustomNotification();
                        notification.setTitle('New Opportunity Assigned');
                        notification.setBody('Opportunity ' + newOpp.Name + ' has been created and assigned to you.');
                        notification.setSenderId(UserInfo.getUserId());
                        notification.setTargetId(newOpp.Id);
                        notification.setNotificationTypeId(notificationType1.Id);
                        notification.send(new Set<String>{ salesUser.Id });
                        
                        
                        
                        
                    }
                    
                    // if (newOpp.Email__c != null) {
                    //     EmailTemplate oppCreatedTemplate = [
                    //         SELECT Id, Subject, HtmlValue, Body 
                    //         FROM EmailTemplate  
                    //         WHERE DeveloperName = 'New_Opportunity_Created_From_SiteVisit' 
                    //         LIMIT 1
                    //     ];
                    //     String htmlBody = oppCreatedTemplate.HtmlValue;
                    //     htmlBody = htmlBody
                    //     .replace('{oppName}', newOpp.Name != null ? newOpp.Name : '')
                    //     .replace('{oppPhone}', newOpp.Phone__c != null ? newOpp.Phone__c : '')
                    //     .replace('{oppEmail}', newOpp.Email__c != null ? newOpp.Email__c : '')
                    //     .replace('{!Opportunity.Id}', newOpp.Id);
                    //     Id orgWideEmailAddressId = [SELECT Id FROM OrgWideEmailAddress ].Id;
                    //     System.debug('orgWideEmailAddressIdOpp::>>' + orgWideEmailAddressId);
                    
                    //     Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                    //     email.setOrgWideEmailAddressId(orgWideEmailAddressId);
                    //     email.setToAddresses(new String[] { newOpp.Email__c });
                    //     email.setSubject(oppCreatedTemplate.Subject);
                    
                    //     email.setWhatId(newOpp.Id);
                    //     email.setSaveAsActivity(false);
                    //     email.setHtmlBody(htmlBody);
                    
                    //     Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
                    
                    //     System.debug('Email sent to Account for new Opportunity: ' + newOpp.Id);
                    // }
                    
                    try {
                        CustomNotificationType  notificationTypeId = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'New_Lead_Assigned' LIMIT 1];
                        //Id userId = (UserInfo.getUserId());
                        Id userId = newOpp.OwnerId; 
                        String recordId = newOpp.Id;
                        Messaging.CustomNotification notification = new Messaging.CustomNotification();
                        notification.setNotificationTypeId(notificationTypeId.Id); 
                        notification.setTitle('New Opportunity Assigned'); 
                        notification.setBody('A new Opportunity has been assigned to you: ' + lead.Name);
                        notification.setTargetId(recordId);
                        System.debug('New Opportunity ID: ' + newOpp.Id);
                        notification.setSenderId(UserInfo.getUserId());
                        //notification.send(new List<Id>{newOpp.OwnerId});
                        notification.send(new Set<String>{ userId });
                        System.debug('Custom notification sent to new Opportunity owner: ' + newOpp.OwnerId);
                    } catch (Exception ex) {
                        System.debug('Failed to send notification: ' + ex.getMessage());
                    }
                }
            }
            else if(oppId != null && oppId != '' && (leadId == null || leadId == '')){
                System.debug('second visit..');
                Opportunity Opp = [SELECT Id, Name, Channel_Partner__c FROM Opportunity WHERE Id =: oppId];
                visitRecord.Channel_Partner__c = Opp.Channel_Partner__c;
                visitRecord.Opportunity__c = oppId;
                
                //
            }
            // System.debug(' --- location:'+location);
            
            //ConvertLeadManually.doConvertLeadManually(leadId);
            // if(!String.isBlank(location)){
            //     List<Location__c> locationrec = [Select Id,name From Location__c WHERE Id =: location LIMIT 1];
            //     system.debug('locationrec ==> '+locationrec);
            //     if(!locationrec.isEMpty()){
            //         visitRecord.Location__c = locationrec[0].Id;
            //     }
            //     system.debug('visitRecord.Location__c ==> '+visitRecord.Location__c);
            // }
            // Visit__c visitRecord = (Visit__c) JSON.deserialize(visitString, Visit__c.class);
            // visitRecord.Lead = leadId;
            // if(day == 0 && month==0 && year==0){
            
            // }else{
            //     visitRecord.Date_Of_Birth__c = Date.newInstance(year, month, day); 
            // }
            // if(visitday == 0 && visitmonth==0 && visityear==0){
            
            // }else{
            //     visitRecord.Actual_visit_date__c = Date.newInstance(visityear, visitmonth, visitday); 
            // }
            if(!String.isBlank(visitRecord.Id)){
                system.debug('inside...');
                update visitRecord;
            }else{
                visitRecord.Status__c = 'SV Completed';
                insert visitRecord;
                
                List<Visit__c> insertedVisit = [SELECT Id, Name, Remarks__c, Requirement_Type__c, Opportunity__r.Phone__c, Opportunity__r.Email__c, Opportunity__r.Lead_Type__c, Opportunity__r.AccountId, Opportunity__r.Owner.Name,Opportunity__r.Id FROM Visit__c WHERE Id = :visitRecord.Id
                                                LIMIT 1
                                               ];
                
                List<Contact> customerContact = [
                    SELECT Name
                    FROM Contact
                    WHERE AccountId = :insertedVisit[0].Opportunity__r.AccountId
                    ORDER BY LastModifiedDate DESC
                    LIMIT 1
                ];
                
                EmailTemplate temp = [
                    SELECT Id, Subject, HtmlValue, Body
                    FROM EmailTemplate
                    WHERE DeveloperName = 'Visit_Status_SV_Completed_Notification_Email'
                    LIMIT 1
                ];
                
                String customerName = customerContact != null ? customerContact[0].Name : 'N/A';
                System.debug('customerName::>>' + customerName);
                String htmlBody = temp.HtmlValue
                    .replace('{!Visit__c.Id}', insertedVisit[0].Id)
                    .replace('{!Opportunity.Phone__c}', insertedVisit[0].Opportunity__r.Phone__c != null ? insertedVisit[0].Opportunity__r.Phone__c : '')
                    .replace('{!Opportunity.Email__c}', insertedVisit[0].Opportunity__r.Email__c != null ? insertedVisit[0].Opportunity__r.Email__c : '')
                    .replace('{!Opportunity.Lead_Type__c}', insertedVisit[0].Opportunity__r.Lead_Type__c != null ? insertedVisit[0].Opportunity__r.Lead_Type__c : '')
                    .replace('{!Visit__c.Requirement_Type__c}', insertedVisit[0].Requirement_Type__c != null ? insertedVisit[0].Requirement_Type__c : '')
                    .replace('{!Visit__c.Remarks__c}', insertedVisit[0].Remarks__c != null ? insertedVisit[0].Remarks__c : '')
                    .replace('{salesUserAssign}', insertedVisit[0].Opportunity__r.Owner.Name != null ? insertedVisit[0].Opportunity__r.Owner.Name : '')
                    .replace('{!Customer.Name}', customerName);
                System.debug('htmlBody::>>' + htmlBody);
                
                Id orgWideEmailAddressId = [SELECT Id FROM OrgWideEmailAddress ].Id;
                System.debug('orgWideEmailAddressId::>>' + orgWideEmailAddressId);
                
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setOrgWideEmailAddressId(orgWideEmailAddressId);
                email.setSubject(temp.Subject);
                email.setToAddresses(new String[]{Label.Gre_Email});
                email.setWhatId(insertedVisit[0].Id);
                email.setSaveAsActivity(false);
                email.setHtmlBody(htmlBody);
                
                
                Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
                System.debug('Email sent successfully for Visit Id: ' + visitRecord.Id);
                
                //Email and Notifictaion on visit Creation
                Visit__c visitRec = [
                    SELECT Id, Name, Actual_Visit_Date__c, 
                    CreatedBy.Name
                    FROM Visit__c
                    WHERE Id = :visitRecord.Id
                    LIMIT 1
                ];
                
                // Query Email Template (Custom HTML template stored in Salesforce)
                EmailTemplate template = [
                    SELECT Id, HtmlValue, Subject
                    FROM EmailTemplate
                    WHERE DeveloperName = 'SiteVisitCreationEmail'
                    LIMIT 1
                ];
                
                Opportunity opp = [
                    SELECT Id, Name, OwnerId, Owner.Name 
                    FROM Opportunity 
                    WHERE Id = :insertedVisit[0].Opportunity__r.Id
                    LIMIT 1
                ];
                
                User salesUser = [select Id,Email,Name from User Where Id =: Opp.ownerId Limit 1];
                
                // Replace placeholders in HTML
                String body = template.HtmlValue;
                body = body.replace('{!SalesPersonName}',salesUser.Name);
                body = body.replace('{!VisitDate}', visitRec.Actual_Visit_Date__c!=null ?String.valueOf(visitRec.Actual_Visit_Date__c):'');
                
                body = body.replace('{!CreatedBy}', visitRec.CreatedBy.Name);
                
                // Create email
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new List<String>{salesUser.Email});
                mail.setSubject('New Visit Created - ' + visitRec.Name);
                mail.setHtmlBody(body);
                mail.setSaveAsActivity(false);
                
                // Send
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{mail});
                
                CustomNotificationType  notificationTypeId1 = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'New_Lead_Assigned' LIMIT 1];
                
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setNotificationTypeId(notificationTypeId1.Id); 
                notification.setTitle('New Visit Created'); 
                notification.setBody('A new Vist has been created..');
                notification.setTargetId(visitRecord.Id);
                
                notification.setSenderId(UserInfo.getUserId());
                
                notification.send(new Set<String>{ insertedVisit[0].Opportunity__r.OwnerId });
                
                
            }
            
            //     List<Visit__c> insertedVisit = [SELECT Id, Name, Remarks__c, Opportunity__r.Phone__c, Opportunity__r.Email__c, Opportunity__r.Lead_Type__c, Opportunity__r.AccountId FROM Visit__c WHERE Id =: visitRecord.Id LIMIT 1];
            //     List<Contact> con = [select Id, Name from Contact where AccountId = :insertedVisit.Opportunity__r.AccountId ORDER BY LastModifiedDate DESC LIMIT 1] ;
            
            //     Id orgWideEmailAddressId = [SELECT Id FROM OrgWideEmailAddress ].Id;
            //     EmailTemplate temp = [SELECT Id, Subject, HtmlValue, Body FROM EmailTemplate WHERE DeveloperName = 'Visit_Status_SV_Completed_Notification_Email'];
            
            //     String customerName = customerContact != null ? customerContact.Name : 'N/A';
            //     System.debug('customerName::>>' + customerName);
            //     String htmlBody = temp.HtmlValue
            //     .replace('{!Visit__c.Id}', insertedVisit.Id)
            //     .replace('{!Opportunity.Phone__c}', insertedVisit.Opportunity__r.Phone__c != null ? insertedVisit.Opportunity__r.Phone__c : '')
            //     .replace('{!Opportunity.Email__c}', insertedVisit.Opportunity__r.Email__c != null ? insertedVisit.Opportunity__r.Email__c : '')
            //     .replace('{!Opportunity.Lead_Type__c}', insertedVisit.Opportunity__r.Lead_Type__c != null ? insertedVisit.Opportunity__r.Lead_Type__c : '')
            //     .replace('{!Visit__c.Requirement_Type__c}', insertedVisit.Requirement_Type__c != null ? insertedVisit.Requirement_Type__c : '')
            //     .replace('{!Visit__c.Remarks__c}', insertedVisit.Remarks__c != null ? insertedVisit.Remarks__c : '')
            //     .replace('{!Customer_Name}', customerContact != null ? customerContact.Name : 'N/A');
            
            
            //     Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            //     email.setOrgWideEmailAddressId([SELECT Id FROM OrgWideEmailAddress LIMIT 1].Id);
            //     email.setSubject(temp.Subject);
            //     email.setToAddresses(new String[]{'sagar.kumar@utilitarianlabs.com'}); //gre@tridasa.in
            //     email.setWhatId(insertedVisit.Id);
            //     email.setSaveAsActivity(false);
            //     email.setHtmlBody(htmlBody);
            //     Messaging.sendEmail(new Messaging.SingleEmailMessage[] { email });
            
            //     // String htmlBody = temp.HtmlValue
            //     //     .replace('{!Visit__c.Name}', insertedVisit[0].Name)
            //     //     .replace('{!Visit__c.Id}', insertedVisit[0].Id);
            //     // email.setOrgWideEmailAddressId(orgWideEmailAddressId);
            //     // email.setSubject(temp.Subject);
            //     // email.setToAddresses(new String[]{'gre@tridasa.in'});
            //     // email.setWhatId(insertedVisit[0].Id);
            //     // email.setSaveAsActivity(false);
            //     // email.setHtmlBody(htmlBody);
            //     // Messaging.sendEmail(new Messaging.SingleEmailMessage[] {email});
            // }
            
            // Lead leadRecToUpdateAsClosedWon = new Lead();
            // leadRecToUpdateAsClosedWon.Id = leadId;
            // leadRecToUpdateAsClosedWon.Lead_Stage__c = ConstantClass.LeadStageConverted;
            // update leadRecToUpdateAsClosedWon;
            return visitRecord.Id;
        }catch(Exception e){
            System.debug('Exception::'+e.getMessage()+e.getLineNumber());
            return e.getMessage()+e.getLineNumber();
        }
    }
     public static Id assignToSalesMember(String leadId, String type) {
        System.debug('Second Time Calling..');
        try {
            List<Lead> lead = [SELECT Id, Project__c FROM Lead WHERE Id =: leadId Limit 1];
            if(lead[0].Project__c == null){
                return 'No Project exist on the Lead...';
            }
            List<Assignment_Group__c> assignGroup = [SELECT Id, Name, GRE_Last_allocated_Id__c FROM Assignment_Group__c WHERE Type__c = : type AND Project__c =: lead[0].Project__c LIMIT 1];
            if(assignGroup.isEmpty()){
                return 'assignment Group is not there in the System.';
            }
            List<Assignment_Group_Member__c> members = [SELECT Id, Assignment_Id__c, Active__c, Group_Member__c FROM Assignment_Group_Member__c WHERE Assignment_Group__c = :assignGroup[0].Id AND Active__c = TRUE AND Out_Of_Office__c = FALSE ORDER BY Assignment_Id__c];
            System.debug('members==>'+members.size());
            if (members.isEmpty()) {
                return null; 
            }
            Decimal lastAssignedId = assignGroup[0].GRE_Last_allocated_Id__c;
            Assignment_Group_Member__c nextAssignee;
            if (lastAssignedId == null) {  
                nextAssignee = members[0];
            } else {
                Integer nextIndex = 0;
                for (Integer i = 0; i < members.size(); i++) {
                    if (members[i].Assignment_Id__c == lastAssignedId) {
                        nextIndex = i + 1;
                        break;
                    }
                }
                System.debug('nextIndex==>'+nextIndex);
                if (nextIndex >= members.size()) {
                    nextIndex = 0;
                }
                nextAssignee = members[nextIndex];
                System.debug('nextAssignee==>'+nextAssignee);
            }
            System.debug('nextAssignee.Assignment_Id__c==>'+nextAssignee.Assignment_Id__c);
            assignGroup[0].GRE_Last_allocated_Id__c = nextAssignee.Assignment_Id__c;
            update assignGroup;
            if(!lead.isEmpty()) {
                lead[0].OwnerId = nextAssignee.Group_Member__c;
                lead[0].Sales_Team_Member__c = nextAssignee.Group_Member__c;
                update lead;
            }
            System.debug('nextAssignee.Group_Member__c==>'+nextAssignee.Group_Member__c);
            return nextAssignee.Group_Member__c;
            
        } catch (Exception e) {
            System.debug('ERROR in GRE Assignment : ' + e.getMessage() + ' at line ' + e.getLineNumber());
            return null;
        }
    }
}