[![Build Status](https://travis-ci.org/ballerina-guides/message-tracing-with-stream-processor.svg?branch=master)](https://travis-ci.org/ballerina-guides/message-tracing-with-stream-processor)

# Integration with WSO2 Stream Processor

WSO2 Stream Processor (SP) enables you to perform distributed message tracing. The Distributed Message Tracer allows you to trace the events that are produced, while Ballerina services serve the requests. The Ballerina services send the tracing data as WSO2 events to WSO2 SP.
  >This guide provides instructions on how Ballerina can be used to integrate with Stream-Processor.
  
The following are the sections available in this guide.

- [What you'll build](#what-you’ll-build)
- [Prerequisites](#prerequisites)
- [Implementation](#implementation)
- [Testing](#testing)
- [Testing with distributed message tracing](#testing-with-distributed-message-tracer.)
     - [Traces](#views-of-traces)

## What you’ll build
To perform this integration with Distributed Message Tracer, a real world use case of a very simple student management system is used.
This system illustrates the manipulation of student details in a school/college management system. The administrator is able to perform the following actions in this service.

    - Add a student's details to the system.
    - List down all the student's details who are registered in the system.
    - Delete a student's details from the system by providing student ID.
    - Generate a mock error (for observability purposes).
    - Get a student's marks list by providing student ID.

![Message-Tracing](images/ballerina-sp.svg "Message-Tracing")

- **Make Requests** : To perform actions on student management service, a console-based client program has been written in Ballerina for your ease of making requests.

## Prerequisites
 
- [Ballerina Distribution](https://ballerina.io/downloads/)
- [MySQL](https://github.com/ballerina-guides/message-tracing-with-stream-processor/blob/master/resources/testdb.sql)
- [WSO2 - Stream Processor v4.3.0 or above](https://github.com/wso2/product-sp/releases)
- A Text Editor or an IDE 

## Implementation

> If you want to skip the basics, you can download the GitHub repo and continue from the [Testing](#testing) section.

### Implementing database
 1. Start MySQL server in your local machine.
 2. Create a database named `testdb` in your MySQL localhost. If you want to skip the database implementation, then directly import the [testdb.sql](https://github.com/ballerina-guides/message-tracing-with-stream-processor/blob/master/resources/testdb.sql) file into your localhost. You can find it in the GitHub repo.

### Create the project structure
        
 For the purpose of this guide, let's use the following package structure.
 
    message-tracing-with-stream-processor
           └── guide
                ├── students
                │   ├── student_management_service.bal
                │   ├── student_marks_management_service.bal
                ├── client_service
                |         └── client_main.bal
                └── ballerina.conf
        

1. Create the above directories in your local machine, along with the empty `.bal` files.

2. Add the following lines in your [ballerina.conf](https://github.com/ballerina-guides/message-tracing-with-stream-processor/blob/master/ballerina.conf).

```toml
[b7a.observability.tracing]
enabled=true
name="wso2sp"

[b7a.observability.tracing.wso2sp]
reporter.wso2sp.publisher.type="thrift"
reporter.wso2sp.publisher.username="admin"
reporter.wso2sp.publisher.password="admin"
reporter.wso2sp.publisher.url="tcp://localhost:7611"
reporter.wso2sp.publisher.authUrl="ssl://localhost:7711"
reporter.wso2sp.publisher.databridge.agent.config="<SET ABSOLUTE PATH>/data.agent.config.yaml"
javax.net.ssl.trustStore="<SET ABSOLUTE PATH>/wso2carbon.jks"
javax.net.ssl.trustStorePassword="admin"
reporter.wso2sp.publisher.service.name="ballerina_hello_world"
```
- In the ballerina.conf file, the absolute path has to be set for the databridge agent config yaml file and the wso2carbon.jks file in order to configure the databridge agent and the wso2carbon keystore. This wso2carbon keystore configuration is required when the databridge is used.
- These files can be found [here](https://github.com/ballerina-guides/message-tracing-with-stream-processor/tree/master/resources/main/resources).
- Also update the [data.agent.config.yaml](https://github.com/ballerina-guides/message-tracing-with-stream-processor/blob/master/resources/main/resources/data.agent.config.yaml) file by including the absolute path of the [required files](https://github.com/ballerina-guides/message-tracing-with-stream-processor/tree/master/resources/main/resources) in the following fields. This is done for the purpose of configuring security keys for a secured data communication in data agent.
  - trustStorePath, keystoreLocation, secretPropertiesFile, masterKeyReaderFile .
  
- Then open the terminal and navigate to `message-tracing-with-stream-processor/guide` and run Ballerina project initializing toolkit in order to initialize this project as Ballerina project.

  ``
     $ ballerina init
  ``
- Also clone and build the ballerina-sp-extension in the following repository [https://github.com/ballerina-platform/ballerina-observability/tree/master/tracing-extensions/modules/ballerina-sp-extension](https://github.com/ballerina-platform/ballerina-observability/tree/master/tracing-extensions/modules/ballerina-sp-extension)

- After the build, navigate to `ballerina-sp-extension/target/distribution/` and copy all the JAR files to your `bre/lib` folder in your ballerina distribution.

- Start WSO2 Stream Processor dashboard and worker. Set up [distributed message tracing.](https://docs.wso2.com/display/SP430/Distributed+Message+Tracer)

- Use `admin` as the username and password. Include the following for your business rules.

    ```
    Span stream definition - @source(type='wso2event',  wso2.stream.id="SpanStream:1.0.0",  @map(type='wso2event')) define stream SpanStreamIn (componentName string, traceId  string, spanId long, baggage string, parentId long, operationName string, startMicros long, finishMicros long, tags string, references string);
    Service Name - componentName
    Operation Name - operationName
    Span ID -  convert(spanId, 'string')
    Trace ID - traceId
    Tags - tags
    Baggage Items - baggage
    Start Time - startMicros
    End Time - finishMicros
    Span References - references
    Parent ID - convert(parentId, 'string')
    Parent span is defined - true 
    ```
    
- Leave the rest of the fields as default values in the business rules.

### Development of student and marks service with Stream Processor

Now let us look into the implementation of the student management service with observability.

##### student_management_service.bal

``` ballerina
// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/mysql;
import ballerina/observe;
import ballerina/runtime;

// Type Student is created to store details of a student.
type Student record {
    int id;
    int age;
    string name;
    int mobNo;
    string address;
};

// Endpoint for marks details client.
http:Client marksServiceEP = new("http://localhost:9191");


// Endpoint for MySQL client.
mysql:Client studentDB = new({
        host: "localhost",
        port: 3306,
        name: "testdb",
        username: "root",
        password: "",
        dbOptions: { useSSL: false }
    });

// Listener for the student service.
listener http:Listener studentServiceListener = new(9292);

// Student data service.
@http:ServiceConfig {
    basePath: "/records"
}
service studentData on studentServiceListener {

    int errors = 0;
    int requestCounts = 0;

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/addStudent"
    }
    // Add Students resource used to add student records to the system.
    resource function addStudents(http:Caller caller, http:Request request) {
        // Initialize an empty HTTP response message.
        studentData.requestCounts += 1;
        http:Response response = new;

        // Accepting the JSON payload sent from a request.
        json|error payloadJson = request.getJsonPayload();

        if (payloadJson is json) {
            //Converting the payload to Student type.

            Student|error studentDetails = Student.convert(payloadJson);

            if (studentDetails is Student) {
                io:println(studentDetails);
                // Calling the function insertData to update database.
                json returnValue = insertData(untaint studentDetails.name, untaint studentDetails.age, untaint
                    studentDetails.mobNo, untaint studentDetails.
                    address);
                response.setJsonPayload(untaint returnValue);
            }

        }

        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default system span.
        _ = observe:addTagToSpan("tot_requests", <string>studentData.requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>studentData.errors);

        // Send the response back to the client with the returned JSON value from insertData function.
        var result = caller->respond(response);
        if (result is error) {
            // Log the error for the service maintainers.
            log:printError("Error responding to the client", err = result);
        }

    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/viewAll"
    }
    // View students resource is to get all the student's details and send to the requested user.
    resource function viewStudents(http:Caller caller, http:Request request) {
        studentData.requestCounts += 1;
        int|error childSpanId = observe:startSpan("Obtain details span");
        http:Response response = new;
        json status = {};

        int spanId2 = observe:startRootSpan("Database call span");
        //Sending a request to MySQL endpoint and getting a response with required data table.
        var returnValue = studentDB->select("SELECT * FROM student", Student, loadToMemory = true);
        _ = observe:finishSpan(spanId2);
        // A table is declared with Student as its type.
        table<Student> dataTable = table{};

        if (returnValue is error) {
            io:println("Select data from student table failed");
        } else {
            dataTable = returnValue;
        }

        // Student details displayed on server side for reference purpose.
        foreach var row in dataTable {
            io:println("Student:" + row.id + "|" + row.name + "|" + row.age);
        }

        // Table is converted to JSON.
        var jsonConversionValue = json.convert(dataTable);
        if (jsonConversionValue is error) {
            status = { "Status": "Data Not available" };
        } else {
            status = jsonConversionValue;
        }
        // Sending back the converted JSON data to the request made to this service.
        response.setJsonPayload(untaint status);
        var result = caller->respond(response);
        if (result is error) {
            log:printError("Error sending response", err = result);
        }

        if (childSpanId is int) {
            _ = observe:finishSpan(childSpanId);
        } else {
            log:printError("Error attaching span ", err = childSpanId);
        }
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default system span.
        _ = observe:addTagToSpan("tot_requests", <string>studentData.requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>studentData.errors);
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/testError"
    }
    // Test Error resource is used to make a mock error.
    resource function testError(http:Caller caller, http:Request request) {
        studentData.requestCounts += 1;
        http:Response response = new;

        studentData.errors += 1;
        io:println(studentData.errors);
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan("tot_requests", <string>studentData.requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>studentData.errors);
        log:printError("error test");
        response.setTextPayload("Test Error made");
        var result = caller->respond(response);
        if (result is error) {
            log:printError("Error sending response", err = result);
        }
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/deleteStu/{studentId}"
    }

    // Delete Students resource for deleteing a student using id.
    resource function deleteStudent(http:Caller caller, http:Request request, int studentId) {
        studentData.requestCounts += 1;
        http:Response response = new;
        json status = {};

        // Calling the deleteData function with id as the parameter and get a return json object.
        var returnValue = deleteData(studentId);
        io:println(returnValue);

        // Pass the obtained JSON object to the request.
        response.setJsonPayload(returnValue);
        var result = caller->respond(response);
        if (result is error) {
            log:printError("Error sending response", err = result);
        }
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default system span.
        _ = observe:addTagToSpan("tot_requests", <string>studentData.requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>studentData.errors);
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/getMarks/{studentId}"
    }
    // Get marks resource for obtaining marks of a particular student.
    resource function getMarks(http:Caller caller, http:Request request, int studentId) {
        studentData.requestCounts += 1;
        http:Response response = new;
        json result = {};

        // Self-defined span for observability purposes.
        int|error firstSpan = observe:startSpan("First span");
        // Request made for obtaining marks of the student with the respective studentId to marks service.
        var requestReturn = marksServiceEP->get("/marks/getMarks/" + untaint studentId);

        if (requestReturn is error) {
            log:printError("Error", err = requestReturn);
        } else {
            var msg = requestReturn.getJsonPayload();
            if (msg is error) {
                log:printError("Error", err = msg);
            } else {
                result = msg;
            }
        }

        // Stopping the previously started span.
        if (firstSpan is int) {
            _ = observe:finishSpan(firstSpan);
        } else {
            log:printError("Error attaching span ", err = firstSpan);
        }
        //Sending the JSON to the client.
        response.setJsonPayload(untaint result);
        var resResult = caller->respond(response);
        if (resResult is error) {
            log:printError("Error sending response", err = resResult);
        }
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default system span.
        _ = observe:addTagToSpan("tot_requests", <string>studentData.requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>studentData.errors);
    }
}

// Function to insert values to the database.
# `insertData()` is a function to add data to student records database.
#
# + name - This is the name of the student to be added.
# + age -Student age.
# + mobNo -Student mobile number.
# + address - Student address.
# + return - This function returns a JSON object. If data is added it returns JSON containing a status and id of student
#            added. If data is not added , it returns the JSON containing a status and error message.

public function insertData(string name, int age, int mobNo, string address) returns (json) {
    json updateStatus = { "Status": "Data Inserted " };
    int uniqueId = 0;
    string sqlString = "INSERT INTO student (name, age, mobNo, address) VALUES (?,?,?,?)";
    // Insert data to the SQL database by invoking update action.
    var returnValue = studentDB->update(sqlString, name, age, mobNo, address);

    if (returnValue is int) {
        table<Student> result = getId(untaint mobNo);
        while (result.hasNext()) {
            var returnValue2 = result.getNext();
            if (returnValue2 is Student) {
                uniqueId = returnValue2.id;
            } else {
                io:println("Unable to get student details ");
            }
        }

        if (uniqueId != 0) {
            updateStatus = { "Status": "Data Inserted Successfully", "id": uniqueId };
        } else {
            updateStatus = { "Status": "Data Not inserted" };
        }
    }
    return updateStatus;
}


# `deleteData()` is a function to delete a student's data from student records database.
#
# + studentId - This is the id of the student to be deleted.
# + return -This function returns a JSON object. If data is deleted it returns JSON containing a status.
#           If data is not deleted , it returns the JSON containing a status and error message.

public function deleteData(int studentId) returns (json) {
    json status = {};
    string sqlString = "DELETE FROM student WHERE id = ?";

    // Delete the existing data by invoking update action.
    var returnValue = studentDB->update(sqlString, studentId);
    io:println(returnValue);

    if (returnValue is int) {
        if (returnValue != 1) {
            status = { "Status": "Data Not Found" };
        } else {
            status = { "Status": "Data Deleted Successfully" };
        }

    } else {
        status = { "Status": "Data Not Deleted" };
    }
    return status;
}

# `getId()` is a function to get the Id of the student added in latest.
#
# + mobNo - This is the mobile number of the student added which is passed as parameter to build up the query.
# + return -This function returns a table with Student type.

// Function to get the generated Id of the student recently added.
public function getId(int mobNo) returns table<Student> {
    //Select data from database by invoking select action.

    string sqlString = "SELECT * FROM student WHERE mobNo = ?";
    // Retrieve student data by invoking select remote function defined in ballerina sql client
    var ret = studentDB->select(sqlString, Student, mobNo);

    table<Student> dataTable = table{};
    if (ret is error) {
    } else {
        dataTable = ret;
    }
    return dataTable;
}

```

Now we will look into the implementation of obtaining the marks of the students from database through another service.

##### student_marks_management_service.bal

``` ballerina
// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/mysql;
import ballerina/observe;
import ballerina/runtime;

// Type Marks is created to represent a set of marks.
type Marks record {
    int studentId;
    int maths;
    int english;
    int science;
};

// Listener for marks service.
listener http:Listener marksServiceListener = new(9191);

// Marks data service.
@http:ServiceConfig {
    basePath: "/marks"
}

service MarksData on marksServiceListener {
    @http:ResourceConfig {
        methods: ["GET"],
        path: "/getMarks/{stuId}"
    }
    // Get marks resource used to get student's marks.
    resource function getMarks(http:Caller httpConnection, http:Request request, int stuId) {
        http:Response response = new;
        json result = findMarks(untaint stuId);
        // Pass the obtained JSON object to the requested client.
        response.setJsonPayload(untaint result);
        var resResult = httpConnection->respond(response);

        if (resResult is error) {
            log:printError("Error sending response", err = resResult);
        }
    }
}

# `findMarks()`is a function to find a student's marks from the marks record database.
#
#  + stuId -  This is the id of the student.
# + return - This function returns a JSON object. If data is added it returns JSON containing a status and id of student added.
#            If data is not added , it returns the JSON containing a status and error message.

public function findMarks(int stuId) returns (json) {
    json status = {};
    string sqlString = "SELECT * FROM marks WHERE student_Id = " + stuId;
    // Getting student marks of the given ID.
    // Invoking select operation in testDB.
    var returnValue = studentDB->select(sqlString, Marks, loadToMemory = true);

    // Assigning data obtained from db to a table.
    table<Marks> dataTable = table {};

    if (returnValue is table<Marks>) {
        dataTable = returnValue;
    } else {
        log:printError("Error Detected", err = returnValue);
        status = { "Status": "Select data from student table failed: " };
        return status;
    }
    // Converting the obtained data in table format to JSON data.
    var jsonConversionValue = json.convert(dataTable);

    if (jsonConversionValue is json) {
        status = jsonConversionValue;
    } else {
        status = { "Status": "Data Not available" };
        log:printError("Error Detected", err = jsonConversionValue);
    }
    return status;
}

```

Lets look into the implementation of the client implementation.

##### client_main.bal

``` ballerina
// Copyright (c) 2018 WSO2 Inc. (http://www.wso2.org) All Rights Reserved.
//
// WSO2 Inc. licenses this file to you under the Apache License,
// Version 2.0 (the "License"); you may not use this file except
// in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

import ballerina/http;
import ballerina/io;
import ballerina/log;

http:Client studentService = new("http://localhost:9292");

public function main() {
    http:Request req = new;
    int operation = 0;
    while (operation != 6) {
        // Print options menu to choose from.
        io:println("Select operation.");
        io:println("1. Add student");
        io:println("2. View all students");
        io:println("3. Delete a student");
        io:println("4. Make a mock error");
        io:println("5: Get a student's marks");
        io:println("6. Exit \n");

        // Read user's choice.
        string choice = io:readln("Enter choice 1 - 5: ");
        if (!isInteger(choice)) {
            io:println("Choice must be of a number");
            io:println();
            continue;
        }

        var intOperation = int.convert(choice);

        if (intOperation is int) {
            io:println(intOperation);
            operation = intOperation;
        }

        // Program runs until the user inputs 6 to terminate the process.
        match operation {

            1 => addStudent(req);
            2 => viewAllStudents();
            3 => deleteStudent();
            4 => makeError();
            5 => getMarks();
            6 => break;
            _ => io:println("Invalid choice");
        }
    }
}

function isInteger(string input) returns boolean {
    string regEx = "\\d+";
    boolean|error isInt = input.matches(regEx);
    if (isInt is error) {
        log:printError("Error", err = isInt);
        return false;
    } else {
        return isInt;
    }

}

// Function  to add students to database.
function addStudent(http:Request req) {
    // Get student name, age mobile number, address.
    var name = io:readln("Enter Student name: ");
    var age = io:readln("Enter Student age: ");
    var mobile = io:readln("Enter mobile number: ");
    var add = io:readln("Enter Student address: ");

    var ageAsInt = int.convert(age);
    var mobNoAsInt = int.convert(mobile);

    if (ageAsInt is int && mobNoAsInt is int) {
        // Create the request as JSON message.
        json jsonMsg = { "name": name, "age": ageAsInt, "mobNo": mobNoAsInt, "address": add, "id": 0 };
        req.setJsonPayload(jsonMsg);

    } else {
        io:println("Adding students failed");
        return;
    }

    // Send the request to students service and get the response from it.
    var resp = studentService->post("/records/addStudent", req);

    if (resp is http:Response) {
        var jsonMsg = resp.getJsonPayload();
        if (jsonMsg is json) {
            string message = "Status: " + jsonMsg["Status"] .toString() + " Added Student Id :- " +
                jsonMsg["id"].toString();
            // Extracting data from JSON received and displaying.
            io:println(message);
        } else {
            log:printError("Error in JSON", err = jsonMsg);
        }

    } else {
        log:printError("Error in response", err = resp);
    }
}

function viewAllStudents() {
    // Sending a request to list down all students and get the response from it.
    var response = studentService->post("/records/viewAll", null);

    if (response is http:Response) {
        var jsonMsg = response.getJsonPayload();

        if (jsonMsg is json) {
            string message = "";

            if (jsonMsg.length() >= 1) {
                int i = 0;
                while (i < jsonMsg.length()) {

                    message = "Student Name: " + jsonMsg[i]["name"] .toString() + ", " + " Student Age: " +
                        jsonMsg[i]["age"] .toString();

                    io:println(message);
                    i += 1;
                }
            } else {
                // Notify user if no records are available.
                message = "\n Student record is empty";
                io:println(message);
            }

        } else {
            log:printError("Error ", err = jsonMsg);
        }

    } else {
        log:printError("Error ", err = response);
    }
}

function deleteStudent() {
    // Get student id.
    string id = io:readln("Enter student id: ");

    // Request made to find the student with the given id and get the response from it.
    var resp = studentService->get("/records/deleteStu/" + id);

    if (resp is http:Response) {
        var jsonMsg = resp.getJsonPayload();
        if (jsonMsg is json) {
            string message = jsonMsg["Status"].toString();
            io:println("\n" + message + "\n");
        } else {
            log:printError("Error ", err = jsonMsg);
        }
    }

}

function makeError() {
    var response = studentService->get("/records/testError");

    if (response is http:Response) {
        var msg = response.getTextPayload();

        if (msg is string) {
            io:println("\n" + msg + "\n");
        } else {
            log:printError("Error", err = msg);
        }
    } else {
        log:printError("Error", err = response);
    }
}

function getMarks() {
    // Get student id.
    var id = io:readln("Enter student id: ");
    // Request made to get the marks of the student with given id and get the response from it.
    var response = studentService->get("/records/getMarks/" + id);

    if (response is http:Response) {
        var jsonMsg = response.getJsonPayload();

        if (jsonMsg is json) {
            string message = "";
            // Validate to check if student with given ID exist in the system.
            if (jsonMsg.length() >= 1) {
                message = "Maths: " + jsonMsg[0]["maths"] .toString() + " English: " + jsonMsg[0]["english"] .toString()
                    +
                    " Science: " + jsonMsg[0]["science"] .toString();

            } else {
                message = "Data not available. Check if student's mark is added or student might not be in our system.";
            }
            io:println("\n" + message + "\n");
        } else {
            log:printError("Error ", err = jsonMsg);
        }
    } else {
        log:printError("Error ", err = response);
    }
}

```

- Now we have completed the implementation of student management service with marks management service.

## Testing 

### Invoking the student management service

You can start both the services by opening a terminal and navigating to `message-tracing-with-stream-processor/guide`, and execute the following command.

```
$ ballerina run --config <path-to-conf>/ballerina.conf students
```

- You need to start the WSO2 Stream Processor dashboard and worker and navigate to the portal page. Here again use `admin` for both the username and password.

 You can observe the service performance by making some http requests to the above services. This is made easy for you as 
 there is a client program implemented. You can start the client program by opening another terminal and navigating to message-tracing-with-stream-processor/guide
 and run the below command
 
 ```
 $ ballerina run client_service
 ``` 
 
### Testing with Distributed Message Tracer.
 
#### Views of traces
 After making some HTTP requests, go to the distributed message tracing dashboard in your WSO2 Stream Processor portal.

 - You are expected to see the traces as below when you press the search button in the dashboard.
 
![SP](images/trace1.png "SP")
 
 - To view a particular trace click on the trace row. And you will see as below
 
![SP](images/trace2.png "SP")
    
 - To view span details with metrics click on a particular span and you are expected to see as below
 
![SP](images/trace3.png "SP")

 You can filter the received traces by providing the service names, time and/or resource names in the tracing search box.

 - Tracing search -
  
 ![SP](images/trace6.png "SP")
  
 - Filter using service name and time -

 ![SP](images/trace5.png "SP")
     
 - Filter using resource name and time -

  ![SP](images/trace4.png "SP")
