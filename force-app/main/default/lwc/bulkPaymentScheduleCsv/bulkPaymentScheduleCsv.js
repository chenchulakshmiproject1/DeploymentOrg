import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchDataOnLoad from '@salesforce/apex/BulkPaymentScheduleController.fetchDataOnLoad';
import createPaymentSchedules from '@salesforce/apex/BulkPaymentScheduleController.createPaymentSchedules';

export default class BulkPaymentScheduleCsv extends LightningElement {

    /* -------------------- UI TRACKING -------------------- */

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

    @track curPageNum;
    @track curPageNumUnit;

    pageSize = 5;
    pageSize2 = 5;

    /* -------------------- MASTER DATA -------------------- */

    existingCodes = new Set();
    get hasExistingRecords() {
    return this.existingRecords && this.existingRecords.length > 0;
    }
    expectedHeaders = [
        'Installment Name',
        'Installment Code',
        'Installment Sequence',
    ];

    apiHeaders = [
        'Name',
        'Installment_Code__c',
        'Installment_Sequence__c',
    ];

    requiredFields = new Set([
        'Installment Name',
        'Installment Code',
        'Installment Sequence'
    ]);

    /* -------------------- LOAD EXISTING DATA -------------------- */

@wire(fetchDataOnLoad)
wiredData({ data, error }) {
    if (data) {
        console.log('Records from Apex:', data.existingRecords);
        this.existingCodes = new Set(
            (data.existingInstallmentCodes || []).map(v => v.toLowerCase())
        );

        this.existingRecords = (data.existingRecords || []).map((item, index) => {
            return {
                ...item,
                sNo: index + 1
            };
        });
        this.paginatedUnitData = this.existingRecords.slice(0, this.pageSize2);

        setTimeout(() => {
            const pagination = this.template.querySelector('.unitPagination');
            if (pagination) pagination.setPagination(this.pageSize2);
        });

    } else if (error) {
        console.error('Error loading data', error);
    }
}

    /* -------------------- TEMPLATE DOWNLOAD -------------------- */

    downloadTemplate() {
        const csv = this.expectedHeaders.join(',') + '\n';
        const uri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);

        const a = document.createElement('a');
        a.href = uri;
        a.download = 'Payment_Schedule_Template.csv';
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

            if (!lines.length) {
                this.showToast('Error', 'Empty file', 'error');
                return;
            }

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

                    /* Field Specific Validation */
                    if (header === 'Installment Name' && value) {
                        if (!/^[A-Za-z ]+$/.test(value)) {
                            errors.push('Installment Name must contain only text');
                            css = 'error-cell';
                        }
                    }

                    if (header === 'Installment Code' && value) {
                
                        const key = value.toLowerCase();
                        if (this.existingCodes.has(key) || fileCodes.has(key)) {
                            errors.push('Duplicate Installment Code');
                            css = 'error-cell';
                        }
                        fileCodes.add(key);
                    }

                    if (header === 'Installment Sequence') {

                    const cleanValue = (value || '').trim();
                    const num = parseFloat(cleanValue);

                    if (!cleanValue) {
                        errors.push('Installment Sequence is required');
                        css = 'error-cell';
                    }
                    else if (!/^-?\d+$/.test(cleanValue)) {
                        errors.push('Installment Sequence must be numeric');
                        css = 'error-cell';
                    }
                    else if (num < 0) {
                        errors.push('Installment Sequence cannot be negative');
                        css = 'error-cell';
                    }
                }
                    // if (header === 'Company' && value) {
                    //     if (!this.companyMap[value.toLowerCase()]) {
                    //         errors.push('Invalid Company');
                    //         css = 'error-cell';
                    //     }
                    // }

                    // if (header === 'Tower' && value) {
                    //     if (!this.towerMap[value.toLowerCase()]) {
                    //         errors.push('Invalid Tower');
                    //         css = 'error-cell';
                    //     }
                    // }

                    // if (header === 'Before AOS Demand Letter' && value) {
                    //     if (
                    //         value.toLowerCase() !== 'true' &&
                    //         value.toLowerCase() !== 'false'
                    //     ) {
                    //         errors.push('Must be TRUE or FALSE');
                    //         css = 'error-cell';
                    //     }
                    // }

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

        if (!this.canSave) {
            this.showToast('Error', 'Fix errors before saving', 'error');
            return;
        }

        const formattedData = this.previewData.map(row =>
            row.cells
                .slice(1, this.expectedHeaders.length + 1)
                .map(cell => cell.value)
        );

        createPaymentSchedules({
            headers: this.apiHeaders,
            data: formattedData
        })
            .then(() => {
                this.showToast('Success', 'Payment Schedules created', 'success');
                this.resetState();
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error.body?.message || 'Insert failed',
                    'error'
                );
            });
    }

    /* -------------------- PAGINATION -------------------- */

    jobPaginationCallback(event) {
        this.paginatedRowsToDisplay =
            event.detail.recordToDisplay || [];
        this.curPageNum = event.detail.curPage || 1;
    }

    jobPaginationCallback2(event) {
        this.paginatedUnitData =
            event.detail.recordToDisplay || [];
        this.curPageNumUnit = event.detail.curPage || 1;
    }

    /* -------------------- HELPERS -------------------- */

    resetState() {
        this.headers = [];
        this.previewData = [];
        this.headerErrorMessage = '';
        this.showHeaderErrors = false;
        this.hasRowErrors = false;
        this.rowErrorRows = [];
        this.canSave = false;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({ title, message, variant })
        );
    }
}