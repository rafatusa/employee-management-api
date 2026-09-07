CREATE TABLE employees (
    id          BIGSERIAL    PRIMARY KEY,
    first_name  VARCHAR(100) NOT NULL,
    last_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(320) NOT NULL,
    department  VARCHAR(100) NOT NULL,
    position    VARCHAR(100) NOT NULL,
    hired_on    DATE         NOT NULL
);

ALTER TABLE employees ADD CONSTRAINT uq_employees_email UNIQUE (email);

CREATE INDEX idx_employees_department ON employees (LOWER(department));
