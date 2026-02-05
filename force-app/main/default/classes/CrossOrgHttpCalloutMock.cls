/**
 * HTTP callout mock for CrossOrgRecordsController (query, PATCH, POST, DELETE).
 */
@isTest
public class CrossOrgHttpCalloutMock implements HttpCalloutMock {
    private final Integer statusCode;
    private final String body;
    private final Boolean throwInRespond;

    public CrossOrgHttpCalloutMock(Integer statusCode, String body) {
        this(statusCode, body, false);
    }

    public CrossOrgHttpCalloutMock(Integer statusCode, String body, Boolean throwInRespond) {
        this.statusCode = statusCode != null ? statusCode : 200;
        this.body = body != null ? body : '{}';
        this.throwInRespond = throwInRespond == true;
    }

    public HttpResponse respond(HttpRequest req) {
        if (throwInRespond) {
            throw new CalloutException('Simulated callout failure');
        }
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setStatus(statusCode >= 200 && statusCode < 300 ? 'OK' : 'Error');
        res.setHeader('Content-Type', 'application/json');
        res.setBody(body);
        return res;
    }
}
