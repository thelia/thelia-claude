# API Documentation Template

```markdown
# API Documentation

Base URL: `{base_url}/api`

## Authentication

```bash
curl -X POST {base_url}/api/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "xxx"}'
```

Response:
```json
{
  "token": "eyJ..."
}
```

Usage:
```bash
curl -H "Authorization: Bearer {token}" {base_url}/api/resource
```

## Endpoints

### {Resource}

#### List

```http
GET /api/{resources}
```

**Query params:**

| Param | Type | Description |
|-------|------|-------------|
| `page` | int | Page number (default: 1) |
| `itemsPerPage` | int | Items per page (default: 30) |
| `order[field]` | string | Sort order (asc/desc) |

**Response 200:**

```json
{
  "hydra:member": [
    {"id": 1, "name": "..."}
  ],
  "hydra:totalItems": 42
}
```

#### Get one

```http
GET /api/{resources}/{id}
```

**Response 200:**

```json
{
  "id": 1,
  "name": "..."
}
```

**Errors:**

| Code | Description |
|------|-------------|
| 404 | Resource not found |

#### Create

```http
POST /api/{resources}
```

**Body:**

```json
{
  "field1": "value",
  "field2": 123
}
```

**Response 201:**

```json
{
  "id": 1,
  "field1": "value"
}
```

**Errors:**

| Code | Description |
|------|-------------|
| 400 | Invalid data |
| 401 | Unauthenticated |

#### Update

```http
PUT /api/{resources}/{id}
```

**Response 200:** Updated resource

#### Delete

```http
DELETE /api/{resources}/{id}
```

**Response 204:** No content
```
