import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchDataOnLoad from '@salesforce/apex/CostSheetCsvController.fetchDataOnLoad';
import getCostSheetTemplates from '@salesforce/apex/CostSheetCsvController.getCostSheetTemplates';
import uploadCostSheet from '@salesforce/apex/CostSheetCsvController.uploadCostSheet';
import { NavigationMixin } from "lightning/navigation";

export default class CostSheetCsvUpload extends NavigationMixin(LightningElement) {
    @track headers = [];
    @track previewData = [];
    @track columns = [];
    @track existingRecords = [];
    @track errorRowNumbers = '';
    @track hasErrors = false;
    @track paginatedUnitData = [];
    @track projectOptions = [];
    @track selectedProjects = [];
    @track selectedProjectNames = 'Select Projects';
    @track showDropdown = false;
    @track filteredRecords = [];
    recordsToInsert = [];
    pageSize = 5;
    companyMap = {};
    projectMap = {};
    unitMap = {};
    pricingElementMap = {};
    taxDetailsMap = {};
    existingTemplateCodes = new Set();

    requiredFields = new Set([
    'Template Name',
    'Company',
    'Project',
    'Template Code',
    'Active','Unit Code',
        'Pricing Element Master','Unit','PE Group','PE Type',
        'Pricing Type','Sequence','Quantity','Rate','Tax Type','Tax Name','App %',
    // ,
    // 'Total Amount Inclusive of Tax',
    // 'Amount',
    // 'Tax Amount'
]);

    expectedHeaders = [
        'Company','Project','Template Code','Template Name','Active','Unit Code',
        'Pricing Element Master','Unit',
        // 'Pricing Element Allocation',
        'PE Group','PE Type',
        'Pricing Type','Sequence','Quantity','Rate',
        // 'Amount','Tax Amount',
        'Tax Type','Tax Name','App %',
        // 'Tax %','Amount'
    ];

    get showSubmit() {
        return this.previewData.length > 0;
    }
    get hasExistingRecords() {
        return this.existingRecords && this.existingRecords.length > 0;
    }
    get disableSubmit() {
        return this.hasErrors || this.recordsToInsert.length === 0;
    }
    jobPaginationCallback2(event) {
        this.paginatedUnitData = event.detail.recordToDisplay || [];
        this.curPageNumUnit = event.detail.curPage || 1;
        this.refreshUnitData();
    }

    jobPaginationCallback(event) {
    this.paginatedRowsToDisplay = event.detail.recordToDisplay || [];
}
    refreshUnitData() {
        const page = this.curPageNumUnit || 1;
        this.paginatedUnitData = [...this.filteredRecords.slice(
            (page - 1) * this.pageSize,
            page * this.pageSize
        )];
    }

    connectedCallback() {
    this.loadExistingRecords();
     this.loadLookupData();
    }
   loadLookupData() {
    fetchDataOnLoad()
        .then(result => {
            this.companyMap = result.companyMap || {};
            this.projectMap = result.projectMap || {};
            this.existingTemplateCodes = new Set(
                (result.existingTemplateCodes || []).map(code => code.toLowerCase())
            );
            this.projectOptions = Object.entries(result.projectMap || {}).map(([name, id]) => ({
                label: name,
                value: id,
                checked: false
            }));
        })
        .catch(error => console.error(error));
}

    loadExistingRecords() {
        getCostSheetTemplates()
            .then(result => {
                
                this.existingRecords = result.map((rec, index) => ({
                    Id: rec.Id,
                    sNo: index + 1,
                    Name: rec.Name,
                    CompanyName: rec.Company__r?.Name,
                    ProjectName: rec.Project__r?.Name,
                    ProjectId: rec.Project__c, 
                    TemplateCode: rec.Template_Code__c,
                    Amount: rec.Amount__c,
                    TotalAmount: rec.Total_Amount_Inclusive_of_Tax__c,
                    TaxAmount: rec.Tax_Amount__c,
                    Active: rec.Active__c ? 'Yes' : 'No'
                }));
                
            this.paginatedUnitData = this.existingRecords.slice(0, this.pageSize);
            this.filteredRecords = [...this.existingRecords];
            setTimeout(() => {
                const pagination = this.template.querySelector('.unitPagination');
                if (pagination) pagination.setPagination(this.pageSize);
            });
            })
            
            .catch(error => {
                console.error(error);
            });
    }

