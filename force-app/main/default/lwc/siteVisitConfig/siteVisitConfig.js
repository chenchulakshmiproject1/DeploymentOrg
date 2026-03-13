import { LightningElement, wire, track } from 'lwc';
import getFields from '@salesforce/apex/SiteVisitConfigController.getFields';
import updateVisibility from '@salesforce/apex/SiteVisitConfigController.updateVisibility';

export default class SiteVisitConfig extends LightningElement {

    @track fields;
    @track sectionsOfVisit =[];
    @track sectionsOfLead =[];
    @track showVisitFields = false;
    @track showLeadFiedls = false;

    @wire(getFields)
    wiredFields({data,error}){

        if(data){
            const map={};
            const map2 = {};
            data?.visitFields?.forEach(field=>{
                const section = field.Section_Name__c || 'Other';
                if(!map[section]){
                    map[section] = [];
                }
                map[section].push(field);
            });

            this.sectionsOfVisit = Object.keys(map).map(sectionName => {
                return {
                    name: sectionName,
                    fields: map[sectionName]
                };
            });
            data?.leadFields?.forEach(field=>{
                const section = field.Section_Name__c || 'Other';
                if(!map2[section]){
                    map2[section] = [];
                }
                map2[section].push(field);
            });

            this.sectionsOfLead = Object.keys(map2).map(sectionName => {
                return {
                    name: sectionName,
                    fields: map2[sectionName]
                };
            });
        }
    }

    handleToggle(event){
        debugger;
        const recordId = event.target.dataset.id;
        const isVisible = event.target.checked;

        updateVisibility({
            recordId : recordId,
            isVisible : isVisible
        });
       const data = this.showVisitFields ? this.sectionsOfVisit : this.sectionsOfLead;

        const cur = data.map(section => ({
            ...section,
            fields: section.fields.map(field =>
                field.Id === recordId
                    ? { ...field, Is_Visible__c: isVisible }
                    : field
            )
        }));

        if (this.showVisitFields) {
            this.sectionsOfVisit = cur;
        } else {
            this.sectionsOfLead = cur;
        }
    }
    handleActivetab(event){
        debugger;
        const tabValue = event.target.value;
        if(tabValue === 'Lead'){
            this.showLeadFiedls = true;
            this.showVisitFields = false;
        }else if(tabValue === 'Visit'){
            this.showLeadFiedls = false;
            this.showVisitFields = true;
        }
    }
    get sections(){
        return this.showVisitFields ? this.sectionsOfVisit : this.sectionsOfLead;
    }
}