# HTTP Authentication Flows by Framework

## Thelia 2

**Characteristics:**
- Login page: `/admin/login`
- Login action: `/admin/checklogin`
- Fields: `thelia_admin_login[username]`, `thelia_admin_login[password]`, `thelia_admin_login[_token]`

**Procedure:**

```bash
# 1. Fetch the page and save the cookie
ddev exec curl -s "http://localhost/admin/login" -c /tmp/cookies.txt -o /tmp/login.html

# 2. Extract the CSRF token
ddev exec grep -oP 'thelia_admin_login\[_token\]" value="\K[^"]+' /tmp/login.html
```

Store the result in `CSRF_TOKEN`, then:

```bash
TEST_USER_EMAIL=$(grep "^TEST_USER_EMAIL=" .env.local | cut -d'=' -f2)
TEST_USER_PASSWORD=$(grep "^TEST_USER_PASSWORD=" .env.local | cut -d'=' -f2)

# 3. Submit the login form
ddev exec curl -s -X POST "http://localhost/admin/checklogin" \
  -b /tmp/cookies.txt \
  -c /tmp/cookies.txt \
  -L \
  --data-urlencode "thelia_admin_login[username]=$TEST_USER_EMAIL" \
  --data-urlencode "thelia_admin_login[password]=$TEST_USER_PASSWORD" \
  --data-urlencode "thelia_admin_login[_token]=$CSRF_TOKEN" \
  -o /tmp/login_result.html
```

**Verify success:**
```bash
ddev exec curl -s "http://localhost/admin" -b /tmp/cookies.txt | grep -oP '<title>\K[^<]+'
```
- Success: title differs from the login page title
- Failure: title still shows the login page

### Thelia 2 + DDEV quick reference

```bash
# Login
ddev exec curl -s "http://localhost/admin/login" -c /tmp/cookies.txt -o /tmp/login.html && \
CSRF=$(ddev exec grep -oP 'thelia_admin_login\[_token\]" value="\K[^"]+' /tmp/login.html) && \
ddev exec curl -s -X POST "http://localhost/admin/checklogin" \
  -b /tmp/cookies.txt -c /tmp/cookies.txt -L \
  --data-urlencode "thelia_admin_login[username]=$(grep ^TEST_USER_EMAIL= .env.local | cut -d= -f2)" \
  --data-urlencode "thelia_admin_login[password]=$(grep ^TEST_USER_PASSWORD= .env.local | cut -d= -f2)" \
  --data-urlencode "thelia_admin_login[_token]=$CSRF" \
  -o /dev/null -w "Login: %{http_code}\n"

# Test a route
ddev exec curl -s -o /dev/null -w "%{http_code}" "http://localhost/admin/route" -b /tmp/cookies.txt
```

---

## Symfony standard (form_login)

**Characteristics:**
- Login page: `/login` or `/admin/login`
- Login action: `/login` or `/login_check`
- Fields: `_username`, `_password`, `_csrf_token`

**Procedure:**

```bash
# 1. Fetch the page and save the cookie
ddev exec curl -s "http://localhost/login" -c /tmp/cookies.txt -o /tmp/login.html

# 2. Extract the CSRF token
ddev exec grep -oP '_csrf_token"[^>]*value="\K[^"]+' /tmp/login.html
```

Store the result in `CSRF_TOKEN`, then:

```bash
TEST_USER_EMAIL=$(grep "^TEST_USER_EMAIL=" .env.local | cut -d'=' -f2)
TEST_USER_PASSWORD=$(grep "^TEST_USER_PASSWORD=" .env.local | cut -d'=' -f2)

# 3. Submit the login form
ddev exec curl -s -X POST "http://localhost/login" \
  -b /tmp/cookies.txt \
  -c /tmp/cookies.txt \
  -L \
  -d "_username=$TEST_USER_EMAIL" \
  -d "_password=$TEST_USER_PASSWORD" \
  -d "_csrf_token=$CSRF_TOKEN" \
  -o /tmp/login_result.html -w "%{http_code}"
```

**Verify success:**
- HTTP 302 redirect to dashboard/home: success
- HTTP 302 redirect back to `/login`: failure (invalid credentials)
- HTTP 200 with login page: failure (invalid CSRF token)

### Symfony + DDEV quick reference

```bash
# Login
ddev exec curl -s "http://localhost/login" -c /tmp/cookies.txt -o /tmp/login.html && \
CSRF=$(ddev exec grep -oP '_csrf_token"[^>]*value="\K[^"]+' /tmp/login.html) && \
ddev exec curl -s -X POST "http://localhost/login" \
  -b /tmp/cookies.txt -c /tmp/cookies.txt -L \
  -d "_username=$(grep ^TEST_USER_EMAIL= .env.local | cut -d= -f2)" \
  -d "_password=$(grep ^TEST_USER_PASSWORD= .env.local | cut -d= -f2)" \
  -d "_csrf_token=$CSRF" \
  -o /dev/null -w "Login: %{http_code}\n"

# Test a route
ddev exec curl -s -o /dev/null -w "%{http_code}" "http://localhost/admin/route" -b /tmp/cookies.txt
```

---

## Symfony API (JSON login / JWT)

**Characteristics:**
- Endpoint: `/api/login` or `/api/login_check`
- Format: JSON
- Response: JWT token or session cookie

**Procedure:**

```bash
TEST_USER_EMAIL=$(grep "^TEST_USER_EMAIL=" .env.local | cut -d'=' -f2)
TEST_USER_PASSWORD=$(grep "^TEST_USER_PASSWORD=" .env.local | cut -d'=' -f2)

ddev exec curl -s -X POST "http://localhost/api/login" \
  -H "Content-Type: application/json" \
  -c /tmp/cookies.txt \
  -d "{\"username\":\"$TEST_USER_EMAIL\",\"password\":\"$TEST_USER_PASSWORD\"}"
```

**Verify success:**
- JSON response containing `token`: success (store the token)
- HTTP 401: invalid credentials

**Subsequent requests with JWT:**
```bash
ddev exec curl -s "http://localhost/api/endpoint" \
  -H "Authorization: Bearer $JWT_TOKEN"
```

### Symfony API (JWT) quick reference

```bash
# Login
TOKEN=$(ddev exec curl -s -X POST "http://localhost/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"user","password":"pass"}' | grep -oP '"token":"\K[^"]+')

# Test a route
ddev exec curl -s "http://localhost/api/resource" -H "Authorization: Bearer $TOKEN"
```
