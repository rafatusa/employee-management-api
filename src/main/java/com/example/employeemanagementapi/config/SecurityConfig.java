package com.example.employeemanagementapi.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.actuate.autoconfigure.security.servlet.EndpointRequest;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;

/**
 * HTTP Basic security: reads require authentication, writes require the admin role.
 */
@Configuration
@EnableWebSecurity
public class SecurityConfig {

    private final String adminUsername;
    private final String adminPassword;

    public SecurityConfig(
            @Value("${app.security.admin-username:admin}") final String adminUsername,
            @Value("${app.security.admin-password}") final String adminPassword) {
        this.adminUsername = adminUsername;
        this.adminPassword = adminPassword;
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    /**
     * Single administrative principal held in memory.
     *
     * <p>This is deliberate for a single-tenant internal directory API: there is
     * no user-management requirement, so persisting a users table would add an
     * attack surface and a migration burden without adding capability. The
     * credential itself is never in the source — it arrives from the
     * API_ADMIN_PASSWORD secret and is BCrypt-hashed before storage. Introducing
     * multi-user access means replacing this bean with a JDBC-backed
     * UserDetailsService, not extending it.
     */
    @Bean
    public UserDetailsService userDetailsService(final PasswordEncoder passwordEncoder) {
        final UserDetails admin = User.withUsername(adminUsername)
                .password(passwordEncoder.encode(adminPassword))
                .roles("ADMIN")
                .build();
        return new InMemoryUserDetailsManager(admin);
    }

    @Bean
    public SecurityFilterChain filterChain(final HttpSecurity http) throws Exception {
        http
                // CSRF protection is disabled deliberately and safely here.
                // CSRF requires the browser to attach an ambient credential
                // (cookie or session) to a forged cross-origin request. This API
                // is STATELESS: it authenticates every request with an explicit
                // HTTP Basic Authorization header, creates no session (see
                // SessionCreationPolicy.STATELESS below) and issues no cookie.
                // There is therefore no ambient credential for an attacker to
                // leverage, and a CSRF token would protect nothing.
                // nosemgrep: spring-csrf-disabled
                .csrf(csrf -> csrf.disable())
                .sessionManagement(session ->
                        session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> auth
                        .requestMatchers(EndpointRequest.to("health", "info")).permitAll()
                        .requestMatchers("/", "/index.html", "/favicon.ico").permitAll()
                        .requestMatchers(HttpMethod.GET, "/api/v1/employees/**").authenticated()
                        .requestMatchers(HttpMethod.POST, "/api/v1/employees/**").hasRole("ADMIN")
                        .requestMatchers(HttpMethod.PUT, "/api/v1/employees/**").hasRole("ADMIN")
                        .requestMatchers(HttpMethod.DELETE, "/api/v1/employees/**").hasRole("ADMIN")
                        .anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults());
        return http.build();
    }
}
