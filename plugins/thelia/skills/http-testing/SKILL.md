---
name: http-testing
description: "Test HTTP routes, API endpoints, and URLs of a web project with curl. Use this skill when asked to test routes, verify an endpoint, validate a URL, check a module, test a REST API, verify HTTP status codes, debug a 404/500/403 route, or test after creating a controller, route, or action. Keywords: test route, curl, HTTP status, endpoint, API test, verify URL, route testing, smoke test, health check, test module, test controller, debug route, test POST, test GET, test DELETE, response code, redirect, CSRF token, authentication, login test, cookie session, JWT token, bearer auth."
---

# HTTP Route Testing

Test HTTP routes of a module or bundle after creation or modification, using curl inside the project environment.

## When to trigger

- After creating or modifying routes, controllers, or API endpoints.
- When asked to "test routes", "check the module", "verify the endpoint", or "validate the URL".
- To produce an HTTP test report.

## Step 1: Detect the environment

Check whether the project uses DDEV or a local server.

```bash
# If .ddev/config.yaml exists, prefix all curl commands with ddev exec
ls .ddev/config.yaml 2>/dev/null && echo "DDEV"
```

| Environment | Command prefix | Base URL |
|-------------|----------------|----------|
| DDEV | `ddev exec` | `http://localhost` |
| Local | none | `http://localhost:8080` |

## Step 2: Check credentials

**Required before testing protected routes.**

```bash
grep "TEST_USER" .env.local 2>/dev/null
```

If not found: STOP immediately. Display:
> "Test credentials missing in .env.local. Provide TEST_USER_EMAIL and TEST_USER_PASSWORD to test protected routes."

Never invent credentials. Wait for the user to provide them.

## Step 3: Detect the framework

```bash
# Fetch the login page
ddev exec curl -s "http://localhost/admin/login" -c /tmp/cookies.txt -o /tmp/login.html

# Look for form field clues
ddev exec grep -E "(thelia_admin_login|_username|email.*password)" /tmp/login.html | head -3
```

| Pattern found | Framework |
|---------------|-----------|
| `thelia_admin_login` | Thelia 2 |
| `_username` + `_password` | Symfony standard |
| `email` + `password` | Symfony (variant) |

## Step 4: Authenticate

See `references/authentication-flows.md` for per-framework procedures:
- **Thelia 2**: login via `/admin/checklogin` with `thelia_admin_login[...]` fields
- **Symfony form_login**: login via `/login` with `_username`, `_password`, `_csrf_token` fields
- **Symfony API (JWT)**: JSON login via `/api/login`, use `Authorization: Bearer $TOKEN`

For each framework, extract the CSRF token from the form before the login POST. Use both `-b` and `-c` to carry cookies between requests.

## Step 5: Test routes

### Single route

```bash
ddev exec curl -s -o /dev/null -w "%{http_code}" "http://localhost/admin/path" -b /tmp/cookies.txt
```

### Batch of routes

```bash
echo "=== TEST ROUTES ===" && \
ddev exec curl -s -o /dev/null -w "GET /admin/list : %{http_code}\n" "http://localhost/admin/list" -b /tmp/cookies.txt && \
ddev exec curl -s -o /dev/null -w "GET /admin/create : %{http_code}\n" "http://localhost/admin/create" -b /tmp/cookies.txt && \
ddev exec curl -s -o /dev/null -w "GET /admin/edit/1 : %{http_code}\n" "http://localhost/admin/edit/1" -b /tmp/cookies.txt
```

### Check redirects

```bash
ddev exec curl -s -w "Redirect: %{redirect_url}\n" "http://localhost/admin/action/1" -b /tmp/cookies.txt -o /dev/null
```

### Verify response content

```bash
ddev exec curl -s "http://localhost/admin/list" -b /tmp/cookies.txt | grep -E "(<title>|<table|expected)" | head -5
```

### Test a POST route with data

```bash
# Extract the CSRF token from the form
CSRF=$(ddev exec curl -s "http://localhost/admin/create" -b /tmp/cookies.txt | grep -oP 'name=".*_token"[^>]*value="\K[^"]+')

# Submit the form
ddev exec curl -s -X POST "http://localhost/admin/create" \
  -b /tmp/cookies.txt \
  -d "form[field1]=value1" \
  -d "form[field2]=value2" \
  -d "form[_token]=$CSRF" \
  -w "%{http_code}"
```

## Step 6: Interpret results

| Code | Meaning | Action |
|------|---------|--------|
| 200 | OK | Route works |
| 201 | Created | Resource created (API) |
| 204 | No Content | Action succeeded without body (API DELETE) |
| 302 | Redirect | Normal after an action, or expired session |
| 401 | Unauthorized | Invalid or expired JWT token (API) |
| 403 | Forbidden | Invalid session or insufficient permissions |
| 404 | Not Found | Route not registered |
| 405 | Method Not Allowed | Wrong HTTP method (GET vs POST) |
| 500 | Server Error | Code bug: read the full response body to diagnose |

### Distinguishing error causes

- **403 before login**: normal on protected routes.
- **403 after login**: permissions issue (voter, role). Check `security.yaml`.
- **302 to /login**: session expired. Re-run the authentication flow.

## Step 7: Generate the report

Produce a report in this format:

```markdown
# Route Testing Report - [ModuleName]

## Environment
- Framework: Thelia 2 / Symfony
- Runtime: DDEV / Local

## Credentials Status
- [x] TEST_USER_EMAIL found in .env.local
- [x] TEST_USER_PASSWORD found in .env.local
- [x] Login successful

## Routes Tested

| Route | Method | HTTP | Status |
|-------|--------|------|--------|
| `/admin/...` | GET | 200 | OK |
| `/admin/.../create` | GET | 200 | OK - Form renders |
| `/admin/.../edit/X` | GET | 200 | OK - Data populated |
| `/admin/.../X` | DELETE | 302 | OK - Redirects to list |
| `/api/.../` | GET | 200 | OK - JSON response |

## Content Verification
- [x] List page displays data
- [x] Create form has all fields
- [x] Edit form populates data
- [x] API returns expected JSON structure

## Errors Found
None / List errors

## Summary
**X/X routes functional**
```

## Common pitfalls

| Framework | Common error | Fix |
|-----------|--------------|-----|
| All | Forgetting `ddev exec` | Always prefix with `ddev exec` in a DDEV environment |
| All | Cookie lost between requests | Use both `-b` and `-c` at login |
| Thelia 2 | POSTing to `/admin/login` | Use `/admin/checklogin` instead |
| Thelia 2 | Using `_username`/`_password` fields | Use `thelia_admin_login[...]` fields |
| Symfony | Forgetting `_csrf_token` | Extract it from the form before the POST |
| API | Missing Authorization header | Add `-H "Authorization: Bearer $TOKEN"` |

## References

- `references/authentication-flows.md`: Detailed per-framework authentication procedures (Thelia 2, Symfony form_login, Symfony API/JWT) with complete curl examples and quick-reference snippets.
