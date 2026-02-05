public with sharing class CrossOrgRecordsController {
    private static final String NAMED_CREDENTIAL = 'Sales_Credential';
    private static final String API_VERSION = 'v65.0';

    @AuraEnabled(cacheable=false)
    public static CrossOrgRecordsResponse getRecords(String objectType, Integer recordLimit, String searchTerm) {
        CrossOrgRecordsResponse response = new CrossOrgRecordsResponse();
        try {
            List<Main_Table_Component__mdt> tableConfigs = getTableConfigs(objectType);
            if (tableConfigs == null || tableConfigs.isEmpty()) {
                response.success = true;
                response.records = new List<Map<String, Object>>();
                response.columns = new List<ColumnDefinition>();
                return response;
            }

            String soql = buildSoql(objectType, recordLimit, searchTerm, tableConfigs);
            List<Map<String, Object>> rows = queryExternalOrg(soql);

            response.success = true;
            response.records = rows;
            response.columns = buildColumnsFromConfigs(tableConfigs, objectType);
        } catch (CalloutException e) {
            response.success = false;
            response.errorMessage = 'Integration error: ' + e.getMessage();
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    private static List<Main_Table_Component__mdt> getTableConfigs(String objectType) {
        return [
            SELECT Field_API_Name__c, Field_Label__c, Field_Type__c, Order__c, Is_Link__c, Is_Sortable__c
            FROM Main_Table_Component__mdt
            WHERE Object_API_Name__c = :objectType
            ORDER BY Order__c ASC NULLS LAST, Field_API_Name__c ASC
        ];
    }

    private static List<Edit_Form_Field_List__mdt> getEditFormConfigs(String objectType) {
        return [
            SELECT Field_API_Name__c, Field_Label__c, Field_Type__c, Order__c, Is_External_Lookup__c
            FROM Edit_Form_Field_List__mdt
            WHERE Object_API_Name__c = :objectType
            ORDER BY Order__c ASC NULLS LAST, Field_API_Name__c ASC
        ];
    }

    private static List<New_Record_Field_List__mdt> getCreateFormConfigs(String objectType) {
        return [
            SELECT Field_API_Name__c, Field_Label__c, Field_Type__c, Order__c, Is_Mandantory__c, Is_External_Lookup__c
            FROM New_Record_Field_List__mdt
            WHERE Object_API_Name__c = :objectType
            ORDER BY Order__c ASC NULLS LAST, Field_API_Name__c ASC
        ];
    }

    private static String deriveLookupObjectFromFieldName(String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) return '';
        String effectiveField = fieldApiName.trim();
        if (effectiveField.contains('.')) {
            Integer lastDot = effectiveField.lastIndexOf('.');
            effectiveField = effectiveField.substring(lastDot + 1).trim();
        }
        if (String.isBlank(effectiveField)) return '';
        if (effectiveField.endsWithIgnoreCase('Id') && effectiveField.length() > 2) {
            String base = effectiveField.substring(0, effectiveField.length() - 2);
            if ('Owner'.equalsIgnoreCase(base)) return 'User';
            return base;
        }
        return '';
    }

    private static String deriveLookupRelationshipName(String fieldApiName) {
        if (String.isBlank(fieldApiName)) return '';
        if (fieldApiName.endsWith('__c')) return fieldApiName.replace('__c', '__r');
        if ('OwnerId'.equalsIgnoreCase(fieldApiName)) return 'Owner';
        if (fieldApiName.endsWithIgnoreCase('Id') && fieldApiName.length() > 2) {
            return fieldApiName.substring(0, fieldApiName.length() - 2);
        }
        return '';
    }

    private static String buildSoql(String objectType, Integer limitCount, String searchTerm, List<Main_Table_Component__mdt> tableConfigs) {
        Integer maxLimit = (limitCount != null && limitCount > 0 && limitCount <= 200) ? limitCount : 50;
        Set<String> fieldSet = new Set<String>();
        fieldSet.add('Id');
        for (Main_Table_Component__mdt cfg : tableConfigs) {
            if (String.isNotBlank(cfg.Field_API_Name__c) && cfg.Field_API_Name__c != 'Id') {
                fieldSet.add(cfg.Field_API_Name__c);
            }
        }
        List<String> fieldNames = new List<String>(fieldSet);
        String selectList = String.join(fieldNames, ', ');
        String whereClause = '';
        if (String.isNotBlank(searchTerm)) {
            String escaped = searchTerm.replace('\'', '\\\'');
            whereClause = ' WHERE Name LIKE \'%' + escaped + '%\'';
        }
        return 'SELECT ' + selectList + ' FROM ' + objectType + whereClause + ' LIMIT ' + maxLimit;
    }

    private static List<ColumnDefinition> buildColumnsFromConfigs(List<Main_Table_Component__mdt> configs, String objectType) {
        Set<String> picklistFields = new Set<String>();
        for (Main_Table_Component__mdt cfg : configs) {
            if (String.isNotBlank(cfg.Field_API_Name__c) && 'picklist'.equalsIgnoreCase(normalizeFieldType(cfg.Field_Type__c))) {
                picklistFields.add(cfg.Field_API_Name__c);
            }
        }
        Map<String, List<Map<String, String>>> picklistOptionsByField = getPicklistOptionsBulk(objectType, picklistFields);
        List<ColumnDefinition> cols = new List<ColumnDefinition>();
        for (Main_Table_Component__mdt cfg : configs) {
            String fieldName = cfg.Field_API_Name__c;
            if (String.isBlank(fieldName)) continue;
            String label = String.isNotBlank(cfg.Field_Label__c) ? cfg.Field_Label__c : apiNameToLabel(fieldName);
            String dataType = normalizeFieldType(cfg.Field_Type__c);
            List<Map<String, String>> options = picklistOptionsByField.get(fieldName);
            Boolean isLink = cfg.Is_Link__c == true;
            Boolean isSortable = cfg.Is_Sortable__c == true;
            cols.add(new ColumnDefinition(fieldName, label, dataType, options, isLink, isSortable));
        }
        return cols;
    }

    private static List<EditFieldDefinition> buildEditFieldsFromConfigs(List<Edit_Form_Field_List__mdt> configs, String objectType) {
        Set<String> picklistFields = new Set<String>();
        for (Edit_Form_Field_List__mdt cfg : configs) {
            if (String.isNotBlank(cfg.Field_API_Name__c) && 'picklist'.equalsIgnoreCase(normalizeFieldType(cfg.Field_Type__c))) {
                picklistFields.add(cfg.Field_API_Name__c);
            }
        }
        Map<String, List<Map<String, String>>> picklistOptionsByField = getPicklistOptionsBulk(objectType, picklistFields);
        List<EditFieldDefinition> fields = new List<EditFieldDefinition>();
        for (Edit_Form_Field_List__mdt cfg : configs) {
            String fieldName = cfg.Field_API_Name__c;
            if (String.isBlank(fieldName)) continue;
            String label = String.isNotBlank(cfg.Field_Label__c) ? cfg.Field_Label__c : apiNameToLabel(fieldName);
            String dataType = normalizeFieldType(cfg.Field_Type__c);
            List<Map<String, String>> options = picklistOptionsByField.get(fieldName);
            Boolean isExternalLookup = (cfg.Is_External_Lookup__c == true);
            String lookupObjectApiName = isExternalLookup ? deriveLookupObjectFromFieldName(objectType, fieldName) : '';
            fields.add(new EditFieldDefinition(fieldName, label, dataType, options, false, isExternalLookup, lookupObjectApiName));
        }
        return fields;
    }

    private static List<EditFieldDefinition> buildEditFieldsFromConfigs(List<New_Record_Field_List__mdt> configs, String objectType) {
        Set<String> picklistFields = new Set<String>();
        for (New_Record_Field_List__mdt cfg : configs) {
            if (String.isNotBlank(cfg.Field_API_Name__c) && 'picklist'.equalsIgnoreCase(normalizeFieldType(cfg.Field_Type__c))) {
                picklistFields.add(cfg.Field_API_Name__c);
            }
        }
        Map<String, List<Map<String, String>>> picklistOptionsByField = getPicklistOptionsBulk(objectType, picklistFields);
        List<EditFieldDefinition> fields = new List<EditFieldDefinition>();
        for (New_Record_Field_List__mdt cfg : configs) {
            String fieldName = cfg.Field_API_Name__c;
            if (String.isBlank(fieldName)) continue;
            String label = String.isNotBlank(cfg.Field_Label__c) ? cfg.Field_Label__c : apiNameToLabel(fieldName);
            String dataType = normalizeFieldType(cfg.Field_Type__c);
            List<Map<String, String>> options = picklistOptionsByField.get(fieldName);
            Boolean required = (cfg.Is_Mandantory__c == true);
            Boolean isExternalLookup = (cfg.Is_External_Lookup__c == true);
            String lookupObjectApiName = isExternalLookup ? deriveLookupObjectFromFieldName(objectType, fieldName) : '';
            fields.add(new EditFieldDefinition(fieldName, label, dataType, options, required, isExternalLookup, lookupObjectApiName));
        }
        return fields;
    }

    private static String normalizeFieldType(String fieldType) {
        if (String.isBlank(fieldType)) return 'text';
        String t = fieldType.trim().toLowerCase();
        if (t == 'text' || t == 'string') return 'text';
        if (t == 'number' || t == 'integer' || t == 'double') return 'number';
        if (t == 'date') return 'date';
        if (t == 'datetime') return 'datetime';
        if (t == 'currency') return 'currency';
        if (t == 'phone') return 'phone';
        if (t == 'email') return 'email';
        if (t == 'picklist') return 'picklist';
        if (t == 'boolean' || t == 'checkbox') return 'checkbox';
        return 'text';
    }

    /** Bulk load picklist options for multiple fields in one SOQL query. */
    private static Map<String, List<Map<String, String>>> getPicklistOptionsBulk(String objectType, Set<String> fieldApiNames) {
        Map<String, List<Map<String, String>>> result = new Map<String, List<Map<String, String>>>();
        if (fieldApiNames == null || fieldApiNames.isEmpty()) return result;
        Set<String> keys = new Set<String>();
        for (String fieldName : fieldApiNames) {
            if (String.isNotBlank(fieldName)) keys.add(objectType + '_' + fieldName);
        }
        if (keys.isEmpty()) return result;
        List<Picklist_Sync__mdt> syncs = [
            SELECT DeveloperName, Picklist_JSON__c
            FROM Picklist_Sync__mdt
            WHERE DeveloperName IN :keys
        ];
        String prefix = objectType + '_';
        for (Picklist_Sync__mdt sync : syncs) {
            String devName = sync.DeveloperName;
            if (String.isBlank(devName) || !devName.startsWith(prefix)) continue;
            String fieldName = devName.substring(prefix.length());
            List<Map<String, String>> options = new List<Map<String, String>>();
            if (String.isNotBlank(sync.Picklist_JSON__c)) {
                try {
                    List<Object> arr = (List<Object>) JSON.deserializeUntyped(sync.Picklist_JSON__c);
                    for (Object item : arr) {
                        Map<String, Object> m = (Map<String, Object>) item;
                        Map<String, String> opt = new Map<String, String>();
                        if (m.containsKey('label')) opt.put('label', String.valueOf(m.get('label')));
                        if (m.containsKey('value')) opt.put('value', String.valueOf(m.get('value')));
                        if (!opt.isEmpty()) options.add(opt);
                    }
                } catch (Exception e) { /* leave options empty */ }
            }
            result.put(fieldName, options);
        }
        return result;
    }

    private static String apiNameToLabel(String apiName) {
        if (String.isBlank(apiName)) return apiName;
        String result = '';
        for (Integer i = 0; i < apiName.length(); i++) {
            String c = apiName.substring(i, i + 1);
            if (c == c.toUpperCase() && i > 0 && result.length() > 0) {
                result += ' ';
            }
            result += (i == 0 ? c.toUpperCase() : c);
        }
        return result;
    }

    private static List<Map<String, Object>> queryExternalOrg(String soql) {
        String endpoint = 'callout:' + NAMED_CREDENTIAL + '/services/data/' + API_VERSION + '/query?q='
            + EncodingUtil.urlEncode(soql, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setHeader('Content-Type', 'application/json');
        req.setTimeout(120000);

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() != 200) {
            throw new AuraHandledException('External org returned ' + res.getStatusCode() + ': ' + res.getStatus());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) body.get('records');
        List<Map<String, Object>> rows = new List<Map<String, Object>>();

        if (records != null) {
            for (Object rec : records) {
                Map<String, Object> recordMap = (Map<String, Object>) rec;
                Map<String, Object> row = new Map<String, Object>();
                for (String key : recordMap.keySet()) {
                    if (key.equals('attributes')) continue;
                    Object val = recordMap.get(key);
                    if (val instanceof Map<String, Object>) {
                        flattenRelationshipIntoRow(row, (Map<String, Object>) val, key);
                    } else {
                        row.put(key, val);
                    }
                }
                rows.add(row);
            }
        }
        return rows;
    }

    private static void flattenRelationshipIntoRow(Map<String, Object> row, Map<String, Object> nested, String prefix) {
        if (nested == null) return;
        for (String key : nested.keySet()) {
            if (key.equals('attributes')) continue;
            Object val = nested.get(key);
            String flatKey = prefix + '.' + key;
            if (val instanceof Map<String, Object>) {
                flattenRelationshipIntoRow(row, (Map<String, Object>) val, flatKey);
            } else {
                row.put(flatKey, val);
            }
        }
    }

    @AuraEnabled(cacheable=false)
    public static CrossOrgSaveResponse updateRecord(String objectType, String recordId, String recordDataJson) {
        CrossOrgSaveResponse response = new CrossOrgSaveResponse();
        try {
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/services/data/' + API_VERSION + '/sobjects/'
                + objectType + '/' + recordId;
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('PATCH');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(recordDataJson);
            req.setTimeout(120000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                response.success = true;
            } else {
                response.success = false;
                response.errorMessage = res.getStatusCode() + ': ' + res.getStatus();
                if (String.isNotBlank(res.getBody())) {
                    String msg = parseErrorMessage(res.getBody());
                    if (String.isNotBlank(msg)) response.errorMessage = msg;
                }
            }
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    private static String parseErrorMessage(String body) {
        try {
            Object parsed = JSON.deserializeUntyped(body);
            if (parsed instanceof Map<String, Object>) {
                Map<String, Object> m = (Map<String, Object>) parsed;
                if (m.containsKey('message')) return String.valueOf(m.get('message'));
            } else if (parsed instanceof List<Object>) {
                List<Object> listVal = (List<Object>) parsed;
                if (!listVal.isEmpty() && listVal[0] instanceof Map<String, Object>) {
                    Map<String, Object> first = (Map<String, Object>) listVal[0];
                    if (first.containsKey('message')) return String.valueOf(first.get('message'));
                }
            }
        } catch (Exception e) { }
        return null;
    }

    @AuraEnabled(cacheable=false)
    public static CrossOrgSaveResponse deleteRecord(String objectType, String recordId) {
        CrossOrgSaveResponse response = new CrossOrgSaveResponse();
        try {
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/services/data/' + API_VERSION + '/sobjects/'
                + objectType + '/' + recordId;
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('DELETE');
            req.setTimeout(120000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                response.success = true;
            } else {
                response.success = false;
                response.errorMessage = res.getStatusCode() + ': ' + res.getStatus();
            }
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled(cacheable=false)
    public static CrossOrgSaveResponse createRecord(String objectType, String recordDataJson) {
        CrossOrgSaveResponse response = new CrossOrgSaveResponse();
        try {
            String endpoint = 'callout:' + NAMED_CREDENTIAL + '/services/data/' + API_VERSION + '/sobjects/'
                + objectType;
            HttpRequest req = new HttpRequest();
            req.setEndpoint(endpoint);
            req.setMethod('POST');
            req.setHeader('Content-Type', 'application/json');
            req.setBody(recordDataJson);
            req.setTimeout(120000);
            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
                response.success = true;
            } else {
                response.success = false;
                response.errorMessage = res.getStatusCode() + ': ' + res.getStatus();
                if (String.isNotBlank(res.getBody())) {
                    String msg = parseErrorMessage(res.getBody());
                    if (String.isNotBlank(msg)) response.errorMessage = msg;
                }
            }
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
        }
        return response;
    }

    @AuraEnabled(cacheable=false)
    public static List<Map<String, String>> searchExternalRecords(String objectApiName, String searchTerm, Integer maxResults) {
        try {
            if (String.isBlank(objectApiName)) {
                return new List<Map<String, String>>();
            }
            String safeObject = objectApiName.trim();
            Integer limitVal = (maxResults != null && maxResults > 0 && maxResults <= 100) ? maxResults : 50;
            String term = String.isNotBlank(searchTerm) ? searchTerm.trim() : '';
            String whereClause = String.isNotBlank(term)
                ? ' WHERE Name LIKE \'%' + term.replace('\'', '\\\'') + '%\''
                : '';
            String soql = 'SELECT Id, Name FROM ' + safeObject + whereClause + ' ORDER BY Name LIMIT ' + limitVal;
            List<Map<String, Object>> rows = queryExternalOrg(soql);
            List<Map<String, String>> options = new List<Map<String, String>>();
            for (Map<String, Object> row : rows) {
                Map<String, String> opt = new Map<String, String>();
                Object idVal = row.get('Id');
                Object nameVal = row.get('Name');
                opt.put('value', idVal != null ? String.valueOf(idVal) : '');
                opt.put('label', nameVal != null ? String.valueOf(nameVal) : '');
                if (String.isNotBlank(opt.get('value'))) options.add(opt);
            }
            return options;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to search records: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<EditFieldDefinition> getCreateFields(String objectType) {
        try {
            return buildEditFieldsFromConfigs(getCreateFormConfigs(objectType), objectType);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load create form fields: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static List<EditFieldDefinition> getEditFields(String objectType) {
        try {
            return buildEditFieldsFromConfigs(getEditFormConfigs(objectType), objectType);
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load edit form fields: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static RecordForEditResponse getRecordForEdit(String objectType, String recordId) {
        try {
            List<Edit_Form_Field_List__mdt> configs = getEditFormConfigs(objectType);
            Set<String> selectFields = new Set<String>();
            selectFields.add('Id');
            Map<String, String> lookupRelationByField = new Map<String, String>();
            for (Edit_Form_Field_List__mdt cfg : configs) {
                if (String.isNotBlank(cfg.Field_API_Name__c)) {
                    selectFields.add(cfg.Field_API_Name__c);
                }
                if (cfg.Is_External_Lookup__c == true && String.isNotBlank(cfg.Field_API_Name__c)) {
                    String relName = deriveLookupRelationshipName(cfg.Field_API_Name__c);
                    if (String.isNotBlank(relName)) {
                        lookupRelationByField.put(cfg.Field_API_Name__c, relName);
                        selectFields.add(relName + '.Name');
                    }
                }
            }
            String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ') + ' FROM ' + objectType
                + ' WHERE Id = \'' + String.escapeSingleQuotes(recordId) + '\' LIMIT 1';
            List<Map<String, Object>> rows = queryExternalOrg(soql);
            if (rows.isEmpty()) {
                throw new AuraHandledException('Record not found.');
            }
            Map<String, Object> record = rows[0];
            Map<String, String> lookupLabels = new Map<String, String>();
            for (String fieldName : lookupRelationByField.keySet()) {
                String relName = lookupRelationByField.get(fieldName);
                String nameKey = relName + '.Name';
                Object nameVal = record.get(nameKey);
                lookupLabels.put(fieldName, nameVal != null ? String.valueOf(nameVal) : '');
            }
            RecordForEditResponse resp = new RecordForEditResponse();
            resp.record = record;
            resp.editFields = buildEditFieldsFromConfigs(configs, objectType);
            resp.lookupLabels = lookupLabels;
            return resp;
        } catch (Exception e) {
            throw new AuraHandledException('Failed to load record for edit: ' + e.getMessage());
        }
    }

    public class RecordForEditResponse {
        @AuraEnabled public Map<String, Object> record;
        @AuraEnabled public List<EditFieldDefinition> editFields;
        @AuraEnabled public Map<String, String> lookupLabels;
    }

    public class EditFieldDefinition {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public List<Map<String, String>> options;
        @AuraEnabled public Boolean required;
        @AuraEnabled public Boolean isExternalLookup;
        @AuraEnabled public String lookupObjectApiName;
        public EditFieldDefinition(String fieldName, String label, String type, List<Map<String, String>> options, Boolean required) {
            this.fieldName = fieldName;
            this.label = label;
            this.type = type;
            this.options = options;
            this.required = (required == true);
            this.isExternalLookup = false;
            this.lookupObjectApiName = '';
        }
        public EditFieldDefinition(String fieldName, String label, String type, List<Map<String, String>> options, Boolean required, Boolean isExternalLookup, String lookupObjectApiName) {
            this.fieldName = fieldName;
            this.label = label;
            this.type = type;
            this.options = options;
            this.required = (required == true);
            this.isExternalLookup = (isExternalLookup == true);
            this.lookupObjectApiName = (lookupObjectApiName != null && lookupObjectApiName.trim().length() > 0) ? lookupObjectApiName.trim() : '';
        }
    }

    public class CrossOrgSaveResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
    }

    public class CrossOrgRecordsResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public List<Map<String, Object>> records;
        @AuraEnabled public List<ColumnDefinition> columns;
    }

    public class ColumnDefinition {
        @AuraEnabled public String fieldName;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public List<Map<String, String>> options;
        @AuraEnabled public Boolean isLink;
        @AuraEnabled public Boolean sortable;

        public ColumnDefinition(String fieldName, String label, String type, List<Map<String, String>> options, Boolean isLink, Boolean sortable) {
            this.fieldName = fieldName;
            this.label = label;
            this.type = type;
            this.options = options;
            this.isLink = isLink;
            this.sortable = sortable;
        }
    }
}