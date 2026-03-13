import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import fetchDataOnLoad from '@salesforce/apex/BulkTaxMasterController.fetchDataOnLoad';
import getTaxMasters from '@salesforce/apex/BulkTaxMasterController.getTaxMasters';
import createTaxMasters from '@salesforce/apex/BulkTaxMasterController.createTaxMasters';

export default class BulkTaxMasterCsv extends LightningElement {
@track hasErrors = true;
@track columns = [];
@track previewData = [];
@track paginatedData = [];
@track recordsToInsert = [];
@track existingRecords = [];
@track paginatedUnitData = [];
@track errorRowNumbers = '';
@track headerErrorMessage = '';
@track showHeaderErrors = false;
taxTypes = [];
roundingMethods = [];
existingTaxNames = [];
pageSize = 5;

expectedHeaders = [
    'Tax Master Name',
    'Tax Type',
    'Short Name',
    'Taxable %',
    'Tax %',
    'Surcharge %',
    'Education Cess %',
    'Higher Education Cess %',
    'From Date',
    'Rounding Method',
    'Active',
    'Addition',
    'Deduction'
  ];

  fieldMap = {
    'Tax Master Name': 'Name',
    'Tax Type': 'Tax_Type__c',
    'Short Name': 'Short_Name__c',
    'Taxable %': 'Taxable__c',
    'Tax %': 'Tax__c',
    'Surcharge %': 'Surcharge__c',
    'Education Cess %': 'Education_Cess__c',
    'Higher Education Cess %': 'Higher_Education_Cess__c',
    'From Date': 'From_Date__c',
    'Rounding Method': 'Rounding_Method__c',
    'Active': 'Active__c',
    'Addition': 'Addition__c',
    'Deduction': 'Deduction__c'
  };

  requiredFields = new Set([
    'Tax Master Name',
    'Tax Type',
    'Short Name',
    'Taxable %',
    'Tax %',
    'Surcharge %',
    'Education Cess %',
    'Higher Education Cess %',
    'From Date',
    'Rounding Method'
  ]);

  checkboxFields = ['Active', 'Addition', 'Deduction'];
  numberFields = [
    'Taxable %',
    'Tax %',
    'Surcharge %',
    'Education Cess %',
    'Higher Education Cess %'
  ];

  get showErrorSummary() {
    return this.errorRowNumbers && this.errorRowNumbers.length > 0;
  }

  get showSubmit() {
    return this.previewData.length > 0;
  }

  get disableSubmit() {
    return this.hasErrors || this.recordsToInsert.length === 0;
  }
  get hasExistingRecords() {
        return this.existingRecords && this.existingRecords.length > 0;
    }
  
    jobPaginationCallback2(event) {
    this.paginatedUnitData = event.detail.recordToDisplay || [];
}

  connectedCallback() {
    fetchDataOnLoad()
      .then(data => {
        this.taxTypes = data.taxTypes || [];
        this.roundingMethods = data.roundingMethods || [];
        this.existingTaxNames = data.existingTaxNames || [];
        this.loadExistingRecords();
        this.resetView();
      })
      .catch(() => {
        this.showToast('Error', 'Failed to load reference data', 'error');
        this.resetView();
      });
  }

