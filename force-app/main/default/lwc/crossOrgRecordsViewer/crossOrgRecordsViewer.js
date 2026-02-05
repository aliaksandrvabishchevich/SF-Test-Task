import { LightningElement, track, api } from 'lwc';
import getRecords from '@salesforce/apex/CrossOrgRecordsController.getRecords';
import getEditFields from '@salesforce/apex/CrossOrgRecordsController.getEditFields';
import getCreateFields from '@salesforce/apex/CrossOrgRecordsController.getCreateFields';
import getRecordForEdit from '@salesforce/apex/CrossOrgRecordsController.getRecordForEdit';
import deleteRecord from '@salesforce/apex/CrossOrgRecordsController.deleteRecord';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CrossOrgRecordModal from 'c/crossOrgRecordModal';

const LIMIT_OPTIONS = [
    { label: '10', value: '10' },
    { label: '25', value: '25' },
    { label: '50', value: '50' },
    { label: '100', value: '100' },
    { label: '200', value: '200' }
];

const SEARCH_DEBOUNCE_MS = 400;
const FETCH_LIMIT = 200;

export default class CrossOrgRecordsViewer extends LightningElement {
    @api objectApiName = 'Account';

    @track tableData = [];
    @track tableColumns = [];
    @track errorMessage = '';
    @track isLoading = false;
    @track hasSearched = false;
    @track currentPage = 1;
    @track pageSize = 25;
    @track sortedBy = '';
    @track sortedDirection = 'asc';

    recordLimitOptions = LIMIT_OPTIONS;

    searchTerm = '';
    _searchTimeout = null;

    connectedCallback() {
        if (this.objectApiName) {
            this.loadRecords();
        }
    }

    get hasData() {
        return this.tableData && this.tableData.length > 0;
    }

    get showSearchOrActions() {
        return this.hasData || this.hasSearched;
    }

    get totalRecords() {
        return this.tableData?.length || 0;
    }

    get totalPages() {
        if (!this.totalRecords || this.pageSize <= 0) return 1;
        return Math.ceil(this.totalRecords / this.pageSize);
    }

    get paginatedData() {
        if (!this.tableData || this.tableData.length === 0) return [];
        const start = (this.currentPage - 1) * this.pageSize;
        return this.tableData.slice(start, start + this.pageSize);
    }

    get displayTableData() {
        const start = (this.currentPage - 1) * this.pageSize;
        return (this.tableData || [])
            .slice(start, start + this.pageSize)
            .map((row, i) => ({ ...row, __rowNum: start + i + 1 }));
    }

    get displayColumns() {
        const rowNumCol = {
            label: '#',
            fieldName: '__rowNum',
            type: 'number',
            sortable: false,
            editable: false,
            cellAttributes: { alignment: 'right' },
            initialWidth: 60
        };
        return [rowNumCol, ...(this.tableColumns || [])];
    }

    get pageStart() {
        return this.totalRecords === 0 ? 0 : (this.currentPage - 1) * this.pageSize + 1;
    }

    get pageEnd() {
        return Math.min(this.currentPage * this.pageSize, this.totalRecords);
    }

    get pageInfoText() {
        if (this.totalRecords === 0) return 'No records';
        return `Page ${this.currentPage} of ${this.totalPages} (${this.pageStart}-${this.pageEnd} of ${this.totalRecords})`;
    }

    get canGoPrev() {
        return this.currentPage > 1;
    }

    get canGoNext() {
        return this.currentPage < this.totalPages;
    }

    get prevDisabled() {
        return !this.canGoPrev;
    }

    get nextDisabled() {
        return !this.canGoNext;
    }

    get pageSizeValue() {
        return String(this.pageSize);
    }

    get hideBuiltInRowNumbers() {
        return false;
    }

    get cardTitle() {
        return (this.objectApiName || 'Records');
    }

    handlePageSizeChange(event) {
        const newSize = parseInt(event.detail.value, 10) || 25;
        if (newSize === this.pageSize) return;
        this.pageSize = newSize;
        const maxPage = Math.max(1, Math.ceil(this.totalRecords / this.pageSize));
        this.currentPage = Math.min(this.currentPage, maxPage);
    }

