import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchDataOnLoad from '@salesforce/apex/BulkPaymentSchemeController.fetchDataOnLoad';
import getPaymentSchemes from '@salesforce/apex/BulkPaymentSchemeController.getPaymentSchemes';
import createPaymentSchemes from '@salesforce/apex/BulkPaymentSchemeController.createPaymentSchemes';

export default class BulkPaymentSchemeCsv extends LightningElement {

    /* ---------------- TRACKED ---------------- */

    @track headers = [];
    @track previewData = [];
    @track paginatedRowsToDisplay = [];
    @track existingRecords = [];
    @track paginatedUnitData = [];
    recordsToInsert = [];
    @track hasErrors = false;
    @track hasRowErrors = false;
    @track showHeaderErrors = false;
    @track headerErrorMessage = '';
    @track errorRowNumbers = '';
    @track canSave = false;

    @track projectOptions = [];
    @track selectedProjects = [];
    @track selectedProjectNames = 'Select Projects';
    @track showDropdown = false;
    @track filteredRecords = [];
    @track curPageNumUnit = 1;

    pageSize = 5;

    /* ---------------- MAPS ---------------- */

    companyMap = {};
    projectMap = {};
    blockMap = {};

    payload = {};
    requiredFields = new Set([
    'Company','Project','Block','Payment Scheme Name','Token Amount',
    'From Date','To Date'
    ]);
    expectedHeaders = [
        'Company','Project','Block','Payment Scheme Name','Token Amount',
        'From Date','To Date'
    ];

    /* ---------------- GETTERS ---------------- */

    get showSubmit() {
        return this.previewData.length > 0;
    }

    get hasExistingRecords() {
        return this.existingRecords && this.existingRecords.length > 0;
    }

