package com.example.employeemanagementapi.employee;

import com.fasterxml.jackson.annotation.JsonFormat;
import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.LocalDate;

/**
 * Inbound payload for creating or replacing an employee.
 *
 * @param firstName  given name
 * @param lastName   family name
 * @param email      unique business email
 * @param department owning department
 * @param position   job title
 * @param hiredOn    hire date (ISO-8601)
 */
public record EmployeeRequest(
        @NotBlank @Size(max = 100) String firstName,
        @NotBlank @Size(max = 100) String lastName,
        @NotBlank @Email @Size(max = 320) String email,
        @NotBlank @Size(max = 100) String department,
        @NotBlank @Size(max = 100) String position,
        @NotNull @JsonFormat(pattern = "yyyy-MM-dd") LocalDate hiredOn) {
}
