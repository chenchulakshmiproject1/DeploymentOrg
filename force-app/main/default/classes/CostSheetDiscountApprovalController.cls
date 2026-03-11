/**
 * @File Name : CostSheetDiscountApprovalController.cls
 * @Description : Controller for Cost Sheet Discount Approval LWC Component.
 *                Handles fetching pending cost sheets, cost sheet details,
 *                saving approvals, and rejecting cost sheets.
 *                Updated: Multiple approvers support, version tracking, cluster-based querying
 * @Author : Yashwanth M V
 * @Last Modified On : 21-12-2025
 */
public without sharing class CostSheetDiscountApprovalController {
    
    @AuraEnabled
    public static UserInfoWrapper getCurrentUserInfo() {
        try {
            User currentUser = [
                SELECT Id, Name, UserRole.Name, Profile.Name, ManagerId
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];
            
            UserInfoWrapper wrapper = new UserInfoWrapper();
            wrapper.userId = currentUser.Id;
            wrapper.userName = currentUser.Name;
            wrapper.userRole = getRoleLevelFromRoleName(currentUser.UserRole?.Name);
            wrapper.profileName = currentUser.Profile?.Name;
            wrapper.managerId = currentUser.ManagerId;
            
            System.debug('Current User Info: ' + JSON.serialize(wrapper));
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error getting user info: ' + e.getMessage());
            throw new AuraHandledException('Error getting user info: ' + e.getMessage());
        }
    }
    
    @AuraEnabled
    public static List<PendingCostSheetWrapper> getPendingCostSheets(String opportunityId) {
        System.debug('=== getPendingCostSheets START ===');
        System.debug('Opportunity Id: ' + opportunityId);
        System.debug('Current User Id: ' + UserInfo.getUserId());
        
        List<PendingCostSheetWrapper> resultList = new List<PendingCostSheetWrapper>();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            String currentUserIdStr = String.valueOf(currentUserId);
            
            List<Cost_Sheet__c> allCostSheets = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Name,
                       Unit__c, Unit__r.Name, Unit__r.Unit_Name__c,
                       Approval_Status__c, Next_Approver_Ids__c, Next_Approvers__c,
                       Current_Approval_Level__c, Total_Approval_Levels__c,
                       Difference_Amount__c, Initial_Total_Amount__c, 
                       Revised_Total_Amount__c, Unit_SBA__c,
                       Highest_Approver_Role__c, Approved_By__c,
                       CreatedDate, CreatedById, Cost_Sheet_Version__c
                FROM Cost_Sheet__c
                WHERE Opportunity__c = :opportunityId
                AND Approval_Status__c IN ('Under Approval', 'Approval Time-Out')
                ORDER BY CreatedDate DESC
            ];
            
            for (Cost_Sheet__c cs : allCostSheets) {
                PendingCostSheetWrapper wrapper = new PendingCostSheetWrapper();
                wrapper.costSheet = cs;
                wrapper.costSheetId = cs.Id;
                wrapper.costSheetName = cs.Name;
                wrapper.unitName = cs.Unit__r?.Name;
                wrapper.differenceAmount = cs.Difference_Amount__c;
                wrapper.approvalStatus = cs.Approval_Status__c;
                wrapper.approvedBy = cs.Approved_By__c;
                wrapper.createdDate = cs.CreatedDate;
                wrapper.version = cs.Cost_Sheet_Version__c;
                
                Boolean isCurrentUserApprover = false;
                if (cs.Next_Approver_Ids__c != null && cs.Next_Approver_Ids__c.contains(currentUserIdStr)) {
                    isCurrentUserApprover = true;
                }
                
                wrapper.isCurrentUserApprover = isCurrentUserApprover;
                
                if (cs.Approval_Status__c == 'Approved' && cs.Approved_By__c != null) {
                    wrapper.isAlreadyApproved = true;
                    wrapper.approvedByName = cs.Approved_By__c;
                } else if (cs.Approval_Status__c == 'Under Approval' && !isCurrentUserApprover) {
                    wrapper.isAlreadyApproved = false;
                } else {
                    wrapper.isAlreadyApproved = false;
                }
                
                if (isCurrentUserApprover || (cs.Approval_Status__c == 'Approved' && wasUserPreviousApprover(cs, currentUserIdStr))) {
                    resultList.add(wrapper);
                }
            }
            
            System.debug('Found ' + resultList.size() + ' cost sheets for current user');
            System.debug('=== getPendingCostSheets END ===');
            
            return resultList;
            
        } catch (Exception e) {
            System.debug('Error in getPendingCostSheets: ' + e.getMessage());
            throw new AuraHandledException('Error fetching pending cost sheets: ' + e.getMessage());
        }
    }
    
    private static Boolean wasUserPreviousApprover(Cost_Sheet__c cs, String userId) {
        if (cs.Approved_By__c != null && cs.CreatedDate != null) {
            DateTime approvalWindow = DateTime.now().addHours(-24);
            if (cs.CreatedDate > approvalWindow) {
                return true;
            }
        }
        return false;
    }
    
    @AuraEnabled
    public static CostSheetDetailsWrapper getCostSheetDetails(String costSheetId) {
        System.debug('=== getCostSheetDetails START ===');
        System.debug('Cost Sheet Id: ' + costSheetId);
        
        CostSheetDetailsWrapper wrapper = new CostSheetDetailsWrapper();
        
        try {
            Id currentUserId = UserInfo.getUserId();
            String currentUserIdStr = String.valueOf(currentUserId);
            
            Cost_Sheet__c costSheet = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Project__c, 
                       Opportunity__r.Cluster__c, Opportunity__r.OwnerId,
                       Unit__c, Unit__r.Name, Unit__r.Super_Built_Up_Area_sq_ft__c,
                       Approval_Status__c, Next_Approver_Ids__c, Next_Approvers__c,
                       Current_Approval_Level__c, Total_Approval_Levels__c,
                       Difference_Amount__c, Initial_Total_Amount__c,
                       Revised_Total_Amount__c, Unit_SBA__c,
                       Highest_Approver_Role__c, Approved_By__c, Cost_Sheet_Version__c
                FROM Cost_Sheet__c
                WHERE Id = :costSheetId
                LIMIT 1
            ];
            
            if (costSheet.Approval_Status__c == 'Approved') {
                wrapper.isSuccess = true;
                wrapper.isAlreadyApproved = true;
                wrapper.approvedByName = costSheet.Approved_By__c;
                wrapper.costSheetId = costSheet.Id;
                wrapper.costSheetName = costSheet.Name;
                return wrapper;
            }
            
            Boolean isAuthorized = false;
            if (costSheet.Next_Approver_Ids__c != null && costSheet.Next_Approver_Ids__c.contains(currentUserIdStr)) {
                isAuthorized = true;
            }
            
            if (!isAuthorized) {
                wrapper.isSuccess = false;
                wrapper.errorMessage = 'You are not authorized to approve this cost sheet.';
                return wrapper;
            }
            
            List<Pricing_Element__c> pricingElements = [
                SELECT Id, Name, Pricing_Element_Master__c, Pricing_Element_Master__r.Name,
                       PE_Type__c, Type__c, Unit__c, Sequence__c,
                       Quantity__c, Rate__c, Amount__c, Final_Amount__c,
                       Tax_Amount__c, CGST_Tax_Percentage__c, SGST_Tax_Percentage__c,
                       Discount_Psft__c, Discount_LS__c,
                       STM_Given_Discount__c, SM_Given_Discount__c, 
                       SH_Given_Discount__c, MD_Given_Discount__c
                FROM Pricing_Element__c
                WHERE Cost_Sheet__c = :costSheetId
                ORDER BY Sequence__c ASC
            ];
            
            List<DiscountApprovalService.DiscountLevelConfig> discountLevels =
                DiscountApprovalService.getDiscountLevelsForProject(costSheet.Opportunity__r.Project__c);
            
            wrapper.isSuccess = true;
            wrapper.isAlreadyApproved = false;
            wrapper.costSheetId = costSheet.Id;
            wrapper.costSheetName = costSheet.Name;
            wrapper.opportunityId = costSheet.Opportunity__c;
            wrapper.projectId = costSheet.Opportunity__r.Project__c;
            wrapper.clusterId = costSheet.Opportunity__r.Cluster__c;
            wrapper.unitId = costSheet.Unit__c;
            wrapper.unitName = costSheet.Unit__r?.Name;
            wrapper.unitSBA = costSheet.Unit_SBA__c != null ? costSheet.Unit_SBA__c :
                (costSheet.Unit__r?.Super_Built_Up_Area_sq_ft__c != null ?
                costSheet.Unit__r.Super_Built_Up_Area_sq_ft__c : 0);
            
            wrapper.currentApprovalLevel = costSheet.Current_Approval_Level__c != null ?
                Integer.valueOf(costSheet.Current_Approval_Level__c) : 1;
            wrapper.totalApprovalLevels = costSheet.Total_Approval_Levels__c != null ?
                Integer.valueOf(costSheet.Total_Approval_Levels__c) : 1;
            wrapper.highestApproverRole = costSheet.Highest_Approver_Role__c;
            wrapper.currentVersion = costSheet.Cost_Sheet_Version__c != null ?
                costSheet.Cost_Sheet_Version__c : 1.0;
            
            wrapper.initialTotalAmount = costSheet.Initial_Total_Amount__c;
            wrapper.revisedTotalAmount = costSheet.Revised_Total_Amount__c;
            wrapper.differenceAmount = costSheet.Difference_Amount__c;
            
            wrapper.pricingElements = pricingElements;
            
            wrapper.discountLevels = new List<DiscountLevelWrapper>();
            for (DiscountApprovalService.DiscountLevelConfig config : discountLevels) {
                DiscountLevelWrapper levelWrapper = new DiscountLevelWrapper();
                levelWrapper.role = config.role;
                levelWrapper.minimumAmount = config.minimumAmount;
                levelWrapper.maximumAmount = config.maximumAmount;
                levelWrapper.levelNumber = config.levelNumber;
                wrapper.discountLevels.add(levelWrapper);
            }
            
            if (wrapper.currentApprovalLevel <= discountLevels.size()) {
                wrapper.currentApproverRole = discountLevels[wrapper.currentApprovalLevel - 1].role;
            }
            
            System.debug('Cost Sheet Details loaded successfully');
            System.debug('Pricing Elements: ' + pricingElements.size());
            System.debug('=== getCostSheetDetails END ===');
            
            return wrapper;
            
        } catch (Exception e) {
            System.debug('Error in getCostSheetDetails: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            
            wrapper.isSuccess = false;
            wrapper.errorMessage = 'Error loading cost sheet details: ' + e.getMessage();
            return wrapper;
        }
    }
    
    
    @AuraEnabled
    public static ApprovalResultWrapper saveApprovalDiscounts(String approvalDataJson) {
        System.debug('=== saveApprovalDiscounts START ===');
        System.debug('Approval Data: ' + approvalDataJson);
        
        Savepoint sp = Database.setSavepoint();
        ApprovalResultWrapper result = new ApprovalResultWrapper();
        
        try {
            ApprovalDataWrapper approvalData = (ApprovalDataWrapper) JSON.deserialize(
                approvalDataJson, ApprovalDataWrapper.class
            );
            
            Id costSheetId = approvalData.costSheetId;
            Integer currentLevel = approvalData.currentApprovalLevel;
            Decimal newDifference = approvalData.differenceAmount;
            
            Cost_Sheet__c costSheet = [
                SELECT Id, Name, Opportunity__c, Opportunity__r.Project__c,
                       Opportunity__r.Cluster__c, Opportunity__r.OwnerId,
                       Next_Approver_Ids__c, Next_Approvers__c, Current_Approval_Level__c,
                       Total_Approval_Levels__c, Highest_Approver_Role__c,
                       Approval_Status__c, Cost_Sheet_Version__c
                FROM Cost_Sheet__c
                WHERE Id = :costSheetId
                LIMIT 1
            ];
            
            if (costSheet.Approval_Status__c == 'Approved') {
                result.isSuccess = false;
                result.isAlreadyApproved = true;
                result.approvedByName = costSheet.Approved_By__c;
                result.errorMessage = 'This cost sheet has already been approved.';
                return result;
            }
            
            Id currentUserId = UserInfo.getUserId();
            String currentUserIdStr = String.valueOf(currentUserId);
            
            if (costSheet.Next_Approver_Ids__c == null || !costSheet.Next_Approver_Ids__c.contains(currentUserIdStr)) {
                result.isSuccess = false;
                result.errorMessage = 'You are not authorized to approve this cost sheet.';
                return result;
            }
            
            User currentUser = [
                SELECT Id, Name, UserRole.Name, ManagerId, Profile.Name
                FROM User
                WHERE Id = :currentUserId
                LIMIT 1
            ];
            String currentUserRole = getRoleLevelFromRoleName(currentUser.UserRole?.Name);
            System.debug('Current User: ' + currentUser.Name + ', Role: ' + currentUserRole);
            
            List<DiscountApprovalService.DiscountLevelConfig> discountLevels =
                DiscountApprovalService.getDiscountLevelsForProject(costSheet.Opportunity__r.Project__c);
            
            // Boolean isManagement = currentUserRole.containsIgnoreCase('Management') ||
            //     currentUser.Profile.Name == 'Management';
            
            // if (isManagement) {
            //     Decimal mgmtMaxLimit = getManagementMaxLimit(discountLevels);
            //     System.debug('Management Max Limit: ' + mgmtMaxLimit);
            //     System.debug('New Difference: ' + newDifference);
                
            //     if (mgmtMaxLimit != null && newDifference > mgmtMaxLimit) {
            //         result.isSuccess = false;
            //         result.errorMessage = 'Discount exceeds maximum limit of ₹' + mgmtMaxLimit.format() +
            //             '/sqft. Please reduce the discount amount.';
            //         return result;
            //     }
            // }
            
            Boolean discountChanged = checkIfDiscountChanged(costSheetId, approvalData.pricingElements);
            System.debug('Discount Changed: ' + discountChanged);
            
            List<Pricing_Element__c> pricingElementsToUpdate = new List<Pricing_Element__c>();
            
            String currentLevelRole = '';
            if (currentLevel <= discountLevels.size()) {
                currentLevelRole = discountLevels[currentLevel - 1].role;
            }
            
            for (PricingElementApprovalWrapper peWrapper : approvalData.pricingElements) {
                Pricing_Element__c pe = new Pricing_Element__c();
                pe.Id = peWrapper.id;
                
                if (currentLevelRole.containsIgnoreCase('Sales Manager')) {
                    pe.SM_Given_Discount__c = peWrapper.approvalDiscount;
                } else if (currentLevelRole.containsIgnoreCase('Sales Head')) {
                    pe.SH_Given_Discount__c = peWrapper.approvalDiscount;
                } else if (currentLevelRole.containsIgnoreCase('Management')) {
                    pe.MD_Given_Discount__c = peWrapper.approvalDiscount;
                }
                
                if (peWrapper.isLsType) {
                    pe.Discount_LS__c = peWrapper.approvalDiscount;
                } else {
                    pe.Discount_Psft__c = peWrapper.approvalDiscount;
                }
                
                pricingElementsToUpdate.add(pe);
            }
            
            if (!pricingElementsToUpdate.isEmpty()) {
                update pricingElementsToUpdate;
                System.debug('Updated ' + pricingElementsToUpdate.size() + ' pricing elements');
            }
            
            if (discountChanged) {
                DiscountApprovalService.incrementCostSheetVersion(costSheetId);
                System.debug('Version incremented');
            }
            
            DiscountApprovalService.ApprovalLevelInfo levelInfo =
                DiscountApprovalService.determineApprovalLevel(newDifference, discountLevels);
            
            System.debug('New Difference: ' + newDifference);
            System.debug('Level Info - Required Role: ' + levelInfo.requiredRole);
            System.debug('Level Info - Level Number: ' + levelInfo.levelNumber);
            System.debug('Level Info - Within STM Limit: ' + levelInfo.withinStmLimit);
            System.debug('Current Level: ' + currentLevel);
            
            Boolean canApprove = levelInfo.withinStmLimit || (levelInfo.levelNumber <= currentLevel);
            
            System.debug('Can Approve at current level: ' + canApprove);
            
            if (canApprove) {
                DiscountApprovalService.updateCostSheetStatus(
                    costSheetId,
                    'Approved',
                    null,
                    null,
                    currentLevel,
                    newDifference,
                    currentUser.Name
                );
                
                DiscountApprovalService.sendNotificationToPreviousApprovers(
                    costSheetId, currentUserId, 'Approved', newDifference
                );
                
                CostSheetGenerationController.createPaymentSchedule(costSheetId);
                
                result.isSuccess = true;
                result.requiresNextLevel = false;
                result.message = 'Cost Sheet approved successfully!';
                
                System.debug('Approval Complete - Cost Sheet Approved by ' + currentUser.Name);
                
            } else {
                DiscountApprovalService.ApproverInfo nextApprovers = 
                    DiscountApprovalService.getNextLevelApprovers(
                        currentLevel,
                        discountLevels,
                        costSheet.Opportunity__r.Cluster__c
                    );
                
                if (nextApprovers.approverIds.isEmpty()) {
                    result.isSuccess = false;
                    result.errorMessage = 'Could not find next level approvers. Please contact administrator.';
                    Database.rollback(sp);
                    return result;
                }
                
                String nextApproverRole = '';
                if (currentLevel < discountLevels.size()) {
                    nextApproverRole = discountLevels[currentLevel].role;
                }
                
                DiscountApprovalService.updateCostSheetStatus(
                    costSheetId,
                    'Under Approval',
                    nextApprovers.approverIds,
                    nextApprovers.approverNames,
                    currentLevel + 1,
                    newDifference,
                    null
                );   
                
                if (levelInfo.levelNumber > costSheet.Total_Approval_Levels__c) {
                    DiscountApprovalService.updateCostSheetApprovalMetadata(
                        costSheetId,
                        levelInfo.levelNumber,
                        levelInfo.requiredRole
                    );
                }
                
               
                for (Id approverId : nextApprovers.approverIds) {
                    DiscountApprovalService.sendApprovalNotification(
                        costSheetId, approverId, currentUserId, newDifference, nextApproverRole
                    );
                    DiscountApprovalService.sendApprovalEmail(
                        costSheetId, approverId, currentUserId, newDifference
                    );
                }
                
                DiscountApprovalService.sendNotificationToPreviousApprovers(
                    costSheetId, currentUserId, 'Sent to Next Level', newDifference
                );
                
                result.isSuccess = true;
                result.requiresNextLevel = true;
                result.nextApproverNames = String.join(nextApprovers.approverNames, ', ');
                result.nextApproverRole = nextApproverRole;
                result.message = 'Discount exceeds your approval limit. Sent to ' + nextApproverRole + 
                    ' (' + nextApprovers.approverNames.size() + ' approver(s)) for further approval.';
                
                System.debug('Sent to next approvers: ' + nextApprovers.approverNames);
            }
            
            System.debug('=== saveApprovalDiscounts END ===');
            return result;
            
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug('Error in saveApprovalDiscounts: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            System.debug('Stack: ' + e.getStackTraceString());
            
            result.isSuccess = false;
            result.errorMessage = 'Error saving approval: ' + e.getMessage();
            return result;
        }
    }
    
    private static Boolean checkIfDiscountChanged(Id costSheetId, List<PricingElementApprovalWrapper> newElements) {
        System.debug('=== checkIfDiscountChanged START ===');
        
        
        Map<Id, Pricing_Element__c> existingElements = new Map<Id, Pricing_Element__c>([
            SELECT Id, Discount_Psft__c, Discount_LS__c, PE_Type__c
            FROM Pricing_Element__c
            WHERE Cost_Sheet__c = :costSheetId
        ]);
        
        for (PricingElementApprovalWrapper newPe : newElements) {
            Pricing_Element__c existingPe = existingElements.get(newPe.id);
            
            if (existingPe != null) {
                Decimal existingDiscount = 0;
                if (newPe.isLsType) {
                    existingDiscount = existingPe.Discount_LS__c != null ? existingPe.Discount_LS__c : 0;
                } else {
                    existingDiscount = existingPe.Discount_Psft__c != null ? existingPe.Discount_Psft__c : 0;
                }
                
                Decimal newDiscount = newPe.approvalDiscount != null ? newPe.approvalDiscount : 0;
                
                System.debug('Element ' + newPe.id + ': Existing=' + existingDiscount + ', New=' + newDiscount);
                
                if (existingDiscount != newDiscount) {
                    System.debug('Discount changed for element: ' + newPe.id);
                    return true;
                }
            }
        }
        
        System.debug('No discount changes detected');
        System.debug('=== checkIfDiscountChanged END ===');
        return false;
    }
    
    // private static Decimal getManagementMaxLimit(List<DiscountApprovalService.DiscountLevelConfig> discountLevels) {
    //     for (DiscountApprovalService.DiscountLevelConfig level : discountLevels) {
    //         if (level.role.containsIgnoreCase('Management')) {
    //             return level.maximumAmount;
    //         }
    //     }
    //     return null;
    // }
    
    
    @AuraEnabled
    public static Boolean rejectCostSheet(String costSheetId) {
        System.debug('=== rejectCostSheet START ===');
        System.debug('Cost Sheet Id: ' + costSheetId);
        
        try {
            Id currentUserId = UserInfo.getUserId();
            String currentUserIdStr = String.valueOf(currentUserId);
            
            Cost_Sheet__c costSheet = [
                SELECT Id, Next_Approver_Ids__c, Approval_Status__c
                FROM Cost_Sheet__c
                WHERE Id = :costSheetId
                LIMIT 1
            ];
            
            if (costSheet.Approval_Status__c != 'Under Approval') {
                throw new AuraHandledException('This cost sheet has already been processed.');
            }
            
            if (costSheet.Next_Approver_Ids__c == null || !costSheet.Next_Approver_Ids__c.contains(currentUserIdStr)) {
                throw new AuraHandledException('You are not authorized to reject this cost sheet.');
            }
            
            Boolean success = DiscountApprovalService.rejectCostSheet(costSheetId);
            
            System.debug('=== rejectCostSheet END - Success: ' + success + ' ===');
            return success;
            
        } catch (Exception e) {
            System.debug('Error in rejectCostSheet: ' + e.getMessage());
            throw new AuraHandledException('Error rejecting cost sheet: ' + e.getMessage());
        }
    }
    
    private static String getRoleLevelFromRoleName(String roleName) {
        if (String.isBlank(roleName)) {
            return 'Unknown';
        }
        
        if (roleName.containsIgnoreCase('Management')) {
            return 'Management';
        } else if (roleName.containsIgnoreCase('Sales Head')) {
            return 'Sales Head';
        } else if (roleName.containsIgnoreCase('Sales Manager')) {
            return 'Sales Manager';
        } else if (roleName.containsIgnoreCase('Sales Team')) {
            return 'Sales Team Member';
        }
        
        return roleName;
    }
    
    
    public class UserInfoWrapper {
        @AuraEnabled public Id userId { get; set; }
        @AuraEnabled public String userName { get; set; }
        @AuraEnabled public String userRole { get; set; }
        @AuraEnabled public String profileName { get; set; }
        @AuraEnabled public Id managerId { get; set; }
    }
    
    public class PendingCostSheetWrapper {
        @AuraEnabled public Cost_Sheet__c costSheet { get; set; }
        @AuraEnabled public Id costSheetId { get; set; }
        @AuraEnabled public String costSheetName { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public Decimal differenceAmount { get; set; }
        @AuraEnabled public String approvalStatus { get; set; }
        @AuraEnabled public String approvedBy { get; set; }
        @AuraEnabled public DateTime createdDate { get; set; }
        @AuraEnabled public Decimal version { get; set; }
        @AuraEnabled public Boolean isCurrentUserApprover { get; set; }
        @AuraEnabled public Boolean isAlreadyApproved { get; set; }
        @AuraEnabled public String approvedByName { get; set; }
    }
    
    public class CostSheetDetailsWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean isAlreadyApproved { get; set; }
        @AuraEnabled public String approvedByName { get; set; }
        @AuraEnabled public Id costSheetId { get; set; }
        @AuraEnabled public String costSheetName { get; set; }
        @AuraEnabled public Id opportunityId { get; set; }
        @AuraEnabled public Id projectId { get; set; }
        @AuraEnabled public Id clusterId { get; set; }
        @AuraEnabled public Id unitId { get; set; }
        @AuraEnabled public String unitName { get; set; }
        @AuraEnabled public Decimal unitSBA { get; set; }
        @AuraEnabled public Integer currentApprovalLevel { get; set; }
        @AuraEnabled public Integer totalApprovalLevels { get; set; }
        @AuraEnabled public String highestApproverRole { get; set; }
        @AuraEnabled public String currentApproverRole { get; set; }
        @AuraEnabled public Decimal currentVersion { get; set; }
        @AuraEnabled public Decimal initialTotalAmount { get; set; }
        @AuraEnabled public Decimal revisedTotalAmount { get; set; }
        @AuraEnabled public Decimal differenceAmount { get; set; }
        @AuraEnabled public List<Pricing_Element__c> pricingElements { get; set; }
        @AuraEnabled public List<DiscountLevelWrapper> discountLevels { get; set; }
        
        public CostSheetDetailsWrapper() {
            this.isSuccess = false;
            this.isAlreadyApproved = false;
            this.pricingElements = new List<Pricing_Element__c>();
            this.discountLevels = new List<DiscountLevelWrapper>();
        }
    }
    
    public class DiscountLevelWrapper {
        @AuraEnabled public String role { get; set; }
        @AuraEnabled public Decimal minimumAmount { get; set; }
        @AuraEnabled public Decimal maximumAmount { get; set; }
        @AuraEnabled public Integer levelNumber { get; set; }
    }
    
    public class ApprovalDataWrapper {
        @AuraEnabled public Id costSheetId { get; set; }
        @AuraEnabled public Integer currentApprovalLevel { get; set; }
        @AuraEnabled public Decimal differenceAmount { get; set; }
        @AuraEnabled public List<PricingElementApprovalWrapper> pricingElements { get; set; }
    }
    
    public class PricingElementApprovalWrapper {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public Decimal approvalDiscount { get; set; }
        @AuraEnabled public Boolean isLsType { get; set; }
    }
    
    public class ApprovalResultWrapper {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Boolean requiresNextLevel { get; set; }
        @AuraEnabled public String nextApproverNames { get; set; }
        @AuraEnabled public String nextApproverRole { get; set; }
        @AuraEnabled public Boolean isAlreadyApproved { get; set; }
        @AuraEnabled public String approvedByName { get; set; }
        
        public ApprovalResultWrapper() {
            this.isSuccess = false;
            this.requiresNextLevel = false;
            this.isAlreadyApproved = false;
        }
    }
}