    get disableSubmit() {
        return this.hasErrors || Object.keys(this.payload).length === 0;
    }
    jobPaginationCallback2(event) {
        this.paginatedUnitData = event.detail.recordToDisplay || [];
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

    jobPaginationCallback(event) {
    this.paginatedRowsToDisplay = event.detail.recordToDisplay || [];
    }
    downloadTemplate() {
    const csv = this.expectedHeaders.join(',') + '\n';
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = 'Payment_Scheme_Template.csv';
        a.click();
    }



    uploadTemplate() {
        this.template.querySelector('.upload').click();
    }
    openFilePicker() {
        this.template.querySelector('input.upload').click();
    }

    /* ---------------- INIT ---------------- */

    connectedCallback() {
        this.loadExistingRecords();
        this.loadLookupData();
    }

    loadLookupData() {
        fetchDataOnLoad()
            .then(res => {
                this.companyMap = res.companyMap || {};
                this.projectMap = res.projectMap || {};
                this.blockMap = res.blockMap || {};
                this.projectOptions = Object.entries(this.projectMap).map(([name, id]) => ({
                label: name.charAt(0).toUpperCase() + name.slice(1),
                value: id,
                checked: false
            }));
        });
    }

    /* ---------------- LOAD EXISTING ---------------- */

    loadExistingRecords() {
        getPaymentSchemes()
            .then(result => {

                this.existingRecords = result.map((rec, index) => ({
                    Id: rec.Id,
                    sNo: index + 1,
                    Name: rec.Name,
                    CompanyName: rec.Company__r?.Name,
                    ProjectName: rec.Project__r?.Name,
                    ProjectId:rec.Project__c,
                    BlockName: rec.Block__r?.Name,
                    TokenAmount: rec.Token_Amount__c,
                    FromDate: rec.From_Date__c,
                    ToDate: rec.To_Date__c
                }));

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
            });
    }

    /* ---------------- FILE UPLOAD ---------------- */

 handleFileUpload(event) {

    this.resetState();

    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();

    reader.onload = () => {

        const text = reader.result;
        const lines = text.split(/\r?\n/).filter(l => l.trim());
        if (!lines.length) return;

        /* -------- CSV PARSER -------- */
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

        /* -------- HEADER VALIDATION -------- */

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

        /* -------- DATE VALIDATOR -------- */
        const isValidDate = (dateStr) => {
            if (!dateStr) return false;
            const parts = dateStr.split('-');
            if (parts.length !== 3) return false;

            const day = Number(parts[0]);
            const month = Number(parts[1]);
            const year = Number(parts[2]);

            if (
                isNaN(day) || isNaN(month) || isNaN(year) ||
                day < 1 || day > 31 ||
                month < 1 || month > 12 ||
                year < 1900
            ) return false;

            return true;
        };

        /* -------- ROW PROCESSING -------- */

        const rows = [];

        lines.slice(1).forEach((line, index) => {

            const cols = parseCsvLine(line);
            while (cols.length < dataHeaders.length) cols.push('');

            const cells = [];
            const errors = [];
            const rowNo = index + 1;

            /* Extract values properly */
            const companyName = cols[dataHeaders.indexOf('Company')];
            const projectName = cols[dataHeaders.indexOf('Project')];
            const blockName = cols[dataHeaders.indexOf('Block')];
            const schemeName = cols[dataHeaders.indexOf('Payment Scheme Name')];
            const tokenAmount = cols[dataHeaders.indexOf('Token Amount')];
            const fromDate = cols[dataHeaders.indexOf('From Date')];
            const toDate = cols[dataHeaders.indexOf('To Date')];

            const companyId = this.companyMap[companyName?.toLowerCase()];
            const projectId = this.projectMap[projectName?.toLowerCase()];
            const blockId = this.blockMap[blockName?.toLowerCase()];

            /* Serial Number */
            cells.push({
                id: `sno_${index}`,
                value: rowNo,
                className: ''
            });

            dataHeaders.forEach((header, colIndex) => {

                const value = cols[colIndex] || '';
                let css = '';

                /* Required Validation */
                if (!value || value.trim() === '') {
                    errors.push(`${header} is required`);
                    css = 'error-cell';
                }

                /* Lookup Validations */
                if (header === 'Company' && value && !companyId) {
                    errors.push('Invalid Company');
                    css = 'error-cell';
                }

                if (header === 'Project' && value && !projectId) {
                    errors.push('Invalid Project');
                    css = 'error-cell';
                }

                if (header === 'Block' && value && !blockId) {
                    errors.push('Invalid Block');
                    css = 'error-cell';
                }

                /* Token Amount Validation */
                if (header === 'Token Amount' && value) {
                    if (isNaN(value) || Number(value) < 0) {
                        errors.push('Token Amount must be a positive number');
                        css = 'error-cell';
                    }
                }

                /* Date Validation */
                if (header === 'From Date' && value && !isValidDate(value)) {
                    errors.push('From Date must be in DD-MM-YYYY format');
                    css = 'error-cell';
                }

                if (header === 'To Date' && value && !isValidDate(value)) {
                    errors.push('To Date must be in DD-MM-YYYY format');
                    css = 'error-cell';
                }

                cells.push({
                    id: `row_${index}_${colIndex}`,
                    value: value,
                    className: css
                });
            });

            /* If Errors */
            if (errors.length > 0) {

                this.hasRowErrors = true;

                cells.push({
                    id: `error_${index}`,
                    value: errors.join(' | '),
                    className: 'error-cell'
                });

            } else {

                /* Push Valid Record */
                this.recordsToInsert.push({
                    name: schemeName,
                    companyId: companyId,
                    projectId: projectId,
                    blockId: blockId,
                    tokenAmount: Number(tokenAmount),
                    fromDate: fromDate,
                    toDate: toDate
                });
            }

            rows.push({
                id: `row_${index}`,
                cells
            });
        });

        /* Add Error Header */
        if (this.hasRowErrors) {
            this.headers = [...this.headers, 'Error'];
        }

        this.previewData = rows;

        this.paginatedRowsToDisplay =
            this.previewData.slice(0, this.pageSize);

        setTimeout(() => {
            const pagination =
                this.template.querySelector('.previewPagination');
            if (pagination) {
                pagination.setPagination(this.pageSize);
            }
        });

        this.canSave =
            !this.showHeaderErrors &&
            !this.hasRowErrors &&
            this.previewData.length > 0;
    };

    reader.readAsText(file);
}

    /* ---------------- RESET ---------------- */

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

    /* ---------------- SAVE ---------------- */

    handleSave() {
        createPaymentSchemes({ recordsJson: JSON.stringify(this.recordsToInsert) })
            .then(() => {
                this.toast('Success', 'Cost Sheet created successfully', 'success');
                this.previewData = [];
                this.recordsToInsert = [];
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
}