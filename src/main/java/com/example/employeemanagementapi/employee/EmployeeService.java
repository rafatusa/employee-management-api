package com.example.employeemanagementapi.employee;

import java.util.List;
import java.util.Locale;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * Business operations over the employee directory.
 */
@Service
public class EmployeeService {

    private final EmployeeRepository repository;

    public EmployeeService(final EmployeeRepository repository) {
        this.repository = repository;
    }

    @Transactional(readOnly = true)
    public List<EmployeeResponse> findAll(final String department) {
        final List<Employee> found = (department == null || department.isBlank())
                ? repository.findAll()
                : repository.findByDepartmentIgnoreCase(department.trim());
        return found.stream().map(EmployeeResponse::from).toList();
    }

    @Transactional(readOnly = true)
    public EmployeeResponse findById(final Long id) {
        return repository.findById(id)
                .map(EmployeeResponse::from)
                .orElseThrow(() -> new EmployeeNotFoundException(id));
    }

    @Transactional
    public EmployeeResponse create(final EmployeeRequest request) {
        final String email = normaliseEmail(request.email());
        if (repository.existsByEmail(email)) {
            throw new DuplicateEmailException(email);
        }
        final Employee employee = new Employee(
                request.firstName().trim(),
                request.lastName().trim(),
                email,
                request.department().trim(),
                request.position().trim(),
                request.hiredOn());
        return EmployeeResponse.from(repository.save(employee));
    }

    @Transactional
    public EmployeeResponse update(final Long id, final EmployeeRequest request) {
        final Employee employee = repository.findById(id)
                .orElseThrow(() -> new EmployeeNotFoundException(id));
        final String email = normaliseEmail(request.email());
        if (!employee.getEmail().equals(email) && repository.existsByEmail(email)) {
            throw new DuplicateEmailException(email);
        }
        employee.setFirstName(request.firstName().trim());
        employee.setLastName(request.lastName().trim());
        employee.setEmail(email);
        employee.setDepartment(request.department().trim());
        employee.setPosition(request.position().trim());
        employee.setHiredOn(request.hiredOn());
        return EmployeeResponse.from(repository.save(employee));
    }

    @Transactional
    public void delete(final Long id) {
        if (!repository.existsById(id)) {
            throw new EmployeeNotFoundException(id);
        }
        repository.deleteById(id);
    }

    private static String normaliseEmail(final String email) {
        return email.trim().toLowerCase(Locale.ROOT);
    }
}
