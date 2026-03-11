import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchDataOnLoad from '@salesforce/apex/BulkPricingElementController.fetchDataOnLoad';
import createPricingElements from '@salesforce/apex/BulkPricingElementController.createPricingElements';

export default class BulkPricingElementCsv extends LightningElement {

    /* -------------------- TRACKED PROPERTIES -------------------- */

    @track headers = [];
    @track previewData = [];
    @track paginatedRowsToDisplay = [];

    @track headerErrorMessage = '';
    @track showHeaderErrors = false;

    @track hasRowErrors = false;
    @track rowErrorRows = [];

    @track canSave = false;

    @track existingRecords = [];
    @track paginatedUnitData = [];

    @track recordsToInsert = [];

    pageSize = 5;

    categories = [];
    baseUnits = [];
    conversionUnits = [];
    parkingTypes = [];
    existingCodes = new Set();
    

    /* -------------------- EXPECTED HEADERS -------------------- */

    expectedHeaders = [
        'Pricing Element Master Name',
        'Category',
        'Base Unit',
        'Code',
        'Conversion Unit',
        'Conversion Factor'
    ];

    fieldMap = {
        'Pricing Element Master Name': 'Name',
        'Category': 'Category__c',
        'Base Unit': 'Base_Unit__c',
        'Code': 'Code__c',
        'Conversion Unit': 'Conversion_Unit__c',
        'Conversion Factor': 'Conversion_Factor__c'
    };

    requiredFields = new Set([
        'Pricing Element Master Name',
        'Category',
        'Base Unit',
        'Code',
        'Conversion Unit',
        'Conversion Factor'
    ]);

    /* -------------------- GETTERS -------------------- */

    get hasExistingRecords() {
        return this.existingRecords && this.existingRecords.length > 0;
    }

    
    jobPaginationCallback2(event) {
        this.paginatedUnitData = event.detail.recordToDisplay || [];
        this.curPageNumUnit = event.detail.curPage || 1;
    }

    jobPaginationCallback(event) {
    this.paginatedRowsToDisplay = event.detail.recordToDisplay || [];
}

    /* -------------------- LOAD DATA -------------------- */

    @wire(fetchDataOnLoad)
    wiredData({ data, error }) {
        if (data) {

            this.categories = data.categories || [];
            this.baseUnits = data.baseUnits || [];
            this.conversionUnits = data.conversionUnits || [];
            this.parkingTypes = data.parkingTypes || [];
            this.existingCodes = new Set(data.existingCodes || []);

            this.existingRecords = (data.existingRecords || []).map((item, index) => {
                return { ...item, sNo: index + 1 };
            });

            this.paginatedUnitData = this.existingRecords.slice(0, this.pageSize);
            console.log('Existing Records:', this.existingRecords);
            console.log('Paginated Data:', this.paginatedUnitData);
            setTimeout(() => {
                const pagination = this.template.querySelector('.unitPagination');
                if (pagination) pagination.setPagination(this.pageSize);
            });

        } else if (error) {
            console.error('Wire error:', error);
        }
    }
    

    /* -------------------- TEMPLATE DOWNLOAD -------------------- */

    downloadTemplate() {
        const csv = this.expectedHeaders.join(',') + '\n';
        const a = document.createElement('a');
        a.href = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        a.download = 'Pricing_Element_Master_Template.csv';
        a.click();
    }

    handleUpload() {
        this.template.querySelector('.upload').click();
    }

    openFilePicker() {
        this.template.querySelector('input.upload').click();
    }

    /* -------------------- FILE UPLOAD -------------------- */

