// Run: Execute Anonymous Apex with Editor Contents (or: sf apex run -f scripts/apex/dashboardApiTest.apex)
// 1) Fetches raw API response from dashboard endpoint
// 2) Logs root structure and sample of body for analysis
// 3) Calls DashboardDataController.getDashboardChartData and logs chart JSON

String endpoint = '/services/data/v65.0/analytics/dashboards/01ZgL000005ZVhBUAW';
String path = endpoint.trim();
if (!path.startsWith('/')) path = '/' + path;
String fullUrl = 'callout:Sales_Credential' + path;

HttpRequest req = new HttpRequest();
req.setEndpoint(fullUrl);
req.setMethod('GET');
req.setHeader('Content-Type', 'application/json');
req.setTimeout(120000);

HttpResponse res = new Http().send(req);
String body = res.getBody();
Integer status = res.getStatusCode();

System.debug('=== API Response Status: ' + status + ' ===');
System.debug('=== Raw body length: ' + (body != null ? body.length() : 0) + ' ===');

// Log first 12000 chars to see structure (debug log limit friendly)
if (String.isNotBlank(body)) {
    Integer len = Math.min(12000, body.length());
    System.debug('=== Raw body (first ' + len + ' chars) ===');
    System.debug(body.substring(0, len));
    if (body.length() > len) {
        System.debug('... [truncated, total ' + body.length() + ' chars]');
    }
}

// Log root keys for structure analysis
try {
    Object root = JSON.deserializeUntyped(body);
    if (root instanceof Map<String, Object>) {
        Map<String, Object> m = (Map<String, Object>) root;
        System.debug('=== Root keys: ' + String.join(new List<String>(m.keySet()), ', ') + ' ===');
        for (String key : m.keySet()) {
            Object val = m.get(key);
            String typeStr = 'Object';
            if (val == null) typeStr = 'null';
            else if (val instanceof List<Object>) typeStr = 'List(size=' + ((List<Object>)val).size() + ')';
            else if (val instanceof Map<String, Object>) typeStr = 'Map';
            else if (val instanceof String) typeStr = 'String';
            else if (val instanceof Boolean) typeStr = 'Boolean';
            else if (val instanceof Integer) typeStr = 'Integer';
            else if (val instanceof Decimal) typeStr = 'Decimal';
            System.debug('  ' + key + ' => ' + typeStr);
        }
    } else if (root instanceof List<Object>) {
        System.debug('=== Root is List, size: ' + ((List<Object>)root).size() + ' ===');
    }
} catch (Exception e) {
    System.debug('Parse root error: ' + e.getMessage());
}

// Call controller and log chart result
System.debug('=== Controller getDashboardChartData result ===');
String chartJson = DashboardDataController.getDashboardChartData(endpoint);
System.debug(chartJson != null ? chartJson : 'null');
