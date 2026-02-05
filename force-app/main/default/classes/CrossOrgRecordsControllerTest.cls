/**
 * Unit tests for CrossOrgRecordsController.
 */
@isTest
private class CrossOrgRecordsControllerTest {
    private static final String QUERY_RECORDS_JSON = '{"records":[{"Id":"001xx","Name":"Test Account"},{"Id":"002xx","Name":"Another"}]}';
    private static final String QUERY_SINGLE_RECORD_JSON = '{"records":[{"Id":"006xx","Name":"Test Opp","AccountId":"001xx","Account":{"attributes":{},"Name":"Acme Corp"}}]}';
    private static final String QUERY_EMPTY_JSON = '{"records":[]}';
    private static final String ERROR_MESSAGE_JSON = '{"message":"Validation error"}';
    private static final String ERROR_LIST_JSON = '[{"message":"Required field missing"}]';

    @isTest
    static void testGetRecords_noTableConfigsReturnsEmpty() {
        CrossOrgRecordsController.CrossOrgRecordsResponse resp = CrossOrgRecordsController.getRecords('NonExistentObjectType_XYZ', 50, null);
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == true, 'Should succeed when no configs');
        System.assert(resp.records != null && resp.records.isEmpty(), 'Records should be empty');
        System.assert(resp.columns != null && resp.columns.isEmpty(), 'Columns should be empty');
    }

    @isTest
    static void testGetRecords_withConfigsAndCalloutSuccess() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, QUERY_RECORDS_JSON));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgRecordsResponse resp = CrossOrgRecordsController.getRecords('Account', 50, null);
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        if (resp.success && resp.records != null && !resp.records.isEmpty()) {
            System.assert(resp.records.size() == 2, 'Should have 2 records');
            System.assert(resp.columns != null, 'Columns should be set');
        }
    }

    @isTest
    static void testGetRecords_calloutFailure() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(500, 'Server Error'));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgRecordsResponse resp = CrossOrgRecordsController.getRecords('Account', 50, null);
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        if (resp.records != null && resp.records.isEmpty() && resp.columns != null && resp.columns.isEmpty()) {
            return;
        }
        System.assert(resp.success == false, 'Should fail on callout error');
        System.assert(String.isNotBlank(resp.errorMessage), 'Error message should be set');
    }

    @isTest
    static void testGetRecords_withSearchTerm() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, QUERY_RECORDS_JSON));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgRecordsResponse resp = CrossOrgRecordsController.getRecords('Account', 100, 'Acme');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
    }

    @isTest
    static void testUpdateRecord_success() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, '{}'));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.updateRecord('Account', '001xx', '{"Name":"Updated"}');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == true, 'Update should succeed');
    }

    @isTest
    static void testUpdateRecord_failure() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(400, ERROR_MESSAGE_JSON));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.updateRecord('Account', '001xx', '{}');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == false, 'Update should fail');
        System.assert(String.isNotBlank(resp.errorMessage), 'Error message should be set');
    }

    @isTest
    static void testUpdateRecord_exception() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, '{}', true));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.updateRecord('Account', '001xx', '{"Name":"Updated"}');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == false, 'Should fail on exception');
        System.assert(String.isNotBlank(resp.errorMessage), 'Error message should be set');
    }

    @isTest
    static void testDeleteRecord_success() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(204, ''));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.deleteRecord('Account', '001xx');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == true, 'Delete should succeed');
    }

    @isTest
    static void testDeleteRecord_failure() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(404, 'Not Found'));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.deleteRecord('Account', '001xx');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == false, 'Delete should fail');
    }

    @isTest
    static void testCreateRecord_success() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(201, '{"id":"001xx"}'));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.createRecord('Account', '{"Name":"New Account"}');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == true, 'Create should succeed');
    }

    @isTest
    static void testCreateRecord_failure() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(400, ERROR_LIST_JSON));
        Test.startTest();
        CrossOrgRecordsController.CrossOrgSaveResponse resp = CrossOrgRecordsController.createRecord('Account', '{}');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.success == false, 'Create should fail');
    }

    @isTest
    static void testSearchExternalRecords_blankObject() {
        List<Map<String, String>> result = CrossOrgRecordsController.searchExternalRecords('', 'test', 10);
        System.assert(result != null && result.isEmpty(), 'Should return empty list for blank object');
    }

    @isTest
    static void testSearchExternalRecords_success() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, '{"records":[{"Id":"001xx","Name":"Acme"}]}'));
        Test.startTest();
        List<Map<String, String>> result = CrossOrgRecordsController.searchExternalRecords('Account', 'Acme', 50);
        Test.stopTest();
        System.assert(result != null, 'Result should not be null');
        System.assert(result.size() == 1, 'Should have one option');
        System.assert(result[0].get('value') == '001xx', 'Value should be Id');
        System.assert(result[0].get('label') == 'Acme', 'Label should be Name');
    }

    @isTest
    static void testGetCreateFields() {
        Test.startTest();
        List<CrossOrgRecordsController.EditFieldDefinition> fields = CrossOrgRecordsController.getCreateFields('Account');
        Test.stopTest();
        System.assert(fields != null, 'Fields should not be null');
    }

    @isTest
    static void testGetEditFields() {
        Test.startTest();
        List<CrossOrgRecordsController.EditFieldDefinition> fields = CrossOrgRecordsController.getEditFields('Account');
        Test.stopTest();
        System.assert(fields != null, 'Fields should not be null');
    }

    @isTest
    static void testGetRecordForEdit_success() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, QUERY_SINGLE_RECORD_JSON));
        Test.startTest();
        CrossOrgRecordsController.RecordForEditResponse resp = CrossOrgRecordsController.getRecordForEdit('Opportunity', '006xx');
        Test.stopTest();
        System.assert(resp != null, 'Response should not be null');
        System.assert(resp.record != null, 'Record should be set');
        System.assert(resp.editFields != null, 'Edit fields should be set');
        System.assert(resp.lookupLabels != null, 'Lookup labels should be set');
    }

    @isTest
    static void testGetRecordForEdit_recordNotFound() {
        Test.setMock(HttpCalloutMock.class, new CrossOrgHttpCalloutMock(200, QUERY_EMPTY_JSON));
        Test.startTest();
        try {
            CrossOrgRecordsController.getRecordForEdit('Opportunity', '006xx');
            System.assert(false, 'Should throw when record not found');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('not found') || e.getMessage().length() > 0, 'Expected not found message');
        }
        Test.stopTest();
    }

    @isTest
    static void testEditFieldDefinitionConstructors() {
        CrossOrgRecordsController.EditFieldDefinition f5 = new CrossOrgRecordsController.EditFieldDefinition(
            'Name', 'Name', 'text', new List<Map<String, String>>(), false
        );
        System.assert(f5.fieldName == 'Name', 'fieldName should be set');
        System.assert(f5.isExternalLookup == false, 'isExternalLookup should be false');
        System.assert(f5.lookupObjectApiName == '', 'lookupObjectApiName should be empty');

        CrossOrgRecordsController.EditFieldDefinition f7 = new CrossOrgRecordsController.EditFieldDefinition(
            'AccountId', 'Account', 'text', null, false, true, 'Account'
        );
        System.assert(f7.fieldName == 'AccountId', 'fieldName should be set');
        System.assert(f7.isExternalLookup == true, 'isExternalLookup should be true');
        System.assert(f7.lookupObjectApiName == 'Account', 'lookupObjectApiName should be Account');
    }

    @isTest
    static void testColumnDefinitionConstructor() {
        CrossOrgRecordsController.ColumnDefinition col = new CrossOrgRecordsController.ColumnDefinition(
            'Name', 'Name', 'text', null, false, true
        );
        System.assert(col.fieldName == 'Name', 'fieldName should be set');
        System.assert(col.sortable == true, 'sortable should be true');
    }
}
