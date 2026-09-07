package com.example.employeemanagementapi.employee;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import org.junit.jupiter.api.Test;

class EmployeeTest {

    private static Employee sample() {
        return new Employee("Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15));
    }

    @Test
    void constructorPopulatesEveryField() {
        final Employee employee = sample();

        assertThat(employee.getFirstName()).isEqualTo("Ada");
        assertThat(employee.getLastName()).isEqualTo("Lovelace");
        assertThat(employee.getEmail()).isEqualTo("ada@example.com");
        assertThat(employee.getDepartment()).isEqualTo("Engineering");
        assertThat(employee.getPosition()).isEqualTo("Principal Engineer");
        assertThat(employee.getHiredOn()).isEqualTo(LocalDate.of(2020, 1, 15));
        assertThat(employee.getId()).isNull();
    }

    @Test
    void settersReplaceValues() {
        final Employee employee = sample();

        employee.setFirstName("Grace");
        employee.setLastName("Hopper");
        employee.setEmail("grace@example.com");
        employee.setDepartment("Research");
        employee.setPosition("Rear Admiral");
        employee.setHiredOn(LocalDate.of(1944, 7, 2));

        assertThat(employee.getFirstName()).isEqualTo("Grace");
        assertThat(employee.getLastName()).isEqualTo("Hopper");
        assertThat(employee.getEmail()).isEqualTo("grace@example.com");
        assertThat(employee.getDepartment()).isEqualTo("Research");
        assertThat(employee.getPosition()).isEqualTo("Rear Admiral");
        assertThat(employee.getHiredOn()).isEqualTo(LocalDate.of(1944, 7, 2));
    }

    @Test
    void equalsIsIdentityBasedForTransientInstances() {
        final Employee first = sample();
        final Employee second = sample();

        assertThat(first).isEqualTo(first);
        // Both are transient (null id), so they are never considered equal.
        assertThat(first).isNotEqualTo(second);
        assertThat(first).isNotEqualTo("not-an-employee");
        assertThat(first).isNotEqualTo(null);
    }

    @Test
    void hashCodeIsStableForTransientInstances() {
        assertThat(sample().hashCode()).isEqualTo(sample().hashCode());
    }

    @Test
    void toStringExposesEmailAndId() {
        assertThat(sample().toString()).contains("ada@example.com");
    }
}
