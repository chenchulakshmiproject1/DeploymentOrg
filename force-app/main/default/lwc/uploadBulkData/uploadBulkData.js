import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import utillogo from '@salesforce/resourceUrl/utillogo3';

export default class UploadBulkData extends LightningElement {
    @track activeTab = 'dashboard';
    @track isSidebarVisible = true;
    @track logoUrl = utillogo;

    sidebarItems = [
        { key: 'dashboard', label: 'Dashboard', icon: 'utility:apps' },
        { key: 'inventoryUpload', label: 'Inventory Upload', icon: 'utility:upload' },
        { key: 'taxMaster', label: 'Tax Master', icon: 'utility:money' },
        { key: 'paymentSchedule', label: 'Payment Schedule', icon: 'utility:date_input' },
        { key: 'pricingElements', label: 'Pricing Elements', icon: 'utility:currency' },
        { key: 'costSheetTemplate', label: 'Cost Sheet Template', icon: 'utility:description' },
        { key: 'paymentSchemes', label: 'Payment Schemes', icon: 'utility:table' },
        { key: 'costSchemeLinking', label: 'Cost Scheme Linking', icon: 'utility:link' },
        { key: 'opportunityStages', label: 'Opportunity Stages', icon: 'utility:share' },
        { key: 'userManagement', label: 'User Management', icon: 'utility:people' },
        { key: 'siteVisitConfig', label: 'Site Visit Config', icon: 'utility:event' },
        { key: 'integrationConfig', label: 'Integration Configuration', icon: 'utility:apps' },
    ];

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference?.state?.c__key) {
            this.activeTab = currentPageReference.state.c__key;
        }
    }

    connectedCallback() {
        this.toggleSidebarBasedOnScreen();
        window.addEventListener('resize', this.toggleSidebarBasedOnScreen);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this.toggleSidebarBasedOnScreen);
    }

    toggleSidebarBasedOnScreen = () => {
        this.isSidebarVisible = window.innerWidth > 1024;
    };

    handleClick(event) {
        this.activeTab = event.currentTarget.dataset.key;
        this.highlightActiveMenu();
    }

    renderedCallback() {
        this.highlightActiveMenu();
    }

    highlightActiveMenu() {
        const items = this.template.querySelectorAll('.sidebar-item, .mobile-sidebar-item');
        items.forEach(item => {
            item.classList.toggle('active', item.dataset.key === this.activeTab);
        });
    }

    get isDashboard() {
        return this.activeTab === 'dashboard';
    }

    get isInventoryUpload() {
        return this.activeTab === 'inventoryUpload';
    }

    get isTaxMaster() {
        return this.activeTab === 'taxMaster';
    }

    get isPaymentSchedule() {
        return this.activeTab === 'paymentSchedule';
    }

    get isPricingElements() {
        return this.activeTab === 'pricingElements';
    }

    get isCostSheetTemplate() {
        return this.activeTab === 'costSheetTemplate';
    }

    get isPaymentSchemes() {
        return this.activeTab === 'paymentSchemes';
    }

    get isCostSchemeLinking() {
        return this.activeTab === 'costSchemeLinking';
    }

    get isOpportunityStages() {
        return this.activeTab === 'opportunityStages';
    }

    get isUserManagement() {
        return this.activeTab === 'userManagement';
    }

    get isSiteVisitConfig() {
        return this.activeTab === 'siteVisitConfig';
    }

    get isIntegrationConfig() {
        return this.activeTab === 'integrationConfig';
    }
    
    handleDashboardNavigate(event){

    this.activeTab = event.detail.key;

    this.highlightActiveMenu();

    }
}