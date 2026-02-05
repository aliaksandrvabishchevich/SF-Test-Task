import LightningModal from 'lightning/modal';
import { api, track } from 'lwc';
import updateRecord from '@salesforce/apex/CrossOrgRecordsController.updateRecord';
import createRecord from '@salesforce/apex/CrossOrgRecordsController.createRecord';
import searchExternalRecords from '@salesforce/apex/CrossOrgRecordsController.searchExternalRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const EXTERNAL_LOOKUP_SEARCH_DEBOUNCE_MS = 350;
const EXTERNAL_LOOKUP_MAX_RESULTS = 50;

const EMAIL_REGEX = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;

function isValidEmail(s) {
    if (s == null || String(s).trim() === '') return true;
    return EMAIL_REGEX.test(String(s).trim());
}

function isValidPhone(s) {
    if (s == null || String(s).trim() === '') return true;
    const digitsOnly = String(s).replace(/\D/g, '');
    return digitsOnly.length >= 10;
}

/** Lookup object: from server when set, else derived from Object API Name.Field API Name or just Field API Name. */
/** Normalize value for change detection (trim, empty string vs null, date to YYYY-MM-DD). */
function normalizedValue(val) {
    if (val == null) return '';
    if (typeof val === 'object' && val.hasOwnProperty?.('value')) return normalizedValue(val.value);
    const s = String(val).trim();
    if (!s) return '';
    const d = new Date(s);
    if (!isNaN(d.getTime())) return d.toISOString().slice(0, 10);
    return s;
}

function getLookupObjectForField(fieldDef) {
    if (!fieldDef) return '';
    const fromServer =
        fieldDef.lookupObjectApiName != null
            ? String(fieldDef.lookupObjectApiName).trim()
            : (fieldDef.LookupObjectApiName != null ? String(fieldDef.LookupObjectApiName).trim() : '');
    if (fromServer) return fromServer;
    let name = (fieldDef.fieldName || fieldDef.FieldName || '').trim();
    if (name.includes('.')) name = name.slice(name.lastIndexOf('.') + 1).trim();
    if (name.length > 2 && name.toLowerCase().endsWith('id')) {
        const base = name.slice(0, -2);
        if (base.toLowerCase() === 'owner') return 'User';
        return base;
    }
    return '';
}

export default class CrossOrgRecordModal extends LightningModal {
    @api record = {};
    @api objectApiName = '';
    @api editFields = [];
    @api lookupLabels = {};

    @track recordData = {};
    @track saveLoading = false;
    @track errorMessage = '';
    @track externalLookupOptionsMap = {};
    @track externalLookupSearchTerm = {};
    @track externalLookupDisplayMap = {};
    @track externalLookupDropdownOpen = {};
    _externalSearchTimeouts = {};
    /** Snapshot of initial record values for edit mode (used to detect changed fields only). */
    _initialRecordValues = {};

    connectedCallback() {
        this.recordData = this.record && typeof this.record === 'object' ? { ...this.record } : {};
        // Prepopulate external lookup display with existing values when opening for edit
        const labels = this.lookupLabels && typeof this.lookupLabels === 'object' ? this.lookupLabels : {};
        if (Object.keys(labels).length > 0) {
            this.externalLookupDisplayMap = { ...this.externalLookupDisplayMap, ...labels };
        }
        // Store initial values so we can send only changed fields on update
        if (this.record && typeof this.record === 'object') {
            this._initialRecordValues = { ...this.record };
        }
    }

    get isEditMode() {
        return !!(this.record && this.record.Id);
    }

    get modalTitle() {
        if (this.isEditMode) {
            const name = this.recordData?.Name || this.record?.Name || 'Record';
            return `${name}`;
        }
        return `New ${this.objectApiName || 'Record'}`;
    }

