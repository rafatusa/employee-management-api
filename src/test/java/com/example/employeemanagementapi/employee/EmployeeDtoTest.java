package com.example.employeemanagementapi.employee;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;

/**
 * Covers the request/response carriers, including the mapping helper that the
 * service relies on. Records generate their accessors, but the mapping in
 * EmployeeResponse.from is hand-written and worth asserting directly.
 */
class EmployeeDtoTest {

    private static final LocalDate HIRED = LocalDate.of(2020, 1, 15);

    @Test
    void requestExposesEveryComponent() {
        final EmployeeRequest request = new EmployeeRequest(
                "Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", HIRED);

        assertThat(request.firstName()).isEqualTo("Ada");
        assertThat(request.lastName()).isEqualTo("Lovelace");
        assertThat(request.email()).isEqualTo("ada@example.com");
        assertThat(request.department()).isEqualTo("Engineering");
        assertThat(request.position()).isEqualTo("Principal Engineer");
        assertThat(request.hiredOn()).isEqualTo(HIRED);
    }

    @Test
    void requestValueSemantics() {
        final EmployeeRequest first = new EmployeeRequest(
                "Ada", "Lovelace", "ada@example.com", "Engineering", "Principal Engineer", HIRED);
        final EmployeeRequest second = new EmployeeRequest(
                "Ada", "Lovelace", "ada@example.com", "Engineering", "Principal Engineer", HIRED);

        assertThat(first).isEqualTo(second);
        assertThat(first).hasSameHashCodeAs(second);
        assertThat(first.toString()).contains("ada@example.com");
    }

    @Test
    void responseExposesEveryComponent() {
        final EmployeeResponse response = new EmployeeResponse(
                7L, "Grace", "Hopper", "grace@example.com", "Research", "Rear Admiral", HIRED);

        assertThat(response.id()).isEqualTo(7L);
        assertThat(response.firstName()).isEqualTo("Grace");
        assertThat(response.lastName()).isEqualTo("Hopper");
        assertThat(response.email()).isEqualTo("grace@example.com");
        assertThat(response.department()).isEqualTo("Research");
        assertThat(response.position()).isEqualTo("Rear Admiral");
        assertThat(response.hiredOn()).isEqualTo(HIRED);
    }

    @Test
    void responseValueSemantics() {
        final EmployeeResponse first = new EmployeeResponse(
                1L, "Ada", "Lovelace", "ada@example.com", "Engineering", "Principal Engineer", HIRED);
        final EmployeeResponse second = new EmployeeResponse(
                1L, "Ada", "Lovelace", "ada@example.com", "Engineering", "Principal Engineer", HIRED);

        assertThat(first).isEqualTo(second);
        assertThat(first).hasSameHashCodeAs(second);
        assertThat(first.toString()).contains("ada@example.com");
    }

    @Test
    void fromMapsEveryEntityField() {
        final Employee employee = new Employee(
                "Alan", "Turing", "alan@example.com", "Research", "Cryptanalyst", HIRED);

        final EmployeeResponse response = EmployeeResponse.from(employee);

        // id is null until the entity is persisted
        assertThat(response.id()).isNull();
        assertThat(response.firstName()).isEqualTo("Alan");
        assertThat(response.lastName()).isEqualTo("Turing");
        assertThat(response.email()).isEqualTo("alan@example.com");
        assertThat(response.department()).isEqualTo("Research");
        assertThat(response.position()).isEqualTo("Cryptanalyst");
        assertThat(response.hiredOn()).isEqualTo(HIRED);
    }
}
