import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from "lightning/platformResourceLoader";

import getOnLoadData from '@salesforce/apex/CostSheetGenerationController.getOnLoadData';
import getUnitRecord from '@salesforce/apex/CostSheetGenerationController.getUnitRecord';
import getDiscountConfig from '@salesforce/apex/CostSheetGenerationController.getDiscountConfig';
import getTemplateData from '@salesforce/apex/CostSheetGenerationController.getTemplateData';
import getParkingRecords from '@salesforce/apex/CostSheetGenerationController.getParkingRecords';
import saveAllCostSheetData from '@salesforce/apex/CostSheetGenerationController.saveAllCostSheetData';

import modal from "@salesforce/resourceUrl/QuickActionCSS";


export default class CostSheetGeneration extends NavigationMixin(LightningElement) {

    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
    }


    @track firstScreen = true;
    @track secondScreen = false;
    @track thirdScreen = false;
    @track fourthScreen = false;
    @track isLoading = false;
    @track isDataLoaded = false;
    @track showErrorBlock = false;
    @track errorMessage = '';
    @track registrationPercentage = '';
    @track baseCostTotal = 0;
    @track otherChargesTotal = 0;
    @track hasRegistrationPE = false;


    @track projectId = '';
    @track selectedUnitId = '';
    @track selectedCostSchemeId = '';
    @track searchKey = '';
    @track isDropdownOpen = false;
    @track filteredTemplateOptions = [];
    @track isUnitDisabled = false;
    @track isNextDisabled = false;
    @track isFinalSaveDisabled = false;

    @track pricingElements = [];
    @track discountLineItem = [];
    @track selectedUnitRec = null;
    @track templateData = null;
    @track projectData = null;
    @track wiredOnLoadData;
    
    @track discountByPricingMap = [];
    @track discountAdded = false;

    @track totalAmount = 0;
    @track realAmount = 0;
    @track taxAmount = 0;
    @track formattedTotalAmount = '0';


    @track flatCostTotal = 0;
    @track amenitiesTotal = 0;
    @track infraTotal = 0;
    @track saleValue = 0;


    @track parkingDetails = {};
    @track parkingDetailTable = false;
    @track noParkingDetails = false;
    @track availableSingleParking = 0;
    @track availableDualParking = 0;
    @track templateParkingCount = 0;
    @track updatedDefaultParkingCount = 1;


    @track parkingTypeOptions = [];


    @track parkingRows = [];


    @track parkingCGSTtax = 0;
    @track parkingSGSTtax = 0;


    @track calculatedSingleCount = 0;
    @track calculatedDualCount = 0;
    @track totalParkingSpaces = 0;
    @track defaultParkingCount = 1;


    @track defaultSingleCount = 0;
    @track defaultDualCount = 0;

    @track hasParkingValidationError = false;

    @track singleParkingDetail = null;
    @track dualParkingDetail = null;


    get defaultParkingDisplay() {
        return this.defaultParkingCount || 1;
    }


    @track pendingData = {
        costSheet: {
            opportunityId: '',
            unitId: '',
            costSchemeLinkingId: '',
            costSheetTemplateId: ''
        },
        pricingElements: [],
        parkingElements: [],
        discountData: [],
        hasDiscount: false
    };

    @track initialTotalAmount = 0;
    @track revisedTotalAmount = 0;
    @track totalTaxAmount = 0;
    @track initialTotalFormatted = '0';
    @track revisedTotalFormatted = '0';
    @track totalTaxFormatted = '0';
    @track differencePerSqft = '0';
    @track hasDiscountApplied = false;
    @track hasValidationErrors = false;
    @track unitSBA = 0;


    unitList = [];
    unitOptions = [];
    templateList = [];
    templateOptions = [];
    opp = null;
    carParkingTax = {};
    newCostSheetId = '';

    get defaultUnit() {
        if (this.selectedUnitId != null && this.isUnitDisabled === true) {
            return true;
        }
        return false;
    }

    get pricingElementsCount() {
        return this.pricingElements ? this.pricingElements.length : 0;
    }

    get hasPricingElements() {
        return this.pricingElements && this.pricingElements.length > 0;
    }


    connectedCallback() {
        loadStyle(this, modal);
    }

    @wire(getOnLoadData, { recordId: '$_recordId' })
    wiredData(result) {
        console.log(' wiredData method called');
        this.wiredOnLoadData = result;
        const { error, data } = result;

        if (data) {
            console.log('Data received:', JSON.stringify(data));

            if (data.validationError === true && data.errorMessage) {
                this.showToast('Error', data.errorMessage, 'error');
                this.closeComponent();
                return;
            }

            this.isDataLoaded = true;
            this.showErrorBlock = (data.errorMessage != null && data.errorMessage !== '');
            this.errorMessage = data.errorMessage || '';

            this.opp = data.opp || null;
            this.projectId = (this.opp && this.opp.Project__c) ? this.opp.Project__c : '';

            this.projectData = data.projectData || null;

            if (this.opp) {
                this.pendingData.costSheet.opportunityId = this.opp.Id;
            }

            this.carParkingTax = data.carParkingTax || null;

            this.unitList = data.unitList || [];
            if (this.unitList.length > 0) {
                this.unitOptions = this.unitList.map(unit => ({
                    label: unit.Name,
                    value: unit.Id
                }));
            }

            this.templateList = data.costSheetTemplateList || [];

            if (this.opp && this.opp.Unit__c) {
                this.selectedUnitId = this.opp.Unit__c;
                this.pendingData.costSheet.unitId = this.opp.Unit__c;
                this.isUnitDisabled = true;
                this.fetchUnitRecord();
            }

        } else if (error) {
            console.error('Error:', JSON.stringify(error));
            this.showToast('Error', 'Failed to load data. Please try again.', 'error');
            this.closeComponent();
        }
    }

    handleChangeUnit(event) {
        debugger;
        this.selectedUnitId = event.detail.id;
        console.log('selectedUnitId ===> ' + this.selectedUnitId);


        this.selectedCostSchemeId = '';
        this.searchKey = '';
        this.filteredTemplateOptions = [];
        this.isDropdownOpen = false;

        if (this.selectedUnitId) {
            this.fetchUnitRecord();
        } else {
            this.selectedUnitRec = null;
        }
    }

    fetchUnitRecord() {
        getUnitRecord({ unitId: this.selectedUnitId })
            .then(result => {
                console.log('Unit Record:', JSON.stringify(result));
                this.selectedUnitRec = result;
                this.filterTemplates();
            })
            .catch(error => {
                console.error('Error fetching unit record:', error);
            });
    }

    handleSearchChange(event) {
        this.searchKey = event.target.value;
        this.filterTemplates();
    }

    toggleDropdown() {
        this.isDropdownOpen = !this.isDropdownOpen;
    }

    handleOptionClick(event) {
        const selectedValue = event.currentTarget.dataset.value;
        this.selectedCostSchemeId = selectedValue;
        const selectedOption = this.filteredTemplateOptions.find(option => option.value === selectedValue);
        this.searchKey = selectedOption?.label || '';
        this.isDropdownOpen = false;
    }

    filterTemplates() {
        console.log('=== filterTemplates START ===');
        console.log('templateList:', JSON.stringify(this.templateList));
        console.log('selectedUnitId:', this.selectedUnitId);
        console.log('selectedUnitRec:', JSON.stringify(this.selectedUnitRec));


        this.filteredTemplateOptions = [];


        if (!this.templateList || this.templateList.length === 0) {
            console.log('EXIT: No templates available');
            return;
        }


        if (!this.selectedUnitId) {
            console.log('EXIT: No unit selected yet');
            return;
        }

        // Get unit's tower ID
        let unitTowerId = null;
        if (this.selectedUnitRec && this.selectedUnitRec.Floor__r && this.selectedUnitRec.Floor__r.Blocks__c) {
            unitTowerId = this.selectedUnitRec.Floor__r.Blocks__c;
        }
        console.log('Unit Tower ID:', unitTowerId);

        // Filter templates
        for (let i = 0; i < this.templateList.length; i++) {
            const template = this.templateList[i];
            console.log('Processing Template:', template.Name);

            const blockLinkings = template.Cost_Scheme_Linkings__r || [];
            const unitLinkings = template.Cost_Unit_Linking__r || [];

            console.log('Block Linkings count:', blockLinkings.length);
            console.log('Unit Linkings count:', unitLinkings.length);

            for (let j = 0; j < blockLinkings.length; j++) {
                const blockLink = blockLinkings[j];
                console.log('Block Link:', JSON.stringify(blockLink));

                for (let k = 0; k < unitLinkings.length; k++) {
                    const unitLink = unitLinkings[k];
                    console.log('Unit Link:', JSON.stringify(unitLink));

                    const unitMatch = (unitLink.Unit__c === this.selectedUnitId);
                    console.log('Unit Match:', unitMatch);

                    let blockMatch = true;
                    if (unitTowerId && blockLink.Payment_Scheme__r && blockLink.Payment_Scheme__r.Block__c) {
                        blockMatch = (blockLink.Payment_Scheme__r.Block__c === unitTowerId);
                        console.log('Block Match:', blockMatch);
                    }


                    if (unitMatch && blockMatch) {
                        const paymentSchemeName = (blockLink.Payment_Scheme__r && blockLink.Payment_Scheme__r.Name)
                            ? blockLink.Payment_Scheme__r.Name
                            : 'Unknown';
                        const label = `${template.Name} - ${paymentSchemeName}`;


                        if (label.toLowerCase().includes(this.searchKey.toLowerCase())) {

                            const alreadyExists = this.filteredTemplateOptions.some(opt => opt.value === blockLink.Id);
                            if (!alreadyExists) {
                                console.log('ADDING option:', label);
                                this.filteredTemplateOptions.push({
                                    label: label,
                                    value: blockLink.Id
                                });
                            }
                        }
                    }
                }
            }
        }

        console.log('=== filterTemplates END ===');
        console.log('Final filteredTemplateOptions:', JSON.stringify(this.filteredTemplateOptions));
    }

    handleNext() {

        if (!this.selectedUnitId || this.selectedUnitId === '') {
            this.showToast('Error', 'Please select a Unit before proceeding.', 'error');
            return;
        }

        if (!this.selectedCostSchemeId || this.selectedCostSchemeId === '') {
            this.showToast('Error', 'Please select a Cost Sheet Template before proceeding.', 'error');
            return;
        }

        this.isNextDisabled = true;
        this.isLoading = true;

        this.pendingData.costSheet.unitId = this.selectedUnitId;
        this.pendingData.costSheet.costSchemeLinkingId = this.selectedCostSchemeId;
        this.pendingData.costSheet.opportunityId = this.opp.Id;

        const oppId = this.opp.Id;

        getDiscountConfig({ opp: oppId })
            .then(result => {
                if (result) {
                    this.discountLineItem = result;
                    console.log('Discount Line Items:', JSON.stringify(this.discountLineItem));
                }

                return getTemplateData({
                    unitId: this.selectedUnitId,
                    cslId: this.selectedCostSchemeId
                });
            })
            .then(result => {
                console.log('Template Data:', JSON.stringify(result));

                if (!result.isSuccess) {
                    this.showToast('Error', result.errorMessage || 'Failed to fetch template data.', 'error');
                    this.isNextDisabled = false;
                    this.isLoading = false;
                    return;
                }

                // Store template data
                this.templateData = result;
                this.projectData = result.projectData;
                this.registrationPercentage = result.registrationPercentage;

                this.pendingData.costSheet.costSheetTemplateId = result.costSchemeLinking.Cost_Sheet_Template__c;

                this.buildPricingElements(result);


                if (result.unitData && result.unitData.Default_Parking__c !== undefined && result.unitData.Default_Parking__c !== null) {
                    this.defaultParkingCount = result.unitData.Default_Parking__c;
                } else {
                    this.defaultParkingCount = 1;
                }

                this.firstScreen = false;
                this.secondScreen = true;

                this.isNextDisabled = false;
                this.isLoading = false;

                this.showToast('Success', 'Pricing elements loaded successfully.', 'success');
            })
            .catch(error => {
                console.error('Error in handleNext:', JSON.stringify(error));
                this.showToast('Error', 'Something went wrong! ' + (error.body?.message || error.message || ''), 'error');
                this.isNextDisabled = false;
                this.isLoading = false;
            });
    }

    buildPricingElements(templateData) {
        console.log('=== buildPricingElements START ===');

        const unit = templateData.unitData;
        const project = templateData.projectData || {};
        const specificationType = project.Project_Type__c;

        console.log('Unit Specification Type:', specificationType);

        if (specificationType === 'Villa') {
            this.buildVillaPricingElements(templateData);
        } else if (specificationType === 'Plot') {
            this.buildOpenPlotPricingElements(templateData);
        } else {
            this.buildApartmentPricingElements(templateData);
        }

        console.log('=== buildPricingElements END ===');
    }

    buildApartmentPricingElements(templateData) {
        console.log('=== buildApartmentPricingElements START ===');

        const unit = templateData.unitData;
        const cpas = templateData.pricingAssociations || [];
        const taxLinkings = templateData.taxLinkings || [];
        const project = templateData.projectData || {};

        this.unitSBA = unit.Super_Built_Up_Area_sq_ft__c || 0;
        const sba = this.unitSBA;
        console.log('Unit SBA:', sba);

        const taxMap = this.buildTaxMap(taxLinkings);

        this.hasRegistrationPE = cpas.some(cpa => {
            const peName = (cpa.Pricing_Element_Master__r?.Name || '').toLowerCase();
            return peName.includes('registration') && !peName.includes('stamp') && !peName.includes('mutation');
        });

        console.log('Has Registration PE:', this.hasRegistrationPE);

        const builtElements = [];
        let serialNumber = 1;

        this.flatCostTotal = 0;
        this.amenitiesTotal = 0;
        this.infraTotal = 0;

        this.baseCostTotal = 0;
        this.otherChargesTotal = 0;

        cpas.forEach((cpa, index) => {
            const peName = cpa.Pricing_Element_Master__r?.Name || '';
            const peNameLower = peName.toLowerCase();
            const peType = cpa.PE_Type__c || '';
            const unitType = cpa.Unit__c || 'sqft';
            const cpaType = cpa.Type__c || 'Agreement';

            let quantity = 0;
            let rate = 0;
            let amount = 0;
            let isFormulaElement = false;
            let group = 'Other';
            let costCategory = 'Other';

            if (peNameLower.includes('basic sale price') || peNameLower.includes('salable') || peNameLower.includes('saleable')) {
                quantity = sba;
                rate = unit.Base_Price_per_sqft__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                costCategory = 'BaseCost';
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('corner')) {
                quantity = sba;
                rate = unit.Corner_Rs_Sft__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('facing') || peNameLower.includes('east') || peNameLower.includes('north')) {
                quantity = sba;
                rate = unit.Facing_Rs_Sft__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                costCategory = 'OtherCharges';
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('floor rise')) {
                quantity = sba;
                rate = unit.Floor_Rise__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('premium')) {
                quantity = sba;
                rate = unit.Premium_Charges__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('infrastructure') || peNameLower.includes('infra')) {
                quantity = sba;
                rate = unit.Infrastructure_Charges__c || 0;
                amount = rate * quantity;
                group = 'Infrastructure';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('amenities') || peNameLower.includes('ammenities')) {
                const isLumpsum = (unitType === 'LS');

                if (isLumpsum) {
                    quantity = cpa.Quantity__c || 0;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                } else {
                    quantity = sba;
                    rate = unit.Amenities_Charges__c || cpa.Rate__c || 0;
                    amount = rate * quantity;
                }

                group = 'Amenities';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName} (${isLumpsum ? 'LS' : 'sqft'}): Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else if (peNameLower.includes('legal') || peNameLower.includes('documentation')) {
                quantity = cpa.Quantity__c || 1;
                rate = cpa.Rate__c || 0;
                amount = rate * quantity;
                group = '';
                costCategory = 'OtherCharges'; // B
                console.log(`${peName}: Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('registration') &&
                !peNameLower.includes('stamp') &&
                !peNameLower.includes('mutation')) {
                isFormulaElement = true;
                group = 'Registration';
                costCategory = 'Registration';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('stamp duty') || peNameLower.includes('mutation')) {
                isFormulaElement = true;
                group = 'Registration';
                costCategory = 'Registration';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('maintenance') || peNameLower.includes('maintainance')) {
                isFormulaElement = true;
                group = 'Maintenance';
                costCategory = 'Maintenance';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('modt')) {
                isFormulaElement = true;
                group = 'Registration';
                costCategory = 'Registration';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('corpus')) {
                quantity = sba;
                rate = unit.Corpus_Fund_Rs_sft__c || 0;
                amount = rate * quantity;
                group = 'Maintenance';
                costCategory = 'Maintenance';
                console.log(`${peName}: Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            else {
                if (unitType === 'sqft' || unitType === 'sqm') {
                    quantity = sba;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                } else {
                    quantity = cpa.Quantity__c || 1;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                }
                costCategory = 'OtherCharges';
                console.log(`${peName} (Default): Rate=${rate}, Qty=${quantity}, Amount=${amount}`);
            }

            if (!isFormulaElement) {
                if (group === 'Flat Cost') {
                    this.flatCostTotal += amount;
                } else if (group === 'Amenities') {
                    this.amenitiesTotal += amount;
                } else if (group === 'Infrastructure') {
                    this.infraTotal += amount;
                }

                if (costCategory === 'BaseCost') {
                    this.baseCostTotal += amount;
                } else if (costCategory === 'OtherCharges') {
                    this.otherChargesTotal += amount;
                }
            }

            const taxes = taxMap[cpa.Id] || { cgst: 0, sgst: 0, igst: 0 };
            const totalTaxPercent = taxes.cgst + taxes.sgst + taxes.igst;
            const taxAmount = amount > 0 ? (amount * totalTaxPercent) / 100 : 0;

            const isLsType = peType === 'LS' || unitType === 'LS';

            const element = {
                tempId: 'pe_' + Date.now() + '_' + index,
                Pricing_Element_Master__c: cpa.Pricing_Element_Master__c,
                Pricing_Element_Master__r: {
                    Name: peName,
                    Id: cpa.Pricing_Element_Master__c
                },
                Cost_Pricing_Association__c: cpa.Id,
                PE_Type__c: peType,
                Type__c: cpaType,
                Unit__c: unitType,
                Sequence__c: cpa.Sequence__c || index,
                Quantity__c: quantity,
                Rate__c: rate,
                Amount__c: amount,
                Discount_Amount__c: 0,
                ActualAmount: amount,

                CGST_Tax_Percentage__c: taxes.cgst,
                SGST_Tax_Percentage__c: taxes.sgst,
                IGST_Tax_Percentage__c: taxes.igst,
                totalTaxPercent: totalTaxPercent,
                Tax_Amount__c: taxAmount,

                Discount_Psft__c: 0,
                Discount_LS__c: 0,
                discountPsftError: '',
                discountLsError: '',
                isDiscountPsftEditable: !isLsType,
                isDiscountLsEditable: isLsType,

                FinalAmount: amount,
                formattedFinalAmount: this.formatCurrency(amount),
                STM_Given_Discount__c: null,

                Description__c: cpa.Description__c || '',
                parking_Element__c: false,
                serialNumber: serialNumber++,
                isFormulaElement: isFormulaElement,
                group: group,
                showDescription: false,

                formattedRate: this.formatCurrency(rate),
                formattedAmount: this.formatCurrency(amount),
                formattedTaxAmount: this.formatCurrency(taxAmount),
                peTypeBadgeClass: isLsType ? 'pe-type-badge pe-type-badge-ls' : 'pe-type-badge pe-type-badge-psft'
            };

            builtElements.push(element);
        });

        console.log('Flat Cost Total:', this.flatCostTotal);
        console.log('Amenities Total:', this.amenitiesTotal);
        console.log('Infrastructure Total:', this.infraTotal);

        if (this.hasRegistrationPE) {
            console.log('REGISTRATION PE DETECTED - Using A+B Calculation:');
            console.log('  TOTAL BASE COST (A):', this.baseCostTotal);
            console.log('  TOTAL OTHER CHARGES (B):', this.otherChargesTotal);
            this.saleValue = this.baseCostTotal + this.otherChargesTotal;
            console.log('TOTAL FLAT COST (A+B):', this.saleValue);
        } else {
            this.saleValue = this.flatCostTotal + this.amenitiesTotal + this.infraTotal;
            console.log('Sale Value (Standard):', this.saleValue);
        }

        builtElements.forEach(element => {
            if (element.isFormulaElement) {
                const peName = element.Pricing_Element_Master__r.Name;
                const peNameLower = peName.toLowerCase();

                let amount = 0;
                let rate = 0;
                let quantity = 1;

                if (peNameLower.includes('registration') && !peNameLower.includes('stamp') && !peNameLower.includes('mutation')) {

                    const percentage = this.registrationPercentage;
                    amount = (this.saleValue * percentage) / 100;
                    rate = percentage;
                    quantity = 1;
                    console.log(`Registration Charges: ${this.saleValue} × ${percentage}% = ${amount}`);
                }

                else if (peNameLower.includes('stamp duty') || peNameLower.includes('mutation')) {
                    const percentage = project.Stamp_Duty_Percentage__c || 7.6;
                    const fixedRs = project.Stamp_Duty_and_Mutation_Charges_Rs__c || 1050;
                    amount = (this.saleValue * percentage / 100) + fixedRs;
                    rate = amount;
                    console.log(`Stamp Duty: ${this.saleValue} × ${percentage}% + ${fixedRs} = ${amount}`);
                }

                else if (peNameLower.includes('modt')) {
                    amount = this.saleValue * 0.80 * 0.005;
                    rate = amount;
                    console.log(`MODT: ${this.saleValue} × 80% × 0.5% = ${amount}`);
                }


                else if (peNameLower.includes('maintenance') || peNameLower.includes('maintainance')) {
                    const rs = project.Maintanance_Charges_Rs__c || 3;
                    const months = project.Maintainence_Charges_Months__c || 24;
                    quantity = sba;
                    rate = rs * months;
                    amount = sba * rs * months;
                    console.log(`Maintenance: ${sba} × ${rs} × ${months} = ${amount}`);
                }

                element.Quantity__c = quantity;
                element.Rate__c = rate;
                element.Amount__c = amount;
                element.FinalAmount = amount;
                element.ActualAmount = amount;
                element.formattedRate = this.formatCurrency(rate);
                element.formattedAmount = this.formatCurrency(amount);
                element.formattedFinalAmount = this.formatCurrency(amount);

                const taxAmount = amount > 0 ? (amount * element.totalTaxPercent) / 100 : 0;
                element.Tax_Amount__c = taxAmount;
                element.formattedTaxAmount = this.formatCurrency(taxAmount);
            }
        });

        this.pricingElements = builtElements;
        this.pendingData.pricingElements = builtElements;

        this.recalculateAllTotals();
        // this.calculateParkingFromPricingElements();

        console.log('=== buildApartmentPricingElements END ===');
        console.log('Built Elements:', this.pricingElements.length);
    }
    // ============================================
    // VILLA CALCULATION LOGIC
    // ============================================
    buildVillaPricingElements(templateData) {
        console.log('=== buildVillaPricingElements START ===');

        const unit = templateData.unitData;
        const cpas = templateData.pricingAssociations || [];
        const taxLinkings = templateData.taxLinkings || [];
        const project = templateData.projectData || {};


        this.unitSBA = unit.Super_Built_Up_Area_sq_ft__c || 0;
        const sba = this.unitSBA;
        console.log('Unit SBA:', sba);


        const taxMap = this.buildTaxMap(taxLinkings);
        console.log('Tax Map:', JSON.stringify(taxMap));

        const builtElements = [];
        let serialNumber = 1;


        this.flatCostTotal = 0;
        this.amenitiesTotal = 0;
        this.infraTotal = 0;

        cpas.forEach((cpa, index) => {
            const peName = cpa.Pricing_Element_Master__r?.Name || '';
            const peNameLower = peName.toLowerCase();
            const peType = cpa.PE_Type__c || '';
            const unitType = cpa.Unit__c || 'sqft';
            const cpaType = cpa.Type__c || 'Agreement';

            let quantity = 0;
            let rate = 0;
            let amount = 0;
            let isFormulaElement = false;
            let group = 'Other';

            if (peNameLower.includes('basic sale price') ||
                peNameLower.includes('salable') ||
                peNameLower.includes('saleable')) {
                quantity = sba;
                rate = unit.Base_Price_per_sqft__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                console.log(`${peName}: SBA=${sba}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('corner')) {
                amount = unit.Corner_Premium__c || 0;
                quantity = 1;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName}: Amount=${amount}`);
            }

            else if (peNameLower.includes('north east') ||
                peNameLower.includes('northeast')) {
                amount = unit.North_East__c || 0;
                quantity = amount > 0 ? 1 : 0;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName}: Unit.North_East__c=${unit.North_East__c}, Amount=${amount}`);
            }

            else if (peNameLower.includes('park facing') ||
                peNameLower.includes('park-facing') ||
                peNameLower.includes('parkfacing')) {
                amount = unit.Park_Facing__c || 0;
                quantity = amount > 0 ? 1 : 0;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName}: Unit.Park_Facing__c=${unit.Park_Facing__c}, Amount=${amount}`);
            }

            else if (peNameLower.includes('east facing') ||
                peNameLower.includes('east-facing')) {
                amount = unit.Facing_Charges_Rs_LS__c || 0;
                quantity = amount > 0 ? 1 : 0;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName}: Unit.Facing_Charges_Rs_LS__c=${unit.Facing_Charges_Rs_LS__c}, Amount=${amount}`);
            }

            else if (peNameLower.includes('east/north') ||
                peNameLower.includes('east north')) {
                amount = unit.East_North__c || 0;
                quantity = 1;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName}: Amount=${amount}`);
            }

            else if (peNameLower.includes('facing')) {
                amount = unit.Facing_Charges_Rs_LS__c || 0;
                quantity = 1;
                rate = amount;
                group = 'Flat Cost';
                console.log(`${peName} (Generic Facing): Amount=${amount}`);
            }

            else if (peNameLower.includes('extra land')) {
                quantity = unit.Extra_Land__c || 0;
                rate = unit.Extra_Land_Yard__c || 0;
                amount = rate * quantity;
                group = 'Flat Cost';
                console.log(`${peName}: Yards=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('amenities') || peNameLower.includes('amenity')) {
                const isLumpsum = (unitType === 'LS');

                if (isLumpsum) {
                    quantity = cpa.Quantity__c || 1;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                    console.log(`${peName} (LS): Amount=${amount}`);
                } else {
                    quantity = sba;
                    rate = unit.Cost_of_Amenities__c || 0;
                    amount = rate * quantity;
                    console.log(`${peName} (sqft): SBA=${sba}, Rate=${rate}, Amount=${amount}`);
                }
                group = 'Amenities';
            }

            else if (peNameLower.includes('elevator')) {
                quantity = sba;
                rate = unit.Elevator_Charges_Rs_Sft__c || 0;
                amount = rate * quantity;
                group = 'Other';
                console.log(`${peName}: SBA=${sba}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('corpus')) {
                quantity = cpa.Quantity__c || 1;
                rate = cpa.Rate__c || 0;
                amount = rate * quantity;
                group = 'Maintenance';
                console.log(`${peName}: Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('caution')) {
                quantity = cpa.Quantity__c || 1;
                rate = cpa.Rate__c || 0;
                amount = rate * quantity;
                group = 'Maintenance';
                console.log(`${peName}: Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('legal') || peNameLower.includes('documentation')) {
                quantity = cpa.Quantity__c || 1;
                rate = cpa.Rate__c || 0;
                amount = rate * quantity;
                group = 'Registration';
                console.log(`${peName}: Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('municipal') || peNameLower.includes('water connection')) {
                // quantity = unit.Quantity__c || 1;
                // rate     = cpa.Rate__c || 0;
                amount = unit.Municipal_Charges_Rs_LS__c;
                group = 'Additional';
                console.log(`${peName}: Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            else if (peNameLower.includes('stamp duty') || peNameLower.includes('mutation')) {
                isFormulaElement = true;
                group = 'Registration';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('modt')) {
                isFormulaElement = true;
                group = 'Registration';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else if (peNameLower.includes('maintenance') || peNameLower.includes('maintainance')) {
                isFormulaElement = true;
                group = 'Maintenance';
                console.log(`${peName}: Formula element - will calculate in Phase 2`);
            }

            else {
                console.warn(`⚠️ Unmatched PE: "${peName}"`);
                if (unitType === 'sqft' || unitType === 'sqm') {
                    quantity = sba;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                } else {
                    quantity = cpa.Quantity__c || 1;
                    rate = cpa.Rate__c || 0;
                    amount = rate * quantity;
                }
                console.log(`${peName} (Default): Qty=${quantity}, Rate=${rate}, Amount=${amount}`);
            }

            rate = rate;
            amount = amount;


            if (!isFormulaElement && amount > 0) {
                if (group === 'Flat Cost') {
                    this.flatCostTotal += amount;
                } else if (group === 'Amenities') {
                    this.amenitiesTotal += amount;
                } else if (group === 'Infrastructure') {
                    this.infraTotal += amount;
                }
            }


            const taxes = taxMap[cpa.Id] || { cgst: 0, sgst: 0, igst: 0 };
            const totalTaxPercent = taxes.cgst + taxes.sgst + taxes.igst;
            const taxAmount = amount > 0 ? (amount * totalTaxPercent) / 100 : 0;


            const isLsType = peType === 'LS' || unitType === 'LS';


            const element = {
                tempId: 'pe_' + Date.now() + '_' + index,
                Pricing_Element_Master__c: cpa.Pricing_Element_Master__c,
                Pricing_Element_Master__r: {
                    Name: peName,
                    Id: cpa.Pricing_Element_Master__c
                },
                Cost_Pricing_Association__c: cpa.Id,
                PE_Type__c: peType,
                Type__c: cpaType,
                Unit__c: unitType,
                Sequence__c: cpa.Sequence__c || index,
                Quantity__c: quantity,
                Rate__c: rate,
                Amount__c: amount,
                Discount_Amount__c: 0,
                ActualAmount: amount,

                CGST_Tax_Percentage__c: taxes.cgst,
                SGST_Tax_Percentage__c: taxes.sgst,
                IGST_Tax_Percentage__c: taxes.igst,
                totalTaxPercent: totalTaxPercent,
                Tax_Amount__c: taxAmount,

                Discount_Psft__c: 0,
                Discount_LS__c: 0,
                discountPsftError: '',
                discountLsError: '',
                isDiscountPsftEditable: !isLsType,
                isDiscountLsEditable: isLsType,

                FinalAmount: amount,
                formattedFinalAmount: this.formatCurrency(amount),
                STM_Given_Discount__c: null,


                Description__c: cpa.Description__c || '',
                parking_Element__c: false,
                serialNumber: serialNumber++,
                isFormulaElement: isFormulaElement,
                group: group,
                showDescription: false,

                // Formatted values
                formattedRate: this.formatCurrency(rate),
                formattedAmount: this.formatCurrency(amount),
                formattedTaxAmount: this.formatCurrency(taxAmount),
                peTypeBadgeClass: isLsType ? 'pe-type-badge pe-type-badge-ls' : 'pe-type-badge pe-type-badge-psft'
            };

            builtElements.push(element);
        });

        console.log('=== PHASE 2: Formula Calculations (Villa) ===');
        console.log('Flat Cost Total:', this.flatCostTotal);
        console.log('Amenities Total:', this.amenitiesTotal);

        this.saleValue = this.flatCostTotal + this.amenitiesTotal + this.infraTotal;
        console.log('Sale Value:', this.saleValue);

        builtElements.forEach(element => {
            if (element.isFormulaElement) {
                const peName = element.Pricing_Element_Master__r.Name;
                const peNameLower = peName.toLowerCase();

                let amount = 0;
                let rate = 0;
                let quantity = 1;


                if (peNameLower.includes('stamp duty') || peNameLower.includes('mutation')) {
                    const percentage = project.Stamp_Duty_Percentage__c || 7.6;
                    const fixedRs = project.Stamp_Duty_and_Mutation_Charges_Rs__c || 1050;
                    amount = (this.saleValue * percentage / 100) + fixedRs;
                    rate = amount;
                    quantity = 1;
                    console.log(`Stamp Duty: ${this.saleValue} × ${percentage}% + ${fixedRs} = ${amount}`);
                }

                else if (peNameLower.includes('modt')) {
                    amount = this.saleValue * 0.80 * 0.005;
                    rate = amount;
                    quantity = 1;
                    console.log(`MODT: ${this.saleValue} × 80% × 0.5% = ${amount}`);
                }

                else if (peNameLower.includes('maintenance') || peNameLower.includes('maintainance')) {
                    const rs = project.Maintanance_Charges_Rs__c || 4;
                    const months = project.Maintainence_Charges_Months__c || 24;
                    quantity = sba;
                    rate = rs * months;
                    amount = sba * rs * months;
                    console.log(`Maintenance: ${sba} × ${rs} × ${months} = ${amount}`);
                }


                element.Quantity__c = quantity;
                element.Rate__c = rate;
                element.Amount__c = amount;
                element.FinalAmount = amount;
                element.ActualAmount = amount;
                element.formattedRate = this.formatCurrency(rate);
                element.formattedAmount = this.formatCurrency(amount);
                element.formattedFinalAmount = this.formatCurrency(amount);


                const taxAmount = amount > 0 ? (amount * element.totalTaxPercent) / 100 : 0;
                element.Tax_Amount__c = taxAmount;
                element.formattedTaxAmount = this.formatCurrency(taxAmount);
            }
        });


        this.pricingElements = builtElements;
        this.pendingData.pricingElements = builtElements;


        this.recalculateAllTotals();
        //  this.calculateParkingFromPricingElements();
        console.log('Built Elements:', this.pricingElements.length);
    }


    buildOpenPlotPricingElements(templateData) {
        console.log('=== buildOpenPlotPricingElements START ===');

        this.buildVillaPricingElements(templateData);

        console.log('=== buildOpenPlotPricingElements END ===');
    }


    buildTaxMap(taxLinkings) {
        const taxMap = {};

        taxLinkings.forEach(tax => {
            if (!tax?.Cost_Pricing_Association__c) return;

            const cpaId = tax.Cost_Pricing_Association__c;
            if (!taxMap[cpaId]) {
                taxMap[cpaId] = { cgst: 0, sgst: 0, igst: 0 };
            }

            const taxType = tax.Tax_Master__r?.Tax_Type__c;
            const taxPercent = tax.Tax_Master__r?.Tax__c || 0;

            if (taxType === 'CGST') {
                taxMap[cpaId].cgst = taxPercent;
            } else if (taxType === 'SGST') {
                taxMap[cpaId].sgst = taxPercent;
            } else if (taxType === 'IGST') {
                taxMap[cpaId].igst = taxPercent;
            }
        });

        return taxMap;
    }


    formatCurrency(value) {
        if (value === null || value === undefined) return '0';
        return new Intl.NumberFormat('en-IN').format(value);
    }

    handleDiscountPsftChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let value = parseFloat(event.target.value);

        if (isNaN(value) || value < 0) {
            value = 0;
        }

        console.log('handleDiscountPsftChange - Index:', index, 'Value:', value);

        const element = this.pricingElements[index];
        const rate = element.Rate__c || 0;

        let validationError = '';
        if (value < 0) {
            validationError = 'Discount cannot be negative';
            value = 0;
        } else if (value > rate) {
            validationError = `Cannot exceed rate (₹${this.formatCurrency(rate)})`;
        }

        this.pricingElements = this.pricingElements.map((item, idx) => {
            if (idx === index) {
                const updatedElement = {
                    ...item,
                    Discount_Psft__c: value,
                    discountPsftError: validationError
                };

                if (!validationError) {
                    return this.calculateElementFinalAmount(updatedElement);
                }
                return updatedElement;
            }
            return item;
        });

        this.recalculateAllTotals();
        this.checkValidationErrors();
    }

    handleDiscountLsChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let value = parseFloat(event.target.value);

        if (isNaN(value) || value < 0) {
            value = 0;
        }

        console.log('handleDiscountLsChange - Index:', index, 'Value:', value);

        const element = this.pricingElements[index];
        const amount = element.Amount__c || 0;

        let validationError = '';
        if (value < 0) {
            validationError = 'Discount cannot be negative';
            value = 0;
        } else if (value > amount) {
            validationError = `Cannot exceed amount (₹${this.formatCurrency(amount)})`;
        }

        this.pricingElements = this.pricingElements.map((item, idx) => {
            if (idx === index) {
                const updatedElement = {
                    ...item,
                    Discount_LS__c: value,
                    discountLsError: validationError
                };

                if (!validationError) {
                    return this.calculateElementFinalAmount(updatedElement);
                }
                return updatedElement;
            }
            return item;
        });

        this.recalculateAllTotals();
        this.checkValidationErrors();
    }

    calculateElementFinalAmount(element) {
        const isLsType = element.Unit__c === 'LS';
        let finalAmount = 0;

        if (isLsType) {
            const discountLs = Math.max(0, element.Discount_LS__c || 0); 
            const amount = element.Amount__c || 0;
            finalAmount = amount - discountLs;
        } else {
            const discountPsft = Math.max(0, element.Discount_Psft__c || 0);
            const rate = element.Rate__c || 0;
            const sba = element.Quantity__c || 0;

            
            const effectiveDiscount = Math.min(discountPsft, rate);
            finalAmount = (rate - effectiveDiscount) * sba;
        }

       
        finalAmount = Math.max(0, finalAmount);

      
        const totalTaxPercent = element.totalTaxPercent || 0;
        const taxAmount = finalAmount > 0 ? (finalAmount * totalTaxPercent) / 100 : 0;

        let stmDiscount = null;
        if (isLsType && element.Discount_LS__c > 0) {
            stmDiscount = element.Discount_LS__c;
        } else if (!isLsType && element.Discount_Psft__c > 0) {
            stmDiscount = element.Discount_Psft__c;
        }

        return {
            ...element,
            FinalAmount: finalAmount,
            formattedFinalAmount: this.formatCurrency(finalAmount),
            Tax_Amount__c: taxAmount,
            formattedTaxAmount: this.formatCurrency(taxAmount),
            STM_Given_Discount__c: stmDiscount
        };
    }

    recalculateAllTotals() {
        console.log('recalculateAllTotals START');

        
        this.initialTotalAmount = this.pricingElements.reduce((sum, element) => {
            const amount = parseFloat(element.Amount__c) || 0;
            return sum + Math.max(0, amount); 
        }, 0);

      
        this.revisedTotalAmount = this.pricingElements.reduce((sum, element) => {
            const finalAmount = parseFloat(element.FinalAmount) || 0;
            return sum + Math.max(0, finalAmount); 
        }, 0);

     
        this.totalTaxAmount = this.pricingElements.reduce((sum, element) => {
            const taxAmount = parseFloat(element.Tax_Amount__c) || 0;
            return sum + Math.max(0, taxAmount); 
        }, 0);

       
        this.initialTotalFormatted = this.formatCurrency(this.initialTotalAmount);
        this.revisedTotalFormatted = this.formatCurrency(this.revisedTotalAmount);
        this.totalTaxFormatted = this.formatCurrency(this.totalTaxAmount);

        
        this.realAmount = this.revisedTotalFormatted;
        this.taxAmount = this.totalTaxFormatted;
        this.totalAmount = this.revisedTotalAmount + this.totalTaxAmount;
        this.formattedTotalAmount = this.formatCurrency(this.totalAmount);

       
        this.calculateDifferencePerSqft();

       
        this.hasDiscountApplied = this.pricingElements.some(element =>
            (element.Discount_Psft__c && element.Discount_Psft__c > 0) ||
            (element.Discount_LS__c && element.Discount_LS__c > 0)
        );

        console.log('Initial Total:', this.initialTotalAmount);
        console.log('Revised Total:', this.revisedTotalAmount);
        console.log('Total Tax:', this.totalTaxAmount);
        console.log('Has Discount Applied:', this.hasDiscountApplied);

        console.log('=== recalculateAllTotals END ===');
    }

    // calculateParkingFromPricingElements() {
    //     console.log('=== calculateParkingFromPricingElements START ===');

    //     const parkingPEConfig = [
    //         { name: 'amenities with 1 car parking back to back', count: 1 },
    //         { name: 'amenities with family car parking', count: 1 },
    //         { name: 'amenities with single car parking', count: 1 },
    //         { name: 'one extra car parking back to back', count: 1 },
    //         { name: 'amenities with two car parking (back to back)', count: 2 }
    //     ];

    //     let totalParkingFromPE = 0;

    //     if (this.pricingElements && this.pricingElements.length > 0) {
    //         this.pricingElements.forEach(element => {
    //             const peName = element.Pricing_Element_Master__r?.Name || '';
    //             const peNameLower = peName.toLowerCase().trim();

    //             for (const config of parkingPEConfig) {
    //                 if (peNameLower === config.name.toLowerCase()) {
    //                     totalParkingFromPE += config.count;
    //                     console.log(`Parking PE Found: "${peName}" → +${config.count} parking`);
    //                     break;
    //                 }
    //             }
    //         });
    //     }

    //     this.templateParkingCount = totalParkingFromPE;

    //     const unitDefault = this.defaultParkingCount || 1;
    //     this.updatedDefaultParkingCount = unitDefault + this.templateParkingCount;

    //     console.log('Unit Default Parking:', unitDefault);
    //     console.log('Template Parking Count:', this.templateParkingCount);
    //     console.log('Updated Default Parking Count:', this.updatedDefaultParkingCount);
    //     console.log('=== calculateParkingFromPricingElements END ===');

    //     return this.templateParkingCount;
    // }

    calculateDifferencePerSqft() {
        if (!this.unitSBA || this.unitSBA <= 0) {
            this.differencePerSqft = '0';
            return 0;
        }

        
        const initialTotal = Math.max(0, this.initialTotalAmount || 0);
        const revisedTotal = Math.max(0, this.revisedTotalAmount || 0);

        const initialPerSqft = initialTotal / this.unitSBA;
        const revisedPerSqft = revisedTotal / this.unitSBA;

       
        let difference = initialPerSqft - revisedPerSqft;

        const roundedDifference = Math.abs(Math.round(difference));

        this.differencePerSqft = this.formatCurrency(roundedDifference);

        console.log('Difference Calculation:');
        console.log('  Initial Total:', initialTotal);
        console.log('  Revised Total:', revisedTotal);
        console.log('  Unit SBA:', this.unitSBA);
        console.log('  Initial/SBA:', initialPerSqft.toFixed(2));
        console.log('  Revised/SBA:', revisedPerSqft.toFixed(2));
        console.log('  Raw Difference:', difference);
        console.log('  Final Difference:', roundedDifference);

        return roundedDifference;
    }

    checkValidationErrors() {
        this.hasValidationErrors = this.pricingElements.some(element =>
            (element.discountPsftError && element.discountPsftError !== '') ||
            (element.discountLsError && element.discountLsError !== '')
        );
    }

    calculateTotals() {
        this.recalculateAllTotals();
    }

    handleDescriptionChange(event) {
        const index = event.target.dataset.index;
        const value = event.target.value;

        this.pricingElements = this.pricingElements.map((item, idx) => {
            if (idx === parseInt(index, 10)) {
                return {
                    ...item,
                    Description__c: value
                };
            }
            return item;
        });

        console.log('Description updated for index:', index, 'Value:', value);
    }

    handleThirdScreen() {
        this.secondScreen = false;
        this.thirdScreen = true;
    }

    // ============================================
    // SCREEN 3 - PARKING (UPDATED)
    // ============================================

    handleFourthScreenBack() {
        this.secondScreen = true;
        this.thirdScreen = false;
    }

    handleParking() {
        this.getParkingDetails();
    }

    getParkingDetails() {
        getParkingRecords({ unitId: this.selectedUnitId })
            .then(result => {
                console.log('=== getParkingDetails Result ===');
                console.log('Result:', JSON.stringify(result));

                if (result && Array.isArray(result) && result.length > 0) {
                    this.parkingDetails = result;

                    this.availableSingleParking = 0;
                    this.availableDualParking = 0;
                    this.singleParkingDetail = null;
                    this.dualParkingDetail = null;

                    const typeOptions = [];
                    const typesAdded = new Set();

                    this.parkingDetails.forEach(item => {
                        console.log('Parking Item:', item.Parking_Type__c, 'Available:', item.Available_Parking__c);

                        if (item.Parking_Type__c === 'Single') {
                            this.availableSingleParking = item.Available_Parking__c || 0;
                            this.singleParkingDetail = item;
                        } else if (item.Parking_Type__c === 'Dual') {
                            this.availableDualParking = item.Available_Parking__c || 0;
                            this.dualParkingDetail = item;
                        }

                        if (item.Parking_Type__c && !typesAdded.has(item.Parking_Type__c)) {
                            typeOptions.push({
                                label: item.Parking_Type__c,
                                value: item.Parking_Type__c
                            });
                            typesAdded.add(item.Parking_Type__c);
                        }
                    });

                    this.parkingTypeOptions = typeOptions;

                    if (this.carParkingTax) {
                        this.parkingCGSTtax = this.carParkingTax.CGST__c || 0;
                        this.parkingSGSTtax = this.carParkingTax.SGST__c || 0;
                    }

                    console.log('Available Single:', this.availableSingleParking);
                    console.log('Available Dual:', this.availableDualParking);
                    console.log('Parking Type Options:', JSON.stringify(this.parkingTypeOptions));

                    this.noParkingDetails = false;
                    this.parkingDetailTable = true;

                    this.initializeParkingDefaults();
                    this.initializeParkingRows();

                } else {
                    console.log('No parking records found');
                    this.noParkingDetails = true;
                    this.parkingDetailTable = false;
                }
            })
            .catch(error => {
                console.error('Error in getParkingDetails:', error);
                this.showToast('Error', 'Unable to fetch parking details.', 'error');
                this.noParkingDetails = true;
                this.parkingDetailTable = false;
            });
    }

    initializeParkingDefaults() {
        console.log('=== initializeParkingDefaults START ===');

      
        const defaultSpaces = this.defaultParkingCount || 1;

       
        this.updatedDefaultParkingCount = defaultSpaces;

        
        if (defaultSpaces % 2 === 0) {
            this.defaultSingleCount = 0;
            this.defaultDualCount = defaultSpaces / 2;
        } else {
            this.defaultSingleCount = 1;
            this.defaultDualCount = Math.floor((defaultSpaces - 1) / 2);
        }

        
        this.calculatedSingleCount = this.defaultSingleCount;
        this.calculatedDualCount = this.defaultDualCount;
        this.totalParkingSpaces = defaultSpaces;

        console.log('Default Parking Calculation:');
        console.log('  Default Parking (from Unit):', defaultSpaces);
        console.log('  Default Single Count:', this.defaultSingleCount);
        console.log('  Default Dual Count:', this.defaultDualCount);
        console.log('  Total Parking Spaces:', this.totalParkingSpaces);
        console.log('=== initializeParkingDefaults END ===');
    }

    initializeParkingRows() {
        console.log('=== initializeParkingRows START ===');
        console.log('Available parkingTypeOptions:', JSON.stringify(this.parkingTypeOptions));
        
        const emptyRow = this.createEmptyParkingRow();

        emptyRow.availableOptions = [...this.parkingTypeOptions];

        this.parkingRows = [emptyRow];

        this.hasParkingValidationError = false;

        console.log('Parking Rows Initialized:', JSON.stringify(this.parkingRows));
        console.log('=== initializeParkingRows END ===');
    }
    createEmptyParkingRow() {
        return {
            id: 'row_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9),
            parkingType: '',
            quantity: null,
            amount: null,
            discountLs: 0,
            finalAmount: 0,
            taxAmount: 0,
            typeError: '',
            quantityError: '',
            amountError: '',
            discountError: ''
        };
    }

    handleAddParkingRow() {
        console.log('=== handleAddParkingRow ===');

        if (this.parkingRows.length >= 2) {
            this.showToast('Warning', 'Maximum 2 parking rows allowed.', 'warning');
            return;
        }

       
        const firstRowType = this.parkingRows.length > 0 ? this.parkingRows[0].parkingType : '';

        console.log('First row type:', firstRowType);

      
        let autoSelectType = '';
        if (firstRowType && firstRowType !== '') {
            const otherType = this.parkingTypeOptions.find(option => option.value !== firstRowType);
            if (otherType) {
                autoSelectType = otherType.value;
            }
        }

        console.log('Auto-select type for new row:', autoSelectType);

        const newRow = this.createEmptyParkingRow();
        newRow.parkingType = autoSelectType;

        const newRowIndex = this.parkingRows.length;

        this.parkingRows = [...this.parkingRows, newRow];

       
        this.enrichParkingRowsWithOptions();

        console.log('Row added. Total rows:', this.parkingRows.length);
        console.log('Updated parking rows:', JSON.stringify(this.parkingRows));
    }

    handleDeleteParkingRow(event) {
        const index = parseInt(event.target.dataset.index, 10);
        console.log('=== handleDeleteParkingRow - Index:', index, '===');

        this.parkingRows = this.parkingRows.filter((row, idx) => idx !== index);

        this.enrichParkingRowsWithOptions();

        this.recalculateParkingTotals();
        this.checkParkingValidationErrors();

        console.log('Row deleted. Remaining rows:', this.parkingRows.length);
    }

    handleParkingTypeChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        const selectedType = event.detail.value;

        console.log('=== handleParkingTypeChange - Index:', index, 'Type:', selectedType, '===');

        const isDuplicate = this.parkingRows.some((row, idx) => {
            return idx !== index && row.parkingType === selectedType && row.parkingType !== '';
        });

        if (isDuplicate) {
            this.showToast('Warning', `${selectedType} parking is already selected in another row. Please choose a different type.`, 'warning');

            
            this.parkingRows = this.parkingRows.map((row, idx) => {
                if (idx === index) {
                    return {
                        ...row,
                        parkingType: '',
                        typeError: 'Please select a different parking type'
                    };
                }
                return row;
            });

           
            this.enrichParkingRowsWithOptions();
            this.checkParkingValidationErrors();
            return;
        }

       
        this.parkingRows = this.parkingRows.map((row, idx) => {
            if (idx === index) {
                return {
                    ...row,
                    parkingType: selectedType,
                    typeError: ''
                };
            }
            return row;
        });

        this.enrichParkingRowsWithOptions();

        this.validateParkingRowQuantity(index);
        this.recalculateParkingTotals();
    }

    getParkingTypeOptionsForRow(rowIndex) {
       
        const selectedTypesInOtherRows = new Set();

        this.parkingRows.forEach((row, idx) => {
            
            if (idx !== rowIndex && row.parkingType && row.parkingType !== '') {
                selectedTypesInOtherRows.add(row.parkingType);
            }
        });

        console.log('Row Index:', rowIndex);
        console.log('Selected types in other rows:', [...selectedTypesInOtherRows]);

       
        const filteredOptions = this.parkingTypeOptions.filter(option => {
            return !selectedTypesInOtherRows.has(option.value);
        });

        console.log('Filtered options for row', rowIndex, ':', JSON.stringify(filteredOptions));

        return filteredOptions;
    }

    enrichParkingRowsWithOptions() {
        console.log('=== enrichParkingRowsWithOptions START ===');

        if (!this.parkingTypeOptions || this.parkingTypeOptions.length === 0) {
            console.log('No parking type options available yet');
            return;
        }

        this.parkingRows = this.parkingRows.map((row, index) => {
            const availableOptions = this.getParkingTypeOptionsForRow(index);
            console.log(`Row ${index} - Current Type: ${row.parkingType}, Available Options:`, JSON.stringify(availableOptions));

            return {
                ...row,
                availableOptions: availableOptions
            };
        });

        console.log('=== enrichParkingRowsWithOptions END ===');
    }

    handleParkingRowQuantityChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let quantity = parseInt(event.target.value, 10);

        if (isNaN(quantity) || quantity < 0) {
            quantity = null;
        }

        console.log('=== handleParkingRowQuantityChange - Index:', index, 'Quantity:', quantity, '===');

        
        this.parkingRows = this.parkingRows.map((row, idx) => {
            if (idx === index) {
                const updatedRow = {
                    ...row,
                    quantity: quantity,
                    quantityError: '' 
                };
                return this.calculateParkingRowAmounts(updatedRow);
            }
            return row;
        });

        
        this.validateParkingRowQuantity(index);
        this.recalculateParkingTotals();
    }

    handleParkingRowAmountChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let amount = parseFloat(event.target.value);

        if (isNaN(amount) || amount < 0) {
            amount = null;
        }

        console.log('=== handleParkingRowAmountChange - Index:', index, 'Amount:', amount, '===');

      
        this.parkingRows = this.parkingRows.map((row, idx) => {
            if (idx === index) {
                const updatedRow = {
                    ...row,
                    amount: amount,
                    amountError: '' 
                };
                return this.calculateParkingRowAmounts(updatedRow);
            }
            return row;
        });

       
        this.validateParkingRowDiscount(index);
        this.recalculateParkingTotals();
    }

    handleParkingRowDiscountChange(event) {
        const index = parseInt(event.target.dataset.index, 10);
        let discount = parseFloat(event.target.value);

        if (isNaN(discount) || discount < 0) {
            discount = 0;
            event.target.value = 0;
        }

        console.log('=== handleParkingRowDiscountChange - Index:', index, 'Discount:', discount, '===');

        
        this.parkingRows = this.parkingRows.map((row, idx) => {
            if (idx === index) {
                const updatedRow = {
                    ...row,
                    discountLs: discount
                };
                return this.calculateParkingRowAmounts(updatedRow);
            }
            return row;
        });

        
        this.validateParkingRowDiscount(index);
        this.recalculateParkingTotals();
    }

    calculateParkingRowAmounts(row) {
        const amount = row.amount || 0;
        const discount = row.discountLs || 0;

      
        const amountAfterDiscount = Math.max(0, amount - discount);

       
        const totalTaxPercent = (this.parkingCGSTtax || 0) + (this.parkingSGSTtax || 0);
        const taxAmount = amountAfterDiscount > 0 ? (amountAfterDiscount * totalTaxPercent) / 100 : 0;

        
        const finalAmount = amountAfterDiscount;

        return {
            ...row,
            taxAmount: taxAmount,
            finalAmount: finalAmount
        };
    }

    validateParkingRowQuantity(index) {
        const row = this.parkingRows[index];

        if (!row) return;

        let quantityError = '';

       
        if (row.parkingType && row.quantity > 0) {
            if (row.parkingType === 'Single') {
                if (row.quantity > this.availableSingleParking) {
                    quantityError = `Only ${this.availableSingleParking} Single parking available`;
                }
            } else if (row.parkingType === 'Dual') {
                if (row.quantity > this.availableDualParking) {
                    quantityError = `Only ${this.availableDualParking} Dual parking available`;
                }
            }
        }

        
        this.parkingRows = this.parkingRows.map((r, idx) => {
            if (idx === index) {
                return {
                    ...r,
                    quantityError: quantityError
                };
            }
            return r;
        });

       
        this.checkParkingValidationErrors();
    }

    validateParkingRowDiscount(index) {
        const row = this.parkingRows[index];

        if (!row) return;

        let discountError = '';

        if (row.discountLs > 0 && row.amount > 0 && row.discountLs > row.amount) {
            discountError = `Max discount: ₹${this.formatCurrency(row.amount)}`;
        }

        
        this.parkingRows = this.parkingRows.map((r, idx) => {
            if (idx === index) {
                return {
                    ...r,
                    discountError: discountError
                };
            }
            return r;
        });

        
        this.checkParkingValidationErrors();
    }

    validateAllParkingRows() {
        console.log('=== validateAllParkingRows ===');

        let hasErrors = false;

        this.parkingRows = this.parkingRows.map((row, index) => {
            let typeError = '';
            let quantityError = '';
            let amountError = '';
            let discountError = '';

           
            const hasData = row.parkingType || row.quantity || row.amount;

            if (hasData) {
               
                if (!row.parkingType || row.parkingType === '') {
                    typeError = 'Parking Type is required';
                    hasErrors = true;
                }

               
                if (!row.quantity || row.quantity <= 0) {
                    quantityError = 'Quantity is required';
                    hasErrors = true;
                } else {
                   
                    if (row.parkingType === 'Single' && row.quantity > this.availableSingleParking) {
                        quantityError = `Only ${this.availableSingleParking} Single parking available`;
                        hasErrors = true;
                    } else if (row.parkingType === 'Dual' && row.quantity > this.availableDualParking) {
                        quantityError = `Only ${this.availableDualParking} Dual parking available`;
                        hasErrors = true;
                    }
                }

              
                if (!row.amount || row.amount <= 0) {
                    amountError = 'Amount is required';
                    hasErrors = true;
                }

               
                if (row.discountLs > 0 && row.amount > 0 && row.discountLs > row.amount) {
                    discountError = `Max discount: ₹${this.formatCurrency(row.amount)}`;
                    hasErrors = true;
                }
            }

            return {
                ...row,
                typeError: typeError,
                quantityError: quantityError,
                amountError: amountError,
                discountError: discountError
            };
        });

        this.hasParkingValidationError = hasErrors;

        return !hasErrors;
    }

    checkParkingValidationErrors() {
       
        this.hasParkingValidationError = this.parkingRows.some(row =>
            (row.typeError && row.typeError !== '') ||
            (row.quantityError && row.quantityError !== '') ||
            (row.amountError && row.amountError !== '') ||
            (row.discountError && row.discountError !== '')
        );
    }

    recalculateParkingTotals() {
        console.log('=== recalculateParkingTotals START ===');

       
        let extraSingleCount = 0;
        let extraDualCount = 0;

      
        this.parkingRows.forEach(row => {
            if (row.parkingType && row.quantity > 0 && row.amount > 0) {
                if (row.parkingType === 'Single') {
                    extraSingleCount += row.quantity;
                } else if (row.parkingType === 'Dual') {
                    extraDualCount += row.quantity;
                }
            }
        });

        
        this.calculatedSingleCount = this.defaultSingleCount + extraSingleCount;
        this.calculatedDualCount = this.defaultDualCount + extraDualCount;

        
        this.totalParkingSpaces = (this.calculatedSingleCount * 1) + (this.calculatedDualCount * 2);

        
        this.recalculateGrandTotalWithParking();

        console.log('Parking Totals:');
        console.log('  Default Single:', this.defaultSingleCount);
        console.log('  Default Dual:', this.defaultDualCount);
        console.log('  Extra Single:', extraSingleCount);
        console.log('  Extra Dual:', extraDualCount);
        console.log('  Total Single:', this.calculatedSingleCount);
        console.log('  Total Dual:', this.calculatedDualCount);
        console.log('  Total Parking Spaces:', this.totalParkingSpaces);
        console.log('=== recalculateParkingTotals END ===');
    }

    recalculateGrandTotalWithParking() {
        console.log('=== recalculateGrandTotalWithParking START ===');

        const pricingRealAmount = this.revisedTotalAmount || 0;
        const pricingTaxAmount = this.totalTaxAmount || 0;

        
        let totalParkingAmount = 0;
        let totalParkingTax = 0;

        this.parkingRows.forEach(row => {
            if (row.parkingType && row.quantity > 0 && row.amount > 0) {
                totalParkingAmount += (row.finalAmount || 0); 
                totalParkingTax += (row.taxAmount || 0);
            }
        });

       
        const grandTotal = pricingRealAmount + pricingTaxAmount + totalParkingAmount + totalParkingTax;

        this.totalAmount = grandTotal;
        this.formattedTotalAmount = this.formatCurrency(grandTotal);

        const hasRowDiscount = this.parkingRows.some(row => row.discountLs > 0);
        if (hasRowDiscount) {
            this.discountAdded = true;
        }

        console.log('Grand Total Calculation:');
        console.log('  Pricing Amount:', pricingRealAmount);
        console.log('  Pricing Tax:', pricingTaxAmount);
        console.log('  Parking Amount (before tax):', totalParkingAmount);
        console.log('  Parking Tax:', totalParkingTax);
        console.log('  Grand Total:', grandTotal);
        console.log('=== recalculateGrandTotalWithParking END ===');
    }

    handleFouth() {
        console.log('=== handleFouth START ===');

       
        if (this.parkingDetailTable && this.parkingRows.length > 0) {
            
            const hasAnyData = this.parkingRows.some(row =>
                row.parkingType || row.quantity || row.amount
            );

            if (hasAnyData) {
               
                const isValid = this.validateAllParkingRows();

                if (!isValid) {
                    this.showToast('Error', 'Please fill all required fields for parking details.', 'error');
                    return;
                }
            }
        }

      
        this.addParkingToPricingElements();

     
        this.recalculateTotalsForFourthScreen();

      
        this.discountAdded = this.pricingElements.some(item =>
            (item.Discount_Psft__c != null && item.Discount_Psft__c > 0) ||
            (item.Discount_LS__c != null && item.Discount_LS__c > 0)
        );

        this.pricingElements = this.pricingElements.map(element => {
            return {
                ...element,
                formattedRate: element.Rate__c ? this.formatCurrency(element.Rate__c) : '0',
                formattedAmount: element.Amount__c ? this.formatCurrency(element.Amount__c) : '0',
                formattedDiscountPsft: element.Discount_Psft__c ? this.formatCurrency(element.Discount_Psft__c) : '0',
                formattedDiscountLs: element.Discount_LS__c ? this.formatCurrency(element.Discount_LS__c) : '0',
                formattedFinalAmount: element.FinalAmount ? this.formatCurrency(element.FinalAmount) : '0',
                formattedTaxAmount: element.Tax_Amount__c ? this.formatCurrency(element.Tax_Amount__c) : '0'
            };
        });

       
        this.discountByPricingMap = [];
        this.pricingElements.forEach(item => {
            if (item.STM_Given_Discount__c != null && item.STM_Given_Discount__c > 0) {
                this.discountByPricingMap.push({
                    discountAmount: item.STM_Given_Discount__c,
                    id: item.Pricing_Element_Master__c,
                    isLsType: item.PE_Type__c === 'LS' || item.Unit__c === 'LS'
                });
            }
        });

      
        this.pendingData.hasDiscount = this.discountAdded;
        this.pendingData.singleParkingCount = this.calculatedSingleCount;
        this.pendingData.dualParkingCount = this.calculatedDualCount;
        this.pendingData.defaultParkingCount = this.defaultParkingCount || 1;

      
        let userAddedSingle = 0;
        let userAddedDual = 0;
        this.parkingRows.forEach(row => {
            if (row.parkingType && row.quantity > 0 && row.amount > 0) {
                if (row.parkingType === 'Single') {
                    userAddedSingle += row.quantity || 0;
                } else if (row.parkingType === 'Dual') {
                    userAddedDual += row.quantity || 0;
                }
            }
        });
        this.pendingData.userAddedSingleCount = userAddedSingle;
        this.pendingData.userAddedDualCount = userAddedDual;

        
        this.thirdScreen = false;
        this.fourthScreen = true;

        console.log('Parking Data Stored:');
        console.log('  Default Parking (from Unit):', this.defaultParkingCount);
        console.log('  Default Single:', this.defaultSingleCount);
        console.log('  Default Dual:', this.defaultDualCount);
        console.log('  User Added Single:', userAddedSingle);
        console.log('  User Added Dual:', userAddedDual);
        console.log('  Final Single:', this.calculatedSingleCount);
        console.log('  Final Dual:', this.calculatedDualCount);
        console.log('  Total Spaces:', this.totalParkingSpaces);
        console.log('=== handleFouth END ===');
    }

    addParkingToPricingElements() {
        console.log('=== addParkingToPricingElements START ===');

        
        this.pricingElements = this.pricingElements.filter(el => !el.parking_Element__c);

        let lastSequence = 0;
        this.pricingElements.forEach(el => {
            const seq = el.Sequence__c || 0;
            if (seq > lastSequence) {
                lastSequence = seq;
            }
        });

        console.log('Last sequence from pricing elements:', lastSequence);

        
        const parkingMastersMap = {};
        if (this.templateData && this.templateData.parkingMasters) {
            this.templateData.parkingMasters.forEach(pm => {
                parkingMastersMap[pm.Parking_Type__c] = pm;
            });
        }
        
        const cgst = this.parkingCGSTtax || 0;
        const sgst = this.parkingSGSTtax || 0;
        const totalTaxPercent = cgst + sgst;

        let parkingSequence = lastSequence;

       
        this.parkingRows.forEach((row, index) => {
           
            if (row.parkingType && row.quantity > 0 && row.amount > 0) {
                const parkingMaster = parkingMastersMap[row.parkingType];

                if (!parkingMaster) {
                    console.warn(`No parking master found for type: ${row.parkingType}`);
                    return;
                }
                parkingSequence++;

                let stmGivenDiscount = null;
                if (row.discountLs > 0) {
                    stmGivenDiscount = row.discountLs;
                }

               
                const amountAfterDiscount = Math.max(0, row.amount - (row.discountLs || 0));

                const parkingElement = {
                    tempId: 'parking_' + Date.now() + '_' + index,
                    Pricing_Element_Master__c: parkingMaster.Id,
                    Pricing_Element_Master__r: {
                        Name: parkingMaster.Name,
                        Id: parkingMaster.Id
                    },
                    PE_Type__c: 'Additional Charges',
                    Type__c: 'Agreement',
                    Unit__c: 'LS',
                    Sequence__c: parkingSequence,
                    Quantity__c: row.quantity,
                    Rate__c: row.amount, 
                    Amount__c: row.amount,

                    
                    CGST_Tax_Percentage__c: cgst,
                    SGST_Tax_Percentage__c: sgst,
                    IGST_Tax_Percentage__c: 0,
                    totalTaxPercent: totalTaxPercent,
                    Tax_Amount__c: row.taxAmount,

                   
                    Discount_Psft__c: 0,
                    Discount_LS__c: row.discountLs || 0,
                    STM_Given_Discount__c: stmGivenDiscount,
                    FinalAmount: amountAfterDiscount, 
                    ActualAmount: amountAfterDiscount,

                    
                    isDiscountPsftEditable: false,
                    isDiscountLsEditable: true,

                    
                    Description__c: `Extra ${row.parkingType} Parking`,
                    parking_Element__c: true,
                    serialNumber: 0,
                    showDescription: false,

                    
                    formattedRate: this.formatCurrency(row.amount / row.quantity),
                    formattedAmount: this.formatCurrency(row.amount),
                    formattedFinalAmount: this.formatCurrency(amountAfterDiscount), 
                    formattedTaxAmount: this.formatCurrency(row.taxAmount),
                    formattedDiscountPsft: '0',
                    formattedDiscountLs: this.formatCurrency(row.discountLs || 0),

                    
                    peTypeBadgeClass: 'pe-type-badge pe-type-badge-ls'
                };

                this.pricingElements.push(parkingElement);
                console.log(`${row.parkingType} Parking Element Added:`, parkingElement);
            }
        });

        
        this.pricingElements.forEach((el, idx) => {
            el.serialNumber = idx + 1;
        });

        console.log('=== addParkingToPricingElements END ===');
    }


    recalculateTotalsForFourthScreen() {
        console.log('=== recalculateTotalsForFourthScreen START ===');

        this.initialTotalAmount = this.pricingElements.reduce((sum, element) => {
            return sum + (parseFloat(element.Amount__c) || 0);
        }, 0);

        this.revisedTotalAmount = this.pricingElements.reduce((sum, element) => {
            return sum + (parseFloat(element.FinalAmount) || 0);
        }, 0);

        this.totalTaxAmount = this.pricingElements.reduce((sum, element) => {
            return sum + (parseFloat(element.Tax_Amount__c) || 0);
        }, 0);

        this.initialTotalFormatted = this.formatCurrency(this.initialTotalAmount);
        this.revisedTotalFormatted = this.formatCurrency(this.revisedTotalAmount);
        this.totalTaxFormatted = this.formatCurrency(this.totalTaxAmount);

        this.totalAmount = this.revisedTotalAmount + this.totalTaxAmount;
        this.formattedTotalAmount = this.formatCurrency(this.totalAmount);

        this.realAmount = this.revisedTotalFormatted;
        this.taxAmount = this.totalTaxFormatted;

        this.calculateDifferencePerSqft();

        console.log('Fourth Screen Totals:');
        console.log('  Initial Total:', this.initialTotalAmount);
        console.log('  Revised Total:', this.revisedTotalAmount);
        console.log('  Total Tax:', this.totalTaxAmount);
        console.log('  Grand Total:', this.totalAmount);

        console.log('=== recalculateTotalsForFourthScreen END ===');
    }

    handleBack() {
        this.thirdScreen = true;
        this.fourthScreen = false;
    }

    handleFinalSave() {
        console.log('=== handleFinalSave START ===');

        this.isFinalSaveDisabled = true;
        this.isLoading = true;

        const saveData = this.prepareSaveData();
        console.log('Save Data:', JSON.stringify(saveData));

        saveAllCostSheetData({ saveDataJson: JSON.stringify(saveData) })
            .then(result => {
                console.log('Save Result:', JSON.stringify(result));

                if (result.isSuccess) {
                    this.newCostSheetId = result.costSheetId;

                    if (result.requiresApproval) {
                        this.showToast('Success', 'Cost Sheet saved successfully! Submitted for discount approval.', 'success');
                    } else {
                        this.showToast('Success', 'Cost Sheet saved successfully!', 'success');
                    }

                    this.isFinalSaveDisabled = false;
                    this.isLoading = false;
                    this.closeComponent();

                } else {
                    this.showToast('Error', result.errorMessage || 'Failed to save Cost Sheet.', 'error');
                    this.isFinalSaveDisabled = false;
                    this.isLoading = false;
                }
            })
            .catch(error => {
                console.error('Error in handleFinalSave:', JSON.stringify(error));
                this.showToast('Error', 'Failed to save Cost Sheet: ' + (error.body?.message || error.message || 'Unknown error'), 'error');
                this.isFinalSaveDisabled = false;
                this.isLoading = false;
            });

        console.log('=== handleFinalSave END ===');
    }

    prepareSaveData() {
        const differenceAmount = this.calculateDifferencePerSqft();

        const pricingElementsForSave = this.pricingElements.map(pe => {
            return {
                pricingElementMasterId: pe.Pricing_Element_Master__c,
                peType: pe.PE_Type__c || null,
                type: pe.Type__c || null,
                unit: pe.Unit__c || null,
                sequence: pe.Sequence__c || 0,
                quantity: pe.Quantity__c || 0,
                rate: pe.Rate__c || 0,
                amount: pe.Amount__c || 0,

                cgstTaxPercent: pe.CGST_Tax_Percentage__c || 0,
                sgstTaxPercent: pe.SGST_Tax_Percentage__c || 0,
                igstTaxPercent: pe.IGST_Tax_Percentage__c || 0,
                taxAmount: pe.Tax_Amount__c || 0,

                discountPsft: pe.Discount_Psft__c || 0,
                discountLs: pe.Discount_LS__c || 0,
                stmGivenDiscount: pe.STM_Given_Discount__c || null,
                finalAmount: pe.FinalAmount || 0,

                description: pe.Description__c || '',
                isParkingElement: pe.parking_Element__c || false
            };
        });

        const discountDataForSave = this.discountByPricingMap.map(dd => {
            return {
                pricingElementMasterId: dd.id,
                discountAmount: dd.discountAmount,
                isLsType: dd.isLsType
            };
        });

        const saveData = {
            opportunityId: this.pendingData.costSheet.opportunityId || this.opp?.Id,
            unitId: this.pendingData.costSheet.unitId || this.selectedUnitId,
            costSchemeLinkingId: this.pendingData.costSheet.costSchemeLinkingId || this.selectedCostSchemeId,
            costSheetTemplateId: this.pendingData.costSheet.costSheetTemplateId,

            hasDiscount: this.discountAdded || false,
            differenceAmount: differenceAmount,
            unitSBA: this.unitSBA,
            initialTotalAmount: this.initialTotalAmount,
            revisedTotalAmount: this.revisedTotalAmount,

            singleParkingCount: this.calculatedSingleCount,
            dualParkingCount: this.calculatedDualCount,

            pricingElements: pricingElementsForSave,
            discountData: discountDataForSave
        };

        console.log('Prepared Save Data:', JSON.stringify(saveData));
        return saveData;
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(event);
    }

    closeComponent() {
        try {
            this.dispatchEvent(new CloseActionScreenEvent());
        } catch (e) {
            console.log('CloseActionScreenEvent failed:', e);
        }
        this.dispatchEvent(new CustomEvent('close'));
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    
    get hasParkingRows() {
        return this.parkingRows && this.parkingRows.length > 0;
    }

    
    get canAddParkingRow() {
        return this.parkingRows.length < 2;
    }


    get availableParkingTypesForNewRow() {
       
        const selectedTypes = new Set();
        this.parkingRows.forEach(row => {
            if (row.parkingType) {
                selectedTypes.add(row.parkingType);
            }
        });

        return this.parkingTypeOptions.filter(option => !selectedTypes.has(option.value));
    }

}