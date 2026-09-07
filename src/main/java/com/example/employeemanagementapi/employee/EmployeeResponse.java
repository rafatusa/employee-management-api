package com.example.employeemanagementapi.employee;

import com.fasterxml.jackson.annotation.JsonFormat;
import java.time.LocalDate;

/**
 * Outbound representation of an employee.
 *
 * @param id         surrogate key
 * @param firstName  given name
 * @param lastName   family name
 * @param email      unique business email
 * @param department owning department
 * @param position   job title
 * @param hiredOn    hire date (ISO-8601)
 */
public record EmployeeResponse(
        Long id,
        String firstName,
        String lastName,
        String email,
        String department,
        String position,
        @JsonFormat(pattern = "yyyy-MM-dd") LocalDate hiredOn) {

    static EmployeeResponse from(final Employee employee) {
        return new EmployeeResponse(
                employee.getId(),
                employee.getFirstName(),
                employee.getLastName(),
                employee.getEmail(),
                employee.getDepartment(),
                employee.getPosition(),
                employee.getHiredOn());
    }
}
