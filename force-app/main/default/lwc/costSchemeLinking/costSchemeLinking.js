import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import processUpload from '@salesforce/apex/CostSchemeBulkUploadController.processUpload';
import getCostSchemeLinkings from '@salesforce/apex/CostSchemeBulkUploadController.getCostSchemeLinkings';
import getPaymentSchemes from '@salesforce/apex/CostSchemeBulkUploadController.getPaymentSchemes';
import getCostSheetTemplates from '@salesforce/apex/CostSchemeBulkUploadController.getCostSheetTemplates';
import getProjects from '@salesforce/apex/CostSchemeBulkUploadController.getProjects';
import { NavigationMixin } from "lightning/navigation";

export default class CostSchemeLinking extends NavigationMixin(LightningElement) {

    expectedHeaders = [
        'Payment Scheme',
        'Cost Sheet Template',
        'Z Code'
    ];

    @track headers = [];
    @track previewData = [];
    @track paginatedRowsToDisplay = [];
    @track hasErrors = false;
    @track headerErrorMessage = '';
    @track showHeaderErrors = false;
    @track errorRowNumbers = '';
    @track existingRecords = [];
    @track paginatedUnitData = [];
    existingCostSchemeKeys = [];

    @track projectOptions = [];
    @track selectedProjects = [];
    @track selectedProjectNames = 'Select Projects';
    @track showDropdown = false;
    @track filteredRecords = [];
    @track curPageNumUnit = 1;

    pageSize = 5;
    payload = [];
    paymentSchemeSet = new Set();
    costSheetTemplateSet = new Set();


    get hasExistingRecords() {
        return this.existingRecords && this.existingRecords.length > 0;
    }

    get canSave() {
        return !this.hasErrors && this.previewData.length > 0;
    }
    get showErrorSummary() {
    return this.errorRowNumbers && this.errorRowNumbers.length > 0;
    }
    get hasHeaders() {
    return this.headers && this.headers.length > 0;
    }

    connectedCallback() {
    this.loadExistingRecords();
    this.loadProjects();

    getPaymentSchemes().then(data => {
        this.paymentSchemeSet = new Set(
            data.map(v => v.toLowerCase())
        );
    });

    getCostSheetTemplates().then(data => {
        this.costSheetTemplateSet = new Set(
            data.map(v => v.toLowerCase())
        );
    });
    } 

    loadExistingRecords() {
        getCostSchemeLinkings()
            .then(result => {

                this.existingRecords = result.map((rec, index) => ({
                    Id: rec.Id,
                    sNo: index + 1,
                    CostSchemeLinkingName: rec.Name,
                    CostSheetTemplateName: rec.Cost_Sheet_Template__r?.Name,
                    ProjectId: rec.Payment_Scheme__r?.Project__c,
                    PaymentScheme: rec.Payment_Scheme__r?.Name,
                    CreatedDate: rec.CreatedDate
                }));
                this.existingCostSchemeKeys = result.map(rec =>
                (rec.Payment_Scheme__r?.Name || '').toLowerCase() + '-' +
                (rec.Cost_Sheet_Template__r?.Name || '').toLowerCase()
            );
                this.filteredRecords = [...this.existingRecords];  
                this.curPageNumUnit = 1;
                this.paginatedUnitData = this.filteredRecords.slice(0, this.pageSize);

                setTimeout(() => {
                    const pagination =
                        this.template.querySelector('.unitPagination');
                    if (pagination) {
                        pagination.setPagination(this.pageSize);
                    }
                });
            })
            .catch(error => {
                console.error(error);
            });
    }

    jobPaginationCallback2(event) {
        this.paginatedUnitData =
            event.detail.recordToDisplay || [];
            this.curPageNumUnit = event.detail.curPage || 1;
            this.refreshUnitData();
    }
    refreshUnitData() {
    const page = this.curPageNumUnit || 1;
    this.paginatedUnitData = [...this.filteredRecords.slice(
        (page - 1) * this.pageSize,
        page * this.pageSize
    )];
}


    downloadTemplate() {
        const csv = this.expectedHeaders.join(',') + '\n';
        const uri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        const a = document.createElement('a');
        a.href = uri;
        a.download = 'Cost_Scheme_Linking_Template.csv';
        a.click();
    }

    uploadTemplate() {
        const input = this.template.querySelector('.upload');
        if (input) input.click();
    }

