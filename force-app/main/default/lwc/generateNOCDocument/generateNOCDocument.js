import { LightningElement, api, track } from 'lwc';
import generateNOCDocument from '@salesforce/apex/digioRepository.generateNOCDocument';
import sendigiodetails from '@salesforce/apex/digioRepository.sendigiodetails';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';

export default class GenerateNOCDocument extends LightningElement {
    @api recordId;
    @track showSpinner = true;
    @track subDocUrl;
    @track digioID;

    connectedCallback() {
        setTimeout(() => {
            this.generateDocument();
        }, 100);
    }

    generateDocument() {
        debugger;
        generateNOCDocument({ recordId: this.recordId, templateKeyName: 'NOC For Customer' })
            .then(result => {
                this.subDocUrl = result.subDocUrl;
                this.digioID = result.digiDocId;
                console.log('subDocUrl ===> ' + result);
                if (this.subDocUrl) {
                    this.showSpinner = false;
                }
            })
            .catch(error => {
                console.log(error);
            });
    }
    sendEmailtoCustomerwithAttachment() {
        debugger;
        if (this.digioID) {speechSynthesis
            this.showSpinner = true;

            // Call Apex method to download the document using digioID
            sendigiodetails({ digiDocId: this.digioID, oppId: this.recordId, docname: 'NOC For Customer' })
                .then(() => {
                    this.showSpinner = false;
                    console.log('Document downloaded successfully');
                    this.dispatchEvent(new CloseActionScreenEvent());
                    // You can add additional logic to send email or notify the user
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: 'Email sent successfully with attachment.',
                            variant: 'success'
                        })
                    );
                    // You can add additional logic to send email or notify the user
                })
                .catch(error => {
                    this.showSpinner = false;
                    console.error('Error downloading document: ', error);
                });
        } else {
            console.error('No digioID available to download document');
        }
    }
}