    handleSearchChange(event) {
        this.searchTerm = event.detail.value || '';
        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }
        this._searchTimeout = setTimeout(() => {
            this.loadRecords();
            this._searchTimeout = null;
        }, SEARCH_DEBOUNCE_MS);
    }

    loadRecords() {
        if (!this.objectApiName) {
            this.errorMessage = 'SObject API name is required.';
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';
        this.hasSearched = true;

        getRecords({
            objectType: this.objectApiName,
            recordLimit: FETCH_LIMIT,
            searchTerm: this.searchTerm || null
        })
            .then((response) => {
                this.isLoading = false;
                if (response.success) {
                    this.tableData = response.records || [];
                    this.tableColumns = this.buildTableColumns(response.columns || []);
                    this.currentPage = 1;
                    this.sortedBy = '';
                    this.sortedDirection = 'asc';
                } else {
                    this.errorMessage = response.errorMessage || 'An error occurred.';
                    this.tableData = [];
                    this.tableColumns = [];
                    this.sortedBy = '';
                    this.sortedDirection = 'asc';
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.errorMessage = error.body?.message || error.message || 'Failed to load records.';
                this.tableData = [];
                this.tableColumns = [];
                this.sortedBy = '';
                this.sortedDirection = 'asc';
            });
    }

    handleFirstPage() {
        this.currentPage = 1;
    }

    handlePrevPage() {
        if (this.canGoPrev) this.currentPage -= 1;
    }

    handleNextPage() {
        if (this.canGoNext) this.currentPage += 1;
    }

    handleLastPage() {
        this.currentPage = this.totalPages;
    }

    handleSort(event) {
        const { fieldName, sortDirection } = event.detail;
        if (!fieldName || !this.tableData || this.tableData.length === 0) return;
        const isAsc = sortDirection === 'asc';
        const sorted = [...this.tableData].sort((a, b) => {
            let aVal = a[fieldName];
            let bVal = b[fieldName];
            const aNull = aVal == null || aVal === '';
            const bNull = bVal == null || bVal === '';
            if (aNull && bNull) return 0;
            if (aNull) return isAsc ? 1 : -1;
            if (bNull) return isAsc ? -1 : 1;
            if (typeof aVal === 'string') aVal = (aVal || '').toLowerCase();
            if (typeof bVal === 'string') bVal = (bVal || '').toLowerCase();
            if (aVal < bVal) return isAsc ? -1 : 1;
            if (aVal > bVal) return isAsc ? 1 : -1;
            return 0;
        });
        this.tableData = sorted;
        this.sortedBy = fieldName;
        this.sortedDirection = sortDirection;
    }

    buildTableColumns(columns) {
        const result = [];
        columns.forEach((col) => {
            const isLink = col.isLink === true;
            if (isLink) {
                result.push({
                    label: col.label,
                    fieldName: col.fieldName,
                    type: 'button',
                    typeAttributes: {
                        label: { fieldName: col.fieldName },
                        variant: 'base',
                        name: 'viewRecord'
                    },
                    cellAttributes: { alignment: 'left' },
                    sortable: col.sortable === true
                });
                return;
            }
            const colType = (col.type || 'text').toLowerCase();
            const isPicklist = colType === 'picklist';
            const colDef = {
                label: col.label,
                fieldName: col.fieldName,
                type: isPicklist ? 'picklist' : colType,
                editable: false,
                sortable: col.sortable === true
            };
            if (isPicklist) {
                colDef.typeAttributes = {
                    options: col.options && col.options.length > 0 ? col.options : [],
                    value: { fieldName: col.fieldName },
                    context: { fieldName: 'Id' },
                    placeholder: 'Select'
                };
            }
            result.push(colDef);
        });
        result.push({
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'Edit', name: 'edit' },
                    { label: 'Delete', name: 'delete' }
                ]
            }
        });
        return result;
    }

    openRecordModal(record, fieldsPromise, lookupLabels) {
        fieldsPromise
            .then((fields) =>
                CrossOrgRecordModal.open({
                    size: 'medium',
                    record: record || {},
                    objectApiName: this.objectApiName,
                    editFields: fields || [],
                    lookupLabels: lookupLabels || {}
                })
            )
            .then((result) => {
                if (result?.saved) this.loadRecords();
            })
            .catch(() => {});
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (!this.objectApiName) {
            this.errorMessage = 'Object type is required.';
            return;
        }

        if (actionName === 'viewRecord' || actionName === 'edit') {
            if (!row?.Id) {
                this.errorMessage = 'Record Id is required to edit.';
                return;
            }
            getRecordForEdit({ objectType: this.objectApiName, recordId: row.Id })
                .then((resp) => {
                    const editFields = Array.isArray(resp.editFields)
                        ? resp.editFields.map((f) => ({ ...f }))
                        : [];
                    this.openRecordModal(resp.record, Promise.resolve(editFields), resp.lookupLabels || {});
                })
                .catch(() => {});
        } else if (actionName === 'delete') {
            if (!row?.Id) {
                this.errorMessage = 'Record Id is required to delete.';
                return;
            }
            this.handleDelete(row.Id);
        }
    }

    handleNewRecord() {
        if (!this.objectApiName) {
            this.errorMessage = 'Object type is required.';
            return;
        }
        this.openRecordModal({}, getCreateFields({ objectType: this.objectApiName }), null);
    }

    handleDelete(recordId) {
        if (!this.objectApiName || !recordId) {
            this.errorMessage = 'Object type and record Id are required.';
            return;
        }
        if (!confirm('Are you sure you want to delete this record in the external org? This cannot be undone.')) {
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        deleteRecord({
            objectType: this.objectApiName,
            recordId: recordId
        })
            .then((response) => {
                this.isLoading = false;
                if (response.success) {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Deleted',
                            message: 'Record deleted in external org.',
                            variant: 'success'
                        })
                    );
                    this.loadRecords();
                } else {
                    this.errorMessage = response.errorMessage || 'Failed to delete.';
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.errorMessage = error.body?.message || error.message || 'Failed to delete.';
            });
    }
}