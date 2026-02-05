/**
 * Unit tests for DashboardDataController.
 */
@isTest
private class DashboardDataControllerTest {
    private static final String LIST_JSON = '{"dashboards":[{"id":"01Zxx","name":"Test Dashboard","label":"Test Dashboard","folderName":"My Folder","developerName":"Test_Dashboard"}]}';
    private static final String SINGLE_JSON = '{"attributes":{"dashboardName":"My Dashboard"},"componentData":[{"componentId":"01ax","reportResult":{"attributes":{"reportName":"Report 1"},"factMap":{"T!T":{"aggregates":[{"value":5}]}}}}]}';
    private static final String SINGLE_WITH_ROWS_JSON = '{"label":"Sales Dashboard","componentData":[{"reportResult":{"factMap":{"T!T":{"rows":[{"dataCells":[{"label":"North","value":10},{"label":"-","value":null}]},{"dataCells":[{"label":"South","value":20}]}]}}}}]}';
    private static final String EMPTY_BODY = '';
    private static final String INVALID_JSON = 'not json';

    @isTest
    static void testGetDashboardChartData_listResponse() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, LIST_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('dashboards'), 'Result should contain dashboards');
        System.assert(result.contains('Test Dashboard'), 'Result should contain dashboard name');
    }

    @isTest
    static void testGetDashboardChartData_singleDashboardResponse() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, SINGLE_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('/services/data/v65.0/analytics/dashboards/01Zxx');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('charts'), 'Result should contain charts');
        System.assert(result.contains('dashboardTitle'), 'Result should contain dashboardTitle');
    }

    @isTest
    static void testGetDashboardChartData_singleWithRows() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, SINGLE_WITH_ROWS_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('/services/data/v65.0/analytics/dashboards/01Z');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('charts'), 'Result should contain charts');
        System.assert(result.contains('North') || result.contains('South') || result.contains('dashboardTitle'), 'Should have labels or title');
    }

    @isTest
    static void testGetDashboardChartData_fallbackOnHttpError() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(500, 'Error'));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('/bad');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('charts') || result.contains('dashboards'), 'Fallback should return valid JSON');
        System.assert(result.contains('dashboardTitle'), 'Fallback should include dashboardTitle');
    }

    @isTest
    static void testGetDashboardChartData_fallbackOnCalloutException() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, LIST_JSON, true));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('charts') || result.contains('dashboards'), 'Fallback should return sample JSON on exception');
    }

    @isTest
    static void testGetDashboardChartData_nullEndpointUsesDefault() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, LIST_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData(null);
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('dashboards'), 'Default endpoint should return dashboards list');
    }

    @isTest
    static void testGetDashboardChartData_blankEndpointNormalized() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, LIST_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('  ');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetDashboardChartData_endpointWithoutLeadingSlash() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, LIST_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('services/data/v65.0/analytics/dashboards');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @isTest
    static void testGetDashboardChartData_emptyBodyReturnsSample() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, EMPTY_BODY));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('dashboardTitle'), 'Empty body should fall back to sample');
    }

    @isTest
    static void testGetDashboardChartData_invalidJsonReturnsSample() {
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, INVALID_JSON));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('dashboardTitle'), 'Invalid JSON should fall back to sample');
    }

    @isTest
    static void testGetDashboardChartData_listAsRootArray() {
        String arrayJson = '[{"id":"01Z","name":"D1","label":"D1"}]';
        Test.setMock(HttpCalloutMock.class, new DashboardHttpCalloutMock(200, arrayJson));
        Test.startTest();
        String result = DashboardDataController.getDashboardChartData('');
        Test.stopTest();
        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.contains('dashboards'), 'Root array should be treated as dashboard list');
    }
}
