# Salesforce DX Project: Cross-Org Records & Dashboard

Salesforce project with Cross-Org Records (view/edit/create/delete records in an external org via REST API) and Dashboard Charts. Configuration is driven by custom metadata.

---

## Project Structure

```
force-app/main/default/
├── classes/           # Apex controllers, mocks, tests
├── lwc/                # Lightning Web Components
├── objects/            # Custom metadata type definitions
├── customMetadata/     # Custom metadata records (field lists, picklists)
└── staticresources/    # Chart.js for dashboard
```

---

## Apex Classes

| File | Description |
|------|-------------|
| **CrossOrgRecordsController.cls** | Main controller to load, view, create, update , delete records.
| **CrossOrgRecordsControllerTest.cls** | Unit tests for CrossOrgRecordsController: 
| **CrossOrgHttpCalloutMock.cls** | HTTP callout mock for CrossOrg controller
| **DashboardDataController.cls** | Fetches dashboard/list data from Analytics API via. Transforms single-dashboard response to Chart.js format (charts + dashboardTitle) and list response to dashboards array. Falls back to sample JSON on error or empty/invalid response. |
| **DashboardDataControllerTest.cls** | Unit tests for DashboardDataController: list response, single dashboard, single with factMap rows, HTTP error fallback, callout exception fallback, null/blank endpoint, empty/invalid JSON, root array as dashboard list. |
| **DashboardHttpCalloutMock.cls** | HTTP callout mock for Dashboard controller. Optional status code, body, and throwInRespond for exception-path tests. |

---

## Lightning Web Components (LWC)

| Component | Path | Description |
|-----------|------|-------------|
| **crossOrgRecordsViewer** | `lwc/crossOrgRecordsViewer/` | Table of records from the external org. Object type and columns from metadata. Supports search, sort, open record in modal (view/edit), delete, and “New” to open create modal.|
| **crossOrgRecordModal** | `lwc/crossOrgRecordModal/` | Modal for **edit** or **create**. Edit: loads record via `getRecordForEdit`, tracks initial values, and on Save sends **only changed fields** to `updateRecord`. Create: sends all filled fields to `createRecord`. Supports text, date, picklist, and external lookup (search) fields. Validation for required, email, phone. |
| **dashboardCharts** | `lwc/dashboardCharts/` | Renders dashboard/list from Analytics API. Uses `DashboardDataController.getDashboardChartData` and Chart.js (static resource). Shows dashboard list or chart cards (doughnut/bar) with optional drill-down. |

---

## Custom Metadata Types & Records

### Type Definitions (`objects/`)

| Type | Purpose |
|------|---------|
| **Main_Table_Component__mdt** | Table columns per object: `Object_API_Name__c`, `Field_API_Name__c`, `Field_Label__c`, `Field_Type__c`, `Order__c`, `Is_Link__c`, `Is_Sortable__c`. |
| **Edit_Form_Field_List__mdt** | Edit form fields: `Object_API_Name__c`, `Field_API_Name__c`, `Field_Label__c`, `Field_Type__c`, `Order__c`, `Is_External_Lookup__c`, `Lookup_Object_API_Name__c`. |
| **New_Record_Field_List__mdt** | New-record form fields: same as edit plus `Is_Mandantory__c`. |
| **Picklist_Sync__mdt** | Picklist options per object/field: `Object_API_Name__c`, `Field_API_Name__c`, `Picklist_JSON__c` (array of `{value, label}`). |

### Records (`customMetadata/`)

- **Edit_Form_Field_List.*** — Edit form configs for Account, Lead, Opportunity.
- **Main_Table_Component.*** — Table column configs for Account, Lead, Opportunity.
- **New_Record_Field_List.*** — New-record form configs for Account, Lead, Opportunity.
- **Picklist_Sync.*** — Picklist JSON for Industry, Lead Source, Stage, etc.
- **Sales_Configuration.*** — Optional; deploy only if `Sales_Configuration__mdt` exists in the org.

---

## Static Resources

| Resource | Description |
|----------|-------------|
| **chartjs** | ChartJS library to display dashboards
---

