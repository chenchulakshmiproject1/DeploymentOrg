import { LightningElement, track, wire } from 'lwc';
import getStageData from '@salesforce/apex/OpportunityStageController.getStageData';
import { refreshApex } from '@salesforce/apex';
import createTaskMaster from '@salesforce/apex/TaskMasterController.createTaskMaster';
import deleteTaskMaster from '@salesforce/apex/TaskMasterController.deleteTaskMaster';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class OpportunityStageCustomization extends LightningElement {
    @track stages = [];
    @track isLoading = true;
    @track error = null;
    @track totalSelectedTasks = 0;
    
    // Add Task Modal properties
    @track isModalOpen = false;
    @track selectedStageName = '';
    @track isSaving = false;
    
    // Delete Modal properties
    @track isDeleteModalOpen = false;
    @track isDeleting = false;
    @track selectedStageForDelete = '';
    @track selectedTasksForDelete = [];
    @track selectedTasksCount = 0;
    
    
    @track actionTypeValue = '';
    @track actionUrlValue = '';
    @track taskSubjectValue = '';
    @track isActiveValue = true;
    @track isCommonTaskValue = false;
    @track remarksValue = '';
    
    // Picklist options
    actionTypeOptions = [
        { label: 'Email', value: 'Email' },
        { label: 'Call', value: 'Call' },
        { label: 'Meeting', value: 'Meeting' },
        { label: 'Task', value: 'Task' },
        { label: 'Send Document', value: 'Send Document' }
    ];
    
    // Array of colors for bullet points
    bulletColors = [
        '#2e844a', // Green
        '#027e46', // Dark Green
        '#04844b', // Emerald
        '#54698d', // Blue
        '#16325c', // Navy
        '#e9642b', // Orange
        '#c23934', // Red
        '#4b7a8c', // Teal
        '#665c4a', // Brown
        '#6b6d6d'  // Gray
    ];
    
    wiredStageDataResult;

    @wire(getStageData)
    wiredStageData(result) {
        this.wiredStageDataResult = result;
        const { data, error } = result;
        
        this.isLoading = false;
        
        if (data && data.success) {
            this.stages = data.stages.map((stage, index) => {
                // Assign a color based on index
                const colorIndex = index % this.bulletColors.length;
                const bulletColor = this.bulletColors[colorIndex];
                
                return {
                    ...stage,
                    tasks: stage.tasks.map(task => ({
                        ...task,
                        selected: false
                    })),
                    selectedCount: 0,
                    totalTasks: stage.tasks.length,
                    bulletColor: bulletColor,
                    bulletStyle: `color: ${bulletColor};`
                };
            });
            this.error = null;
            this.updateTotalSelectedCount();
        } else if (error) {
            this.error = 'Error loading stage data. Please try again.';
            console.error('Error:', error);
        }
    }

    handleAddTaskClick(event) {
        const stageName = event.currentTarget.dataset.stageName;
        this.selectedStageName = stageName;
        this.resetForm();
        this.isModalOpen = true;
    }

    
    handleDeleteTaskClick(event) {
        const stageName = event.currentTarget.dataset.stageName;
        

        const stage = this.stages.find(s => s.stageName === stageName);
        
        if (!stage) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Stage not found',
                    variant: 'error'
                })
            );
            return;
        }

        
        const selectedTasks = stage.tasks.filter(task => task.selected);
        
        if (selectedTasks.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'No Tasks Selected',
                    message: 'Please select at least one task to delete',
                    variant: 'warning'
                })
            );
            return;
        }

    
        this.selectedStageForDelete = stageName;
        this.selectedTasksForDelete = selectedTasks;
        this.selectedTasksCount = selectedTasks.length;
        this.isDeleteModalOpen = true;
    }

    
    closeDeleteModal() {
        this.isDeleteModalOpen = false;
        this.selectedStageForDelete = '';
        this.selectedTasksForDelete = [];
        this.selectedTasksCount = 0;
        this.isDeleting = false;
    }

    
    async confirmDelete() {
        this.isDeleting = true;
        
        try {
        
            const taskIds = this.selectedTasksForDelete.map(task => task.id);
            
        
            const result = await deleteTaskMaster({ taskIds: taskIds });
            
            if (result && result.success) {
                
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: result.message || `${this.selectedTasksCount} task${this.selectedTasksCount > 1 ? 's' : ''} deleted successfully`,
                        variant: 'success'
                    })
                );
                
        
                this.closeDeleteModal();
                
        
                await this.refreshData();
            } else {
                throw new Error(result.message || 'Error deleting tasks');
            }
        } catch (error) {
            console.error('Error deleting tasks:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.message || 'Error deleting tasks. Please try again.',
                    variant: 'error'
                })
            );
            this.isDeleting = false;
        }
    }

    
    closeModal() {
        this.isModalOpen = false;
        this.resetForm();
    }

    
    resetForm() {
        this.actionTypeValue = '';
        this.actionUrlValue = '';
        this.taskSubjectValue = '';
        this.isActiveValue = true;
        this.isCommonTaskValue = false;
        this.remarksValue = '';
        this.isSaving = false;
    }

    
    handleOverlayClick() {
        if (this.isModalOpen) {
            this.closeModal();
        } else if (this.isDeleteModalOpen) {
            this.closeDeleteModal();
        }
    }


    handleModalClick(event) {
        event.stopPropagation();
    }

    
    handleActionTypeChange(event) {
        this.actionTypeValue = event.detail.value;
    }

    handleActionUrlChange(event) {
        this.actionUrlValue = event.target.value;
    }

    handleTaskSubjectChange(event) {
        this.taskSubjectValue = event.target.value;
    }

    handleIsActiveChange(event) {
        this.isActiveValue = event.target.checked;
    }

    handleIsCommonTaskChange(event) {
        this.isCommonTaskValue = event.target.checked;
    }

    handleRemarksChange(event) {
        this.remarksValue = event.target.value;
    }

    
    validateForm() {
        let isValid = true;
        let errorMessage = '';


        if (!this.taskSubjectValue || this.taskSubjectValue.trim() === '') {
        errorMessage += 'Task Subject is required.';
        isValid = false;
    }

        if (!isValid) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Validation Error',
                    message: errorMessage,
                    variant: 'error'
                })
            );
        }

        return isValid;
    }

  /*  async handleCreateTask() {
        if (!this.validateForm()) {
            return;
        }

        this.isSaving = true;

        try {
    
            const taskData = {
                objectType: 'Opportunity', 
                taskSubject: this.taskSubjectValue,
                stageName: this.selectedStageName, 
                isActive: this.isActiveValue,
                isCommonTask: this.isCommonTaskValue,
                remarks: this.remarksValue
            };

            const result = await createTaskMaster({ taskData: JSON.stringify(taskData) });

            if (result && result.success) {
            
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Task created successfully',
                        variant: 'success'
                    })
                );

                this.closeModal();

                await this.refreshData();
            } else {
                throw new Error(result.message || 'Error creating task');
            }
        } catch (error) {
            console.error('Error creating task:', error);
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: error.message || 'Error creating task. Please try again.',
                    variant: 'error'
                })
            );
        } finally {
            this.isSaving = false;
        }
    }*/

    async handleCreateTask() {
    if (!this.validateForm()) {
        return;
    }

    this.isSaving = true;

    try {
        let taskData;
        
        if (this.isCommonTaskValue) {
            // Get all stage names
            const allStageNames = this.stages.map(stage => stage.stageName);
            
            // Create an array of task data for ALL stages
            taskData = {
                tasks: allStageNames.map(stageName => ({
                    objectType: 'Opportunity',
                    taskSubject: this.taskSubjectValue,
                    stageName: stageName,
                    isActive: this.isActiveValue,
                    isCommonTask: true,
                    remarks: this.remarksValue
                }))
            };
        } else {
            // Single task for selected stage
            taskData = {
                tasks: [{
                    objectType: 'Opportunity',
                    taskSubject: this.taskSubjectValue,
                    stageName: this.selectedStageName,
                    isActive: this.isActiveValue,
                    isCommonTask: false,
                    remarks: this.remarksValue
                }]
            };
        }

        // Call Apex with all tasks in one go
        const result = await createTaskMaster({ 
            taskData: JSON.stringify(taskData) 
        });

        if (result && result.success) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: result.message || 'Task(s) created successfully',
                    variant: 'success'
                })
            );

            this.closeModal();
            await this.refreshData();
        } else {
            throw new Error(result.message || 'Error creating task(s)');
        }
    } catch (error) {
        console.error('Error creating task:', error);
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message: error.message || 'Error creating task. Please try again.',
                variant: 'error'
            })
        );
    } finally {
        this.isSaving = false;
    }
}

    handleTaskSelection(event) {
        const stageIndex = event.target.dataset.stageIndex;
        const taskIndex = event.target.dataset.taskIndex;
        const isChecked = event.target.checked;

        if (stageIndex !== undefined && taskIndex !== undefined) {
          
            const updatedStages = JSON.parse(JSON.stringify(this.stages));
            
            updatedStages[stageIndex].tasks[taskIndex].selected = isChecked;
            
            const stageTasks = updatedStages[stageIndex].tasks;
            updatedStages[stageIndex].selectedCount = 
                stageTasks.filter(task => task.selected).length;
            
            this.stages = updatedStages;
         
            this.updateTotalSelectedCount();
        }
    }

    updateTotalSelectedCount() {
        this.totalSelectedTasks = this.stages.reduce((total, stage) => {
            return total + (stage.selectedCount || 0);
        }, 0);
    }

    get hasSelectedTasks() {
        return this.totalSelectedTasks > 0;
    }

  
    get selectionSummary() {
        return `${this.totalSelectedTasks} task${this.totalSelectedTasks !== 1 ? 's' : ''} selected`;
    }

   
    getSelectedTaskIds() {
        const selectedIds = [];
        this.stages.forEach(stage => {
            stage.tasks.forEach(task => {
                if (task.selected) {
                    selectedIds.push(task.id);
                }
            });
        });
        return selectedIds;
    }

    async refreshData() {
        this.isLoading = true;
        this.error = null;
        
        if (this.wiredStageDataResult) {
            try {
                await refreshApex(this.wiredStageDataResult);
            } catch (error) {
                this.error = 'Error refreshing data. Please try again.';
                console.error('Refresh error:', error);
            } finally {
                this.isLoading = false;
            }
        } else {
            this.isLoading = false;
        }
    }
}