  loadExistingRecords() {
    getTaxMasters()
        .then(result => {

            this.existingRecords = result.map((rec, index) => ({
                Id: rec.Id,
                sNo: index + 1,
                Name: rec.Name,
                TaxType: rec.Tax_Type__c,
                ShortDate: rec.Short_Name__c,
                FromDate: rec.From_Date__c,
                Taxable: rec.Taxable__c,
                Tax: rec.Tax__c,
                RoundingMethod: rec.Rounding_Method__c,
                Active: rec.Active__c ? 'Yes' : 'No'
            }));

            this.paginatedUnitData =
                this.existingRecords.slice(0, this.pageSize);

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

  resetView() {
    this.columns = [];
    this.previewData = [];
    this.paginatedData = [];
    this.recordsToInsert = [];
    this.errorRowNumbers = '';
    this.hasErrors = true;
  }

  downloadTemplate() {
    const csv = this.expectedHeaders.join(',') + '\n';
    const uri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
    const a = document.createElement('a');
    a.href = uri;
    a.download = 'Tax_Master_Template.csv';
    a.click();
  }

  uploadTemplate() {
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
    this.resetView();

    const lines = text.split(/\r?\n/).map(l => l.trim());
    if (!lines.length) return;

    const dataHeaders = lines[0].split(',').map(h => h.trim());

    /* ================= HEADER VALIDATION ================= */

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

    this.columns = [
    { label: 'S.No', class: '' },
    ...dataHeaders.map(h => ({ label: h, class: '' })),
    { label: 'Errors', class: '' }
  ];
    if (this.showHeaderErrors || this.hasErrors) {
        this.columns = [...this.columns, 'Errors'];
    }


    const fileNames = new Set();
    const errorRows = [];

    lines.slice(1).forEach((line, index) => {
        
        const row = line.split(',').map(v => v.trim());
        
        if (row.every(val => !val || val.trim() === '')) {
        return;
        }
        const cells = [{ value: index + 1 }];
        const record = {};
        const errors = [];
        let hasRowError = false;

        this.expectedHeaders.forEach((col, i) => {

            let val = row[i] || '';

            /* Required field check */
            if (this.requiredFields.has(col) && !val) {
                errors.push(col + ' is required');
                hasRowError = true;
            }

            /* Duplicate + Existing Name */
            if (col === 'Tax Master Name' && val) {
                const key = val.toLowerCase();

                if (this.existingTaxNames.includes(key)) {
                    errors.push('Tax Master Name already exists');
                    hasRowError = true;
                }
                else if (fileNames.has(key)) {
                    errors.push('Duplicate Tax Master Name in file');
                    hasRowError = true;
                }
                else {
                    fileNames.add(key);
                }
            }

            /* Checkbox Validation */
            if (this.checkboxFields.includes(col)) {
                if (!val) {
                    record[this.fieldMap[col]] = false;
                }
                else if (val.toLowerCase() === 'true') {
                    record[this.fieldMap[col]] = true;
                }
                else if (val.toLowerCase() === 'false') {
                    record[this.fieldMap[col]] = false;
                }
                else {
                    errors.push(col + ' must be TRUE or FALSE');
                    hasRowError = true;
                }

                cells.push({ value: val });
                return;
            }

            /* Number Validation */
            if (this.numberFields.includes(col)) {

                let numVal = val.replace('%', '').trim();

                if (numVal === '' || isNaN(numVal)) {
                    errors.push(col + ' must be numeric');
                    hasRowError = true;
                } else {
                    record[this.fieldMap[col]] = Number(numVal);
                }

                cells.push({ value: val });
                return;
            }

            /* Date Validation */
            if (col === 'From Date' && val) {

                const parts = val.split('-');

                if (parts.length !== 3) {
                    errors.push('Invalid From Date format (DD-MM-YYYY)');
                    hasRowError = true;
                } else {
                    const isoDate = `${parts[2]}-${parts[1]}-${parts[0]}`;
                    if (isNaN(new Date(isoDate).getTime())) {
                        errors.push('Invalid From Date');
                        hasRowError = true;
                    } else {
                        record[this.fieldMap[col]] = isoDate;
                    }
                }

                cells.push({ value: val });
                return;
            }

            /* Picklist Validation */
            if (col === 'Tax Type' && val && !this.taxTypes.includes(val)) {
                errors.push('Invalid Tax Type');
                hasRowError = true;
            }

            if (col === 'Rounding Method' && val && !this.roundingMethods.includes(val)) {
                errors.push('Invalid Rounding Method');
                hasRowError = true;
            }

            record[this.fieldMap[col]] = val;
            cells.push({ value: val });
        });

        if (hasRowError) {
            errorRows.push(index + 1);
            cells.push({
                value: errors.join(' | '),
                class: 'error-column'
            });
        } else if (this.showHeaderErrors || errorRows.length > 0) {
            cells.push({
                value: '-',
                class: ''
            });
        }else {
            cells.push({ value: '-' });
            this.recordsToInsert.push(record);
        }

        this.previewData.push({
            rowKey: index + 1,
            cells
        });
    });

    this.errorRowNumbers = errorRows.join(', ');
    this.hasErrors = errorRows.length > 0;
    this.columns = this.columns.map(col => {
    if (col.label === 'Errors') {
        return {
            ...col,
            class: this.hasErrors ? 'error-header' : ''
        };
    }
    return col;
});
    
}

  handleSubmit() {
    if (this.disableSubmit) return;

    createTaxMasters({ recordsJson: JSON.stringify(this.recordsToInsert) })
      .then(() => {
        this.showToast('Success', 'Tax Masters created successfully', 'success');
        this.resetView();
      })
      .catch(err => {
        this.showToast('Error', err.body?.message || 'Insert failed', 'error');
      });
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
    handleRowClick(event) {
        debugger
        const recordId = event.currentTarget.dataset.id;
        window.open('/' + recordId, '_blank');
    }
}