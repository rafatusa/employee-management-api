package com.example.employeemanagementapi.employee;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;

class EmployeeExceptionTest {

    @Test
    void notFoundMessageNamesTheId() {
        final EmployeeNotFoundException ex = new EmployeeNotFoundException(42L);

        assertThat(ex).isInstanceOf(RuntimeException.class);
        assertThat(ex.getMessage()).isEqualTo("Employee 42 was not found");
    }

    @Test
    void duplicateEmailMessageNamesTheAddress() {
        final DuplicateEmailException ex = new DuplicateEmailException("ada@example.com");

        assertThat(ex).isInstanceOf(RuntimeException.class);
        assertThat(ex.getMessage()).isEqualTo("Email ada@example.com is already registered");
    }
}
