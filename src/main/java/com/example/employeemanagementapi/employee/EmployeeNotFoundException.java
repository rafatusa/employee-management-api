package com.example.employeemanagementapi.employee;

/**
 * Raised when an employee id does not resolve to a stored record.
 */
public class EmployeeNotFoundException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    public EmployeeNotFoundException(final Long id) {
        super("Employee " + id + " was not found");
    }
}
