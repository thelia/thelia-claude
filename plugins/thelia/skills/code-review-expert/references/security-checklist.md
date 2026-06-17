# Security Checklist: Code Review

All rules in this section are **blocking**. One item not respected means merge is blocked.

## Contents

- SQL Injection
- XSS via Twig `|raw`
- CSRF
- Credentials / Secrets
- Dynamic Code Execution
- Deserialization
- Voters / Authorization
- Rate Limiting
- API Platform: Data Exposure
- Session / Cookies
- Dynamic Include
- Trusted Hosts
- File Uploads
- Logging & Sensitive Data
- Error Messages: Exposing Internals
- CI/CD

## SQL Injection

Flag any variable concatenation inside a SQL, DQL, or QueryBuilder query.

```php
// BAD
$query = "SELECT * FROM users WHERE email = '" . $email . "'";
$dql = "SELECT u FROM User u WHERE u.role = '$role'";

// GOOD
$qb->where('u.role = :role')->setParameter('role', $role);
$conn->executeQuery('SELECT * FROM users WHERE email = ?', [$email]);
```

## XSS via Twig `|raw`

Flag any `|raw` on a variable that contains or could contain user data. When rich HTML is needed, require `HtmlSanitizer`:

```twig
{# BAD #}
{{ product.description|raw }}

{# GOOD: if rich HTML is needed #}
{{ product.description|sanitize_html('app.sanitizer')|raw }}

{# GOOD: auto-escaped by default #}
{{ product.description }}
```

Require a code comment explaining why `|raw` is safe for every occurrence.

## CSRF

- Symfony forms: CSRF is included by default. Flag any `csrf_protection: false`.
- Manual HTML forms: verify that `csrf_token()` is present in the template and `isCsrfTokenValid()` in the controller
- API endpoints: stateless APIs (JWT) do not need CSRF

## Credentials / Secrets

- Never hardcode credentials in code (`$dsn = 'mysql://root:secret@...'`)
- Never commit secrets in `.env`. Use the Symfony Secrets vault instead.
- Verify that `APP_DEBUG=false` and `APP_ENV=prod` in production
- Web Profiler disabled in production (it exposes all env vars via `/_profiler/phpinfo`)

## Dynamic Code Execution

Flag any occurrence of:
- `eval()`: no legitimate use in application code
- `system()`, `exec()`, `passthru()`, `shell_exec()`, backticks
- When genuinely necessary (rare), require `escapeshellarg()` on every argument

## Deserialization

```php
// BAD: Remote Code Execution via __wakeup/__destruct
$data = unserialize($input);

// GOOD
$data = json_decode($input, true, flags: JSON_THROW_ON_ERROR);

// If unserialize is required (internal cache only)
$data = unserialize($input, ['allowed_classes' => [SafeClass::class]]);
```

## Voters / Authorization

```php
// BAD: IDOR: any authenticated user can access any resource
#[IsGranted('ROLE_USER')]
public function view(Invoice $invoice): Response { ... }

// GOOD: voter checks ownership
#[IsGranted('invoice.view', 'invoice')]
public function view(Invoice $invoice): Response { ... }
```

Flag any `isGranted('ROLE_*')` on a resource action without passing the subject.

Verify that voters use `supports()` to filter their attributes. A voter that returns `false` by default blocks the other voters.

## Rate Limiting

Sensitive endpoints without a rate limiter are blocking:
- Login / authentication
- Registration
- Password reset / OTP
- API account creation

Verify `login_throttling` in `security.yaml` and/or the `#[RateLimiting]` attribute.

## API Platform: Data Exposure

```php
// BAD: no groups means all properties are exposed (including password hash)
#[ApiResource]
class User { ... }

// GOOD
#[ApiResource(
    normalizationContext: ['groups' => ['user:read']],
    denormalizationContext: ['groups' => ['user:write']],
)]
```

Flag any `#[ApiResource]` without an explicit `normalizationContext`.

Flag any operation without `security`:
```php
// BAD
new Get(), // public by default

// GOOD
new Get(security: "is_granted('ROLE_USER')"),
```

## Session / Cookies

Check in the framework config:
- `framework.session.cookie_secure: true`
- `framework.session.cookie_httponly: true`
- `framework.session.cookie_samesite: 'lax'` or `'strict'`

## Dynamic Include

