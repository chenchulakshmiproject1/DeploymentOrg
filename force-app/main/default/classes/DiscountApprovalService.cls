/**
 * @File Name : DiscountApprovalService.cls
 * @Description : Core service class for Discount Approval workflow.
 *                Handles difference calculation, approval level determination,
 *                approver identification (multiple approvers), and notification sending.
 * @Author : Yashwanth M V
 * @Last Modified On : 12-12-2025
 * @Modification Log :
 *==============================================================================
 * Ver | Date | Author | Modification
 *==============================================================================
 * 1.0 | 2-12-2025 | Yashwanth M V | Initial Version
 * 2.0 | 12-12-2025| Yashwanth M V | Multiple approvers support, cluster-based querying
 **/
public without sharing class DiscountApprovalService {
    
    // ============================================
    // CONSTANTS - Role Hierarchy
    // ============================================
    private static final String ROLE_STM = 'Sales Team Member';
    private static final String ROLE_SM = 'Sales Manager';
    private static final String ROLE_SH = 'Sales Head';
    private static final String ROLE_MGMT = 'Management';
    
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_UNDER_APPROVAL = 'Under Approval';
    private static final String STATUS_REJECTED = 'Rejected';
    
    private static final String DISCOUNT_TYPE = 'Discount';
    
    public static ApprovalResult processDiscountApproval(
        Id costSheetId,
    Decimal differenceAmount,
    Id projectId,
    Id clusterId,
    Id opportunityOwnerId
    ) {
        System.debug('=== processDiscountApproval START ===');
        System.debug('Cost Sheet Id: ' + costSheetId);
        System.debug('Difference Amount: ' + differenceAmount);
        System.debug('Project Id: ' + projectId);
        System.debug('Cluster Id: ' + clusterId);
        System.debug('Opportunity Owner Id: ' + opportunityOwnerId);
        
        ApprovalResult result = new ApprovalResult();
        result.isSuccess = true;
        
        try {
            
            if (differenceAmount == null || differenceAmount <= 0) {
                result.requiresApproval = false;
                result.approvalStatus = STATUS_APPROVED;
                result.message = 'No discount applied. Cost Sheet approved.';
                
                updateCostSheetStatus(costSheetId, STATUS_APPROVED, null, null, 0, null, null);
                
                System.debug('No discount - Direct approval');
                return result;
            }
            
            
            List<DiscountLevelConfig> discountLevels = getDiscountLevelsForProject(projectId);
            
            if (discountLevels.isEmpty()) {
                result.requiresApproval = false;
                result.approvalStatus = STATUS_APPROVED;
                result.message = 'No discount configuration found. Cost Sheet approved.';
                
                updateCostSheetStatus(costSheetId, STATUS_APPROVED, null, null, 0, null, null);
                
                System.debug('No discount config - Direct approval');
                return result;
            }
            
            
            ApprovalLevelInfo levelInfo = determineApprovalLevel(differenceAmount, discountLevels);
            
            System.debug('Level Info - Required Role: ' + levelInfo.requiredRole);
            System.debug('Level Info - Level Number: ' + levelInfo.levelNumber);
            System.debug('Level Info - Within STM Limit: ' + levelInfo.withinStmLimit);
            
            
            if (levelInfo.withinStmLimit) {
                result.requiresApproval = false;
                result.approvalStatus = STATUS_APPROVED;
                result.message = 'Discount within STM limit. Cost Sheet approved.';
                
                updateCostSheetStatus(costSheetId, STATUS_APPROVED, null, null, 0, differenceAmount, null);
                
                System.debug('Within STM limit - Direct approval');
                return result;
            }
            
            
            ApproverInfo approverInfo = getApproversForLevel(discountLevels[0].role, clusterId);
            
            if (approverInfo.approverIds.isEmpty()) {
                result.isSuccess = false;
                result.requiresApproval = true;
                result.message = 'Could not find approvers for role: ' + discountLevels[0].role + '. Please contact administrator.';
                return result;
            }
            
            
            Integer totalLevelsNeeded = levelInfo.levelNumber;
            String highestApproverRole = levelInfo.requiredRole;
            
            
            updateCostSheetStatus(
                costSheetId,
            STATUS_UNDER_APPROVAL,
            approverInfo.approverIds,
            approverInfo.approverNames,
            1,
            differenceAmount,
            null
                );
            
            
            updateCostSheetApprovalMetadata(costSheetId, totalLevelsNeeded, highestApproverRole);
            
            
            String firstApproverRole = discountLevels[0].role;
            for (Id approverId : approverInfo.approverIds) {
                sendApprovalNotification(costSheetId, approverId, opportunityOwnerId, differenceAmount, firstApproverRole);
                sendApprovalEmail(costSheetId, approverId, opportunityOwnerId, differenceAmount);
            }
            
            result.requiresApproval = true;
            result.approvalStatus = STATUS_UNDER_APPROVAL;
            result.approverIds = approverInfo.approverIds;
            result.totalLevels = totalLevelsNeeded;
            result.currentLevel = 1;
            result.message = 'Discount requires approval. Sent to ' + firstApproverRole + ' (' + approverInfo.approverNames.size() + ' approver(s)).';
            
            System.debug('=== processDiscountApproval END - Approval Required ===');
            return result;
            
        } catch (Exception e) {
            System.debug('Error in processDiscountApproval: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
            System.debug('Stack: ' + e.getStackTraceString());
            
            result.isSuccess = false;
            result.message = 'Error processing approval: ' + e.getMessage();
            return result;
        }
    }
    
    
    public static List<DiscountLevelConfig> getDiscountLevelsForProject(Id projectId) {
        System.debug('=== getDiscountLevelsForProject START ===');
        System.debug('Project Id: ' + projectId);
        
        List<DiscountLevelConfig> levels = new List<DiscountLevelConfig>();
        
        if (projectId == null) {
            System.debug('Project Id is null - returning empty list');
            return levels;
        }
        
        List<Discount_Master__c> discountMasters = [
            SELECT Id, Name, Project__c, Type__c, Active__c,
                   (SELECT Id, Roles__c, Minimum__c, Maximum__c 
                    FROM Discount_LineItems__r 
                    ORDER BY Minimum__c ASC)
            FROM Discount_Master__c
            WHERE Project__c = :projectId
            AND Type__c = :DISCOUNT_TYPE
            AND Active__c = true
            LIMIT 1
        ];
        
        if (discountMasters.isEmpty()) {
            System.debug('No active Discount Master found for project');
            return levels;
        }
        
        Discount_Master__c dm = discountMasters[0];
        System.debug('Found Discount Master: ' + dm.Name);
        
        Integer levelNumber = 1;
        for (Discount_LineItem__c lineItem : dm.Discount_LineItems__r) {
            DiscountLevelConfig config = new DiscountLevelConfig();
            config.lineItemId = lineItem.Id;
            config.role = lineItem.Roles__c;
            config.minimumAmount = lineItem.Minimum__c != null ? lineItem.Minimum__c : 0;
            config.maximumAmount = lineItem.Maximum__c != null ? lineItem.Maximum__c : 0;
            config.levelNumber = levelNumber++;
            
            levels.add(config);
            
            System.debug('Level ' + config.levelNumber + ': ' + config.role +
                ' (Min: ' + config.minimumAmount + ', Max: ' + config.maximumAmount + ')');
        }
        
        System.debug('Total levels configured: ' + levels.size());
        System.debug('=== getDiscountLevelsForProject END ===');
        
        return levels;
    }
    
    
    public static ApprovalLevelInfo determineApprovalLevel(
        Decimal differenceAmount,
    List<DiscountLevelConfig> discountLevels
    ) {
        System.debug('=== determineApprovalLevel START ===');
        System.debug('Difference Amount: ' + differenceAmount);
        
        ApprovalLevelInfo levelInfo = new ApprovalLevelInfo();
        levelInfo.withinStmLimit = false;
        levelInfo.levelNumber = 0;
        levelInfo.requiredRole = ROLE_STM;
        
        if (discountLevels.isEmpty()) {
            levelInfo.withinStmLimit = true;
            return levelInfo;
        }
        
        Decimal firstLevelMin = discountLevels[0].minimumAmount;
        
        if (differenceAmount < firstLevelMin) {
            levelInfo.withinStmLimit = true;
            levelInfo.requiredRole = ROLE_STM;
            levelInfo.levelNumber = 0;
            System.debug('Difference below first level min (' + firstLevelMin + ') - STM can approve');
            return levelInfo;
        }
        
        for (Integer i = 0; i < discountLevels.size(); i++) {
            DiscountLevelConfig level = discountLevels[i];
            
            Boolean hasNoMaxLimit = (level.maximumAmount == null || level.maximumAmount == 0);
            
            if (hasNoMaxLimit) {
                if (differenceAmount >= level.minimumAmount) {
                    levelInfo.requiredRole = level.role;
                    levelInfo.levelNumber = level.levelNumber;
                    levelInfo.withinStmLimit = false;
                    
                    System.debug('Difference falls in Level ' + level.levelNumber + ': ' + level.role + ' (No Max Limit)');
                    break;
                }
            } else if (differenceAmount >= level.minimumAmount && differenceAmount <= level.maximumAmount) {
                levelInfo.requiredRole = level.role;
                levelInfo.levelNumber = level.levelNumber;
                levelInfo.withinStmLimit = false;
                
                System.debug('Difference falls in Level ' + level.levelNumber + ': ' + level.role);
                break;
            }
            
            if (!hasNoMaxLimit && differenceAmount > level.maximumAmount) {
                if (i == discountLevels.size() - 1) {
                    levelInfo.requiredRole = level.role;
                    levelInfo.levelNumber = level.levelNumber;
                    levelInfo.exceedsMaximum = true;
                    
                    System.debug('Difference exceeds maximum of highest level');
                }
            }
        }
        
        System.debug('Final Level Info - Role: ' + levelInfo.requiredRole + ', Level: ' + levelInfo.levelNumber);
        System.debug('=== determineApprovalLevel END ===');
        
        return levelInfo;
    }
    
    public static ApproverInfo getApproversForLevel(String role, Id clusterId) {
        System.debug('=== getApproversForLevel START ===');
        System.debug('Role: ' + role);
        System.debug('Cluster Id: ' + clusterId);
        
        ApproverInfo info = new ApproverInfo();
        info.approverIds = new List<Id>();
        info.approverNames = new List<String>();
        
        if (role == ROLE_SM || role.containsIgnoreCase('Sales Manager')) {
            
            info = getApproversFromCluster(clusterId, 'Sales Manager');
        }
        else if (role == ROLE_SH || role.containsIgnoreCase('Sales Head')) {
            
            info = getApproversFromCluster(clusterId, 'Sales Head');
        }
        else if (role == ROLE_MGMT || role.containsIgnoreCase('Management')) {
            
            info = getApproversFromProfile('Management');
        }
        
        System.debug('Found ' + info.approverIds.size() + ' approvers');
        System.debug('Approver Names: ' + info.approverNames);
        System.debug('=== getApproversForLevel END ===');
        
        return info;
    }
    
    public static ApproverInfo getApproversFromCluster(Id clusterId, String role) {
        System.debug('=== getApproversFromCluster START ===');
        System.debug('Cluster Id: ' + clusterId);
        System.debug('Role: ' + role);
        
        ApproverInfo info = new ApproverInfo();
        info.approverIds = new List<Id>();
        info.approverNames = new List<String>();
        
        if (clusterId == null) {
            System.debug('Cluster Id is null');
            return info;
        }
        
        List<Cluster_Team_Member__c> teamMembers = [
            SELECT Id, Team_Member__c, Team_Member__r.Name, Team_Member__r.IsActive, Role__c
            FROM Cluster_Team_Member__c
            WHERE Cluster_Name__c = :clusterId
            AND Role__c = :role
            AND Team_Member__c != null
            AND Team_Member__r.IsActive = true
        ];
        
        for (Cluster_Team_Member__c ctm : teamMembers) {
            info.approverIds.add(ctm.Team_Member__c);
            info.approverNames.add(ctm.Team_Member__r.Name);
            System.debug('Found approver: ' + ctm.Team_Member__r.Name + ' (Role: ' + ctm.Role__c + ')');
        }
        
        System.debug('=== getApproversFromCluster END ===');
        System.debug('info--->'+info);
        return info;
    }
    
    
    public static ApproverInfo getApproversFromProfile(String profileName) {
        System.debug('=== getApproversFromProfile START ===');
        System.debug('Profile Name: ' + profileName);
        
        ApproverInfo info = new ApproverInfo();
        info.approverIds = new List<Id>();
        info.approverNames = new List<String>();
        
        List<User> users = [
            SELECT Id, Name
            FROM User
            WHERE Profile.Name = :profileName
            AND IsActive = true
        ];
        
        for (User u : users) {
            info.approverIds.add(u.Id);
            info.approverNames.add(u.Name);
            System.debug('Found approver: ' + u.Name);
        }
        
        System.debug('=== getApproversFromProfile END ===');
        return info;
    }
    
    
    public static ApproverInfo getNextLevelApprovers(
        Integer currentLevel,
    List<DiscountLevelConfig> discountLevels,
    Id clusterId
    ) {
        System.debug('=== getNextLevelApprovers START ===');
        System.debug('Current Level: ' + currentLevel);
        
        ApproverInfo info = new ApproverInfo();
        info.approverIds = new List<Id>();
        info.approverNames = new List<String>();
        
        if (currentLevel >= discountLevels.size()) {
            System.debug('No more levels - Final approval reached');
            return info;
        }
        
        String nextRole = discountLevels[currentLevel].role;
        System.debug('Next Role: ' + nextRole);
        
        return getApproversForLevel(nextRole, clusterId);
    }
    
    
    // public static void updateCostSheetStatus(
    //     Id costSheetId,
    // String status,
    // List<Id> approverIds,
    // List<String> approverNames,
    // Integer currentLevel,
    // Decimal differenceAmount,
    // String approvedBy
    // ) {
        //     System.debug('=== updateCostSheetStatus START ===');
        //     System.debug('Status: ' + status);
        //     System.debug('Approver Ids: ' + approverIds);
        //     System.debug('Approver Names: ' + approverNames);
        //     System.debug('Current Level: ' + currentLevel);
        //     System.debug('Approved By: ' + approvedBy);
        
        //     Cost_Sheet__c cs = new Cost_Sheet__c();
        //     cs.Id = costSheetId;
        //     cs.Approval_Status__c = status;
        //     cs.Current_Approval_Level__c = currentLevel;
        
        //     if (differenceAmount != null) {
            //         cs.Difference_Amount__c = differenceAmount;
        //     }
        
        
        //     if (approverIds != null && !approverIds.isEmpty()) {
            
            //         cs.Next_Approver_Ids__c = String.join(approverIds, ',');
            //         System.debug('Next Approver Ids: ' + cs.Next_Approver_Ids__c);
        //     } else {
            //         cs.Next_Approver_Ids__c = null;
        //     }
        
        //     if (approverNames != null && !approverNames.isEmpty()) {
            
            //         cs.Next_Approvers__c = String.join(approverNames, ', ');
            //         System.debug('Next Approvers: ' + cs.Next_Approvers__c);
        //     } else {
            //         cs.Next_Approvers__c = null;
        //     }
        
        //     if (approvedBy != null) {
            //         cs.Approved_By__c = approvedBy;
        //     }
        
        //     update cs;
        //     System.debug('=== updateCostSheetStatus END ===');
    // }
    /**
     * Updates Cost Sheet status and manages approval tracking fields
     * This is the SINGLE SOURCE OF TRUTH for all status changes
     */
    public static void updateCostSheetStatus( Id costSheetId, String status, List<Id> approverIds, List<String> approverNames, Integer currentLevel, Decimal differenceAmount, String approvedBy ) {
        System.debug('Cost Sheet Id: ' + costSheetId);
        System.debug('Status: ' + status);
        System.debug('Approver Ids: ' + approverIds);
        System.debug('Approver Names: ' + approverNames);
        System.debug('Current Level: ' + currentLevel);
        System.debug('Approved By: ' + approvedBy);
        
        Cost_Sheet__c cs = new Cost_Sheet__c();
        cs.Id = costSheetId;
        cs.Approval_Status__c = status;
        cs.Current_Approval_Level__c = currentLevel;
        
        if (differenceAmount != null) {
            cs.Difference_Amount__c = differenceAmount;
        }
        
        
        if (status == STATUS_UNDER_APPROVAL || status == 'Under Approval' || status == 'Approval Time-Out') {
            cs.Approval_Sent_DateTime__c = DateTime.now();
            System.debug('Approval Sent DateTime SET to: ' + cs.Approval_Sent_DateTime__c);
        }
        else if (status == STATUS_APPROVED || status == 'Approved' ||
        status == STATUS_REJECTED || status == 'Rejected') {
            cs.Approval_Sent_DateTime__c = null;
            System.debug('Approval Sent DateTime CLEARED');
        }
        
        if (approverIds != null && !approverIds.isEmpty()) {
            cs.Next_Approver_Ids__c = String.join(approverIds, ',');
            System.debug('Next Approver Ids: ' + cs.Next_Approver_Ids__c);
        } else {
            cs.Next_Approver_Ids__c = null;
        }
        
        if (approverNames != null && !approverNames.isEmpty()) {
            cs.Next_Approvers__c = String.join(approverNames, ', ');
            System.debug('Next Approvers: ' + cs.Next_Approvers__c);
        } else {
            cs.Next_Approvers__c = null;
        }
        
        if (approvedBy != null) {
            cs.Approved_By__c = approvedBy;
        }
        
        update cs;
        System.debug('=== updateCostSheetStatus END ===');
    }
    
    public static void updateCostSheetApprovalMetadata( Id costSheetId, Integer totalLevels, String highestApproverRole ) {
        System.debug('=== updateCostSheetApprovalMetadata START ===');
        
        Cost_Sheet__c cs = new Cost_Sheet__c();
        cs.Id = costSheetId;
        cs.Total_Approval_Levels__c = totalLevels;
        cs.Highest_Approver_Role__c = highestApproverRole;
        
        update cs;
        System.debug('=== updateCostSheetApprovalMetadata END ===');
    }
    
    
    public static String checkIfAlreadyApproved(Id costSheetId) {
        System.debug('=== checkIfAlreadyApproved START ===');
        
        Cost_Sheet__c cs = [
            SELECT Id, Approval_Status__c, Approved_By__c
            FROM Cost_Sheet__c
            WHERE Id = :costSheetId
            LIMIT 1
        ];
        
        
        if (cs.Approval_Status__c != STATUS_UNDER_APPROVAL) {
            System.debug('Cost Sheet status: ' + cs.Approval_Status__c + ', Approved By: ' + cs.Approved_By__c);
            return cs.Approved_By__c;
        }
        
        System.debug('Cost Sheet still under approval');
        System.debug('=== checkIfAlreadyApproved END ===');
        return null;
    }
    
    
    public static void incrementCostSheetVersion(Id costSheetId) {
        System.debug('=== incrementCostSheetVersion START ===');
        
        Cost_Sheet__c cs = [
            SELECT Id, Cost_Sheet_Version__c
            FROM Cost_Sheet__c
            WHERE Id = :costSheetId
            LIMIT 1
        ];
        
        Decimal currentVersion = cs.Cost_Sheet_Version__c != null ? cs.Cost_Sheet_Version__c : 1.0;
        Decimal newVersion = currentVersion + 1.0;
        
        cs.Cost_Sheet_Version__c = newVersion;
        update cs;
        
        System.debug('Version updated: ' + currentVersion + ' -> ' + newVersion);
        System.debug('=== incrementCostSheetVersion END ===');
    }
    
    public static void sendApprovalNotification(
        Id costSheetId,
    Id approverId,
    Id submitterId,
    Decimal differenceAmount,
    String approverRole
    ) {
        System.debug('=== sendApprovalNotification START ===');
        
        try {
            Cost_Sheet__c cs = [
                SELECT Id, Name, Opportunity__r.Name, Unit__r.Name
                FROM Cost_Sheet__c
                WHERE Id = :costSheetId
                LIMIT 1
            ];
            
            List<CustomNotificationType> notifTypes = [
                SELECT Id 
                FROM CustomNotificationType 
                WHERE DeveloperName = 'Discount_Approval_Notification'
                LIMIT 1
            ];
            
            if (notifTypes.isEmpty()) {
                System.debug('Custom Notification Type not found: Discount_Approval_Notification');
                return;
            }
            
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(costSheetId);
            notification.setTitle('Discount Approval Required');
            notification.setBody(
                'A discount approval is pending for Cost Sheet ' + cs.Name +
                '. Discount: ₹' + differenceAmount.format() + '/sqft. Please review and take action.'
                );
            
            notification.send(new Set<String>{ approverId });
            
            System.debug('Notification sent successfully to: ' + approverId);
            
        } catch (Exception e) {
            System.debug('Error sending notification: ' + e.getMessage());
        }
        
        System.debug('=== sendApprovalNotification END ===');
    }
    
    
    public static void sendApprovalEmail(
        Id costSheetId,
    Id approverId,
    Id submitterId,
    Decimal differenceAmount
    ) {
        System.debug('=== sendApprovalEmail START ===');
        
        try {
            Cost_Sheet__c cs = [
                SELECT Id, Name, Opportunity__r.Name, Unit__r.Name, Unit__r.Unit_Name__c
                FROM Cost_Sheet__c
                WHERE Id = :costSheetId
                LIMIT 1
            ];
            
            User approver = [SELECT Id, Name, Email FROM User WHERE Id = :approverId LIMIT 1];
            
            List<OrgWideEmailAddress> owea = [
                SELECT Id, Address, DisplayName 
                FROM OrgWideEmailAddress 
                LIMIT 1
            ];
            
            String baseUrl = URL.getOrgDomainUrl().toExternalForm();
            String recordUrl = baseUrl + '/lightning/r/Cost_Sheet__c/' + costSheetId + '/view';
            
            String emailBody = buildApprovalEmailBody(
                approver.Name,
            cs.Name,
            cs.Opportunity__r?.Name,
            cs.Unit__r?.Name,
            differenceAmount,
            recordUrl
                );
            
            Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
            email.setToAddresses(new List<String>{ approver.Email });
            
            if (!owea.isEmpty()) {
                email.setOrgWideEmailAddressId(owea[0].Id);
            }
            
            email.setSubject('Discount Approval Required: ' + cs.Name);
            email.setHtmlBody(emailBody);
            email.setSaveAsActivity(false);
            
            Messaging.SendEmailResult[] results = Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ email });
            
            if (results[0].isSuccess()) {
                System.debug('Email sent successfully to: ' + approver.Email);
            } else {
                System.debug('Email failed: ' + results[0].getErrors()[0].getMessage());
            }
            
        } catch (Exception e) {
            System.debug('Error sending email: ' + e.getMessage());
        }
        
        System.debug('=== sendApprovalEmail END ===');
    }
    
    
    private static String buildApprovalEmailBody(
        String approverName,
    String costSheetName,
    String opportunityName,
    String unitName,
    Decimal differenceAmount,
    String recordUrl
    ) {
        String emailBody = '<!DOCTYPE html><html><head><style>';
        emailBody += 'body { font-family: Arial, sans-serif; color: #333333; margin: 0; padding: 0; background-color: #f4f4f9; }';
        emailBody += '.container { width: 90%; max-width: 600px; margin: 20px auto; background-color: #ffffff; border: 1px solid #dddddd; border-radius: 8px; overflow: hidden; }';
        emailBody += '.header { text-align: center; padding: 20px; background: linear-gradient(135deg, #693C5E 0%, #8B5A7C 100%); color: #ffffff; }';
        emailBody += '.header h1 { margin: 0; font-size: 24px; font-weight: 600; }';
        emailBody += '.content { padding: 30px; }';
        emailBody += '.info-box { background-color: #f8f9fa; border-left: 4px solid #693C5E; padding: 15px; margin: 20px 0; border-radius: 0 4px 4px 0; }';
        emailBody += '.detail-row { display: flex; padding: 10px 0; border-bottom: 1px solid #eeeeee; }';
        emailBody += '.detail-label { font-weight: 600; color: #666666; width: 40%; }';
        emailBody += '.detail-value { color: #333333; width: 60%; }';
        emailBody += '.discount-highlight { background-color: #fff3cd; padding: 15px; border-radius: 6px; text-align: center; margin: 20px 0; }';
        emailBody += '.discount-amount { font-size: 28px; font-weight: 700; color: #693C5E; }';
        emailBody += '.button { display: inline-block; padding: 12px 30px; margin: 20px 0; background: linear-gradient(135deg, #693C5E 0%, #8B5A7C 100%); color: #ffffff; text-decoration: none; border-radius: 6px; font-weight: 600; }';
        emailBody += '.footer { text-align: center; padding: 20px; background-color: #f8f9fa; font-size: 12px; color: #888888; }';
        emailBody += '</style></head><body>';
        
        emailBody += '<div class="container">';
        emailBody += '<div class="header"><h1>Discount Approval Required</h1></div>';
        emailBody += '<div class="content">';
        emailBody += '<p>Hello ' + approverName + ',</p>';
        emailBody += '<div class="info-box">';
        emailBody += 'A discount approval is pending for the following Cost Sheet. Please review and take action.';
        emailBody += '</div>';
        
        emailBody += '<div class="discount-highlight">';
        emailBody += '<div>Discount Amount (per sqft)</div>';
        emailBody += '<div class="discount-amount">₹' + (differenceAmount != null ? differenceAmount.format() : '0') + '</div>';
        emailBody += '</div>';
        
        emailBody += '<div class="detail-row"><span class="detail-label">Cost Sheet:</span><span class="detail-value">' + (costSheetName != null ? costSheetName : 'N/A') + '</span></div>';
        emailBody += '<div class="detail-row"><span class="detail-label">Opportunity:</span><span class="detail-value">' + (opportunityName != null ? opportunityName : 'N/A') + '</span></div>';
        emailBody += '<div class="detail-row"><span class="detail-label">Unit:</span><span class="detail-value">' + (unitName != null ? unitName : 'N/A') + '</span></div>';
        
        emailBody += '<p style="text-align: center;"><a href="' + recordUrl + '" class="button">Review & Approve</a></p>';
        emailBody += '</div>';
        
        emailBody += '<div class="footer">';
        emailBody += '<p>This is an automated message. Please do not reply to this email.</p>';
        emailBody += '<p>&copy; ' + Date.today().year() + ' IRA Realty. All rights reserved.</p>';
        emailBody += '</div>';
        
        emailBody += '</div></body></html>';
        
        return emailBody;
    }
    
    public static void sendNotificationToPreviousApprovers(Id costSheetId,Id currentApproverId, String action, Decimal differenceAmount ) {
        System.debug('=== sendNotificationToPreviousApprovers START ===');
        
        try {
            Cost_Sheet__c cs = [
            SELECT Id, Name, Opportunity__c, Opportunity__r.OwnerId,
                   Opportunity__r.Cluster__c, Opportunity__r.Project__c
            FROM Cost_Sheet__c
            WHERE Id = :costSheetId
            LIMIT 1
        ];
            
            // Query Pricing Elements - ADD MD_Given_Discount__c
            List<Pricing_Element__c> elements = [
            SELECT Id, STM_Given_Discount__c, SM_Given_Discount__c, 
                   SH_Given_Discount__c, MD_Given_Discount__c
            FROM Pricing_Element__c 
            WHERE Cost_Sheet__c = :costSheetId
        ];
            
            Set<String> approverIds = new Set<String>();
            
            // Always notify STM (Opportunity Owner)
            if (cs.Opportunity__r.OwnerId != null) {
                approverIds.add(cs.Opportunity__r.OwnerId);
            }
            
            Boolean smInvolved = false;
            Boolean shInvolved = false;
            Boolean mdInvolved = false;  // ← NEW FLAG
            
            for (Pricing_Element__c pe : elements) {
                if (pe.SM_Given_Discount__c != null && pe.SM_Given_Discount__c != 0) {
                    smInvolved = true;
                }
                if (pe.SH_Given_Discount__c != null && pe.SH_Given_Discount__c != 0) {
                    shInvolved = true;
                }
                // ← NEW: Check for Management involvement
                if (pe.MD_Given_Discount__c != null && pe.MD_Given_Discount__c != 0) {
                    mdInvolved = true;
                }
            }
            
            // Get SM Approvers
            if (smInvolved && cs.Opportunity__r.Cluster__c != null) {
                ApproverInfo smInfo = getApproversFromCluster(cs.Opportunity__r.Cluster__c, 'Sales Manager');
                for (Id smId : smInfo.approverIds) {
                    approverIds.add(smId);
                }
            }
            
            // Get SH Approvers
            if (shInvolved && cs.Opportunity__r.Cluster__c != null) {
                ApproverInfo shInfo = getApproversFromCluster(cs.Opportunity__r.Cluster__c, 'Sales Head');
                for (Id shId : shInfo.approverIds) {
                    approverIds.add(shId);
                }
            }
            
            // ← NEW: Get Management Approvers
            if (mdInvolved) {
                ApproverInfo mdInfo = getApproversFromProfile('Management');
                System.debug('Management Approvers Found: ' + mdInfo.approverIds.size());
                for (Id mdId : mdInfo.approverIds) {
                    approverIds.add(mdId);
                }
            }
            
            // Remove current approver (they don't need notification about their own action)
            approverIds.remove(currentApproverId);
            
            System.debug('Final Approver IDs to notify: ' + approverIds);
            
            if (approverIds.isEmpty()) {
                System.debug('No approvers to notify');
                return;
            }
            
            User currentUser = [SELECT Id, Name FROM User WHERE Id = :currentApproverId LIMIT 1];
            
            List<CustomNotificationType> notifTypes = [
            SELECT Id 
            FROM CustomNotificationType 
            WHERE DeveloperName = 'Discount_Approval_Notification' 
            LIMIT 1
        ];
            
            if (notifTypes.isEmpty()) {
                System.debug('Custom Notification Type not found');
                return;
            }
            
            String title = '';
            String message = '';
            
            if (action == 'Approved') {
                title = 'Cost Sheet Approved';
                message = 'Cost sheet ' + cs.Name + ' has been approved by ' + currentUser.Name + '.';
            } else if (action == 'Rejected') {
                title = 'Cost Sheet Rejected';
                message = 'Cost sheet ' + cs.Name + ' has been rejected by ' + currentUser.Name + '. All discounts have been cleared.';
            } else if (action == 'Sent to Next Level') {
                title = 'Cost Sheet - Additional Approval Required';
                message = 'Cost sheet ' + cs.Name + ' has been reviewed by ' + currentUser.Name + ' and requires additional approval.';
                if (differenceAmount != null) {
                    message += ' Discount: ₹' + differenceAmount.format() + '/sqft';
                }
            }
            
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notifTypes[0].Id);
            notification.setTargetId(costSheetId);
            notification.setTitle(title);
            notification.setBody(message);
            notification.send(approverIds);
            
            System.debug('Notification sent successfully to ' + approverIds.size() + ' users');
            
        } catch (Exception e) {
            System.debug('Error sending notification to previous approvers: ' + e.getMessage());
            System.debug('Line: ' + e.getLineNumber());
        }
        
        System.debug('=== sendNotificationToPreviousApprovers END ===');
    }
    
    
    
    public static Boolean rejectCostSheet(Id costSheetId) {
        System.debug('=== rejectCostSheet START ===');
        
        Savepoint sp = Database.setSavepoint();
        
        try {
            
            User currentUser = [SELECT Id, Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
            Cost_Sheet__c cs = new Cost_Sheet__c();
            cs.Id = costSheetId;
            cs.Approval_Status__c = STATUS_REJECTED;
            cs.Next_Approver_Ids__c = null;
            cs.Next_Approvers__c = null;
            cs.Current_Approval_Level__c = 0;
            cs.Approved_By__c = currentUser.Name + ' (Rejected)';
            update cs;
            
            sendNotificationToPreviousApprovers(costSheetId, UserInfo.getUserId(), 'Rejected', null);
            
            List<Pricing_Element__c> pricingElements = [
                SELECT Id, Discount_Psft__c, Discount_LS__c, 
                       STM_Given_Discount__c, SM_Given_Discount__c, 
                       SH_Given_Discount__c, MD_Given_Discount__c
                FROM Pricing_Element__c
                WHERE Cost_Sheet__c = :costSheetId
            ];
            
            for (Pricing_Element__c pe : pricingElements) {
                pe.Discount_Psft__c = 0;
                pe.Discount_LS__c = 0;
                pe.STM_Given_Discount__c = null;
                pe.SM_Given_Discount__c = null;
                pe.SH_Given_Discount__c = null;
                pe.MD_Given_Discount__c = null;
            }
            
            if (!pricingElements.isEmpty()) {
                update pricingElements;
            }
            
            System.debug('=== rejectCostSheet END - Success ===');
            return true;
            
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug('Error rejecting cost sheet: ' + e.getMessage());
            throw new AuraHandledException('Error rejecting cost sheet: ' + e.getMessage());
        }
    }
    
    
    
    public static ValidationResult validateApproverDiscountLimit(
        Decimal differenceAmount,
    String approverRole,
    Id projectId
    ) {
        System.debug('=== validateApproverDiscountLimit START ===');
        System.debug('Difference: ' + differenceAmount + ', Role: ' + approverRole);
        
        ValidationResult result = new ValidationResult();
        result.isValid = true;
        
        List<DiscountLevelConfig> levels = getDiscountLevelsForProject(projectId);
        
        for (DiscountLevelConfig level : levels) {
            if (level.role == approverRole || level.role.containsIgnoreCase(approverRole)) {
                result.maxLimit = level.maximumAmount;
                result.minLimit = level.minimumAmount;
                
                if (differenceAmount > level.maximumAmount) {
                    result.isValid = false;
                    result.errorMessage = 'Discount exceeds your maximum limit of ₹' + level.maximumAmount.format() + '/sqft. Please reduce the discount amount.';
                }
                break;
            }
        }
        
        System.debug('Validation Result - Valid: ' + result.isValid);
        System.debug('=== validateApproverDiscountLimit END ===');
        
        return result;
    }
    
    
    public class ApproverInfo {
        public List<Id> approverIds { get; set; }
        public List<String> approverNames { get; set; }
        
        public ApproverInfo() {
            this.approverIds = new List<Id>();
            this.approverNames = new List<String>();
        }
    }
    
    
    public class DiscountLevelConfig {
        public Id lineItemId { get; set; }
        public String role { get; set; }
        public Decimal minimumAmount { get; set; }
        public Decimal maximumAmount { get; set; }
        public Integer levelNumber { get; set; }
    }
    
    
    public class ApprovalLevelInfo {
        public String requiredRole { get; set; }
        public Integer levelNumber { get; set; }
        public Boolean withinStmLimit { get; set; }
        public Boolean exceedsMaximum { get; set; }
    }
    
    
    public class ApprovalResult {
        @AuraEnabled public Boolean isSuccess { get; set; }
        @AuraEnabled public Boolean requiresApproval { get; set; }
        @AuraEnabled public String approvalStatus { get; set; }
        @AuraEnabled public List<Id> approverIds { get; set; }
        @AuraEnabled public Integer totalLevels { get; set; }
        @AuraEnabled public Integer currentLevel { get; set; }
        @AuraEnabled public String message { get; set; }
        
        public ApprovalResult() {
            this.isSuccess = false;
            this.requiresApproval = false;
            this.approverIds = new List<Id>();
        }
    }
    
    
    public class ValidationResult {
        @AuraEnabled public Boolean isValid { get; set; }
        @AuraEnabled public String errorMessage { get; set; }
        @AuraEnabled public Decimal maxLimit { get; set; }
        @AuraEnabled public Decimal minLimit { get; set; }
        
        public ValidationResult() {
            this.isValid = true;
        }
    }
}