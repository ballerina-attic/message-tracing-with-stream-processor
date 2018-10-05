import ballerina/io;
import ballerina/http;
import ballerina/test;

endpoint http:Client studentDataEP  {
    url: "http://localhost:9292"
};


@test:Config
// Function to test GET resource 'testError'.
function testMockError() {
    // Initialize the empty http request.
    http:Request request;
    // Send 'GET' request and obtain the response.
    http:Response response = check studentDataEP->get("/records/testError");
    string res = check  response.getTextPayload();
    test:assertEquals(res,"Test Error made",msg = "Test error success");
}

@test:Config
function testinvalidDataDeletion() {
    http:Request request;
    // Send 'GET' request and obtain the response.
    http:Response response = check studentDataEP->get("/records/deleteStu/9999");
    // Expected response json is as below.
    json res = check  response.getJsonPayload();
    test:assertEquals(res.toString(),"{\"Status\":\"Data Not Found\"}",msg = "Test error success");
}