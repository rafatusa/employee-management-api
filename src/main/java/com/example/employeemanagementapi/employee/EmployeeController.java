package com.example.employeemanagementapi.employee;

import jakarta.validation.Valid;
import java.net.URI;
import java.util.List;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

/**
 * CRUD endpoints for the employee directory.
 */
@RestController
@RequestMapping("/api/v1/employees")
public class EmployeeController {

    private final EmployeeService service;

    public EmployeeController(final EmployeeService service) {
        this.service = service;
    }

    @GetMapping
    public List<EmployeeResponse> list(
            @RequestParam(name = "department", required = false) final String department) {
        return service.findAll(department);
    }

    @GetMapping("/{id}")
    public EmployeeResponse get(@PathVariable("id") final Long id) {
        return service.findById(id);
    }

    @PostMapping
    public ResponseEntity<EmployeeResponse> create(@Valid @RequestBody final EmployeeRequest request) {
        final EmployeeResponse created = service.create(request);
        return ResponseEntity.created(URI.create("/api/v1/employees/" + created.id())).body(created);
    }

    @PutMapping("/{id}")
    public EmployeeResponse update(@PathVariable("id") final Long id,
                                   @Valid @RequestBody final EmployeeRequest request) {
        return service.update(id, request);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable("id") final Long id) {
        service.delete(id);
    }
}