    get fieldsWithValues() {
        const fields = this.editFields || [];
        return fields.map((f) => {
            const fieldName = f.fieldName || f.FieldName || '';
            let val = this.recordData[fieldName];
            if (val != null && typeof val === 'object' && val.hasOwnProperty?.('value')) {
                val = val.value;
            }
            if (f.type === 'date' && val) {
                try {
                    const d = new Date(val);
                    if (!isNaN(d.getTime())) val = d.toISOString().slice(0, 10);
                } catch (e) {}
            }
            const isPicklist = (f.type || '').toLowerCase() === 'picklist' && f.options && f.options.length > 0;
            const isExternalLookup = f.isExternalLookup === true || f.IsExternalLookup === true;
            const rawType = (f.type || 'text').toLowerCase();
            const inputType = rawType === 'phone' ? 'tel' : (rawType === 'email' ? 'email' : rawType);
            const required = f.required === true;
            const externalOptions = this.externalLookupOptionsMap[fieldName] || [];
            const hasSelection = val != null && val !== '';
            const displayVal = hasSelection && this.externalLookupDisplayMap[fieldName]
                ? this.externalLookupDisplayMap[fieldName]
                : (this.externalLookupSearchTerm[fieldName] || '');
            const dropdownOpen = this.externalLookupDropdownOpen[fieldName] === true;
            const lookupObj = getLookupObjectForField(f);
            const externalLookupPlaceholder = lookupObj ? `Type to search ${lookupObj} by name...` : 'Type to search by name...';
            return { ...f, fieldName, value: val == null ? '' : String(val), isPicklist, isExternalLookup, inputType, required, externalOptions, externalLookupInputValue: displayVal, externalLookupDropdownOpen: dropdownOpen, externalLookupHasSelection: hasSelection, externalLookupPlaceholder };
        });
    }

    get fieldsLeft() {
        const all = this.fieldsWithValues;
        const mid = Math.ceil(all.length / 2);
        return all.slice(0, mid);
    }

    get fieldsRight() {
        const all = this.fieldsWithValues;
        const mid = Math.ceil(all.length / 2);
        return all.slice(mid);
    }

    handleFieldChange(event) {
        const fieldName = event.target.dataset.field;
        const value = event.detail.value;
        this.recordData = { ...this.recordData, [fieldName]: value };
    }

    handleExternalLookupInput(event) {
        const fieldName = event.target.dataset.field;
        const searchTerm = (event.target.value || '').trim();
        this.externalLookupSearchTerm = { ...this.externalLookupSearchTerm, [fieldName]: event.target.value || '' };
        this.recordData = { ...this.recordData, [fieldName]: '' };
        this.externalLookupDisplayMap = { ...this.externalLookupDisplayMap, [fieldName]: '' };
        this.externalLookupDropdownOpen = { ...this.externalLookupDropdownOpen, [fieldName]: true };
        if (this._externalSearchTimeouts[fieldName]) clearTimeout(this._externalSearchTimeouts[fieldName]);
        this._externalSearchTimeouts[fieldName] = setTimeout(() => {
            const fieldDef = (this.editFields || []).find(
                (f) => (f.fieldName || f.FieldName) === fieldName
            );
            const objectApiName = getLookupObjectForField(fieldDef);
            if (!objectApiName) {
                this.externalLookupOptionsMap = { ...this.externalLookupOptionsMap, [fieldName]: [] };
                return;
            }
            searchExternalRecords({ objectApiName, searchTerm, maxResults: EXTERNAL_LOOKUP_MAX_RESULTS })
                .then((options) => {
                    this.externalLookupOptionsMap = { ...this.externalLookupOptionsMap, [fieldName]: options || [] };
                })
                .catch(() => {});
        }, EXTERNAL_LOOKUP_SEARCH_DEBOUNCE_MS);
    }

    handleExternalLookupSelect(event) {
        const fieldName = event.currentTarget.dataset.field;
        const value = event.currentTarget.dataset.value;
        const label = event.currentTarget.dataset.label || value;
        this.recordData = { ...this.recordData, [fieldName]: value };
        this.externalLookupDisplayMap = { ...this.externalLookupDisplayMap, [fieldName]: label };
        this.externalLookupSearchTerm = { ...this.externalLookupSearchTerm, [fieldName]: '' };
        this.externalLookupDropdownOpen = { ...this.externalLookupDropdownOpen, [fieldName]: false };
        this.externalLookupOptionsMap = { ...this.externalLookupOptionsMap, [fieldName]: [] };
        const input = this.template.querySelector(`lightning-input[data-field="${fieldName}"]`);
        if (input && input.setCustomValidity) input.setCustomValidity('');
    }

    handleExternalLookupFocus() {
        // Keep dropdown open when focusing (already open if there are results)
    }

    handleExternalLookupBlur(event) {
        const fieldName = event.target.dataset.field;
        setTimeout(() => {
            this.externalLookupDropdownOpen = { ...this.externalLookupDropdownOpen, [fieldName]: false };
        }, 200);
    }

    handleExternalLookupClear(event) {
        const fieldName = event.currentTarget.dataset.field;
        this.recordData = { ...this.recordData, [fieldName]: '' };
        this.externalLookupDisplayMap = { ...this.externalLookupDisplayMap, [fieldName]: '' };
        this.externalLookupSearchTerm = { ...this.externalLookupSearchTerm, [fieldName]: '' };
        this.externalLookupDropdownOpen = { ...this.externalLookupDropdownOpen, [fieldName]: false };
        this.externalLookupOptionsMap = { ...this.externalLookupOptionsMap, [fieldName]: [] };
    }

