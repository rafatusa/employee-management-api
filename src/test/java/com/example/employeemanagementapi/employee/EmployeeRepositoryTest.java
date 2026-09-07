package com.example.employeemanagementapi.employee;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.test.context.ActiveProfiles;

@DataJpaTest
@ActiveProfiles("test")
class EmployeeRepositoryTest {

    @Autowired
    private EmployeeRepository repository;

    @BeforeEach
    void seed() {
        repository.deleteAll();
        repository.save(new Employee("Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15)));
        repository.save(new Employee("Grace", "Hopper", "grace@example.com",
                "Research", "Rear Admiral", LocalDate.of(2021, 6, 1)));
    }

    @Test
    void savesAndAssignsIdentity() {
        final Employee saved = repository.save(new Employee("Alan", "Turing", "alan@example.com",
                "Research", "Cryptanalyst", LocalDate.of(2019, 3, 3)));

        assertThat(saved.getId()).isNotNull();
    }

    @Test
    void findsByEmail() {
        assertThat(repository.findByEmail("ada@example.com")).isPresent();
        assertThat(repository.findByEmail("nobody@example.com")).isEmpty();
    }

    @Test
    void reportsEmailExistence() {
        assertThat(repository.existsByEmail("grace@example.com")).isTrue();
        assertThat(repository.existsByEmail("nobody@example.com")).isFalse();
    }

    @Test
    void findsByDepartmentIgnoringCase() {
        assertThat(repository.findByDepartmentIgnoreCase("engineering")).hasSize(1);
        assertThat(repository.findByDepartmentIgnoreCase("RESEARCH")).hasSize(1);
        assertThat(repository.findByDepartmentIgnoreCase("Finance")).isEmpty();
    }

    @Test
    void deletesById() {
        final Long id = repository.findByEmail("ada@example.com").orElseThrow().getId();

        repository.deleteById(id);

        assertThat(repository.findById(id)).isEmpty();
    }
}
