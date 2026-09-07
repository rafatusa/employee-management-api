package com.example.employeemanagementapi.employee;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.time.LocalDate;
import java.util.List;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class EmployeeServiceTest {

    @Mock
    private EmployeeRepository repository;

    private EmployeeService service;

    private Employee stored;

    @BeforeEach
    void setUp() {
        service = new EmployeeService(repository);
        stored = new Employee("Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15));
    }

    private static EmployeeRequest request(final String email) {
        return new EmployeeRequest("Grace", "Hopper", email,
                "Engineering", "Architect", LocalDate.of(2021, 6, 1));
    }

    @Test
    @DisplayName("findAll without a department returns every employee")
    void findAllReturnsAll() {
        when(repository.findAll()).thenReturn(List.of(stored));

        final List<EmployeeResponse> result = service.findAll(null);

        assertThat(result).hasSize(1);
        assertThat(result.get(0).email()).isEqualTo("ada@example.com");
        verify(repository).findAll();
    }

    @Test
    @DisplayName("findAll with a blank department falls back to the full list")
    void findAllTreatsBlankDepartmentAsNoFilter() {
        when(repository.findAll()).thenReturn(List.of(stored));

        assertThat(service.findAll("   ")).hasSize(1);

        verify(repository).findAll();
        verify(repository, never()).findByDepartmentIgnoreCase(any());
    }

    @Test
    @DisplayName("findAll with a department filters and trims the value")
    void findAllFiltersByDepartment() {
        when(repository.findByDepartmentIgnoreCase("Engineering")).thenReturn(List.of(stored));

        assertThat(service.findAll("  Engineering  ")).hasSize(1);

        verify(repository).findByDepartmentIgnoreCase("Engineering");
    }

    @Test
    @DisplayName("findById maps a stored employee")
    void findByIdReturnsEmployee() {
        when(repository.findById(1L)).thenReturn(Optional.of(stored));

        assertThat(service.findById(1L).firstName()).isEqualTo("Ada");
    }

    @Test
    @DisplayName("findById raises when the id is unknown")
    void findByIdRaisesWhenMissing() {
        when(repository.findById(99L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.findById(99L))
                .isInstanceOf(EmployeeNotFoundException.class)
                .hasMessageContaining("99");
    }

    @Test
    @DisplayName("create normalises the email and persists")
    void createPersistsNormalisedEmail() {
        when(repository.existsByEmail("grace@example.com")).thenReturn(false);
        when(repository.save(any(Employee.class))).thenAnswer(inv -> inv.getArgument(0));

        final EmployeeResponse created = service.create(request("  GRACE@Example.com  "));

        final ArgumentCaptor<Employee> captor = ArgumentCaptor.forClass(Employee.class);
        verify(repository).save(captor.capture());
        assertThat(captor.getValue().getEmail()).isEqualTo("grace@example.com");
        assertThat(created.department()).isEqualTo("Engineering");
    }

    @Test
    @DisplayName("create rejects a duplicate email")
    void createRejectsDuplicate() {
        when(repository.existsByEmail("grace@example.com")).thenReturn(true);

        assertThatThrownBy(() -> service.create(request("grace@example.com")))
                .isInstanceOf(DuplicateEmailException.class)
                .hasMessageContaining("grace@example.com");

        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("update overwrites every mutable field")
    void updateOverwritesFields() {
        when(repository.findById(1L)).thenReturn(Optional.of(stored));
        when(repository.existsByEmail("grace@example.com")).thenReturn(false);
        when(repository.save(any(Employee.class))).thenAnswer(inv -> inv.getArgument(0));

        final EmployeeResponse updated = service.update(1L, request("grace@example.com"));

        assertThat(updated.firstName()).isEqualTo("Grace");
        assertThat(updated.lastName()).isEqualTo("Hopper");
        assertThat(updated.position()).isEqualTo("Architect");
        assertThat(updated.hiredOn()).isEqualTo(LocalDate.of(2021, 6, 1));
    }

    @Test
    @DisplayName("update keeps the same email without a duplicate check failure")
    void updateAllowsUnchangedEmail() {
        when(repository.findById(1L)).thenReturn(Optional.of(stored));
        when(repository.save(any(Employee.class))).thenAnswer(inv -> inv.getArgument(0));

        final EmployeeResponse updated = service.update(1L, request("ada@example.com"));

        assertThat(updated.email()).isEqualTo("ada@example.com");
        verify(repository, never()).existsByEmail(any());
    }

    @Test
    @DisplayName("update rejects moving to an email another employee owns")
    void updateRejectsDuplicateEmail() {
        when(repository.findById(1L)).thenReturn(Optional.of(stored));
        when(repository.existsByEmail("grace@example.com")).thenReturn(true);

        assertThatThrownBy(() -> service.update(1L, request("grace@example.com")))
                .isInstanceOf(DuplicateEmailException.class);

        verify(repository, never()).save(any());
    }

    @Test
    @DisplayName("update raises when the id is unknown")
    void updateRaisesWhenMissing() {
        when(repository.findById(42L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.update(42L, request("grace@example.com")))
                .isInstanceOf(EmployeeNotFoundException.class);
    }

    @Test
    @DisplayName("delete removes an existing employee")
    void deleteRemovesEmployee() {
        when(repository.existsById(1L)).thenReturn(true);

        service.delete(1L);

        verify(repository, times(1)).deleteById(1L);
    }

    @Test
    @DisplayName("delete raises when the id is unknown")
    void deleteRaisesWhenMissing() {
        when(repository.existsById(anyLong())).thenReturn(false);

        assertThatThrownBy(() -> service.delete(7L))
                .isInstanceOf(EmployeeNotFoundException.class);

        verify(repository, never()).deleteById(anyLong());
    }
}
