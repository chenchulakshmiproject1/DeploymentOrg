import { LightningElement, track,wire } from 'lwc';
import saveExcelData from '@salesforce/apex/BulkUploadProjectDataController.saveExcelData';
import getDataOnLoad from '@salesforce/apex/BulkUploadProjectDataController.getDataOnLoad';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class BulkUploadProjectData extends LightningElement {
    @track headers = [];
    @track previewData = [];
    @track headerErrorMessage = '';
    @track showHeaderErrors = false;
    @track hasRowErrors = false;
    @track rowErrorRows = [];
    @track canSave = false;
    @track existingUnits = [];
    @track existingCompanies = [];
    @track towersCount = 0;
    @track unitsCount = 0;
    @track paginatedRowsToDisplay = [];
    @track curPageNum;
    @track pageSize = 5;
    @track pageSize2 = 5;
    @track paginatedUnitData = [];
    @track curPageNumUnit;
    @track projectOptions = [];
    @track selectedProjects = [];
    @track selectedProjectNames = 'Select Projects';
    @track showDropdown = false;
    @track filteredUnits = []; 

    expectedHeaders = [
        'Project Name','Project Code','Company','Tower Name','Tower Code',
        'Total Parking','Parking Availability','Floor No','Floor Name',
        'Unit Code','Description','Mortgage','Share'
    ];
    apiheaders = ['Project_Name','Project_Code__c','Company__c','Tower_Name','Tower_Code__c',
        'Total_Parking__c','Parking_Availability__c','Floor_No__c','Floor_Name__c',
        'Unit_Code__c','Description__c','Mortgage','Share'];
    @wire(getDataOnLoad)
    wiredResults({data,error}){
        if(data){
                    this.projectOptions = data.projects.map(p => {
            return {
                label: p.Name,
                value: p.Id,
                checked:false
            };
        });
            this.existingUnits = data?.existingUnits.map((item,index)=>{
                return {
                    ...item,
                    sNo:index+1,
                    Saleable_Area__c:item.Saleable_Area__c!=null?item.Saleable_Area__c:0,
                    towerName:item?.Floor__r?.Tower__r?.Name !=null?item.Floor__r.Tower__r.Name:'',
                    projectId: item?.Floor__r?.Blocks__r?.Project__c ?? '',
                    floorNum:item?.Floor__r?.Floor_No__c!=null?item.Floor__r.Floor_No__c:'',
                    Unit_Type__c:item.Unit_Type__c!=null?item.Unit_Type__c:'',
                    Status__c :item.Status__c !=null?item.Status__c :'',
                }
            });
            this.existingCompanies  = data?.existingCompns;
            this.towersCount = data?.towersCount;
            this.unitsCount = this.existingUnits.length;
            this.filteredUnits = [...this.existingUnits];

             setTimeout(() => {
                const pagination = this.template.querySelector('.unitPagination');
                if (pagination) pagination.setPagination(this.pageSize2);
            });
        }else{
            console.log('error occured while loading the existing units'+error);
        }
    }


    downloadTemplate() {
        const headers = this.expectedHeaders.join(',');
        const csv = headers + '\n';
        const encodedUri = 'data:text/csv;charset=utf-8,' + encodeURIComponent(csv);
        const a = document.createElement('a');
        a.href = encodedUri;
        a.target = '_self';
        a.download = 'Project_Upload_Template.csv';
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
    }

    handleUpload() {
        this.template.querySelector('.upload').click();
    }

    handleFileUpload(event) {
        this.headers = [];
        this.previewData = [];
        this.headerErrorMessage = '';
        this.showHeaderErrors = false;
        this.hasRowErrors = false;
        this.rowErrorRows = [];
        this.canSave = false;

        const file = event.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = () => {
            const text = reader.result;
            const lines = text.split(/\r\n|\n|\r/).map(l => l.trim());

            if (lines.length === 0) {
                this.showToast('Error', 'No data found in the file.', 'error');
                return;
            }

            const dataHeaders = lines[0].split(',').map(h => h.trim());

            const missingHeaders = this.expectedHeaders.filter(h => !dataHeaders.includes(h));
            const invalidHeaders = dataHeaders.filter(h => !this.expectedHeaders.includes(h));

            if (missingHeaders.length > 0 || invalidHeaders.length > 0 || dataHeaders.length !== this.expectedHeaders.length) {
                let msg = '';
                if (missingHeaders.length > 0) msg += 'Missing headers: ' + missingHeaders.join(', ') + '. ';
                if (invalidHeaders.length > 0) msg += 'Invalid headers: ' + invalidHeaders.join(', ') + '. ';
                msg += 'Please use the downloaded template.';
                this.headerErrorMessage = msg;
                this.showHeaderErrors = true;
                // return;
            }
            const msgs = this.headerErrorMessage;
            for (let i = 0; i < this.expectedHeaders.length; i++) {
                if (dataHeaders[i] !== this.expectedHeaders[i]) {
                    this.headerErrorMessage = 'Incorrect order of headers. Please use the downloaded template.';
                    this.showHeaderErrors = true;
                    // return;
                }
            }
            this.headerErrorMessage = msgs+' '+this.headerErrorMessage;

            this.headers = [...dataHeaders];
            let finalHeaders = [...dataHeaders];

            const dataLines = lines.slice(1);

            let rows = [];

            dataLines.forEach((line, rowIndex) => {
                const cols = line.split(',').map(c => c.trim());

                const hasData = cols.some(cell => cell !== '');

                if (hasData) {
                    const cells = cols.map((cell, cellIndex) => ({
                        id: `row_${rowIndex}_cell_${cellIndex}`,
                        value: cell,
                        className: ''
                    }));

                    rows.push({
                        id: `row_${rowIndex}`,
                        rowNo: rowIndex+1,
                        cells: cells,
                        hasError: false
                    });
                }
            });
            const unitIndex = this.headers.indexOf('Unit Code');
            const unitMap = new Map();
            this.rowErrorRows = [];
            rows.forEach((row, rowIndex) => {
                let rowErrors = [];

                this.headers.forEach((header, index) => {
                    if (header !== 'Description') {
                        const cell = row.cells[index];
                        const value = cell ? cell.value : '';
                        if (!value) {
                            rowErrors.push(this.expectedHeaders[index] + ' is required');
                        }
                        else if(header == 'Parking Availability' && (value.toLowerCase() != 'true' && value.toLowerCase() != 'false')){
                            rowErrors.push('Parking Availability should be true or false');
                        }else if(header == 'Company' && !this.existingCompanies.includes(value)){
                            rowErrors.push('Invalid Company name');
                        }
                    }
                });

                const unitVal = row.cells[unitIndex]?.value;
                if (unitVal) {
                    if (unitMap.has(unitVal)) {
                        rowErrors.push('Duplicate Unit Code');
                    } else {
                        unitMap.set(unitVal, true);
                    }
                }

                if (rowErrors.length > 0) {
                    this.hasRowErrors = true;
                    row.hasError = true;
                    this.rowErrorRows.push(rowIndex+1);
                    row.cells.push({
                        id: `row_${rowIndex}_cell_error`,
                        value: rowErrors.join(' | '),
                        className: 'error-cell'
                    });
                }
            });

            if (this.hasRowErrors) {
                finalHeaders = [...this.headers, 'Error'];
                this.headers = finalHeaders;
            }
            this.headers = ['S.No', ...this.headers];

            rows = rows.map((row, index) => {
                return {
                    ...row,
                    cells: [
                        {
                            id: `row_${index}_sno`,
                            value: index + 1,
                            className: ''
                        },
                        ...row.cells
                    ]
                };
            });
            this.previewData = rows;
            this.canSave = !this.showHeaderErrors && !this.hasRowErrors && this.previewData.length > 0;
            setTimeout(() => {
                const pagination = this.template.querySelector('.previewPagination');
                if (pagination) pagination.setPagination(this.pageSize);
            });
        };

        reader.readAsText(file);
    }

    handleSave() {
        if (!this.canSave) {
            this.showToast('Error', 'Please fix the errors before saving.', 'error');
            return;
        }

        const formattedData = this.previewData.map(row =>
            row.cells.slice(1, this.expectedHeaders.length+1).map(cell => cell.value)
        );
        debugger;
       
        saveExcelData({ headers: this.apiheaders, data: formattedData })
            .then(() => {
                this.showToast('Success', 'Data saved successfully!', 'success');
                this.previewData = [];
                this.headers = [];
                this.canSave = false;
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'Unknown error occurred', 'error');
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    openFilePicker() {
        this.template.querySelector('input.upload').click();
    }

    handleDragOver(event) {
        event.preventDefault();
        event.currentTarget.classList.add('drag-over');
    }

    handleDragLeave(event) {
        event.currentTarget.classList.remove('drag-over');
    }
    toggleDropdown(){
    this.showDropdown = !this.showDropdown;
}
  
    handleDrop(event) {
        event.preventDefault();
        event.currentTarget.classList.remove('drag-over');
        const files = event.dataTransfer.files;
        if (files && files.length > 0) {
            const fakeEvent = { target: { files } };
            this.handleFileUpload(fakeEvent);
        }
    }
    
    jobPaginationCallback(event){
        this.paginatedRowsToDisplay = event.detail.recordToDisplay || [];
        this.curPageNum = event.detail.curPage || 1;
        this.refreshItemsToDisplay();
    }
    refreshItemsToDisplay() {
        debugger;
        const page = this.curPageNum || 1;
        this.paginatedRowsToDisplay = [...this.previewData.slice((page - 1) * this.pageSize2, page * this.pageSize2)];
    }
    jobPaginationCallback2(event){
        this.paginatedUnitData = event.detail.recordToDisplay || [];
        this.curPageNumUnit = event.detail.curPage || 1;
        this.refreshItemsToDisplay2();
    }
    refreshItemsToDisplay2() {
        debugger;
        const page = this.curPageNumUnit || 1;
        this.paginatedUnitData = [...this.existingUnits.slice((page - 1) * this.pageSize2, page * this.pageSize2)];
    }
    handleProjectChange(event){
    this.selectedProject = event.detail.value;

    if(!this.selectedProject){
        this.paginatedUnitData = [...this.existingUnits];
        return;
    }

    const filtered = this.existingUnits.filter(unit =>
        unit?.Floor__r?.Tower__r?.Project__c === this.selectedProject  
    );

    this.paginatedUnitData = filtered;
}
   handleProjectSelect(event){

    const projectId = event.target.value;
    const isChecked = event.target.checked;

    this.projectOptions = this.projectOptions.map(opt=>{
        if(opt.value === projectId){
            opt.checked = isChecked;
        }
        return opt;
    });

    if(isChecked){
        this.selectedProjects = [...this.selectedProjects, projectId];
    } else {
        this.selectedProjects = this.selectedProjects.filter(p => p !== projectId);
    }

    const selectedLabels = this.projectOptions
        .filter(p => p.checked)
        .map(p => p.label);

    this.selectedProjectNames =
        selectedLabels.length > 0 ? selectedLabels.join(', ') : 'Select Projects';

    this.filterUnits();
}
    filterUnits(){
        if(this.selectedProjects.length === 0){
            this.filteredUnits = [...this.existingUnits];
        } else {
            this.filteredUnits = this.existingUnits.filter(unit =>
                this.selectedProjects.includes(unit.projectId)
            );
        }

        this.unitsCount = this.filteredUnits.length;
        this.curPageNumUnit = 1;

        setTimeout(() => {
            const pagination = this.template.querySelector('.unitPagination');
            if (pagination) pagination.setPagination(this.pageSize2);
        });
    }
    handleRowClick(event) {
        debugger
        const recordId = event.currentTarget.dataset.id;
        window.open('/' + recordId, '_blank');
    }
}