    handleCancel() {
        this.close();
    }

    handleSave() {
        this.errorMessage = '';

        if (!this.objectApiName || String(this.objectApiName).trim() === '') {
            this.errorMessage = 'Object type is required.';
            return;
        }

        if (this.isEditMode && (!this.record?.Id || String(this.record.Id).trim() === '')) {
            this.errorMessage = 'Record Id is required to update.';
            return;
        }

        const externalLookupFields = (this.editFields || []).filter(
            (f) => f.isExternalLookup === true || f.IsExternalLookup === true
        );
        externalLookupFields.forEach((f) => {
            const fn = f.fieldName || f.FieldName || '';
            const input = this.template.querySelector(`lightning-input[data-field="${fn}"]`);
            if (input && input.setCustomValidity) input.setCustomValidity('');
        });
        let allValid = true;
        const inputs = this.template.querySelectorAll('lightning-input');
        inputs.forEach((input) => {
            if (input.reportValidity && !input.reportValidity()) allValid = false;
        });
        const comboboxes = this.template.querySelectorAll('lightning-combobox');
        comboboxes.forEach((cb) => {
            if (cb.reportValidity && !cb.reportValidity()) allValid = false;
        });
        const externalRequired = (this.editFields || []).filter(
            (f) => (f.isExternalLookup === true || f.IsExternalLookup === true) && f.required
        );
        externalRequired.forEach((f) => {
            const fn = f.fieldName || f.FieldName || '';
            if (!this.recordData[fn]) {
                const input = this.template.querySelector(`lightning-input[data-field="${fn}"]`);
                if (input) {
                    if (input.setCustomValidity) input.setCustomValidity('This field is required.');
                    if (input.reportValidity && !input.reportValidity()) allValid = false;
                }
            }
        });

        const editFieldsList = this.editFields || [];
        for (const f of editFieldsList) {
            const fn = f.fieldName || f.FieldName || '';
            const rawType = (f.type || 'text').toLowerCase();
            const val = this.recordData[fn];
            if (val == null || String(val).trim() === '') continue;
            const strVal = String(val).trim();
            if (rawType === 'email' && !isValidEmail(strVal)) {
                const label = f.label || fn;
                this.errorMessage = `Invalid email format for ${label}.`;
                allValid = false;
                break;
            }
            if (rawType === 'phone' && !isValidPhone(strVal)) {
                const label = f.label || fn;
                this.errorMessage = `Invalid phone format for ${label}.`;
                allValid = false;
                break;
            }
        }

        if (!allValid) {
            this.errorMessage = this.errorMessage || 'Please fix validation errors before saving.';
            return;
        }

        const payload = {};
        editFieldsList.forEach((f) => {
            const fn = f.fieldName || f.FieldName || '';
            const currentVal = this.recordData[fn];
            if (this.isEditMode) {
                const initialVal = this._initialRecordValues[fn];
                if (normalizedValue(currentVal) !== normalizedValue(initialVal)) {
                    payload[fn] = currentVal !== undefined && currentVal !== null ? currentVal : '';
                }
            } else {
                if (currentVal !== undefined && currentVal !== null && currentVal !== '') {
                    payload[fn] = currentVal;
                }
            }
        });

        if (this.isEditMode && Object.keys(payload).length === 0) {
            this.errorMessage = 'No fields were changed.';
            return;
        }

        this.saveLoading = true;
        this.errorMessage = '';

        if (this.isEditMode) {
            updateRecord({
                objectType: this.objectApiName,
                recordId: this.record.Id,
                recordDataJson: JSON.stringify(payload)
            })
                .then((response) => this.handleSaveResponse(response, 'Saved', 'Record updated in external org.', 'Failed to save.'))
                .catch((error) => {
                    this.saveLoading = false;
                    this.errorMessage = error.body?.message || error.message || 'Failed to save.';
                });
        } else {
            createRecord({
                objectType: this.objectApiName,
                recordDataJson: JSON.stringify(payload)
            })
                .then((response) => this.handleSaveResponse(response, 'Created', 'Record created in external org.', 'Failed to create.'))
                .catch((error) => {
                    this.saveLoading = false;
                    this.errorMessage = error.body?.message || error.message || 'Failed to create.';
                });
        }
    }

    handleSaveResponse(response, title, successMessage, failMessage) {
        this.saveLoading = false;
        if (response.success) {
            this.dispatchEvent(new ShowToastEvent({ title, message: successMessage, variant: 'success' }));
            this.close({ saved: true });
        } else {
            this.errorMessage = response.errorMessage || failMessage;
        }
    }
}