    openFilePicker() {
        this.template.querySelector('.upload').click();
    }

    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => this.parseCSV(reader.result);
        reader.readAsText(file);
    }

    parseCSV(text) {

    this.resetState();
    const lines = text.split(/\r?\n/).filter(l => l.trim());
    if (!lines.length) return;

    const dataHeaders = lines[0].split(',').map(h => h.trim());
    const missingHeaders = this.expectedHeaders.filter(h => !dataHeaders.includes(h));
    const invalidHeaders = dataHeaders.filter(h => !this.expectedHeaders.includes(h));

    let headerMsg = '';

    if (missingHeaders.length > 0) {
        headerMsg += 'Missing headers: ' + missingHeaders.join(', ') + '. ';
    }

    if (invalidHeaders.length > 0) {
        headerMsg += 'Invalid headers: ' + invalidHeaders.join(', ') + '. ';
    }

    if (JSON.stringify(dataHeaders) !== JSON.stringify(this.expectedHeaders)) {
        headerMsg += 'Incorrect order of headers. ';
    }

    if (headerMsg) {
        this.headerErrorMessage = headerMsg + 'Please use the downloaded template.';
        this.showHeaderErrors = true;
    } else {
        this.headerErrorMessage = '';
        this.showHeaderErrors = false;
    }

        this.headers = [
            { label: 'S.No', class: '' },
            ...dataHeaders.map(h => ({ label: h, class: '' }))
        ];

    const fileKeys = new Set();
    const errorRows = [];

    lines.slice(1).forEach((line, index) => {

    const row = line.split(',').map(v => v.trim());

    if (row.every(val => !val || val.trim() === '')) {
        return;
    }

    const rowNo = index + 1; 

    const paymentScheme = row[0] || '';
    const costSheetTemplate = row[1] || '';
    const zCode = row[2] || '';

    const errors = [];
    let hasRowError = false;

    if (!paymentScheme) {
        errors.push('Payment Scheme is required');
        hasRowError = true;
    }
    else if (!this.paymentSchemeSet.has(paymentScheme.toLowerCase())) {
        errors.push('Invalid Payment Scheme');
        hasRowError = true;
    }

    if (!costSheetTemplate) {
        errors.push('Cost Sheet Template is required');
        hasRowError = true;
    }
    else if (!this.costSheetTemplateSet.has(costSheetTemplate.toLowerCase())) {
        errors.push('Invalid Cost Sheet Template');
        hasRowError = true;
    }

    if (!zCode) {
        errors.push('Z Code is required');
        hasRowError = true;
    }

    if (hasRowError) {
        errorRows.push(rowNo);
    }

    if (!hasRowError && !this.showHeaderErrors) {
        this.payload.push({
            rowNumber: rowNo,
            paymentSchemeName: paymentScheme,
            costSheetTemplateName: costSheetTemplate,
            zCode: zCode
        });
    }
const rowCells = [
    { value: rowNo },
    { value: paymentScheme },
    { value: costSheetTemplate },
    { value: zCode }
];

if (errors.length > 0) {
    rowCells.push({
        value: errors.join(' | '),
        class: 'error-column'
    });
}
    this.previewData.push({
        rowKey: rowNo,
        cells: rowCells
    });
});
    if (errorRows.length > 0) {
    this.headers = [
        ...this.headers,
        { label: 'Errors', class: 'error-header' }
    ];
}

        this.errorRowNumbers = errorRows.join(', ');
        this.hasErrors = errorRows.length > 0;

        this.headers = this.headers.map(col => {
    if (col.label === 'Errors') {
        return {
            ...col,
            class: this.hasErrors ? 'error-header' : ''
        };
    }
    return col;
});


}
    jobPaginationCallback(event) {
        this.paginatedRowsToDisplay =
            event.detail.recordToDisplay || [];
    }
    handleSave() {

    if (!this.canSave) return;

    processUpload({ rowsJson: JSON.stringify(this.payload) })
        .then(() => {

            this.toast(
                'Success',
                'Upload completed successfully',
                'success'
            );

            this.resetState();
            this.loadExistingRecords();
        })
        .catch(e => {

            console.log(' ERROR', JSON.stringify(e));

            this.toast(
                'Error',
                e.body?.message || 'Insert failed',
                'error'
            );
        });
}
    resetState() {
        this.headers = [];
        this.previewData = [];
        this.paginatedRowsToDisplay = [];
        this.payload = [];
        this.hasErrors = false;
        this.errorRowNumbers = '';
    }

    toast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
    loadProjects() {
    getProjects()
        .then(result => {
            this.projectOptions = result.map(p => ({
                label: p.Name,
                value: p.Id,
                checked: false
            }));
        })
        .catch(error => console.error(error));
}
toggleDropdown() {
    this.showDropdown = !this.showDropdown;
}

handleProjectSelect(event) {
    const projectId = event.target.value;
    const isChecked = event.target.checked;

    this.projectOptions = this.projectOptions.map(opt => {
        if (opt.value === projectId) opt.checked = isChecked;
        return opt;
    });

    if (isChecked) {
        this.selectedProjects = [...this.selectedProjects, projectId];
    } else {
        this.selectedProjects = this.selectedProjects.filter(p => p !== projectId);
    }

    this.selectedProjectNames = this.projectOptions
        .filter(p => p.checked).map(p => p.label).join(', ') || 'Select Projects';

    this.filterRecords();
}

filterRecords() {
    if (this.selectedProjects.length === 0) {
        this.filteredRecords = [...this.existingRecords];
    } else {
        this.filteredRecords = this.existingRecords.filter(rec =>
            this.selectedProjects.includes(rec.ProjectId)
        );
    }

    this.curPageNumUnit = 1;
    this.paginatedUnitData = this.filteredRecords.slice(0, this.pageSize);

    setTimeout(() => {
        const pagination = this.template.querySelector('.unitPagination');
        if (pagination) pagination.setPagination(this.pageSize);
    });
}
    handleRowClick(event) {
        debugger
        const recordId = event.currentTarget.dataset.id;
        window.open('/' + recordId, '_blank');
    }
    createIndividualRec(){
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Cost_Scheme_Linking__c', 
                actionName: 'new'
            }
        });
    }
}