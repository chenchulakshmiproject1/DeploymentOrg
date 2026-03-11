import { LightningElement,track,wire } from 'lwc';
import getLeadRecords from '@salesforce/apex/SiteVisitFormLWCController.getLeadRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import updateLeadDetails from '@salesforce/apex/SiteVisitFormLWCController.updateLeadDetails';
import getFieldsOnLoad from '@salesforce/apex/SiteVisitFormLWCController.getFieldsOnLoad';
import getPickListLookupDependentValues from '@salesforce/apex/SiteVisitFormLWCController.getPickListLookupDependentValues';
import createRecordDynamic from '@salesforce/apex/SiteVisitFormLWCController.createRecordDynamic';
import insertVisitRecord from '@salesforce/apex/SiteVisitFormLWCController.insertVisitRecord';


export default class SiteVistFormComponent extends LightningElement {
    @track searchValue = '';
    @track showVisitAfterCreatn = false;
    @track errorMsg = false;
    @track showLeadDetails = false;
    @track showAllLeadDetails = false;
    @track showAllOppDetails = false;
    @track showCreateLead = false;
    @track showVisitSection = false;
    @track showCustReq = false;
    @track visitDet = false;
    @track showGRE = false;
    @track showSalesManager = false;
    @track relVisits = false;
    @track leadDetails = {};
    @track leadList = [];
    @track oppList = [];
    @track visitId = '';
    @track visit = {};
    @track oppXvisitMap = {};
    @track visitList = [];
    @track oppName = '';
    @track opp = {};
    @track oppId = '';
    @track leadId = '';


    @track visitFields = [];
    @track leadFields = [];
    @track picklistFields = [];
    @track lookUpFields = [];
    @track dependentPicklistFields = [];
    @track leadSections = [];
    @track visitSections = [];
    @track currentFields = [];

