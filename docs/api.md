# API Reference

Base URL: `http://<elastic-ip>` (Nginx on port 80 proxies to the application).

## Authentication

HTTP Basic. Every endpoint requires authentication except `/actuator/health`, `/actuator/info` and
the landing page.

| Operation | Required role |
|---|---|
| `GET` on `/api/v1/employees/**` | any authenticated user |
| `POST` / `PUT` / `DELETE` | `ADMIN` |

The admin credentials come from the `API_ADMIN_USERNAME` / `API_ADMIN_PASSWORD` environment
variables, which Chef renders from repository secrets.

```bash
curl -u admin:$API_ADMIN_PASSWORD http://<host>/api/v1/employees
```

An unauthenticated request returns `401 Unauthorized`.

---

## Resource: Employee

```json
{
  "id": 1,
  "firstName": "Ada",
  "lastName": "Lovelace",
  "email": "ada@example.com",
  "department": "Engineering",
  "position": "Principal Engineer",
  "hiredOn": "2020-01-15"
}
```

### Field constraints

| Field | Type | Constraints |
|---|---|---|
| `id` | integer | Read-only, server-assigned |
| `firstName` | string | Required, non-blank, ≤ 100 chars |
| `lastName` | string | Required, non-blank, ≤ 100 chars |
| `email` | string | Required, valid email, ≤ 320 chars, **unique**; normalised to lowercase |
| `department` | string | Required, non-blank, ≤ 100 chars |
| `position` | string | Required, non-blank, ≤ 100 chars |
| `hiredOn` | string | Required, ISO-8601 date (`yyyy-MM-dd`) |

---

## Endpoints

### `GET /api/v1/employees`

Lists employees. Optional `department` query parameter filters case-insensitively.

```bash
curl -u admin:••• "http://<host>/api/v1/employees?department=Engineering"
```

**200 OK** — JSON array of employees.

---

### `GET /api/v1/employees/{id}`

**200 OK** — the employee.
**404 Not Found** — no employee with that id.

---

### `POST /api/v1/employees`

Creates an employee. Requires `ADMIN`.

```bash
curl -u admin:••• -X POST http://<host>/api/v1/employees \
  -H 'Content-Type: application/json' \
  -d '{
        "firstName": "Grace",
        "lastName": "Hopper",
        "email": "grace@example.com",
        "department": "Research",
        "position": "Rear Admiral",
        "hiredOn": "2021-06-01"
      }'
```

**201 Created** — the created employee; `Location` header points at the new resource.
**400 Bad Request** — validation failure.
**409 Conflict** — the email is already registered.

---

### `PUT /api/v1/employees/{id}`

Replaces an employee. Requires `ADMIN`. Same body as `POST`.

**200 OK** — the updated employee.
**400 / 404 / 409** — as above.

---

### `DELETE /api/v1/employees/{id}`

Requires `ADMIN`.

**204 No Content** — deleted.
**404 Not Found** — no employee with that id.

---

### `GET /actuator/health`

Public. Reports application liveness and database connectivity.

```json
{ "status": "UP" }
```

A `DOWN` status here almost always means the application cannot reach RDS — see the operations
guide.

---

## Error format

All errors share one shape:

```json
{
  "timestamp": "2026-09-07T12:34:56.789Z",
  "status": 404,
  "error": "Not Found",
  "message": "Employee 99 was not found",
  "path": "/api/v1/employees/99"
}
```

| Status | Meaning |
|---|---|
| `400` | Validation failed — `message` lists the offending fields |
| `401` | Missing or incorrect credentials |
| `403` | Authenticated but lacking the `ADMIN` role |
| `404` | Resource does not exist |
| `409` | Email already registered |
