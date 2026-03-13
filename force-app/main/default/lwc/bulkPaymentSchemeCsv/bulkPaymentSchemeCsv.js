import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import fetchDataOnLoad from '@salesforce/apex/BulkPaymentSchemeController.fetchDataOnLoad';
import getPaymentSchemes from '@salesforce/apex/BulkPaymentSchemeController.getPaymentSchemes';
import createPaymentSchemes from '@salesforce/apex/BulkPaymentSchemeController.createPaymentSchemes';
import { NavigationMixin } from "lightning/navigation";


export default class BulkPaymentSchemeCsv extends NavigationMixin(LightningElement) {

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
    @track scheduleMasterMap = {};
    @track installmentTypes = [];

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
        'From Date','To Date','Schedule Installment','Type','% Installment','Display Order'
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
                this.scheduleMasterMap = res.scheduleMasterMap || {};
                this.installmentTypes = res.installmentTypes || [];
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

            const rows = text.split(/\r?\n/).filter(r => r.trim());

            if (!rows.length) return;

            const headers = rows[0].split(',').map(h => h.trim());

            if (JSON.stringify(headers) !== JSON.stringify(this.expectedHeaders)) {
                this.headerErrorMessage =
                    'CSV headers are incorrect. Please use downloaded template.';
                this.showHeaderErrors = true;
                return;
            }

            this.headers = ['S.No', ...headers, 'Errors'];

            const errorRows = [];
            const schemeRunningTotal = {};
            const schemeOrders = {};
            const schemeParents = {};

            rows.slice(1).forEach((line, index) => {

                const values = line.split(',').map(v => v.trim());
                const cells = [];

                const errors = [];

                const [
                    companyRaw, projectRaw, blockRaw, schemeRaw,
                    tokenRaw, fromDateRaw, toDateRaw,
                    scheduleName, type, percentRaw, orderRaw
                ] = values;

                if (schemeRaw) {
                    schemeParents[schemeRaw] = {
                        company: companyRaw,
                        project: projectRaw,
                        block: blockRaw,
                        token: tokenRaw,
                        fromDate: fromDateRaw,
                        toDate: toDateRaw
                    };
                }

                const schemeName = schemeRaw || Object.keys(schemeParents).slice(-1)[0];
                const parent = schemeParents[schemeName];

                if (!parent) {
                    errors.push('Parent details missing');
                }

                const company = parent?.company;
                const project = parent?.project;
                const block = parent?.block;
                const token = parent?.token;
                const fromDate = parent?.fromDate;
                const toDate = parent?.toDate;

                const companyId = this.companyMap[company?.toLowerCase()];
                const projectId = this.projectMap[project?.toLowerCase()];
                const blockId = this.blockMap[block?.toLowerCase()];
                const scheduleId = this.scheduleMasterMap[scheduleName?.toLowerCase()];

                if (!companyId) errors.push('Invalid Company');
                if (!projectId) errors.push('Invalid Project');
                if (!blockId) errors.push('Invalid Block');
                if (!scheduleId) errors.push('Invalid Schedule Installment');
                if (!this.installmentTypes.includes(type)) errors.push('Invalid Type');

                let percent = null;

                if (!percentRaw) {
                    errors.push('Installment % required');
                } else {
                    percent = Number(percentRaw.replace('%', ''));
                    if (isNaN(percent)) {
                        errors.push('Installment % must be number');
                    }
                }

                const order = Number(orderRaw);

                if (isNaN(order)) {
                    errors.push('Display Order must be number');
                }

                if (!this.payload[schemeName]) {

                    this.payload[schemeName] = {
                        name: schemeName,
                        companyId,
                        projectId,
                        blockId,
                        tokenAmount: Number(token),
                        fromDate,
                        toDate,
                        installments: []
                    };

                    schemeRunningTotal[schemeName] = 0;
                    schemeOrders[schemeName] = new Set();
                }

                if (percent !== null) {

                    schemeRunningTotal[schemeName] += percent;

                    if (schemeRunningTotal[schemeName] > 100) {
                        errors.push(
                            `Installment % exceeds 100 (${schemeRunningTotal[schemeName]}%)`
                        );
                    }
                }

                const expectedOrder = schemeOrders[schemeName].size + 1;

                if (!isNaN(order) && order !== expectedOrder) {
                    errors.push('Display Order must start from 1 and be sequential');
                }

                if (schemeOrders[schemeName].has(order)) {
                    errors.push('Duplicate Display Order');
                } else if (!isNaN(order)) {
                    schemeOrders[schemeName].add(order);
                }

                if (errors.length === 0) {

                    this.payload[schemeName].installments.push({
                        scheduleMasterId: scheduleId,
                        type,
                        percentage: percent,
                        displayOrder: order
                    });

                } else {

                    this.hasRowErrors = true;
                }

                const effectiveValues = [
                    company, project, block, schemeName,
                    token, fromDate, toDate,
                    scheduleName, type, percentRaw, orderRaw
                ];

                cells.push({
                    id: `sno_${index}`,
                    value: index + 1,
                    className: ''
                });

                effectiveValues.forEach((v, i) => {

                    cells.push({
                        id: `row_${index}_${i}`,
                        value: v ?? '',
                        className: errors.length ? 'error-cell' : ''
                    });
                });

                cells.push({
                    id: `err_${index}`,
                    value: errors.join('; '),
                    className: errors.length ? 'error-cell' : ''
                });

                if (errors.length) errorRows.push(index + 1);

                this.previewData.push({
                    id: `row_${index}`,
                    cells
                });

            });

            this.errorRowNumbers = errorRows.join(', ');

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
        createPaymentSchemes({ recordsJson: JSON.stringify(this.payload) })
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
        // window.location.href = '/' + recordId;
        // this[NavigationMixin.Navigate]({
        //     type: 'standard__recordPage',
        //     attributes: {
        //         recordId: recordId,
        //         actionName: 'view'
        //     }
        // });
    }
    createIndividualRec(){
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Payment_Scheme__c', 
                actionName: 'new'
            }
        });
    }
}