    downloadTemplate() {
        const csv = this.expectedHeaders.join(',') + '\n';
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = 'Cost_Sheet_Template.csv';
        a.click();
    }

    uploadTemplate() {
        const input = this.template.querySelector('.upload');
        input.value = null;
        input.click();
    }
    openFilePicker() {
        this.template.querySelector('input.upload').click();
    }
    handleFileUpload(event) {

        this.resetState();

        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            const text = reader.result;

            const lines = text.split(/\r?\n/).filter(l => l.trim());
            if (!lines.length) return;

            /* ---------------- CSV PARSER (Handles Quotes) ---------------- */

            const parseCsvLine = (line) => {
                const result = [];
                let current = '';
                let inQuotes = false;

                for (let char of line) {
                    if (char === '"') {
                        inQuotes = !inQuotes;
                    } else if (char === ',' && !inQuotes) {
                        result.push(current.trim());
                        current = '';
                    } else {
                        current += char;
                    }
                }
                result.push(current.trim());
                return result;
            };

            /* ---------------- HEADER VALIDATION ---------------- */

            const dataHeaders = parseCsvLine(lines[0])
                .map(h => h.replace(/^\uFEFF/, '').trim());

            const missing = this.expectedHeaders.filter(h => !dataHeaders.includes(h));
            const invalid = dataHeaders.filter(h => !this.expectedHeaders.includes(h));

            if (
                missing.length > 0 ||
                invalid.length > 0 ||
                JSON.stringify(dataHeaders) !== JSON.stringify(this.expectedHeaders)
            ) {
                this.headerErrorMessage =
                    'CSV headers are incorrect. Please use downloaded template.';
                this.showHeaderErrors = true;
            }

            this.headers = ['S.No', ...dataHeaders];

            /* ---------------- ROW PROCESSING ---------------- */

            const rows = [];
            const fileCodes = new Set();
            const payloadMap = new Map();

            lines.slice(1).forEach((line, index) => {

                const cols = parseCsvLine(line);
                while (cols.length < dataHeaders.length) cols.push('');

                const cells = [];
                const errors = [];
                const rowNo = index + 1;

                /* Serial Number */
                cells.push({
                    id: `sno_${index}`,
                    value: rowNo,
                    className: ''
                });

                dataHeaders.forEach((header, colIndex) => {

                    const value = cols[colIndex] || '';
                    let css = '';

                    /* Required */
                    if (this.requiredFields.has(header) && (!value || value.trim() === '')) {
                        errors.push(`${header} is required`);
                        css = 'error-cell';
                    }

                     /* Company Lookup */
                    if (header === 'Company' && value) {
                        if (!this.companyMap[value.toLowerCase()]) {
                            errors.push('Invalid Company');
                            css = 'error-cell';
                        }
                    }
                    /* Project Lookup */
                    if (header === 'Project' && value) {
                        if (!this.projectMap[value.toLowerCase()]) {
                            errors.push('Invalid Project');
                            css = 'error-cell';
                        }
                    }
                      /* Amount Validations */
                    // if (
                    //     header === 'Amount' ||
                    //     header === 'Tax Amount' ||
                    //     header === 'Total Amount Inclusive of Tax'
                    // ) {
                    //     if (value && (isNaN(value) || Number(value) < 0)) {
                    //         errors.push(`${header} must be a positive number`);
                    //         css = 'error-cell';
                    //     }
                    // }
                     /* Duplicate Code */
                    if (header === 'Template Code' && value) {
                        const key = value.toLowerCase();
                        if (this.existingTemplateCodes.has(key) || fileCodes.has(key)) {
                            errors.push('Duplicate Template Code');
                            css = 'error-cell';
                        }
                        fileCodes.add(key);
                    }
                       /* Boolean */
                    if (header === 'Active' && value) {
                        if (
                            value.toLowerCase() !== 'true' &&
                            value.toLowerCase() !== 'false'
                        ) {
                            errors.push('Active must be TRUE or FALSE');
                            css = 'error-cell';
                        }
                    }
debugger;
                    cells.push({
                        id: `row_${index}_${colIndex}`,
                        value: value,
                        className: css
                    });
                });

                /* If Row Has Errors */
                if (errors.length > 0) {

                    this.hasRowErrors = true;
                    this.rowErrorRows.push(rowNo);

                    cells.push({
                        id: `error_${index}`,
                        value: errors.join(' | '),
                        className: 'error-cell'
                    });

                }else {
                    const company = cols[0];
                    const project = cols[1];
                    const templateCode = cols[2];
                    const templateName = cols[3];
                    const active = cols[4];
                    const unitCode = cols[5];

                    // const pricingElementMaster = cols[6];
                    const unit = cols[7];
                    const pricingElementAlloc = cols[6];
                    const peGroup = cols[8];
                    const peType = cols[9];
                    const pricingType = cols[10];
                    const sequence = cols[11];
                    const quantity = cols[12];
                    const rate = cols[13];
                    const taxType = cols[14];
                    const taxName = cols[15];
                    const appPercent = cols[16];

                    if (!payloadMap.has(templateCode)) {

                        payloadMap.set(templateCode, {
                            template: {
                                companyId: this.companyMap[company?.toLowerCase()],
                                projectId: this.projectMap[project?.toLowerCase()],
                                templateCode: templateCode,
                                templateName: templateName,
                                active: active?.toLowerCase() === 'true'
                            },
                            unitCodes: [],
                            pricingRows: []
                        });

                    }

                    const payload = payloadMap.get(templateCode);

                    if (unitCode) {
                        payload.unitCodes.push(unitCode);
                    }

                    payload.pricingRows.push({
                        // pricingElementMaster,
                        pricingElementAlloc,
                        unit,
                        peGroup,
                        peType,
                        type: pricingType,
                        sequence: Number(sequence),
                        quantity: Number(quantity),
                        rate: Number(rate),
                        taxType,
                        taxName,
                        appPercent: Number(appPercent)
                    });

                    // this.recordsToInsert.push(record);
                }

                rows.push({
                    id: `row_${index}`,
                    cells: cells
                });
            });
                this.recordsToInsert = Array.from(payloadMap.values());

            /* Add Error Column if Needed */
            if (this.hasRowErrors) {
                this.headers = [...this.headers, 'Error'];
            }

            this.previewData = rows;

            /* Initialize Preview Pagination */
            this.paginatedRowsToDisplay =
                this.previewData.slice(0, this.pageSize);

            setTimeout(() => {
                const pagination =
                    this.template.querySelector('.previewPagination');
                if (pagination) {
                    pagination.setPagination(this.pageSize);
                }
            });

            /* Enable Save Only If No Errors */
            this.canSave =
                !this.showHeaderErrors &&
                !this.hasRowErrors &&
                this.previewData.length > 0;
        };

        reader.readAsText(file);
    }
    resetState() {
            this.headers = [];
            this.previewData = [];
            this.paginatedRowsToDisplay = [];
            this.headerErrorMessage = '';
            this.showHeaderErrors = false;
            this.hasRowErrors = false;
            this.rowErrorRows = [];
            this.canSave = false;
            this.recordsToInsert = [];
        }
    handleSave() {
        uploadCostSheet({ payloadJson: JSON.stringify(this.recordsToInsert) })
            .then(() => {
                this.toast('Success', 'Cost Sheet created successfully', 'success');
                this.previewData = [];
                this.recordsToInsert = [];
                this.resetState();
            })
            .catch(e => {
                this.toast(
                    'Error',
                    e?.body?.message || 'Insert failed',
                    'error'
                );
            });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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

    const selectedLabels = this.projectOptions
        .filter(p => p.checked)
        .map(p => p.label);

    this.selectedProjectNames = selectedLabels.length > 0
        ? selectedLabels.join(', ')
        : 'Select Projects';

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
     this.refreshUnitData();
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
                objectApiName: 'Cost_Sheet_Template__c', 
                actionName: 'new'
            }
        });
    }
}