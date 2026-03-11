import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getPendingCostSheets from '@salesforce/apex/CostSheetDiscountApprovalController.getPendingCostSheets';
import getCostSheetDetails from '@salesforce/apex/CostSheetDiscountApprovalController.getCostSheetDetails';
import saveApprovalDiscounts from '@salesforce/apex/CostSheetDiscountApprovalController.saveApprovalDiscounts';
import rejectCostSheet from '@salesforce/apex/CostSheetDiscountApprovalController.rejectCostSheet';
import getCurrentUserInfo from '@salesforce/apex/CostSheetDiscountApprovalController.getCurrentUserInfo';

export default class CostSheetDiscountApproval extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.initializeComponent();
        }
    }

    @track isLoading = true;
    @track loadingMessage = 'Loading...';
    @track hasError = false;
    @track errorMessage = '';
    @track noPendingCostSheets = false;
    @track showScreen1 = true;
    @track showScreen2 = false;
    @track currentUserId = '';
    @track currentUserName = '';
    @track currentUserRole = '';
    @track currentApprovalLevel = 0;
    @track pendingCostSheets = [];
    @track selectedCostSheetId = '';
    @track selectedCostSheetName = '';

    @track pricingElements = [];
    @track unitSBA = 0;
    @track initialTotalAmount = 0;
    @track revisedTotalAmount = 0;
    @track currentDifference = 0;
    @track totalApprovalLevels = 0;
    @track currentVersion = 1.0;
    @track currentApproverRole = '';

    @track initialTotalFormatted = '0';
    @track revisedTotalFormatted = '0';
    @track currentDifferenceFormatted = '0';
    @track isAlreadyApproved = false;
    @track approvedByName = '';
    @track showRejectModal = false;
    @track hasValidationErrors = false;
    discountLevels = [];
    projectId = '';
    clusterId = '';
    opportunityId = '';
    originalPricingElements = [];

    get pendingCostSheetsCount() {
        return this.pendingCostSheets ? this.pendingCostSheets.length : 0;
    }

    get pricingElementsCount() {
        return this.pricingElements ? this.pricingElements.length : 0;
    }

    get isNextDisabled() {
        return !this.selectedCostSheetId;
    }

    get isSaveDisabled() {
        return this.hasValidationErrors || this.isLoading || this.isAlreadyApproved;
    }

    get isRejectDisabled() {
        return this.isLoading || this.isAlreadyApproved;
    }

    get showSmDiscountColumn() {
        return this.currentApprovalLevel >= 2;
    }

    get showShDiscountColumn() {
        return this.currentApprovalLevel >= 3;
    }

    get approvalLevelLabel() {
        if (this.currentApprovalLevel === 1 && this.totalApprovalLevels === 1) {
            return 'Final Approval';
        } else if (this.currentApprovalLevel === 1) {
            return `Level 1 of ${this.totalApprovalLevels}`;
        } else if (this.currentApprovalLevel === 2 && this.totalApprovalLevels === 2) {
            return 'Final Approval (Level 2 of 2)';
        } else if (this.currentApprovalLevel === 2) {
            return `Level 2 of ${this.totalApprovalLevels}`;
        } else if (this.currentApprovalLevel === 3) {
            return 'Final Approval (Level 3 of 3)';
        }
        return `Level ${this.currentApprovalLevel}`;
    }

    get versionLabel() {
        return `Version ${this.currentVersion}`;
    }

    get approvedBannerMessage() {
        return `This Cost Sheet has been approved by ${this.approvedByName}`;
    }

    connectedCallback() {
        console.log('connectedCallback - recordId:', this._recordId);
    }

    async initializeComponent() {
        console.log('=== initializeComponent START ===');
        this.isLoading = true;
        this.loadingMessage = 'Loading user information...';

        try {
            const userInfo = await getCurrentUserInfo();
            console.log('User Info:', JSON.stringify(userInfo));

            this.currentUserId = userInfo.userId;
            this.currentUserName = userInfo.userName;
            this.currentUserRole = userInfo.userRole;

            this.loadingMessage = 'Loading pending approvals...';
            await this.loadPendingCostSheets();

        } catch (error) {
            console.error('Error initializing component:', error);
            this.hasError = true;
            this.errorMessage = 'Error loading data: ' + (error.body?.message || error.message || 'Unknown error');
        } finally {
            this.isLoading = false;
        }

        console.log('=== initializeComponent END ===');
    }

    async loadPendingCostSheets() {
        console.log('=== loadPendingCostSheets START ===');

        try {
            const result = await getPendingCostSheets({ opportunityId: this._recordId });
            console.log('Pending Cost Sheets:', JSON.stringify(result));

            if (!result || result.length === 0) {
                this.noPendingCostSheets = true;
                this.pendingCostSheets = [];
                return;
            }

            this.noPendingCostSheets = false;
            this.pendingCostSheets = result.map(wrapper => ({
                Id: wrapper.costSheetId,
                Name: wrapper.costSheetName,
                unitName: wrapper.unitName || 'N/A',
                createdDate: this.formatDate(wrapper.createdDate),
                formattedDifference: this.formatCurrency(wrapper.differenceAmount),
                version: wrapper.version || 1.0,
                approvalStatus: wrapper.approvalStatus,
                isSelected: false,
                rowClass: 'cost-sheet-row',

                isAlreadyApproved: wrapper.isAlreadyApproved || false,
                approvedByName: wrapper.approvedByName || '',
                isCurrentUserApprover: wrapper.isCurrentUserApprover,

                statusBadgeClass: this.getStatusBadgeClass(wrapper.approvalStatus, wrapper.isAlreadyApproved),
                statusLabel: this.getStatusLabel(wrapper.approvalStatus, wrapper.isAlreadyApproved, wrapper.approvedByName)
            }));

        } catch (error) {
            console.error('Error loading pending cost sheets:', error);
            throw error;
        }

        console.log('=== loadPendingCostSheets END ===');
    }

    getStatusBadgeClass(status, isAlreadyApproved) {
        if (isAlreadyApproved || status === 'Approved') {
            return 'slds-badge slds-badge_success';
        } else if (status === 'Under Approval') {
            return 'slds-badge slds-badge_warning';
        } else if (status === 'Rejected') {
            return 'slds-badge slds-badge_error';
        }
        return 'slds-badge';
    }

    getStatusLabel(status, isAlreadyApproved, approvedByName) {
        if (isAlreadyApproved) {
            return `Approved by ${approvedByName}`;
        }
        return status || 'Pending';
    }

    handleCostSheetSelect(event) {
        const selectedId = event.currentTarget.dataset.id;
        console.log('Selected Cost Sheet:', selectedId);

        const selected = this.pendingCostSheets.find(cs => cs.Id === selectedId);

        if (selected && selected.isAlreadyApproved) {
            this.showToast('Info', `This Cost Sheet has already been approved by ${selected.approvedByName}`, 'info');
            return;
        }

        this.selectedCostSheetId = selectedId;

        this.pendingCostSheets = this.pendingCostSheets.map(cs => ({
            ...cs,
            isSelected: cs.Id === selectedId,
            rowClass: cs.Id === selectedId ? 'cost-sheet-row selected' : 'cost-sheet-row'
        }));

        if (selected) {
            this.selectedCostSheetName = selected.Name;
        }
    }

    async handleNextToScreen2() {
        if (!this.selectedCostSheetId) {
            this.showToast('Warning', 'Please select a cost sheet to continue.', 'warning');
            return;
        }

        this.isLoading = true;
        this.loadingMessage = 'Loading cost sheet details...';

        try {
            const result = await getCostSheetDetails({ costSheetId: this.selectedCostSheetId });
            console.log('Cost Sheet Details:', JSON.stringify(result));

            if (!result.isSuccess) {
                this.showToast('Error', result.errorMessage || 'Failed to load cost sheet details.', 'error');
                this.isLoading = false;
                return;
            }

            if (result.isAlreadyApproved) {
                this.isAlreadyApproved = true;
                this.approvedByName = result.approvedByName || 'another approver';

                this.showScreen1 = false;
                this.showScreen2 = true;
                this.isLoading = false;
                return;
            }

            this.isAlreadyApproved = false;
            this.approvedByName = '';

            this.currentApprovalLevel = result.currentApprovalLevel;
            this.totalApprovalLevels = result.totalApprovalLevels;
            this.discountLevels = result.discountLevels || [];
            this.projectId = result.projectId;
            this.clusterId = result.clusterId;
            this.opportunityId = result.opportunityId;
            this.currentVersion = result.currentVersion || 1.0;
            this.currentApproverRole = result.currentApproverRole || '';

            this.unitSBA = result.unitSBA || 0;
            this.initialTotalAmount = result.initialTotalAmount || 0;
            this.revisedTotalAmount = result.revisedTotalAmount || 0;
            this.currentDifference = result.differenceAmount || 0;

            this.initialTotalFormatted = this.formatCurrency(this.initialTotalAmount);
            this.revisedTotalFormatted = this.formatCurrency(this.revisedTotalAmount);
            this.currentDifferenceFormatted = this.formatCurrency(this.currentDifference);

            this.buildPricingElements(result.pricingElements || []);

            this.showScreen1 = false;
            this.showScreen2 = true;

        } catch (error) {
            console.error('Error loading cost sheet details:', error);
            this.showToast('Error', 'Error loading details: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    buildPricingElements(elements) {
        console.log('=== buildPricingElements START ===');

        this.pricingElements = elements.map((pe, index) => {
            const isLsType = pe.PE_Type__c === 'LS' || pe.Unit__c === 'LS';

            let defaultDiscount = 0;
            if (isLsType) {
                defaultDiscount = pe.Discount_LS__c || 0;
            } else {
                defaultDiscount = pe.Discount_Psft__c || 0;
            }

            const maxDiscount = isLsType ? (pe.Amount__c || 0) : (pe.Rate__c || 0);

            return {
                Id: pe.Id,
                serialNumber: index + 1,
                pricingElementName: pe.Pricing_Element_Master__r?.Name || 'Unknown',
                pricingElementMasterId: pe.Pricing_Element_Master__c,
                peType: pe.PE_Type__c || 'N/A',
                peTypeBadgeClass: isLsType ? 'pe-type-badge ls' : 'pe-type-badge psft',
                isLsType: isLsType,

                
                quantity: pe.Quantity__c || 0,
                rate: pe.Rate__c || 0,
                amount: pe.Amount__c || 0,
                finalAmount: pe.Final_Amount__c || pe.Amount__c || 0,

                
                stmDiscount: pe.STM_Given_Discount__c,
                smDiscount: pe.SM_Given_Discount__c,
                shDiscount: pe.SH_Given_Discount__c,

                
                approvalDiscount: defaultDiscount,
                originalDiscount: defaultDiscount, 
                
                formattedRate: this.formatCurrency(pe.Rate__c),
                formattedAmount: this.formatCurrency(pe.Amount__c),
                formattedStmDiscount: this.formatCurrency(pe.STM_Given_Discount__c),
                formattedSmDiscount: this.formatCurrency(pe.SM_Given_Discount__c),
                formattedShDiscount: this.formatCurrency(pe.SH_Given_Discount__c),

                
                maxDiscount: maxDiscount,
                validationError: '',

                
                isDisabled: this.isAlreadyApproved
            };
        });

       
        this.originalPricingElements = JSON.parse(JSON.stringify(this.pricingElements));

        console.log('Pricing Elements Built:', this.pricingElements.length);
        console.log('=== buildPricingElements END ===');
    }


    handleApprovalDiscountChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const value = parseFloat(event.target.value) || 0;

        console.log('Discount Change - Index:', index, 'Value:', value);

        const element = this.pricingElements[index];
        let validationError = '';

        if (value < 0) {
            validationError = 'Cannot be negative';
        } else if (value > element.maxDiscount) {
            validationError = `Cannot exceed ${element.isLsType ? 'amount' : 'rate'}: ₹${this.formatCurrency(element.maxDiscount)}`;
        }

        this.pricingElements = this.pricingElements.map((item, idx) => {
            if (idx === index) {
                return {
                    ...item,
                    approvalDiscount: value,
                    validationError: validationError
                };
            }
            return item;
        });

        this.recalculateTotals();

        this.checkValidationErrors();
    }

    recalculateTotals() {
        let newRevisedTotal = 0;

        this.pricingElements.forEach(element => {
            const discount = element.approvalDiscount || 0;
            let finalAmount = 0;

            if (element.isLsType) {
                finalAmount = element.amount - discount;
            } else {
                finalAmount = (element.rate - discount) * element.quantity;
            }

            newRevisedTotal += Math.max(0, finalAmount);
        });

        this.revisedTotalAmount = newRevisedTotal;
        this.revisedTotalFormatted = this.formatCurrency(newRevisedTotal);

        if (this.unitSBA > 0) {
            const initialPerSqft = this.initialTotalAmount / this.unitSBA;
            const revisedPerSqft = newRevisedTotal / this.unitSBA;
            this.currentDifference = Math.ceil(initialPerSqft - revisedPerSqft);
            this.currentDifferenceFormatted = this.formatCurrency(this.currentDifference);
        }
    }

    checkValidationErrors() {
        this.hasValidationErrors = this.pricingElements.some(
            element => element.validationError && element.validationError !== ''
        );
    }

    hasDiscountChanged() {
        for (let i = 0; i < this.pricingElements.length; i++) {
            const current = this.pricingElements[i];
            const original = this.originalPricingElements[i];

            if (current && original) {
                const currentDiscount = current.approvalDiscount || 0;
                const originalDiscount = original.originalDiscount || 0;

                if (currentDiscount !== originalDiscount) {
                    console.log(`Discount changed for element ${i}: ${originalDiscount} -> ${currentDiscount}`);
                    return true;
                }
            }
        }
        return false;
    }

    async handleSaveApproval() {
        console.log('=== handleSaveApproval START ===');

        if (this.isAlreadyApproved) {
            this.showToast('Info', 'This Cost Sheet has already been approved.', 'info');
            return;
        }

        if (this.hasValidationErrors) {
            this.showToast('Error', 'Please fix validation errors before saving.', 'error');
            return;
        }

        this.isLoading = true;
        this.loadingMessage = 'Saving approval...';

        try {
            const discountChanged = this.hasDiscountChanged();
            console.log('Discount Changed:', discountChanged);

            const approvalData = {
                costSheetId: this.selectedCostSheetId,
                currentApprovalLevel: this.currentApprovalLevel,
                differenceAmount: this.currentDifference,
                pricingElements: this.pricingElements.map(pe => ({
                    id: pe.Id,
                    approvalDiscount: pe.approvalDiscount,
                    isLsType: pe.isLsType
                }))
            };

            console.log('Approval Data:', JSON.stringify(approvalData));

            const result = await saveApprovalDiscounts({ approvalDataJson: JSON.stringify(approvalData) });
            console.log('Save Result:', JSON.stringify(result));

            if (result.isSuccess) {
                if (result.isAlreadyApproved) {
                    this.showToast('Info', `This Cost Sheet has already been approved by ${result.approvedByName}`, 'info');
                    this.isAlreadyApproved = true;
                    this.approvedByName = result.approvedByName;
                } else if (result.requiresNextLevel) {
                    this.showToast('Success', result.message, 'success');
                } else {
                    this.showToast('Success', 'Discounts approved successfully! Cost Sheet is now finalized.', 'success');
                }

                this.handleClose();

                setTimeout(() => {
                    window.location.reload();
                }, 1500);

            } else {
                if (result.isAlreadyApproved) {
                    this.isAlreadyApproved = true;
                    this.approvedByName = result.approvedByName || 'another approver';
                    this.showToast('Info', `This Cost Sheet has already been approved by ${this.approvedByName}`, 'info');
                } else {
                    this.showToast('Error', result.errorMessage || 'Failed to save approval.', 'error');
                }
            }

        } catch (error) {
            console.error('Error saving approval:', error);
            this.showToast('Error', 'Error saving: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }

        console.log('=== handleSaveApproval END ===');
    }

    handleRejectCostSheet() {
        if (this.isAlreadyApproved) {
            this.showToast('Info', 'This Cost Sheet has already been approved and cannot be rejected.', 'info');
            return;
        }
        this.showRejectModal = true;
    }

    handleCancelReject() {
        this.showRejectModal = false;
    }

    async handleConfirmReject() {
        console.log('=== handleConfirmReject START ===');

        this.showRejectModal = false;
        this.isLoading = true;
        this.loadingMessage = 'Rejecting cost sheet...';

        try {
            const result = await rejectCostSheet({ costSheetId: this.selectedCostSheetId });
            console.log('Reject Result:', result);

            if (result) {
                this.showToast('Success', 'Cost Sheet has been rejected.', 'success');
                this.handleClose();

                setTimeout(() => {
                    window.location.reload();
                }, 1500);
            } else {
                this.showToast('Error', 'Failed to reject cost sheet.', 'error');
            }

        } catch (error) {
            console.error('Error rejecting cost sheet:', error);
            this.showToast('Error', 'Error: ' + (error.body?.message || error.message), 'error');
        } finally {
            this.isLoading = false;
        }

        console.log('=== handleConfirmReject END ===');
    }


    handleBackToScreen1() {
        this.showScreen2 = false;
        this.showScreen1 = true;
        this.selectedCostSheetId = '';
        this.selectedCostSheetName = '';
        this.pricingElements = [];
        this.originalPricingElements = [];
        this.isAlreadyApproved = false;
        this.approvedByName = '';

        this.pendingCostSheets = this.pendingCostSheets.map(cs => ({
            ...cs,
            isSelected: false,
            rowClass: 'cost-sheet-row'
        }));

        this.loadPendingCostSheets();
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }


    formatCurrency(value) {
        if (value === null || value === undefined) return '0';
        return new Intl.NumberFormat('en-IN').format(value);
    }

    formatDate(dateString) {
        if (!dateString) return 'N/A';
        const date = new Date(dateString);
        return date.toLocaleDateString('en-IN', {
            day: '2-digit',
            month: 'short',
            year: 'numeric'
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }
}