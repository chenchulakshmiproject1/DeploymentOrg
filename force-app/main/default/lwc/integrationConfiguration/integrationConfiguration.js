import { LightningElement, track } from 'lwc';
import getIntegrationConfigMetadata from '@salesforce/apex/IntegrationConfigurationController.getIntegrationConfigMetadata';
import saveIntegrationConfig from '@salesforce/apex/IntegrationConfigurationController.saveIntegrationConfig';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class IntegrationConfiguration extends LightningElement {
    @track sections = [];
    @track activeTab = 'GoogleDriveIntegration';
    @track isLoading = false;

    connectedCallback() {
        debugger;
        this.loadConfig();
    }

    loadConfig() {
        debugger;
        this.isLoading = true;

        getIntegrationConfigMetadata()
            .then(result => {
                this.sections = result || [];
                if (this.sections.length > 0 && !this.activeTab) {
                    this.activeTab = this.sections[0].settingType;
                }
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error while loading configuration.',
                    'error'
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleActiveTab(event) {
        this.activeTab = event.target.value;
    }

    handleInputChange(event) {
        debugger;
        const settingType = event.target.dataset.section;
        const fieldIndex = Number(event.target.dataset.index);
        const value = event.target.value;

        this.sections = this.sections.map(section => {
            if (section.settingType === settingType) {
                const updatedFields = section.fields.map((field, index) => {
                    if (index === fieldIndex) {
                        return {
                            ...field,
                            value: value
                        };
                    }
                    return field;
                });

                return {
                    ...section,
                    fields: updatedFields
                };
            }
            return section;
        });
    }

    handleSave() {
        debugger;
        this.isLoading = true;

        const payload = this.sections.map(section => {
            return {
                settingType: section.settingType,
                settingLabel: section.settingLabel,
                recordName: section.recordName,
                fields: section.fields.map(field => {
                    return {
                        fieldApiName: field.fieldApiName,
                        label: field.label,
                        type: field.type,
                        isSecret: field.isSecret,
                        value: field.value
                    };
                })
            };
        });
        console.log('Payload to save:', JSON.stringify(payload));
        saveIntegrationConfig({ sections: payload })
            .then(() => {
                this.showToast('Success', 'Configuration saved successfully.', 'success');
                this.loadConfig();
            })
            .catch(error => {
                this.showToast(
                    'Error',
                    error?.body?.message || 'Error while saving configuration.',
                    'error'
                );
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    get tabs() {
        return this.sections.map(section => {
            return {
                label: section.settingLabel,
                value: section.settingType
            };
        });
    }

    get activeSection() {
        return this.sections.find(section => section.settingType === this.activeTab);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}