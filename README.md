  [![Build Status](https://travis-ci.org/Shairam/message-tracing-with-stream-processor.svg?branch=master)](https://travis-ci.org/Shairam/message-tracing-with-stream-processor)
  
## Integration with WSO2 Stream Processor

WSO2 stream processor provides us with distributed message tracing. The Distributed Message Tracer allows you to trace the events which are produced while ballerina services serve for requests. The ballerina services send these tracing data as WSO2 events.
 
The following are the sections available in this guide.

- [What you'll build](#what-you’ll-build)
- [Prerequisites](#prerequisites)
- [Implementation](#implementation)
- [Testing](#testing)
- [Testing with distributed message tracing](#testing-with-distributed-message-tracer.)
     - [Traces](#views-of-traces)
     



## What you’ll build 

To perform this integration with Stream Processor,  a real world use case of a very simple student management system is used.

![SP](images/ballerina-sp.svg "Ballerina-SP")

- **Make Requests** : To perform actions on student  management service, a console based client program has been written in Ballerina for your ease of making requests.

## Prerequisites
 
- [Ballerina Distribution](https://ballerina.io/learn/getting-started/)
- [MYSQL](https://github.com/Shairam/ballerina-sp-tracing/blob/master/resources/testdb.sql)
- [WSO2 - Stream Processor v4.3.0](https://github.com/wso2/product-sp/releases)
- A Text Editor or an IDE 

## Implementation

> If you want to skip the basics, you can download the GitHub repo and continue from the "Testing" section.

### Implementing database
 - Start MYSQL server in your local machine.
 - Create a database with name `testdb` in your MYSQL localhost. If you want to skip the database implementation, then directly import the [testdb.sql](https://github.com/Shairam/ballerina-sp-tracing/blob/master/resources/testdb.sql) file into your localhost. You can find it in the Github repo.
 
 
 

### Create the project structure
        
 For the purpose of this guide, let's use the following package structure.
        
    
    ballerina-sp-tracing
           └── guide
                ├── students
                │   ├── student_management_service.bal
                │   ├── student_marks_management_service.bal
                ├── client_service
                |         └── client_main.bal
                └── ballerina.conf
        

- Create the above directories in your local machine, along with the empty `.bal` files.

- You have to add the following lines in your [ballerina.conf](https://github.com/Shairam/ballerina-sp-tracing/blob/master/ballerina.conf).

```ballerina
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
- In the ballerina.conf file for line number 11 and 12, you are required to give the appropriate absolute path to the following files mentioned in the lines.
- You can find these files [here](https://github.com/Shairam/ballerina-sp-tracing/tree/extras-1/resources/main/resources).
- Also you need to update the [data.agent.config.yaml](https://github.com/Shairam/ballerina-sp-tracing/blob/extras-1/resources/main/resources/data.agent.config.yaml) file by including the absolute path of the [required files](https://github.com/Shairam/ballerina-sp-tracing/tree/extras-1/resources/main/resources) in the following fields. 
  - trustStorePath, keystoreLocation, secretPropertiesFile, masterKeyReaderFile .
- Then open the terminal and navigate to `ballerina-sp-tracing/guide` and run Ballerina project initializing toolkit.

  ``
     $ ballerina init
  ``
  
  
- Also you need to clone and build the ballerina-sp-extension in the following repository [https://github.com/ballerina-platform/ballerina-observability](https://github.com/ballerina-platform/ballerina-observability) 

- After building  move to `ballerina-sp-extension/target/distribution/` and copy all the jar files to your `bre/lib` folder in your ballerina distribution.

- Start WSO2 Stream Processor dashboard and worker. Set up the [distributed message tracing.](https://docs.wso2.com/display/SP420/Distributed+Message+Tracer)

- Use `admin` as username and password. Include the following for your business rules.

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
    
- Leave the rest fields as default values for parent span.

### Development of student and marks service with Stream Processor

Now let us look into the implementation of the student management with observability.

##### student_management_service.bal

``` ballerina
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

//End point for marks details client.
endpoint http:Client marksService {
    url: " http://localhost:9191"
};

//Endpoint for mysql client.
endpoint mysql:Client testDB {
    host: "localhost",
    port: 3306,
    name: "testdb",
    username: "root",
    password: "",
    poolOptions: { maximumPoolSize: 5 },
    dbOptions: { useSSL: false }
};

//This service listener.
endpoint http:Listener listener1 {
    port: 9292
};

// Student data service.
@http:ServiceConfig {
    basePath: "/records"
}
service<http:Service> StudentData bind listener1 {

    int errors = 0;
    int requestCounts = 0;

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/addStudent"
    }
    // Add Students resource used to add student records to the system.
    addStudents(endpoint httpConnection, http:Request request) {
        // Initialize an empty http response message
        requestCounts++;
        http:Response response;
        Student stuData;

        // Accepting the Json payload sent from a request.
        var payloadJson = check request.getJsonPayload();

        // Converting the payload to Student type.
        stuData = check <Student>payloadJson;

        // Calling the function insertData to update database.
        json ret = insertData(stuData.name, stuData.age, stuData.mobNo, stuData.address);

        // Send the response back to the client with the returned json value from insertData function
        response.setJsonPayload(ret);
        _ = httpConnection->respond(response);

        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan("tot_requests", <string>requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>errors);
    }

    @http:ResourceConfig {
        methods: ["POST"],
        path: "/viewAll"
    }
    // View students resource is to get all the students details and send to the requested user.
    viewStudents(endpoint httpConnection, http:Request request) {
        requestCounts++;
        int chSpanId = check observe:startSpan("Check span 1");
        http:Response response;
        json status = {};

        int spanId2 = observe:startRootSpan("Database call span");
        var selectRet = testDB->select("SELECT * FROM student", Student, loadToMemory = true);
        //Sending a request to mysql endpoint and getting a response with required data table.
        _ = observe:finishSpan(spanId2);
        // A table is declared with Student as its type.
        table<Student> dt;

        // Match operator used to check if the response returned value with one of the types below.
        match selectRet {
            table tableReturned => dt = tableReturned;
            error e => io:println("Select data from student table failed: "
                    + e.message);
        }

        // Student details displayed on server side for reference purpose.
        io:println("Iterating data first time:");
        foreach row in dt {
            io:println("Student:" + row.id + "|" + row.name + "|" + row.age);
        }

        // Table is converted to json.
        var jsonConversionRet = <json>dt;
        match jsonConversionRet {
            json jsonRes => {
                status = jsonRes;
            }
            error e => {
                status = { "Status": "Data Not available", "Error": e.message };
            }
        }
        // Sending back the converted json data to the request made to this service.
        response.setJsonPayload(untaint status);
        _ = httpConnection->respond(response);

        _ = observe:finishSpan(chSpanId);
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan("tot_requests", <string>requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>errors);

    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/testError"
    }
    // Test Error resource to make a mock error.
    testError(endpoint httpConnection, http:Request request) {
        requestCounts++;
        http:Response response;

        errors++;
        io:println(errors);
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan("error_counts", <string>errors);
        _ = observe:addTagToSpan("tot_requests", <string>requestCounts);
        log:printError("error test");
        response.setTextPayload("Test Error made");
        _ = httpConnection->respond(response);
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/deleteStu/{stuId}"
    }
    // Delete Students resource for deleteing a student using id.
    deleteStudent(endpoint httpConnection, http:Request request, int stuId) {
        requestCounts++;
        http:Response response;
        json status = {};

        // Calling deleteData function with id as parameter and get a return json object.
        var ret = deleteData(stuId);
        io:println(ret);

        // Pass the obtained json object to the request.
        response.setJsonPayload(ret);
        _ = httpConnection->respond(response);
        // The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan(spanId = -1, "tot_requests", <string>requestCounts);
        _ = observe:addTagToSpan(spanId = -1, "error_counts", <string>errors);
    }

    @http:ResourceConfig {
        methods: ["GET"],
        path: "/getMarks/{stuId}"
    }
    // Get marks resource for obtaining marks of a particular student.
    getMarks(endpoint httpConnection, http:Request request, int stuId) {
        requestCounts++;
        http:Response response;
        json result;

        // Self defined span for observability purposes.
        int firstsp = check observe:startSpan("First span");
        // Request made for obtaining marks of the student with the respective stuId to marks Service.
        var requ = marksService->get("/marks/getMarks/" + untaint stuId);

        match requ {
            http:Response response2 => {
                var msg = response2.getJsonPayload();
                // Gets the Json object.
                match msg {
                    json js => {
                        result = js;
                    }

                    error er => {
                        log:printError(er.message, err = er);
                    }
                }
            }
            error err => {
                log:printError(err.message, err = err);
            }
        }
        // Stopping the previously started span.
        _ = observe:finishSpan(firstsp);
        //Sending the Json to the client.
        response.setJsonPayload(untaint result);
        _ = httpConnection->respond(response);

        //  The below function adds tags that are to be passed as metrics in the traces. These tags are added to the default ootb system span.
        _ = observe:addTagToSpan("tot_requests", <string>requestCounts);
        _ = observe:addTagToSpan("error_counts", <string>errors);
    }
}

// Function to insert values to database
  # `insertData()` is a function to add data to student records database.
  # + name - This is the name of the student to be added.
  # + age - Student age.
  # + mobNo - Student mobile number.
  # + address - Student address.
  # + return -   This function returns a json object. If data is added it returns json containing a status and id of student added.
  #          If data is not added , it returns the json containing a status and error message.

public function insertData(string name, int age, int mobNo, string address) returns (json) {
    json updateStatus;
    int uid;
    string sqlString = "INSERT INTO student (name, age, mobNo, address) VALUES (?,?,?,?)";
    // Insert data to SQL database by invoking update action.
    var ret = testDB->update(sqlString, name, age, mobNo, address);

    // Use match operator to check the validity of the result from database.
    match ret {
        int updateRowCount => {
         var result = getId(untaint mobNo);
            // Getting info of the student added
            match result {
                table dt => {
                    while (dt.hasNext()) {
                        var ret2 = <Student>dt.getNext();
                        match ret2 {
                            // Getting the  id of the latest student added.
                            Student stu => uid = stu.id;
                            error e => io:println("Error in get employee from table: " + e.message);
                        }
                    }
                }
                error er => {
                    io:println(er.message);
                }
            }

            updateStatus = { "Status": "Data Inserted Successfully", "id": uid };
        }
        error err => {
            updateStatus = { "Status": "Data Not Inserted", "Error": err.message };
        }
    }
    return updateStatus;
}


// Function to delete student data from database.
# `deleteData()` is a function to delete a student's data from student records database.
# + stuId - This is the id of the student to be deleted.
# + return - This function returns a json object. If data is deleted it returns json containing a status.
#              If data is not deleted , it returns the json containing a status and error message.

public function deleteData(int stuId) returns (json) {
    json status = {};
    string sqlString = "DELETE FROM student WHERE id = ?";

    // Delete existing data by invoking update action.
    var ret = testDB->update(sqlString, stuId);
    io:println(ret);
    match ret {
        int updateRowCount => {
            if (updateRowCount != 1){
                status = { "Status": "Data Not Found" };
            }
            else {
                status = { "Status": "Data Deleted Successfully" };
            }
        }
        error err => {
            status = { "Status": "Data Not Deleted", "Error": err.message };
            io:println(err.message);
        }
    }
    return status;
}

# `getId()` is a function to get the Id of the student added in latest.
# + mobNo - This is the mobile number of the student added which is passed as parameter to build up the query.
# + return -  This function returns either a table which has only one row of the student details or an error.

// Function to get the generated Id of the student recently added.
public function getId(int mobNo) returns (table|error) {
    //Select data from database by invoking select action.
    var ret2 = testDB->select("Select * FROM student WHERE mobNo = " + mobNo, Student, loadToMemory = true);
    table<Student> dt;
    match ret2 {
        table tableReturned => dt = tableReturned;
        error e => io:println("Select data from student table failed: " + e.message);
    }
    return dt;
}





```

Now we will look into the implementation of obtaining the marks of the students from database through another service.


##### student_marks_management_service.bal

``` ballerina
import ballerina/http;
import ballerina/io;
import ballerina/log;
import ballerina/mysql;
import ballerina/observe;
import ballerina/runtime;

type Marks record {
    int studentId;
    int maths;
    int english;
    int science;
};

endpoint mysql:Client testDB1 {
    host: "localhost",
    port: 3306,
    name: "testdb",
    username: "root",
    password: "",
    poolOptions: { maximumPoolSize: 5 },
    dbOptions: { useSSL: false }
};

// This service listener
endpoint http:Listener listener {
    port: 9191
};

// Marks data service.
@http:ServiceConfig {
    basePath: "/marks"
}
service<http:Service> MarksData bind listener {
    @http:ResourceConfig {
        methods:["GET"],
        path: "/getMarks/{stuId}"
    }
    // Get marks resource used to get student's marks.
    getMarks(endpoint httpConnection, http:Request request, int stuId) {
        http:Response response = new;
        json result = findMarks(untaint stuId);
        // Pass the obtained json object to the requested client.
        response.setJsonPayload(untaint result);
        _ = httpConnection->respond(response);
    }
}

# `findMarks()` is a function to find a student's marks from the marks record database.
#  + stuId -  This is the id of the student.
# + return - This function returns a json object. If data is added it returns json containing a status and id of student added.
#          If data is not added , it returns the json containing a status and error message.

public function findMarks(int stuId) returns (json) {
    json status = {};
    string sqlString = "SELECT * FROM marks WHERE student_Id = " + stuId;
    // Getting student marks of the given ID.
    //Invoking select operation in testDB
    var ret = testDB1->select(sqlString, Marks, loadToMemory = true);
    // Stopping the previously started span

    //Assigning data obtained from db to a table
    table<Marks> datatable;
    match ret {
        table tableReturned => datatable = tableReturned;
        error er => {
             log:printError(er.message, err = er);
            status = { "Status": "Select data from student table failed: ", "Error": er.message };
            return status;
        }
    }
    // Converting the obtained data in table format to json data.
    var jsonConversionRet = <json>datatable;
    match jsonConversionRet {
        json jsonRes => {
            status = jsonRes;
        }
        error e => {
            status = { "Status": "Data Not available", "Error": e.message };
        }
    }
    io:println(status);
    return status;
}




```

Lets look into the implementation of the client implementation.

##### client_main.bal

``` ballerina
             import ballerina/http;
             import ballerina/io;
             import ballerina/log;
             
             endpoint http:Client studentData {
                 url: " http://localhost:9292"
             };
             
             public function main(string... args) {
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
                     if (!isInteger(choice)){
                         io:println("Choice must be of a number");
                         io:println();
                         continue;
                     }
             
                     operation = check <int>choice;
                     // Program runs until the user inputs 6 to terminate the process.
                     if (operation == 6) {
                         break;
                     }
                     // User chooses to add a student.
                     if (operation == 1) {
                         addStudent(req);
                     }
                     // User chooses to list down all the students.
                     else if (operation == 2) {
                         viewAllStudents();
                     }
                     // User chooses to delete a student by Id.
                     else if (operation == 3) {
                         deleteStudent();
                     }
                     // User chooses to make a mock error.
                     else if (operation == 4) {
                         makeError();
                     }
                     else if (operation == 5){
                         getMarks();
                     }
                     else {
                         io:println("Invalid choice");
                     }
                 }
             }
             
             function isInteger(string input) returns boolean {
                 string regEx = "\\d+";
                 boolean isInt = check input.matches(regEx);
                 return isInt;
             }
             
             function addStudent(http:Request req) {
                 // Get student name, age mobile number, address.
                 var name = io:readln("Enter Student name: ");
                 var age = io:readln("Enter Student age: ");
                 var mobile = io:readln("Enter mobile number: ");
                 var add = io:readln("Enter Student address: ");
             
                 // Create the request as json message.
                 json jsonMsg = { "name": name, "age": check <int>age, "mobNo": check <int>mobile, "address": add };
                 req.setJsonPayload(jsonMsg);
             
                 // Send the request to students service and get the response from it.
                 var resp = studentData->post("/records/addStudent", req);
                 match resp {
                     http:Response response => {
                         var msg = response.getJsonPayload();
                         //obtaining the result from the response received
                         match msg {
                             json jsonPL => {
                                 string message = "Status: " + jsonPL["Status"] .toString() + " Added Student Id :- " +
                                     jsonPL["id"].toString();
                                 // Extracting data from json received and displaying.
                                 io:println(message);
                             }
             
                             error err => {
                                 log:printError(err.message, err = err);
                             }
                         }
                     }
                     error err => {
                         log:printError(err.message, err = err);
                     }
                 }
             }
             
             function viewAllStudents() {
                 // Sending a request to list down all students and get the response from it.
                 var requ = studentData->post("/records/viewAll", null);
                 match requ {
                     http:Response response => {
                         var msg = response.getJsonPayload();
                         // Obtaining the result from the response received.
                         match msg {
                             json jsonPL => {
                                 string message;
                                 // Validate to check if records are available.
                                 if (lengthof jsonPL >= 1) {
                                     int i;
                                     io:println();
                                     // Loop through the received json array and display data.
                                     while (i < lengthof jsonPL) {
                                         message = "Student Name: " + jsonPL[i]["name"] .toString() + ", " + " Student Age: " + jsonPL[i]["age"] .toString();
                                         io:println(message);
                                         i++;
                                     }
                                     io:println();
                                 }
                                 else {
                                     // Notify user if no records are available.
                                     message = "Student record is empty";
                                     io:println(message);
                                 }
                             }
                             error err => {
                                 log:printError(err.message, err = err);
                             }
                         }
                     }
                     error err => {
                         log:printError(err.message, err = err);
                     }
                 }
             }
             
             function deleteStudent(){
                 // Get student id.
                 var id = io:readln("Enter student id: ");
                 // Request made to find the student with the given id and get the response from it.
                 var requ = studentData->get("/records/deleteStu/" + check <int>id);
                 match requ {
                     http:Response response => {
                         var msg = response.getJsonPayload();
                         // Obtaining the result from the response received.
                         match msg {
                             json jsonPL => {
                                 string message;
                                 message = jsonPL["Status"].toString();
                                 io:println("\n"+ message + "\n");
                             }
                             error err => {
                                 log:printError(err.message, err = err);
                             }
                         }
                     }
                     error er => {
                         io:println(er.message);
                         log:printError(er.message, err = er);
                     }
                 }
             }
             
             function makeError() {
                 var requ = studentData->get("/records/testError");
                 match requ {
                     http:Response response => {
                         var msg = response.getTextPayload();
                         // Obtaining the result from the response received.
                         match msg {
                             string message => {
                                 io:println("\n"+ message + "\n");
                             }
                             error err => {
                                 log:printError(err.message, err = err);
                             }
                         }
                     }
                     error er => {
                         log:printError(er.message, err = er);
                     }
                 }
             }
             
             function getMarks(){
                 // Get student id.
                 var id = io:readln("Enter student id: ");
                 // Request made to get the marks of the student with given id and get the response from it.
                 var requ = studentData->get("/records/getMarks/" + check <int>id);
                 match requ {
                     http:Response response => {
                         var msg = response.getJsonPayload();
                         // Obtaining the result from the response received.
                         match msg {
                             json jsonPL => {
                                 string message;
                                 if (lengthof jsonPL >= 1) {
                                     // Validate to check if student with given ID exist in the system.
                                     message = "Maths: " + jsonPL[0]["maths"] .toString() + " English: " + jsonPL[0]["english"] .toString() + " Science: " + jsonPL[0]["science"] .toString();
                                 }
                                 else {
                                     message = "Data not available. Check if student's mark is added or student might not be in our system.";
                                 }
                                 io:println("\n"+ message + "\n");
                             }
                             error err => {
                                 log:printError(err.message, err = err);
                             }
                         }
                     }
                     error err => {
                         log:printError(err.message, err = err);
                     }
                 }
             }
```

- Now we have completed the implementation of student management service with marks management service.


## Testing 

### Invoking the student management service

You can start both the services by opening a terminal and navigating to `ballerina-sp-tracing/guide`, and execute the following command.

```
$ ballerina run --config <path-to-conf>/ballerina.conf students
```

- You need to start the WSO2 Stream Processor dashboard and worker and navigate to the portal page. Here again use `admin` for both the username and password.

 You can observe the service performance by making some http requests to the above services. This is made easy for you as 
 there is a client program implemented. You can start the client program by opening another terminal and navigating to ballerina-sp-tracing/guide
 and run the below command
 
 ```
 $ ballerina run client_service
 ``` 
 
### Testing with Distributed Message Tracer.
 
#### Views of traces
 After making some http requests, go to the distributed message tracing dashboard in your WSO2 Stream Processor portal.


 - You are expected to see the traces as below when you press the search button in the dashboard.
 
![SP](images/trace1.png "SP")
 
 - To view a particular trace click on the trace row. And you will see as below
 
![SP](images/trace2.png "SP")
    
 - To view span details with metrics click on a particular span and you are expected to see as below
 
![SP](images/trace3.png "SP")

- You can filter the received traces by providing the service names, time and/or resource names in the tracing search box.

  - Tracing search -
  
  ![SP](images/trace6.png "SP")
  
  - Filter using service name and time -

   ![SP](images/trace5.png "SP")
     
  - Filter using resource name and time -

   ![SP](images/trace4.png "SP")
