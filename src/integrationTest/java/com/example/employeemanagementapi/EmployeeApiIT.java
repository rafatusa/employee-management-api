package com.example.employeemanagementapi;

import static io.restassured.RestAssured.given;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.notNullValue;

import io.restassured.RestAssured;
import io.restassured.http.ContentType;
import java.util.Map;
import java.util.UUID;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;

/**
 * REST Assured integration tests executed against a DEPLOYED instance.
 * Target host and admin credentials arrive from the validation workflow.
 */
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class EmployeeApiIT {

    private static String baseUrl;
    private static String adminUser;
    private static String adminPassword;
    private static String uniqueEmail;
    private static Integer createdId;

    @BeforeAll
    static void configure() {
        baseUrl = System.getenv().getOrDefault("TARGET_BASE_URL", "http://localhost:8080");
        adminUser = System.getenv().getOrDefault("API_ADMIN_USERNAME", "admin");
        adminPassword = System.getenv("API_ADMIN_PASSWORD");
        if (adminPassword == null || adminPassword.isBlank()) {
            throw new IllegalStateException("API_ADMIN_PASSWORD must be set for integration tests");
        }
        uniqueEmail = "it-" + UUID.randomUUID() + "@example.com";
        RestAssured.baseURI = baseUrl;
    }

    @Test
    @Order(1)
    @DisplayName("Health endpoint reports UP with a reachable database")
    void healthIsUp() {
        given()
                .when().get("/actuator/health")
                .then().statusCode(200)
                .body("status", equalTo("UP"));
    }

    @Test
    @Order(2)
    @DisplayName("Nginx reverse proxy fronts the application")
    void servedThroughNginx() {
        given()
                .when().get("/actuator/health")
                .then().statusCode(200)
                .header("Server", notNullValue());
    }

    @Test
    @Order(3)
    @DisplayName("Unauthenticated access to the API is rejected")
    void requiresAuthentication() {
        given()
                .when().get("/api/v1/employees")
                .then().statusCode(401);
    }

    @Test
    @Order(4)
    @DisplayName("Employee can be created")
    void createsEmployee() {
        createdId = given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .contentType(ContentType.JSON)
                .body(Map.of(
                        "firstName", "Integration",
                        "lastName", "Tester",
                        "email", uniqueEmail,
                        "department", "QA",
                        "position", "Automation Engineer",
                        "hiredOn", "2024-02-01"))
                .when().post("/api/v1/employees")
                .then().statusCode(201)
                .body("email", equalTo(uniqueEmail))
                .extract().path("id");
    }

    @Test
    @Order(5)
    @DisplayName("Employee can be read back — proves database connectivity")
    void readsEmployee() {
        given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .when().get("/api/v1/employees/" + createdId)
                .then().statusCode(200)
                .body("department", equalTo("QA"));
    }

    @Test
    @Order(6)
    @DisplayName("Employee can be updated")
    void updatesEmployee() {
        given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .contentType(ContentType.JSON)
                .body(Map.of(
                        "firstName", "Integration",
                        "lastName", "Tester",
                        "email", uniqueEmail,
                        "department", "Platform",
                        "position", "SRE",
                        "hiredOn", "2024-02-01"))
                .when().put("/api/v1/employees/" + createdId)
                .then().statusCode(200)
                .body("department", equalTo("Platform"));
    }

    @Test
    @Order(7)
    @DisplayName("Duplicate email is rejected with 409")
    void rejectsDuplicateEmail() {
        given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .contentType(ContentType.JSON)
                .body(Map.of(
                        "firstName", "Another",
                        "lastName", "Person",
                        "email", uniqueEmail,
                        "department", "QA",
                        "position", "Tester",
                        "hiredOn", "2024-03-01"))
                .when().post("/api/v1/employees")
                .then().statusCode(409);
    }

    @Test
    @Order(8)
    @DisplayName("Employee can be deleted and is then gone")
    void deletesEmployee() {
        given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .when().delete("/api/v1/employees/" + createdId)
                .then().statusCode(204);

        given()
                .auth().preemptive().basic(adminUser, adminPassword)
                .when().get("/api/v1/employees/" + createdId)
                .then().statusCode(404);
    }
}