    @wire(getFieldsOnLoad)
    wiredLeadVisitFields({ data, error }) {
        debugger;
        if (data) {
            this.visitFields = [];
            this.leadFields = [];
            this.picklistFields = [];
            this.lookUpFields = [];
            this.dependentPicklistFields = [];
            data.leadVistFields.forEach(item => {
                const field = {
                    ...item,
                    isText: item.Field_Type__c === 'Text',
                    isPhone: item.Field_Type__c === 'Phone',
                    isDate: item.Field_Type__c === 'Date',
                    isDateTime: item.Field_Type__c === 'DateTime',
                    isNumber: item.Field_Type__c === 'Number',
                    isCheckbox: item.Field_Type__c === 'Checkbox',
                    isPicklist: item.Field_Type__c === 'Picklist',
                    isMultiPicklist: item.Field_Type__c === 'MultiPicklist',
                    isDependentPicklist: item.Field_Type__c === 'Dependent Picklist',
                    isLookup: item.Field_Type__c === 'Lookup'
                };
                if(field.isPicklist || field.isMultiPicklist){
                    this.picklistFields.push({
                        id:item.Id,
                        objectapiName:item.Object_API_Name__c,
                        fieldapiName:item.Field_API_Name__c,
                    })
                }else if(field.isDependentPicklist){
                    this.dependentPicklistFields.push({
                       id:item.Id,
                       objectapiName:item.Object_API_Name__c,
                       fieldapiName:item.Field_API_Name__c,
                    })
                }else if(field.isLookup){
                    this.lookUpFields.push({
                        id:item.Id,
                        objectapiName:item.Object_API_Name__c,
                        fieldapiName:item.Field_API_Name__c,
                    })
                }

                if (item.Object_API_Name__c === 'Lead') {
                    this.leadFields.push(field);
                }
                else if (item.Object_API_Name__c === 'Visit__c') {
                    this.visitFields.push(field);
                }

            });
            if(this.picklistFields.length>0 || this.dependentPicklistFields.length>0 || this.lookUpFields.length>0){
                this.getPickDepLookupVal();
                
            }

        } else if (error) {
            console.log(error);
        }
    }
    getPickDepLookupVal(){

        getPickListLookupDependentValues({
            picklistFields:this.picklistFields,
            lookUpFields:this.lookUpFields,
            dependentPicklistFields:this.dependentPicklistFields
        })
        .then(result => {

            if(!result) return;

            const pickMap = result.mapOfIdbyOptions || {};
            const lookupMap = result.mapOfIdbyLookupOptions || {};
            const depMap = result.mapOfIdbyCntrlValbyDependentVal || {};

            /* ---------- LEAD FIELDS ---------- */

            this.leadFields = this.leadFields.map(field => {

                let updated = { ...field };

                if(pickMap[field.Id]){

                    updated.options = pickMap[field.Id].map(opt=>{
                        return{
                            label:opt.label,
                            value:opt.value,
                            selected:false,
                            class:'slds-listbox__option slds-media'
                        }
                    });

                    updated.selectedLabel = 'Select values';
                    updated.isOpen = false;
                }

                if(lookupMap[field.Id]){
                    updated.options = lookupMap[field.Id];
                }

                if(depMap[field.Id]){
                    updated.dependentOptions = depMap[field.Id].values;
                    updated.controllingField = depMap[field.Id].controllingField;
                }

                return updated;
            });


            /* ---------- VISIT FIELDS ---------- */

            this.visitFields = this.visitFields.map(field => {

                let updated = { ...field };

                if(pickMap[field.Id]){

                    updated.options = pickMap[field.Id].map(opt=>{
                        return{
                            label:opt.label,
                            value:opt.value,
                            selected:false,
                            class:'slds-listbox__option slds-media'
                        }
                    });

                    updated.selectedLabel = 'Select values';
                    updated.isOpen = false;
                }

                if(lookupMap[field.Id]){
                    updated.options = lookupMap[field.Id];
                }

                if(depMap[field.Id]){
                    updated.dependentOptions = depMap[field.Id].values;
                    updated.controllingField = depMap[field.Id].controllingField;
                }

                return updated;
            });

        })
        .catch(error => {
            console.error('Error loading picklist/lookup data', error);
        });
    }
    handleSearchChange(event){
        this.searchValue = event.target.value;
    }
    getleadDet(){
        debugger;
        this.visit = {};
        if(this.searchValue != ''){
            getLeadRecords({searchkey:this.searchValue})
            .then(result=>{
                if(result){
                    this.showVisitAfterCreatn = false;
                    this.visitId = '';
                    if(result.leadList.length == 1){
                        this.leadDetails = result.leadList[0];
                        this.leadList = [];
                        this.showLeadDetails = true;
                        this.showAllLeadDetails = false;
                        if(result.oppList.length == 0){
                            this.oppList = [];
                            this.showAllOppDetails = false;
                        }else if(result.oppList.length > 0){
                            this.oppXvisitMap = result.oppXvisitMap;
                            this.oppList = result.oppList;
                            this.showAllOppDetails = true;
                        }
                        this.errorMsg = false;
                        this.showCreateLead = false;
                        this.showVisitSection = false;
                        this.showCustReq = false;
                        this.visitDet = false;
                        this.showGRE = false;
                        this.showSalesManager = false;
                        this.relVisits = false;
                        this.leadId = result.leadList[0].Id;
                    }else if(result.leadList.length > 1){
                        this.leadDetails = {};
                        this.leadList = result.leadList;
                        this.leadList = result.leadList.map((item,index)=>{
                                return {
                                    ...item,
                                    preSalesName: item.Pre_Sales_Team_Member__r ? item.Pre_Sales_Team_Member__r.Name : '',
                                    channelPartner : item.Channel_Partner__r ? item.Channel_Partner__r.Name : '',
                                    index: index+1,
                                };
                            });
                        this.showLeadDetails = false;
                        this.showAllLeadDetails = true;
                        if(result.oppList.length == 0){
                            this.oppList = [];
                            this.showAllOppDetails = false;
                        }else if(result.oppList.length > 0){
                            this.oppXvisitMap = result.oppXvisitMap;
                            this.oppList = result.oppList;
                            this.showAllOppDetails = true;
                        }
                        this.errorMsg = false;
                        this.showCreateLead = false;
                        this.showVisitSection = false;
                        this.showCustReq = false;
                        this.visitDet = false;
                        this.showGRE = false;
                        this.showSalesManager = false;
                        this.relVisits = false;
                    }else if(result.leadList.length == 0 && result.oppList.length == 0){
                        this.leadDetails = {};
                        this.errorMsg = true;
                        this.showAllLeadDetails = false;
                        this.showAllOppDetails = false;
                        this.showLeadDetails = false;
                        this.showCreateLead = false;
                        this.showVisitSection = false;
                        this.showCustReq = false;
                        this.visitDet = false;
                        this.showGRE = false;
                        this.showSalesManager = false;
                        this.relVisits = false;
                    }else{
                        this.errorMsg = false;
                        this.showAllLeadDetails = false;
                        this.oppXvisitMap = result.oppXvisitMap;
                        this.oppList = result.oppList;
                        this.showAllOppDetails = true;
                        this.showLeadDetails = false;
                        this.showCreateLead = false;
                        this.showVisitSection = false;
                        this.showCustReq = false;
                        this.visitDet = false;
                        this.showGRE = false;
                        this.showSalesManager = false;
                        this.relVisits = false;
                    }
                }else{
                    this.leadDetails = {};
                    this.errorMsg = true;
                    this.showLeadDetails = false;
                    this.showCreateLead = false;
                    this.relVisits = false;
                }
                if(this.oppList.length  > 0){
                    this.oppList = this.oppList.map((item,index)=>{
                        return{
                            ...item,
                            index:index+1,
                            preSalesName : item.Pre_Sales_Team_Member__r? item.Pre_Sales_Team_Member__r.Name : '',
                            visitCount : this.oppXvisitMap[item.Id] ? this.oppXvisitMap[item.Id].length : 0,
                        }
                    })
                }
            }).catch(error=>{
                console.log('error'+error);
            })
                
        }else{
            this.showToast(
                'Error',
                'Please enter something to search!',
                'error'
            );
        }
    }
    showToast(title,message,variant){

        this.dispatchEvent(
            new ShowToastEvent({
                title:title,
                message:message,
                variant:variant
            })
        );

    }
    get showCreateVisit(){
        return this.showVisitAfterCreatn || this.showLeadDetails;
    }
    showRelVisits(event){
        const oppId  = event.target.dataset.id;
        this.visitList = this.oppXvisitMap[oppId];
        this.visitList = this.visitList.map((item,index)=>{
            return{
                ...item,
                index:index+1,
            }
        })
        this.oppName = this.oppList.find(item=>item.Id == oppId).Name;
        this.relVisits = true;
    }
    OnClickcreateVisit(event){
        let value;
        if(event){
            const id = event.target.dataset.id;

            value = this.oppList.find(item => item.Id === id) ||
                    this.leadList.find(item => item.Id === id);
        }
        if(this.leadDetails){
            this.leadDetails.By_Pass_Validations__c = true;
        }
        if(this.leadDetails && this.leadDetails.Id && (this.leadDetails.By_Pass_Validations__c === false || this.leadDetails.By_Pass_Validations__c === undefined)){
            this.showToast('Error','Please Check By Pass Validation..','error');
            return;
        }else{
            updateLeadDetails({
                leadId: this.leadDetails.Id,
                bypassValidation: this.leadDetails.By_Pass_Validations__c
            }).then(result=>{
            }).catch(error=>{
                console.log(error);
            });
        }

        if(!value){

            this.opp = {};
            this.oppId = '';
            this.showVisitSection = true;
            this.errorMsg = false;
            this.showLeadDetails = false;
            this.showCreateLead = false;
            this.showVisitAfterCreatn = false;

        }
        else if(value.Name){

            this.opp = value;
            this.oppId = value.Id;
            this.leadDetails = {};
            this.leadId = '';

        }
        else{

            this.leadDetails = value;
            this.leadId = value.Id;
            this.opp = {};
            this.oppId = '';
        }
        this.showVisitSection = true;
        this.showAllLeadDetails = false;
        this.showAllOppDetails = false;
        this.errorMsg = false;
        this.relVisits = false;
        this.showLeadDetails = false;
        this.showCreateLead = false;
        this.showVisitAfterCreatn = false;
    }
    createLead(event){
        this.errorMsg = false;
        this.showCreateLead = true;        
    }
    handleInputChange(event){

        const fieldApi = event.target.dataset.field;
        const objectName = event.target.dataset.object;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;


        if(objectName === 'Lead'){
            this.leadDetails[fieldApi] = value;
        }else{
            this.visit[fieldApi] = value;
        }
        this.leadFields = this.updateDependent(this.leadFields, fieldApi, value);
        this.visitFields = this.updateDependent(this.visitFields, fieldApi, value);

        // this.leadSections = this.groupFieldsBySection(this.leadFields);
        // this.visitSections = this.groupFieldsBySection(this.visitFields);
    }
    updateDependent(fields, fieldApi, value){
        return fields.map(field=>{
            if(field.dependentOptions && field.controllingField === fieldApi){
                return {
                    ...field,
                    options: field.dependentOptions[value] || []
                };
            }
            return field;
        });
    }
    groupFieldsBySection(fields){

        const map = {};

        fields.forEach(field => {

            const section = field.Section_Name__c || 'General';

            if(!map[section]){
                map[section] = [];
            }

            map[section].push(field);

        });

        return Object.keys(map).map(section => {
            return {
                sectionName: section,
                fields: map[section]
            };
        });

    }
    handleMultiSelect(event){

    const value = event.currentTarget.dataset.value;
    const fieldName = event.currentTarget.dataset.field;
    const objectName = event.currentTarget.dataset.object;

    const updateFields = (fields)=>{
        return fields.map(field=>{

            if(field.Field_API_Name__c === fieldName){

                field.options = field.options.map(opt=>{

                    if(opt.value === value){
                        opt.selected = !opt.selected;
                    }

                    opt.class = opt.selected
                        ? 'slds-listbox__option slds-media slds-is-selected'
                        : 'slds-listbox__option slds-media';

                    return opt;
                });

                const selected = field.options
                    .filter(o=>o.selected)
                    .map(o=>o.value);

                const labels = field.options
                    .filter(o=>o.selected)
                    .map(o=>o.label);

                if(objectName === 'Lead'){
                    this.leadDetails[fieldName] = selected.join(';');
                }else if(objectName === 'Visit__c'){
                    this.visit[fieldName] = selected.join(';');
                }

                if(labels.length === 0){
                    field.selectedLabel = 'Select values';
                }
                else if(labels.length <= 3){
                    field.selectedLabel = labels.join(', ');
                }
                else{
                    field.selectedLabel = labels[0] + ', ' + labels[1] + ', ' + labels[2] + ' +'+(labels.length - 3) + ' more';
                }
            }

            return field;
        });
    };

    this.leadFields = updateFields(this.leadFields);
    this.visitFields = updateFields(this.visitFields);

}
    toggleMultiPicklist(event){

        const fieldName = event.currentTarget.dataset.field;

        this.leadFields = this.leadFields.map(field=>{
            if(field.Field_API_Name__c === fieldName){
                field.isOpen = !field.isOpen;
            }
            return field;
        });

        this.visitFields = this.visitFields.map(field=>{
            if(field.Field_API_Name__c === fieldName){
                field.isOpen = !field.isOpen;
            }
            return field;
        });

    }
    get showLeadRVistScreen(){
        if(this.showCreateLead){
            this.currentFields =  this.leadFields;
        } 
        else{
             this.currentFields =  this.visitFields;
        }
        this.currentFields;
        return this.showCreateLead || this.showVisitSection;
    }
    createDymaicRecord(){
        debugger;
        if(!this.currentFields){
            this.showToast('Error','Please fill data','error');
            return;
        }

        const hasError = this.currentFields.some(item => {
            const fieldApi = item.Field_API_Name__c;
            const value = this.currentFields[0].Object_API_Name__c == 'Lead'
                ? this.leadDetails[fieldApi]
                : this.visit[fieldApi];

            return item?.Is_Required__c && (!value || value === '');
        });

        if(hasError){
            this.showToast('Error','Please fill all required fields','error');
            return;
        }

        /* ---------- CREATE LEAD ---------- */

        if(this.showCreateLead){

            createRecordDynamic({
                objectName:'Lead',
                fieldValues:this.leadDetails
            })
            .then(result=>{
                this.leadDetails.Id = result;
                this.visit.Lead__c = result;
                this.showCreateLead = false;
                this.showVisitSection = true;

                this.showToast('Success','Lead created successfully','success');
            })
            .catch(error=>{
                this.showToast('Error',error?.body?.message || error.message,'error');
            });

        }

        /* ---------- CREATE VISIT ---------- */

        else{

            insertVisitRecord({
                visitRecord:this.visit,
                leadId:this.leadId ? this.leadId : this.visit.Lead__c,
                oppId:this.oppId ? this.oppId : this.visit.Opportunity__c
            })
            .then(result=>{

                this.visit.Id = result;
                this.showVisitSection = false;
                this.showVisitAfterCreatn = true;

                this.showToast('Success','Visit created successfully','success');
            })
            .catch(error=>{
                this.showToast('Error',error?.body?.message || error.message,'error');
            });

        }

    }
    convertLeadToOppVisit(visit){
        debugger;
        if(!visit.Lead__c){
            this.showToast('Error','Please create lead first','error');
            return;
        }
        convertLeadAndTagOpportunity({
            leadId: this.visit.Lead__c,
            visitId: visit.Id
        })
        .then(oppId => {
            console.log('Opportunity created:', oppId);
        })
        .catch(error => {
            this.showToast('Error', error.body.message, 'error');
        });
    }
}