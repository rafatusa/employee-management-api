package com.example.employeemanagementapi.employee;

/**
 * Raised when an email address is already used by another employee.
 */
public class DuplicateEmailException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    public DuplicateEmailException(final String email) {
        super("Email " + email + " is already registered");
    }
}