    handleFileUpload(event) {

        this.resetState();

        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();

        reader.onload = () => {

            const lines = reader.result.split(/\r?\n/).filter(l => l.trim());
            if (!lines.length) return;

            const dataHeaders = lines[0].split(',').map(h => h.trim());

            /* -------- HEADER VALIDATION -------- */

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

            /* -------- ROW PROCESSING -------- */

            const rows = [];
            const fileCodes = new Set();

            lines.slice(1).forEach((line, index) => {

                const cols = line.split(',').map(v => v.trim());
                const cells = [];
                const errors = [];
                const rowNo = index + 1;

                cells.push({
                    id: `sno_${index}`,
                    value: rowNo,
                    className: ''
                });

                dataHeaders.forEach((header, colIndex) => {

                    const value = cols[colIndex] || '';
                    let css = '';

                    /* Required Validation */
                    if (this.requiredFields.has(header) && !value) {
                        errors.push(`${header} is required`);
                        css = 'error-cell';
                    }

                    /* Picklist Validation */
                    if (header === 'Category' && value &&
                        !this.categories.includes(value)) {
                        errors.push('Invalid Category');
                        css = 'error-cell';
                    }

                    if (header === 'Base Unit' && value &&
                        !this.baseUnits.includes(value)) {
                        errors.push('Invalid Base Unit');
                        css = 'error-cell';
                    }

                    if (header === 'Conversion Unit' && value &&
                        !this.conversionUnits.includes(value)) {
                        errors.push('Invalid Conversion Unit');
                        css = 'error-cell';
                    }

                    if (header === 'Parking Type' && value &&
                        !this.parkingTypes.includes(value)) {
                        errors.push('Invalid Parking Type');
                        css = 'error-cell';
                    }

                    /* Duplicate Code */
                    if (header === 'Code' && value) {
                        const key = value.toLowerCase();
                        if (this.existingCodes.has(key) || fileCodes.has(key)) {
                            errors.push('Duplicate Code');
                            css = 'error-cell';
                        }
                        fileCodes.add(key);
                    }

                    /* Conversion Factor */
                    if (header === 'Conversion Factor' && value) {
                        if (isNaN(value) || Number(value) <= 0) {
                            errors.push('Must be positive number');
                            css = 'error-cell';
                        }
                    }

                    /* Boolean */
                    if (header === 'Agreement' && value) {
                        if (
                            value.toLowerCase() !== 'true' &&
                            value.toLowerCase() !== 'false'
                        ) {
                            errors.push('Agreement must be TRUE or FALSE');
                            css = 'error-cell';
                        }
                    }

                    cells.push({
                        id: `row_${index}_${colIndex}`,
                        value: value,
                        className: css
                    });
                });

                if (errors.length > 0) {
                    this.hasRowErrors = true;
                    this.rowErrorRows.push(rowNo);

                    cells.push({
                        id: `error_${index}`,
                        value: errors.join(' | '),
                        className: 'error-cell'
                    });
                } else {
                    /* Build record for insert */
                    const record = {};
                    dataHeaders.forEach((header, colIndex) => {
                        const apiField = this.fieldMap[header];
                        if (apiField) {
                            let val = cols[colIndex] || '';

                            if (header === 'Agreement') {
                                val = val ? val.toLowerCase() === 'true' : false;
                            }

                            record[apiField] = val;
                        }
                    });

                    this.recordsToInsert.push(record);
                }

                rows.push({
                    id: `row_${index}`,
                    cells: cells
                });
            });

            if (this.hasRowErrors) {
                this.headers = [...this.headers, 'Error'];
            }

            this.previewData = rows;

            this.canSave =
                !this.showHeaderErrors &&
                !this.hasRowErrors &&
                this.previewData.length > 0;

            setTimeout(() => {
                const pagination =
                    this.template.querySelector('.previewPagination');
                if (pagination) pagination.setPagination(this.pageSize);
            });
        };

        reader.readAsText(file);
    }

    /* -------------------- SAVE -------------------- */

    handleSave() {

        if (!this.canSave || !this.recordsToInsert.length) {
            this.showToast('Error', 'Fix errors before saving', 'error');
            return;
        }

        createPricingElements({
            recordsJson: JSON.stringify(this.recordsToInsert)
        })
            .then(() => {
                this.showToast('Success', 'Pricing Elements created successfully', 'success');
                this.resetState();
            })
            .catch(err => {
                this.showToast('Error', err.body?.message || 'Insert failed', 'error');
            });
    }

    /* -------------------- HELPERS -------------------- */

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

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}