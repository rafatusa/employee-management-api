package com.example.employeemanagementapi.employee;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.doNothing;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.example.employeemanagementapi.config.SecurityConfig;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.time.LocalDate;
import java.util.List;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(controllers = EmployeeController.class)
@Import({SecurityConfig.class, ApiExceptionHandler.class})
@ActiveProfiles("test")
class EmployeeControllerTest {

    private static final String ADMIN_USER = "admin";
    private static final String ADMIN_PASS = "test-admin-password";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private EmployeeService service;

    private static EmployeeResponse sample() {
        return new EmployeeResponse(1L, "Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15));
    }

    private static EmployeeRequest validRequest() {
        return new EmployeeRequest("Ada", "Lovelace", "ada@example.com",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15));
    }

    @Test
    void listRequiresAuthentication() throws Exception {
        mockMvc.perform(get("/api/v1/employees"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void listReturnsEmployees() throws Exception {
        when(service.findAll(null)).thenReturn(List.of(sample()));

        mockMvc.perform(get("/api/v1/employees").with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[0].email").value("ada@example.com"))
                .andExpect(jsonPath("$[0].hiredOn").value("2020-01-15"));
    }

    @Test
    void listPassesDepartmentFilter() throws Exception {
        when(service.findAll("Engineering")).thenReturn(List.of(sample()));

        mockMvc.perform(get("/api/v1/employees")
                        .param("department", "Engineering")
                        .with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1));

        verify(service).findAll("Engineering");
    }

    @Test
    void getReturnsEmployee() throws Exception {
        when(service.findById(1L)).thenReturn(sample());

        mockMvc.perform(get("/api/v1/employees/1").with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.id").value(1));
    }

    @Test
    void getUnknownIdReturns404() throws Exception {
        when(service.findById(99L)).thenThrow(new EmployeeNotFoundException(99L));

        mockMvc.perform(get("/api/v1/employees/99").with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.status").value(404))
                .andExpect(jsonPath("$.path").value("/api/v1/employees/99"));
    }

    @Test
    void createReturns201WithLocation() throws Exception {
        when(service.create(any(EmployeeRequest.class))).thenReturn(sample());

        mockMvc.perform(post("/api/v1/employees")
                        .with(httpBasic(ADMIN_USER, ADMIN_PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(validRequest())))
                .andExpect(status().isCreated())
                .andExpect(header().string("Location", "/api/v1/employees/1"));
    }

    @Test
    void createRejectsInvalidPayload() throws Exception {
        final EmployeeRequest invalid = new EmployeeRequest("", "Lovelace", "not-an-email",
                "Engineering", "Principal Engineer", LocalDate.of(2020, 1, 15));

        mockMvc.perform(post("/api/v1/employees")
                        .with(httpBasic(ADMIN_USER, ADMIN_PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(invalid)))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.status").value(400));
    }

    @Test
    void createDuplicateEmailReturns409() throws Exception {
        when(service.create(any(EmployeeRequest.class)))
                .thenThrow(new DuplicateEmailException("ada@example.com"));

        mockMvc.perform(post("/api/v1/employees")
                        .with(httpBasic(ADMIN_USER, ADMIN_PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(validRequest())))
                .andExpect(status().isConflict())
                .andExpect(jsonPath("$.status").value(409));
    }

    @Test
    void updateReturnsUpdatedEmployee() throws Exception {
        when(service.update(eq(1L), any(EmployeeRequest.class))).thenReturn(sample());

        mockMvc.perform(put("/api/v1/employees/1")
                        .with(httpBasic(ADMIN_USER, ADMIN_PASS))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(validRequest())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.lastName").value("Lovelace"));
    }

    @Test
    void deleteReturns204() throws Exception {
        doNothing().when(service).delete(1L);

        mockMvc.perform(delete("/api/v1/employees/1").with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isNoContent());

        verify(service).delete(1L);
    }

    @Test
    void deleteUnknownIdReturns404() throws Exception {
        doThrow(new EmployeeNotFoundException(55L)).when(service).delete(55L);

        mockMvc.perform(delete("/api/v1/employees/55").with(httpBasic(ADMIN_USER, ADMIN_PASS)))
                .andExpect(status().isNotFound());
    }

    @Test
    void wrongPasswordIsRejected() throws Exception {
        mockMvc.perform(get("/api/v1/employees").with(httpBasic(ADMIN_USER, "wrong-password")))
                .andExpect(status().isUnauthorized());
    }
}
