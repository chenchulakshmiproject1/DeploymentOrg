import { LightningElement } from 'lwc';

export default class ProjectDashboard extends LightningElement {

modules = [

{ key:'inventoryUpload', name:'Inventory Upload', icon:'utility:upload', status:'Configured', statusClass:'status configured', description:'Upload and manage property inventory including units, towers, and floor plans.' },

{ key:'taxMaster', name:'Tax Master', icon:'utility:money', status:'Configured', statusClass:'status configured', description:'Configure GST, stamp duty, registration charges, and other applicable taxes.' },

{ key:'paymentSchedule', name:'Payment Schedule', icon:'utility:date_input', status:'In Progress', statusClass:'status inprogress', description:'Define milestone-based payment schedules for different project phases.' },

{ key:'pricingElements', name:'Pricing Elements', icon:'utility:currency', status:'In Progress', statusClass:'status inprogress', description:'Set up base price, floor rise, PLC, and other pricing components.' },

{ key:'costSheetTemplate', name:'Cost Sheet Template', icon:'utility:description', status:'Not Started', statusClass:'status pending', description:'Design cost sheet templates with all applicable charges and breakdowns.' },

{ key:'paymentSchemes', name:'Payment Schemes', icon:'utility:table', status:'Not Started', statusClass:'status pending', description:'Create flexible payment schemes like CLP, TLP, and down payment plans.' },

{ key:'costSchemeLinking', name:'Cost Scheme Linking', icon:'utility:link', status:'Not Started', statusClass:'status pending', description:'Link cost sheet templates with payment schemes for each unit type.' },

{ key:'opportunityStages', name:'Opportunity Stages', icon:'utility:share', status:'In Progress', statusClass:'status inprogress', description:'Customize pipeline stages and configure automation triggers per stage.' },

{ key:'userManagement', name:'User Management', icon:'utility:people', status:'Not Started', statusClass:'status pending', description:'Create users with roles — Pre Sales, Sales, Finance, Sales Head and more.' },

{ key:'siteVisitConfig', name:'Site Visit Config', icon:'utility:event', status:'Configured', statusClass:'status configured', description:'Configure site visit form fields, mandatory checks, and feedback templates.' }

];

handleCardClick(event){

const key = event.currentTarget.dataset.key;

this.dispatchEvent(
    new CustomEvent('navigate', {
        detail:{ key }
    })
);

}

}