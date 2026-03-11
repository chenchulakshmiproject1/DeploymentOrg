/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : GenerateCostSheetController
 * Author          : Indu C R
 * Created Date    : Mar 10, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Mar 10, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Mar 10, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public without sharing class GenerateCostSheetController {
	@AuraEnabled(cacheable = true)
    public static fetchDataWrapper getOnLoadData(String recordId) {
        Set<Id> allocatedUnitIds = new Set<Id>();
        for(Unit_Allocation__c ua : [SELECT Unit__c FROM Unit_Allocation__c WHERE Opportunity__c = :recordId]) {
            allocatedUnitIds.add(ua.Unit__c);
        }
        
        try {
            System.debug('recordId --->' + recordId);
            
            Tax_Details__c carParkingTax = [
            SELECT Id, Name, CGST__c, SGST__c 
            FROM Tax_Details__c 
            WHERE Name = 'Tax Details' 
            LIMIT 1
        ];

        Opportunity opp = new Opportunity();
        if(recordId.startsWith('00T')){
                Task ts = [select id,WhatId from Task where id =: recordId ];
                if (ts.WhatId == null || !String.valueOf(ts.WhatId).startsWith('006')) {
                    fetchDataWrapper wrp = new fetchDataWrapper();
                    wrp.errorMessage = 'This task is not related to an Opportunity.';
                    wrp.validationError = true;
                    return wrp;
                }
            
                    opp = [
                SELECT Id, Unit__c, Cluster__c, OwnerId, Project__c, 
                    Unit__r.Name, Unit__r.Unit_Name__c
                FROM Opportunity 
                WHERE Id =:ts.WhatId
                ];
        }

        System.debug('opp==>'+opp);
            
            if (opp.Project__c == null) {
                fetchDataWrapper wrp = new fetchDataWrapper();
                wrp.errorMessage = 'Project is not tagged to this Opportunity. Please update the Opportunity with a valid Project before generating the Cost Sheet.';
                wrp.opp = opp;
                wrp.validationError = true;
                return wrp;
            }
            
            if (opp.Cluster__c == null) {
                fetchDataWrapper wrp = new fetchDataWrapper();
                wrp.errorMessage = 'Cluster is not tagged to this Opportunity. Please update the Opportunity with a valid Cluster before generating the Cost Sheet.';
                wrp.opp = opp;
                wrp.validationError = true;
                return wrp;
            }
            
            List<Unit__c> unitList = [
            SELECT Id, Name 
            FROM Unit__c 
            WHERE Status__c != 'Sold' OR Id IN :allocatedUnitIds
        ];
            
            List<Cost_Sheet_Template__c> costSheetTemplateList = [
            SELECT Id, Name, 
                   (SELECT Id, Name, Payment_Scheme__r.Name, Payment_Scheme__r.Tower__c 
                    FROM Cost_Scheme_Linkings__r), 
                   (SELECT Id, Name, Unit__c FROM Cost_Unit_Linking__r)
            FROM Cost_Sheet_Template__c
            WHERE Id IN (SELECT Cost_Sheet_Template__c FROM Cost_Scheme_Linking__c)
        ];
            
            fetchDataWrapper wrp = new fetchDataWrapper();
            wrp.opp = opp;
            wrp.carParkingTax = carParkingTax;
            wrp.unitList = unitList.isEmpty() ? null : unitList;
            wrp.costSheetTemplateList = costSheetTemplateList.isEmpty() ? null : costSheetTemplateList;
            wrp.errorMessage = unitList.isEmpty() || costSheetTemplateList.isEmpty() ? 'Unit or Cost Sheet Template is empty' : null;
            
            return wrp;
            
        } catch (Exception e) {
            System.debug('Error in getOnLoadData: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            throw new AuraHandledException('Error: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static Unit__c getUnitRecord(String unitId) {
        try {
            return [
            SELECT Id, Name, Unit_Name__c, Status__c, 
                   Floor__r.Blocks__c, Super_Built_Up_Area_sq_ft__c
            FROM Unit__c 
            WHERE Id = :unitId
            LIMIT 1
        ];
        } catch (Exception e) {
            throw new AuraHandledException('Error fetching unit record: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static DiscountConfigWrapper getDiscountConfig(String opportunityId) {
        System.debug('=== getDiscountConfig START ===');
        System.debug('Opportunity Id: ' + opportunityId);
        
        DiscountConfigWrapper wrapper = new DiscountConfigWrapper();
        wrapper.hasDiscountConfig = false;
        wrapper.discountLevels = new List<DiscountLevelWrapper>();
        
        try {
            List<Opportunity> oppRecords = [
            SELECT Id, Project__c, Project__r.Name 
            FROM Opportunity 
            WHERE Id = :opportunityId 
            LIMIT 1
        ];
            
            if (oppRecords.isEmpty() || oppRecords[0].Project__c == null) {
                System.debug('No project found on opportunity');
                return wrapper;
            }
            
            Id projectId = oppRecords[0].Project__c;
            wrapper.projectId = projectId;
            
            List<Discount_Master__c> discountMasters = [
            SELECT Id, Name, Project__c, Type__c, Active__c,
                   (SELECT Id, Roles__c, Minimum__c, Maximum__c 
                    FROM Discount_LineItems__r 
                    ORDER BY Minimum__c ASC)
            FROM Discount_Master__c
            WHERE Project__c = :projectId
            AND Type__c = 'Discount'
            AND Active__c = true
            LIMIT 1
        ];
            
            if (discountMasters.isEmpty()) {
                System.debug('No active Discount Master found');
                return wrapper;
            }
            
            Discount_Master__c dm = discountMasters[0];
            wrapper.discountMasterId = dm.Id;
            wrapper.hasDiscountConfig = true;
            
            // Get first level minimum (STM limit)
            if (!dm.Discount_LineItems__r.isEmpty()) {
                wrapper.stmMaxLimit = dm.Discount_LineItems__r[0].Minimum__c - 1;
                if (wrapper.stmMaxLimit < 0) {
                    wrapper.stmMaxLimit = 0;
                }
            }
            
            // Build level wrappers
            for (Discount_LineItem__c li : dm.Discount_LineItems__r) {
                DiscountLevelWrapper level = new DiscountLevelWrapper();
                level.lineItemId = li.Id;
                level.role = li.Roles__c;
                level.minimumAmount = li.Minimum__c;
                level.maximumAmount = li.Maximum__c;
                wrapper.discountLevels.add(level);
            }
            
            System.debug('Discount Config Found - Levels: ' + wrapper.discountLevels.size());
            System.debug('STM Max Limit: ' + wrapper.stmMaxLimit);
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getDiscountConfig: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    // @AuraEnabled
    // public static List<Parking_Details__c> getParkingRecords(String unitId) {
        //     try {
            //         System.debug('unitId: ' + unitId);
            
            //         List<Unit__c> allUnits = [
            //         SELECT Id, Unit_Type__c, Status__c, Unit_Name__c, Floor__r.Tower__r.Id
            //         FROM Unit__c
            //         WHERE Id = :unitId
            //     ];
            
            //         if (allUnits.isEmpty()) {
                //             return new List<Parking_Details__c>();
            //         }
            
            //         List<Parking_Details__c> getAllParkingRecords = [
            //         SELECT Id, Amount__c, Block__c, Name, Parking_Type__c, Total_Parking__c, Available_Parking__c
            //         FROM Parking_Details__c
            //         WHERE Block__c = :allUnits[0].Floor__r.Tower__r.Id
            //             ];
            
            //         return getAllParkingRecords;
            
        //     } catch (Exception e) {
            //         System.debug('Exception occurred: ' + e.getMessage());
            //         return new List<Parking_Details__c>();
        //     }
    // }
    
    @AuraEnabled
    public static List<Parking_Details__c> getParkingRecords(String unitId) {
        try {
            System.debug('unitId: ' + unitId);
            
            if (String.isBlank(unitId)) {
                return new List<Parking_Details__c>();
            }
            
            List<Unit__c> allUnits = [
            SELECT Id, Unit_Type__c, Status__c, Unit_Name__c, 
                   Project_Code__c,
                   Floor__r.Blocks__c,
                   Floor__r.Blocks__r.Id,
                   Floor__r.Blocks__r.Project__c,
                   Floor__r.Blocks__r.Project__r.Project_Type__c
            FROM Unit__c 
            WHERE Id = :unitId
            LIMIT 1
        ];
            
            if (allUnits.isEmpty()) {
                return new List<Parking_Details__c>();
            }
            
            Unit__c unit = allUnits[0];
            
            Id projectId = null;
            String projectType = null;
            Id towerId = null;
            
            if (unit.Project_Code__c != null) {
                projectId = unit.Project_Code__c;
                
                List<Project__c> projects = [
                SELECT Id, Project_Type__c 
                FROM Project__c 
                WHERE Id = :projectId 
                LIMIT 1
            ];
                if (!projects.isEmpty()) {
                    projectType = projects[0].Project_Type__c;
                }
            }
            
            if (unit.Floor__r != null && unit.Floor__r.Blocks__r != null) {
                towerId = unit.Floor__r.Blocks__r.Id;
                
                if (projectId == null) {
                    projectId = unit.Floor__r.Blocks__r.Project__c;
                }
                if (projectType == null) {
                    projectType = unit.Floor__r.Blocks__r.Project__r.Project_Type__c;
                }
            }
            
            System.debug('Project ID: ' + projectId);
            System.debug('Project Type: ' + projectType);
            System.debug('Tower ID: ' + towerId);
            
            List<Parking_Details__c> parkingRecords = new List<Parking_Details__c>();
            
            
            if (projectType == 'Villa' || projectType == 'Plot') {
                System.debug('Querying parking at PROJECT level (Villa/Plot)');
                
                parkingRecords = [
                SELECT Id, Amount__c, Block__c, Project__c, Name, 
                       Parking_Type__c, Total_Parking__c, Available_Parking__c 
                FROM Parking_Details__c 
                WHERE Project__c = :projectId
                AND Block__c = null
            ];
                
            } else {
                System.debug('Querying parking at BLOCK level (Apartment)');
                
                if (towerId != null) {
                    parkingRecords = [
                    SELECT Id, Amount__c, Block__c, Project__c, Name, 
                           Parking_Type__c, Total_Parking__c, Available_Parking__c 
                    FROM Parking_Details__c 
                    WHERE Block__c = :towerId
                ];
                } else {
                    System.debug('WARNING: Tower ID is null for Apartment project');
                }
            }
            
            System.debug('Parking Records Found: ' + parkingRecords.size());
            return parkingRecords;
            
        } catch (Exception e) {
            System.debug('Exception occurred: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            return new List<Parking_Details__c>();
        }
    }
    
    @AuraEnabled
    public static TemplateDataWrapper getTemplateData(String unitId, String cslId) {
        try {
            System.debug('=== getTemplateData START ===');
            System.debug('unitId: ' + unitId);
            System.debug('cslId: ' + cslId);
            
            TemplateDataWrapper wrapper = new TemplateDataWrapper();
            
            List<Unit__c> unitList = [
        SELECT Id, Name, Unit_Name__c, Status__c,
               Super_Built_Up_Area_sq_ft__c, Floor_Rise__c, Corner_Rs_Sft__c, 
               Infrastructure_Charges__c, Premium_Charges__c, Amenities_Charges__c,
               Cost_of_Amenities__c, Facing_Charges_Rs_LS__c, Elevator_Charges_Rs_Sft__c,
               Facing_Rs_Sft__c, Base_Price_per_sqft__c, Car_Parking_Amount__c,
               Corpus_Fund_Rs_sft__c, Corner_Premium__c, East_North__c, North_East__c,
               Park_Facing__c, Extra_Land__c, Extra_Land_Yard__c,
               Car_Parking__c,
               Project_Code__c,
               Default_Parking__c,
               Floor__c,
               Floor__r.Blocks__c, 
               Floor__r.Blocks__r.Project__c, 
               Floor__r.Blocks__r.Project__r.Project_Type__c
        FROM Unit__c 
        WHERE Id = :unitId 
        LIMIT 1
    ];
            
            if (unitList.isEmpty()) {
                wrapper.errorMessage = 'Unit not found';
                return wrapper;
            }
            wrapper.unitData = unitList[0];
            
            Id projectId = null;
            
            if (unitList[0].Project_Code__c != null) {
                projectId = unitList[0].Project_Code__c;
                System.debug('Project ID from direct lookup: ' + projectId);
            }
            
            else if (unitList[0].Floor__r != null &&
                unitList[0].Floor__r.Blocks__r != null &&
            unitList[0].Floor__r.Blocks__r.Project__c != null) {
                projectId = unitList[0].Floor__r.Blocks__r.Project__c;
                System.debug('Project ID from Floor->Tower->Project: ' + projectId);
            }
            
            System.debug('Final Project ID: ' + projectId);
            
            
            Project__c projectData = null;
            
            if (projectId != null) {
                List<Project__c> projects = [
            SELECT Id, Name,
                   Project_Type__c,
                   Stamp_Duty_Percentage__c,
                   Stamp_Duty_and_Mutation_Charges_Rs__c,
                   Maintainence_Charges_Months__c,
                   Maintanance_Charges_Rs__c
            FROM Project__c
            WHERE Id = :projectId
            LIMIT 1
        ];
                
                if (!projects.isEmpty()) {
                    projectData = projects[0];
                    System.debug('Project Data: ' + projectData);
                    System.debug('Project Type: ' + projectData.Project_Type__c);
                }
            }
            wrapper.projectData = projectData;
            
            List<Cost_Scheme_Linking__c> cslList = [
            SELECT Id, Payment_Scheme__c, Cost_Sheet_Template__c,
                   Cost_Sheet_Template__r.Name, Cost_Sheet_Template__r.Amount__c,
                   Cost_Sheet_Template__r.Tax_Amount__c,
                   Payment_Scheme__r.Name, Payment_Scheme__r.Tower__c
            FROM Cost_Scheme_Linking__c 
            WHERE Id = :cslId 
            LIMIT 1
        ];
            
            if (cslList.isEmpty()) {
                wrapper.errorMessage = 'Cost Scheme Linking not found';
                return wrapper;
            }
            wrapper.costSchemeLinking = cslList[0];
            
            
            List<Cost_Pricing_Association__c> pricingAssociations = [
            SELECT Id, Name, Amount__c, Cost_Sheet_Template__c, PE_Type__c, Type__c,
                   Pricing_Element_Master__c, Pricing_Element_Master__r.Name,
                   Pricing_Element_Master__r.Parking_Type__c,
                   Quantity__c, Rate__c, Tax_Amount__c, Unit__c, Sequence__c
            FROM Cost_Pricing_Association__c 
            WHERE Cost_Sheet_Template__c = :cslList[0].Cost_Sheet_Template__c
                ORDER BY Sequence__c ASC
                ];
            wrapper.pricingAssociations = pricingAssociations;
            
            
            Set<Id> pricingAssociationIds = new Set<Id>();
            for (Cost_Pricing_Association__c cpa : pricingAssociations) {
                pricingAssociationIds.add(cpa.Id);
            }
            
            List<Cost_Sheet_Tax_Linking__c> taxLinkings = [
            SELECT Id, Cost_Pricing_Association__c, Tax_Master__c,
                   Tax_Master__r.Tax__c, Tax_Master__r.Tax_Type__c, Tax_Master__r.Name
            FROM Cost_Sheet_Tax_Linking__c 
            WHERE Cost_Pricing_Association__c IN :pricingAssociationIds
        ];
            wrapper.taxLinkings = taxLinkings;
            
            List<Pricing_Element_Master__c> parkingMasters = [
            SELECT Id, Name, Parking_Type__c
            FROM Pricing_Element_Master__c
            WHERE Parking_Type__c != null
        ];
            wrapper.parkingMasters = parkingMasters;
            
            // Get Registration Master
            List<Pricing_Element_Master__c> registrationMaster = [
            SELECT Id, Name
            FROM Pricing_Element_Master__c
            WHERE Name LIKE '%Registration%'
            LIMIT 1
        ];
            if (!registrationMaster.isEmpty()) {
                wrapper.registrationMaster = registrationMaster[0];
            }
            
            try {
                SystemControl__c systemControl = SystemControl__c.getInstance();
                if (systemControl != null && systemControl.Agreement__c != null) {
                    wrapper.registrationPercentage = systemControl.Agreement__c;
                    System.debug('Registration Percentage from SystemControl__c: ' + wrapper.registrationPercentage);
                } else {
                    wrapper.registrationPercentage = 7.6;
                    System.debug('Registration Percentage defaulted to: 7.6');
                }
            } catch (Exception e) {
                System.debug('Error fetching SystemControl__c: ' + e.getMessage());
                wrapper.registrationPercentage = 7.6;
            }
            
            wrapper.isSuccess = true;
            System.debug('=== getTemplateData END - Success ===');
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getTemplateData: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            
            TemplateDataWrapper wrapper = new TemplateDataWrapper();
            wrapper.isSuccess = false;
            wrapper.errorMessage = e.getMessage();
            return wrapper;
        }
    }
    
    
    @AuraEnabled
    public static SaveResultWrapper saveAllCostSheetData(String saveDataJson) {
        Savepoint sp = Database.setSavepoint();
        
        try {
            System.debug('=== saveAllCostSheetData START ===');
            System.debug('Input JSON: ' + saveDataJson);
            
            SaveResultWrapper result = new SaveResultWrapper();
            
            // Deserialize JSON
            SaveDataWrapper saveData = (SaveDataWrapper) JSON.deserialize(saveDataJson, SaveDataWrapper.class);
            
            if (saveData == null) {
                result.isSuccess = false;
                result.errorMessage = 'Invalid save data provided';
                return result;
            }
            
            System.debug('Parsed Save Data:');
            System.debug('  Opportunity ID: ' + saveData.opportunityId);
            System.debug('  Unit ID: ' + saveData.unitId);
            System.debug('  Has Discount: ' + saveData.hasDiscount);
            System.debug('  Difference Amount: ' + saveData.differenceAmount);
            System.debug('  Pricing Elements Count: ' + (saveData.pricingElements != null ? saveData.pricingElements.size() : 0));
            
            // Get Opportunity details for approval process
            Opportunity opp = [
            SELECT Id, Project__c, Cluster__c, OwnerId 
            FROM Opportunity 
            WHERE Id = :saveData.opportunityId 
            LIMIT 1
        ];
            
            // ========================================
            // 1. CREATE COST SHEET (Version 1.0)
            // ========================================
            Cost_Sheet__c costSheet = new Cost_Sheet__c();
            costSheet.Opportunity__c = saveData.opportunityId;
            costSheet.Unit__c = saveData.unitId;
            costSheet.Cost_Scheme_Linking__c = saveData.costSchemeLinkingId;
            costSheet.Initial_Total_Amount__c = saveData.initialTotalAmount;
            costSheet.Revised_Total_Amount__c = saveData.revisedTotalAmount;
            costSheet.Unit_SBA__c = saveData.unitSBA;
            costSheet.Cost_Sheet_Version__c = 1.0;
            costSheet.Single_Parking_Count__c = saveData.singleParkingCount != null ? saveData.singleParkingCount : 1;
            costSheet.Dual_Parking_Count__c = saveData.dualParkingCount != null ? saveData.dualParkingCount : 0;
            
            insert costSheet;
            System.debug('Cost Sheet Created: ' + costSheet.Id + ' with Version 1.0');
            result.costSheetId = costSheet.Id;
            
            // ========================================
            // 2. CREATE PRICING ELEMENTS
            // ========================================
            List<Pricing_Element__c> pricingElementsToInsert = new List<Pricing_Element__c>();
            
            if (saveData.pricingElements != null && !saveData.pricingElements.isEmpty()) {
                for (PricingElementWrapper peWrapper : saveData.pricingElements) {
                    Pricing_Element__c pe = new Pricing_Element__c();
                    pe.Cost_Sheet__c = costSheet.Id;
                    pe.Pricing_Element_Master__c = peWrapper.pricingElementMasterId;
                    pe.PE_Type__c = peWrapper.peType;
                    pe.Type__c = peWrapper.type;
                    pe.Unit__c = peWrapper.unit;
                    pe.Sequence__c = peWrapper.sequence;
                    pe.Quantity__c = peWrapper.quantity;
                    pe.Rate__c = peWrapper.rate;
                    pe.Amount__c = peWrapper.amount;
                    
                    // Tax fields
                    pe.CGST_Tax_Percentage__c = peWrapper.cgstTaxPercent;
                    pe.SGST_Tax_Percentage__c = peWrapper.sgstTaxPercent;
                    pe.IGST_Tax_Percentage__c = peWrapper.igstTaxPercent;
                    pe.Tax_Amount__c = peWrapper.taxAmount;
                    
                    // Discount fields - STM Given Discount
                    pe.Discount_Psft__c = peWrapper.discountPsft;
                    pe.Discount_LS__c = peWrapper.discountLs;
                    pe.STM_Given_Discount__c = peWrapper.stmGivenDiscount;
                    pe.Final_Amount__c = peWrapper.finalAmount;
                    
                    // Other fields
                    pe.Description__c = peWrapper.description;
                    pe.parking_Element__c = peWrapper.isParkingElement;
                    
                    pricingElementsToInsert.add(pe);
                }
                
                insert pricingElementsToInsert;
                System.debug('Pricing Elements Created: ' + pricingElementsToInsert.size());
            }
            
            DiscountApprovalService.ApprovalResult approvalResult;
            
            if (saveData.hasDiscount && saveData.differenceAmount != null && saveData.differenceAmount > 0) {
                System.debug('Processing Discount Approval...');
                System.debug('  Difference Amount: ' + saveData.differenceAmount);
                System.debug('  Project Id: ' + opp.Project__c);
                System.debug('  Cluster Id: ' + opp.Cluster__c);
                System.debug('  Owner Id: ' + opp.OwnerId);
                
                approvalResult = DiscountApprovalService.processDiscountApproval(costSheet.Id, saveData.differenceAmount, opp.Project__c, opp.Cluster__c, opp.OwnerId );
                
                System.debug('Approval Result:');
                System.debug('  Is Success: ' + approvalResult.isSuccess);
                System.debug('  Requires Approval: ' + approvalResult.requiresApproval);
                System.debug('  Status: ' + approvalResult.approvalStatus);
                System.debug('  Message: ' + approvalResult.message);
                
                result.requiresApproval = approvalResult.requiresApproval;
                result.approvalStatus = approvalResult.approvalStatus;
                
                // NEW: Set approver info for multiple approvers
                if (approvalResult.approverIds != null && !approvalResult.approverIds.isEmpty()) {
                    result.approverCount = approvalResult.approverIds.size();
                }
                
                if (!approvalResult.isSuccess) {
                    System.debug('WARNING: Approval processing failed - ' + approvalResult.message);
                }
                
            } else {
                // No discount - directly approved
                System.debug('No discount applied - Cost Sheet approved directly');
                result.requiresApproval = false;
                result.approvalStatus = 'Approved';
                
                // Update cost sheet status to Approved
                Cost_Sheet__c csUpdate = new Cost_Sheet__c();
                csUpdate.Id = costSheet.Id;
                csUpdate.Approval_Status__c = 'Approved';
                update csUpdate;
            }
            
            // Opportunity oppToUpdate = new Opportunity();
            // oppToUpdate.Id = saveData.opportunityId;
            // update oppToUpdate;
            // System.debug('Opportunity Stage Updated');
            
            if (result.approvalStatus == 'Approved') {
                createPaymentScheduleInternal(costSheet.Id);
                System.debug('Payment Schedule Created');
            }
            
            result.isSuccess = true;
            result.message = approvalResult != null && approvalResult.requiresApproval
                ? 'Cost Sheet saved! ' + approvalResult.message
                : 'Cost Sheet saved successfully!';
            
            System.debug('=== saveAllCostSheetData END - Success ===');
            return result;
            
        } catch (Exception e) {
            Database.rollback(sp);
            
            System.debug('Error in saveAllCostSheetData: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            
            SaveResultWrapper result = new SaveResultWrapper();
            result.isSuccess = false;
            result.errorMessage = 'Error saving Cost Sheet: ' + e.getMessage();
            return result;
        }
    }
    
    private static void createPaymentScheduleInternal(Id costSheetId) {
        System.debug('=== Creating Payment Schedule for Cost Sheet: ' + costSheetId + ' ===');
        
        try {
            if (costSheetId == null) return;
            
            Cost_Sheet__c getCostSheet = [
            SELECT Id, Opportunity__c, Name, Cost_Scheme_Linking__c, 
                   Finalize_Cost_Sheet__c, 
                   Total_Agreement_Amount_Excluding_Tax__c,  
                   Total_Agreement_Tax_Amount__c,           
                   Cost_Scheme_Linking__r.Cost_Sheet_Template__c
            FROM Cost_Sheet__c 
            WHERE Id = :costSheetId 
            LIMIT 1
        ];
            
            Cost_Scheme_Linking__c getSchemeLinking = [
            SELECT Id, Payment_Scheme__c, Cost_Sheet_Template__c,
                   Cost_Sheet_Template__r.Amount__c, 
                   Cost_Sheet_Template__r.Tax_Amount__c,
                   Payment_Scheme__r.Token_Amount__c,
                   Payment_Scheme__r.Token_GST_Percentage__c
            FROM Cost_Scheme_Linking__c 
            WHERE Id = :getCostSheet.Cost_Scheme_Linking__c 
            LIMIT 1
        ];
            
            Tax_Details__c costSheetPaymentSchedulePercent = [
            SELECT Id, Name, CGST__c, SGST__c 
            FROM Tax_Details__c 
            WHERE Name = 'Cost Sheet Payment Schedule' 
            LIMIT 1];
            
            Decimal cgst = costSheetPaymentSchedulePercent.CGST__c != null ? costSheetPaymentSchedulePercent.CGST__c : 0;
            Decimal sgst = costSheetPaymentSchedulePercent.SGST__c != null ? costSheetPaymentSchedulePercent.SGST__c : 0;
            Decimal totalPercent = cgst + sgst;
            Decimal taxRate = totalPercent / 100;
            
            Decimal tokenAmount = getSchemeLinking.Payment_Scheme__r.Token_Amount__c;
            Decimal tokenGSTPercent = getSchemeLinking.Payment_Scheme__r.Token_GST_Percentage__c;
            
            
            Decimal totalAgreementExcludingTax = getCostSheet.Total_Agreement_Amount_Excluding_Tax__c;
            Decimal totalAgreementTax = getCostSheet.Total_Agreement_Tax_Amount__c;
            
            if (tokenGSTPercent == null) {
                tokenGSTPercent = 5;
            }
            
            if (tokenAmount == null) {
                tokenAmount = 0;
            }
            if (totalAgreementExcludingTax == null) {
                totalAgreementExcludingTax = 0;
            }
            if (totalAgreementTax == null) {
                totalAgreementTax = 0;
            }
            
            System.debug('Token Amount: ' + tokenAmount);
            System.debug('Token GST %: ' + tokenGSTPercent);
            System.debug('Total Agreement Excluding Tax: ' + totalAgreementExcludingTax);
            System.debug('Total Agreement Tax: ' + totalAgreementTax);
            
            List<Payment_Scheme_Installment__c> getPaymentSchemeRecords = [
            SELECT Id, Payment_Scheme__c, Payment_Scheme__r.Name, 
                   Installment__c, Name,
                   Payment_Schedule_Master__c, 
                   Payment_Schedule_Master__r.Name,
                   Payment_Schedule_Master__r.Installment_Code__c, 
                   Payment_Schedule_Master__r.Installment_Sequence__c,
                   Payment_Schedule_Master__r.Description__c,
                   Display_Order__c
            FROM Payment_Scheme_Installment__c 
            WHERE Payment_Scheme__c = :getSchemeLinking.Payment_Scheme__c
            ORDER BY Display_Order__c ASC
        ];
            
            Boolean isTokenAmountUsed = false;
            Decimal bookingInstallmentPercent = 0;
            
            for (Payment_Scheme_Installment__c psi : getPaymentSchemeRecords) {
                String scheduleName = psi.Payment_Schedule_Master__r.Name;
                
                if (scheduleName != null && scheduleName.containsIgnoreCase('Booking')) {
                    bookingInstallmentPercent = psi.Installment__c;
                    
                    if (psi.Installment__c == 0 && tokenAmount > 0) {
                        isTokenAmountUsed = true;
                    }
                    break;
                }
            }
            
            Decimal baseAmountForCalculation = isTokenAmountUsed
                ? (totalAgreementExcludingTax - tokenAmount)
                : totalAgreementExcludingTax;
            
            System.debug('Is Token Amount Used: ' + isTokenAmountUsed);
            System.debug('Base Amount for Calculation: ' + baseAmountForCalculation);
            
            Decimal bookingAmount = 0;
            Decimal bookingTaxAmount = 0;
            
            if (isTokenAmountUsed) {
                bookingAmount = tokenAmount;
                bookingTaxAmount = (tokenAmount * tokenGSTPercent) / 100;
            } else {
                bookingAmount = (baseAmountForCalculation / 100) * bookingInstallmentPercent;
                bookingTaxAmount = bookingAmount * taxRate;
            }
            
            System.debug('>>> BOOKING AMOUNT: ' + bookingAmount);
            System.debug('>>> BOOKING TAX: ' + bookingTaxAmount);
            
            List<Cost_Sheet_Payment_Schedule__c> allPaymentSchedules = new List<Cost_Sheet_Payment_Schedule__c>();
            
            for (Payment_Scheme_Installment__c psi : getPaymentSchemeRecords) {
                Cost_Sheet_Payment_Schedule__c ps = new Cost_Sheet_Payment_Schedule__c();
                
                Decimal rawAgreement = 0;
                Decimal rawTax = 0;
                
                String scheduleName = psi.Payment_Schedule_Master__r.Name;
                Boolean isBookingAmount = scheduleName != null && scheduleName.containsIgnoreCase('Booking');
                
                Boolean useTokenAmount = isBookingAmount
                    && psi.Installment__c == 0
                    && tokenAmount > 0;
                
                if (useTokenAmount) {
                    System.debug('>>> TOKEN BASED: ' + scheduleName);
                    
                    rawAgreement = tokenAmount;
                    rawTax = (tokenAmount * tokenGSTPercent) / 100;
                    
                    System.debug('    Token Amount: ' + rawAgreement);
                    System.debug('    Token GST %: ' + tokenGSTPercent);
                    System.debug('    Tax Amount: ' + rawTax);
                    
                } else {
                    System.debug('>>> PERCENTAGE BASED: ' + scheduleName + ' (' + psi.Installment__c + '%)');
                    
                    rawAgreement = (baseAmountForCalculation / 100) * psi.Installment__c;
                    rawTax       = (rawAgreement) * taxRate;
                    
                    System.debug('    Base Amount: ' + baseAmountForCalculation);
                    System.debug('    Agreement Value: ' + rawAgreement);
                    System.debug('    Tax Amount: ' + rawTax);
                }
                
                ps.Opportunity__c = getCostSheet.Opportunity__c;
                ps.Cost_Sheet__c = costSheetId;
                ps.Installment__c = psi.Installment__c;
                ps.Type__c = 'Agreement';
                ps.Agreement_Value__c = rawAgreement;
                ps.Tax_Amount__c = rawTax;
                ps.Diff_Agreement_Value__c = ps.Agreement_Value__c - rawAgreement;
                ps.Diff_Tax_Amount__c = ps.Tax_Amount__c - rawTax;
                ps.Other_Charges__c = 0;
                ps.Other_Tax_Amount__c = 0;
                ps.Installment_Sequence__c = psi.Display_Order__c;
                ps.Description__c = psi.Payment_Schedule_Master__r.Description__c;
                ps.Name = psi.Payment_Schedule_Master__r.Name;
                
                allPaymentSchedules.add(ps);
            }
            
            List<Pricing_Element__c> amenitiesPricingElements = [ SELECT Id, Cost_Sheet__c, Pricing_Element_Master__c, 
                   Pricing_Element_Master__r.Name, Type__c, Quantity__c, 
                   Amount__c, Actual_Amount__c, Total_Amount_Excluding_Tax__c, 
                   Final_Tax_Amount__c, Description__c, Sequence__c  
                FROM Pricing_Element__c 
                WHERE Cost_Sheet__c = :costSheetId 
                AND Type__c = 'Non-Agreement'
            ];
            
            System.debug('=== Processing Non-Agreement (Amenities) Records: ' + amenitiesPricingElements.size() + ' ===');
            
            for (Pricing_Element__c pe : amenitiesPricingElements) {
                Cost_Sheet_Payment_Schedule__c ps = new Cost_Sheet_Payment_Schedule__c();
                
                ps.Name    = pe.Pricing_Element_Master__r.Name;
                ps.Type__c = pe.Type__c;
                ps.Cost_Sheet__c = costSheetId;
                ps.Opportunity__c = getCostSheet.Opportunity__c;
                
                ps.Agreement_Value__c = pe.Total_Amount_Excluding_Tax__c != null ? pe.Total_Amount_Excluding_Tax__c : 0;
                ps.Tax_Amount__c = pe.Final_Tax_Amount__c != null ? pe.Final_Tax_Amount__c : 0;
                ps.Description__c = pe.Description__c;
                ps.Installment_Sequence__c = pe.Sequence__c;
                //ps.Installment__c = 0;
                
                System.debug('>>> NON-AGREEMENT: ' + ps.Name);
                System.debug('    Agreement Value: ' + ps.Agreement_Value__c);
                System.debug('    Tax Amount: ' + ps.Tax_Amount__c);
                
                allPaymentSchedules.add(ps);
            }
            
            if (!allPaymentSchedules.isEmpty()) {
                insert allPaymentSchedules;
                System.debug('=== Payment Schedules Created: ' + allPaymentSchedules.size() + ' ===');
            }
            
            Cost_Sheet__c costSheetToUpdate = new Cost_Sheet__c();
            costSheetToUpdate.Id = costSheetId;
            costSheetToUpdate.Booking_Amount__c = bookingAmount;
            costSheetToUpdate.Booking_Tax_Amount__c = bookingTaxAmount;
            update costSheetToUpdate;
            
            System.debug('=== Cost Sheet Updated with Booking Amount: ' + bookingAmount + ', Booking Tax: ' + bookingTaxAmount + ' ===');
            
            
        } catch (Exception e) {
            System.debug('Error: ' + e.getLineNumber() + ' ---> ' + e.getMessage());
            throw new AuraHandledException('Error creating payment schedule: ' + e.getMessage());
        }
    }
    
    
    @AuraEnabled
    public static void createPaymentSchedule(Id costSheetId) {
        System.debug('Processing Cost Sheet ID: ' + costSheetId);
        
        try {
            if (costSheetId != null) {
                createPaymentScheduleInternal(costSheetId);
            }
        } catch (Exception e) {
            System.debug('Error: ' + e.getLineNumber() + ' ---> ' + e.getMessage());
            throw new AuraHandledException('Error creating payment schedule: ' + e.getMessage());
        }
    }
    
    // ============================================
    // UTILITY METHODS
    // ============================================
    
    public static Decimal getDecimalValue(Object value) {
        try {
            if (value == null) {
                return 0;
            } else if (value instanceof Decimal) {
                return (Decimal) value;
            } else if (value instanceof String) {
                return Decimal.valueOf((String) value);
            }
        } catch (Exception e) {
            System.debug('Error converting to Decimal: ' + e.getMessage());
        }
        return 0;
    }
    
    public static Integer getIntegerValue(Object value) {
        try {
            if (value == null) {
                return 1;
            } else if (value instanceof Decimal) {
                return ((Decimal) value).intValue();
            } else if (value instanceof String) {
                return Integer.valueOf((String) value);
            }
        } catch (Exception e) {
            System.debug('Error converting to Integer: ' + e.getMessage());
        }
        return 1;
    }
    
    // ============================================
    // WRAPPER CLASSES
    // ============================================
    
    /**
     * Wrapper for on-load data
     */
    public class fetchDataWrapper {
        @AuraEnabled public List<Unit__c> unitList { get; set; }
        @AuraEnabled public List<Cost_Sheet_Template__c> costSheetTemplateList { get; set; }
        @AuraEnabled public Opportunity opp { get; set; }
        @AuraEnabled public Tax_Details__c carParkingTax { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean validationError { get; set; }
    }
    
    /**
     * Wrapper for template data
     */
    public class TemplateDataWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Unit__c unitData { get; set; }
        @AuraEnabled public Cost_Scheme_Linking__c costSchemeLinking { get; set; }
        @AuraEnabled public List<Cost_Pricing_Association__c> pricingAssociations { get; set; }
        @AuraEnabled public List<Cost_Sheet_Tax_Linking__c> taxLinkings { get; set; }
        @AuraEnabled public List<Pricing_Element_Master__c> parkingMasters { get; set; }
        @AuraEnabled public Pricing_Element_Master__c registrationMaster { get; set; }
        @AuraEnabled public Project__c projectData { get; set; }
        @AuraEnabled public Decimal registrationPercentage { get; set; }
        
        public TemplateDataWrapper() {
            this.isSuccess = false;
            this.pricingAssociations = new List<Cost_Pricing_Association__c>();
            this.taxLinkings = new List<Cost_Sheet_Tax_Linking__c>();
            this.parkingMasters = new List<Pricing_Element_Master__c>();
            this.registrationPercentage = 0;
        }
    }
    
    public class SaveDataWrapper {
        @AuraEnabled public String opportunityId { get; set; }
        @AuraEnabled public String unitId { get; set; }
        @AuraEnabled public String costSchemeLinkingId { get; set; }
        @AuraEnabled public String costSheetTemplateId { get; set; }
        @AuraEnabled public String entryPoint { get; set; }
        
        // Discount related
        @AuraEnabled public Boolean hasDiscount { get; set; }
        @AuraEnabled public Decimal differenceAmount { get; set; }
        @AuraEnabled public Decimal unitSBA { get; set; }
        @AuraEnabled public Decimal initialTotalAmount { get; set; }
        @AuraEnabled public Decimal revisedTotalAmount { get; set; }
        
        @AuraEnabled public Integer singleParkingCount { get; set; }
        @AuraEnabled public Integer dualParkingCount { get; set; }
        
        // Data arrays
        @AuraEnabled public List<PricingElementWrapper> pricingElements { get; set; }
        @AuraEnabled public List<DiscountDataWrapper> discountData { get; set; }
    }
    
    /**
     * Wrapper for pricing element
     */
    public class PricingElementWrapper {
        @AuraEnabled public String pricingElementMasterId { get; set; }
        @AuraEnabled public String peType { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String unit { get; set; }
        @AuraEnabled public Decimal sequence { get; set; }
        @AuraEnabled public Decimal quantity { get; set; }
        @AuraEnabled public Decimal rate { get; set; }
        @AuraEnabled public Decimal amount { get; set; }
        
        // Tax fields
        @AuraEnabled public Decimal cgstTaxPercent { get; set; }
        @AuraEnabled public Decimal sgstTaxPercent { get; set; }
        @AuraEnabled public Decimal igstTaxPercent { get; set; }
        @AuraEnabled public Decimal taxAmount { get; set; }
        
        // Discount fields
        @AuraEnabled public Decimal discountPsft { get; set; }
        @AuraEnabled public Decimal discountLs { get; set; }
        @AuraEnabled public Decimal stmGivenDiscount { get; set; }
        @AuraEnabled public Decimal finalAmount { get; set; }
        
        // Other fields
        @AuraEnabled public String description { get; set; }
        @AuraEnabled public Boolean isParkingElement { get; set; }
    }
    
    /**
     * Wrapper for discount data
     */
    public class DiscountDataWrapper {
        @AuraEnabled public String pricingElementMasterId { get; set; }
        @AuraEnabled public Decimal discountAmount { get; set; }
        @AuraEnabled public Boolean isLsType { get; set; }
    }
    
    /**
     * Wrapper for discount configuration
     */
    public class DiscountConfigWrapper {
        @AuraEnabled public Boolean hasDiscountConfig { get; set; }
        @AuraEnabled public Id discountMasterId { get; set; }
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public Decimal stmMaxLimit { get; set; }
        @AuraEnabled public List<DiscountLevelWrapper> discountLevels { get; set; }
        
        public DiscountConfigWrapper() {
            this.hasDiscountConfig = false;
            this.discountLevels = new List<DiscountLevelWrapper>();
        }
    }
    
    /**
     * Wrapper for discount level
     */
    public class DiscountLevelWrapper {
        @AuraEnabled public Id lineItemId { get; set; }
        @AuraEnabled public String role { get; set; }
        @AuraEnabled public Decimal minimumAmount { get; set; }
        @AuraEnabled public Decimal maximumAmount { get; set; }
    }
    
    /**
     * Wrapper for save result (UPDATED)
     */
    public class SaveResultWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public String costSheetId { get; set; }
        @AuraEnabled public Boolean requiresApproval { get; set; }
        @AuraEnabled public String approvalStatus { get; set; }
        @AuraEnabled public Integer approverCount { get; set; }
        
        public SaveResultWrapper() {
            this.isSuccess = false;
            this.requiresApproval = false;
            this.approverCount = 0;
        }
    }

}