```php
// BAD: LFI (Local File Inclusion)
include $_GET['page'] . '.php';

// GOOD: whitelist
$allowed = ['home', 'about', 'contact'];
$page = in_array($_GET['page'], $allowed, true) ? $_GET['page'] : 'home';
require __DIR__ . '/pages/' . $page . '.php';
```

## Trusted Hosts

Verify that `trusted_hosts` is configured in production to prevent host header injection:
```yaml
framework:
    trusted_hosts: ['example\.com']
```

## File Uploads

### Validate by Content, Not Extension (Blocking)

```php
// BAD: trivially bypassed (photo.php.jpg, photo.phtml)
if (in_array($file->getClientOriginalExtension(), ['jpg', 'png'])) { ... }

// BAD: the MIME type sent by the client is spoofable
if ($file->getClientMimeType() === 'image/jpeg') { ... }

// GOOD: validate by actual content (finfo)
$mimeType = $file->getMimeType(); // uses finfo_file(), not the client header
$allowedTypes = ['image/jpeg', 'image/png', 'image/webp'];
if (!in_array($mimeType, $allowedTypes, true)) {
    throw new InvalidFileException('File type not allowed');
}
```

### Secure Storage (Blocking)

- Store outside the webroot (`var/uploads/`, not `public/uploads/`)
- Randomize filenames (UUID, not the original name)
- Never serve directly. Use a controller that checks permissions.
- Enforce size limits (`upload_max_filesize` + Symfony `#[Assert\File(maxSize: '5M')]`)

```php
// BAD: original name kept, stored in public/
$file->move('public/uploads', $file->getClientOriginalName());

// GOOD
$filename = Uuid::v4() . '.' . $file->guessExtension();
$file->move($this->uploadDirectory, $filename); // outside webroot
```

## Logging & Sensitive Data

### Never Log PII or Secrets (Blocking)

```php
// BAD: plaintext password in logs
$this->logger->info('Login attempt', ['password' => $password]);

// BAD: JWT token in logs
$this->logger->debug('Auth header', ['token' => $request->headers->get('Authorization')]);

// BAD: bulk personal data
$this->logger->info('User created', ['user' => $user]); // serializes the entire object

// GOOD: log only identifiers and business context
$this->logger->info('Login attempt', ['email' => $email, 'ip' => $request->getClientIp()]);
$this->logger->info('User created', ['user_id' => $user->getId()]);
```

Flag any `$this->logger->*()` that contains:
- `password`, `token`, `secret`, `key`, `credential` in context array keys
- A full entity object (uncontrolled serialization)
- `$request->getContent()` raw (may contain sensitive data)

### Structured Logging (Important)

Always use the context array, never string interpolation:

```php
// BAD: not parseable by log aggregators
$this->logger->error("Order $orderId failed: $errorMessage");

// GOOD: structured, filterable
$this->logger->error('Order processing failed', [
    'order_id' => $orderId,
    'error' => $exception->getMessage(),
]);
```

## Error Messages: Exposing Internals

### Do Not Expose Internal Details in Responses (Blocking)

```php
// BAD: exposes DB structure, internal classes, stack trace
catch (\Exception $e) {
    return new JsonResponse(['error' => $e->getMessage()], 500);
    // Message: "SQLSTATE[23000]: Integrity constraint violation: 1062 Duplicate entry 'foo@bar.com' for key 'UNIQ_EMAIL'"
}

// GOOD: generic message for the user, details in logs
catch (UniqueConstraintViolationException $e) {
    $this->logger->error('Duplicate email on registration', [
        'email' => $email,
        'exception' => $e,
    ]);
    return new JsonResponse(['error' => 'This email address is already in use'], 409);
}
```

Verify in `api_platform.yaml` that non-business exceptions are not exposed:
```yaml
api_platform:
    exception_to_status:
        App\Exception\ResourceNotFoundException: 404
        App\Exception\BusinessRuleViolation: 422
    # Doctrine/Symfony exceptions stay as 500 with a generic message
```

In production: `APP_DEBUG=false` ensures Symfony does not show stack traces. But manual `JsonResponse` calls with `$e->getMessage()` bypass this mechanism, so flag them systematically.

## CI/CD

Verify that `symfony check:security` (or `composer audit`) is present in the CI pipeline. Its absence is a medium risk (CVEs in dependencies go undetected).
