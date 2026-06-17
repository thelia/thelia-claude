# JWT Authentication: Complete Reference

## Contents

- Login Flow (Admin / Front)
- Authenticated Requests
- Security on Operations
- JWT Key Generation
- Configuration (LexikJWTAuthenticationBundle, Security Firewall)
- Best Practices
- Error Responses

## Login Flow

### Admin Login

```http
POST /api/admin/login
Content-Type: application/json

{
    "username": "admin@example.com",
    "password": "password"
}
```

Response:
```json
{
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9..."
}
```

### Front Login (Customer)

```http
POST /api/front/login
Content-Type: application/json

{
    "username": "client@example.com",
    "password": "password"
}
```

Response:
```json
{
    "token": "eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9..."
}
```

## Authenticated Requests

Include the JWT token in the `Authorization` header:

```http
GET /api/admin/products
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...
```

```http
POST /api/admin/products
Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiJ9...
Content-Type: application/json

{
    "ref": "NEW-PROD",
    "visible": true
}
```

## Security on Operations

### Expression-based security

```php
#[ApiResource(
    operations: [
        new Get(
            uriTemplate: '/front/account/orders/{id}',
            security: 'object.customer.getId() == user.getId()'
        ),
        new GetCollection(
            uriTemplate: '/front/account/orders',
            security: 'is_granted("ROLE_CUSTOMER")'
        ),
        new Post(
            uriTemplate: '/admin/products',
            security: 'is_granted("ROLE_ADMIN")'
        ),
        new Delete(
            uriTemplate: '/admin/products/{id}',
            security: 'is_granted("ROLE_SUPER_ADMIN")',
            securityMessage: 'Only super admins can delete products.'
        ),
    ],
)]
```

### Available variables in security expressions

- `user`: the authenticated user object
- `object`: the current resource object (for item operations)
- `request`: the Symfony Request object
- `is_granted("ROLE_XXX")`: role check

## JWT Key Generation

Never generate keys manually. Always use the dedicated command:

```bash
ddev exec bin/console lexik:jwt:generate-keypair
```

This creates:
- `config/jwt/private.pem`: private key (signing)
- `config/jwt/public.pem`: public key (verification)

## Configuration

### LexikJWTAuthenticationBundle

```yaml
# config/packages/lexik_jwt_authentication.yaml
lexik_jwt_authentication:
    secret_key: '%env(resolve:JWT_SECRET_KEY)%'
    public_key: '%env(resolve:JWT_PUBLIC_KEY)%'
    pass_phrase: '%env(JWT_PASSPHRASE)%'
    token_ttl: 3600  # 1 hour
```

### Security Firewall

```yaml
# config/packages/security.yaml
security:
    firewalls:
        api:
            pattern: ^/api
            stateless: true
            jwt: ~
        main:
            json_login:
                check_path: /api/admin/login
                success_handler: lexik_jwt_authentication.handler.authentication_success
                failure_handler: lexik_jwt_authentication.handler.authentication_failure

    access_control:
        - { path: ^/api/admin/login, roles: PUBLIC_ACCESS }
        - { path: ^/api/front/login, roles: PUBLIC_ACCESS }
        - { path: ^/api/front, roles: PUBLIC_ACCESS }
        - { path: ^/api/admin, roles: ROLE_ADMIN }
```

## Security Best Practices

- **Token TTL**: Keep it short (1 to 4 hours). Implement refresh tokens for long-lived sessions.
- **HTTPS only**: JWT tokens must never be transmitted over HTTP.
- **No sensitive data in payload**: The JWT payload is base64-encoded, not encrypted.
- **Revocation**: JWTs cannot be revoked individually. Use short TTL plus a blacklist for critical cases.
- **Key rotation**: Rotate JWT keys periodically. Old public keys must remain valid for existing tokens.
- **Protect the private key**: The private key must never be in source control or client-side code.
- **Rate limit login endpoints**: Prevent brute-force attacks on `/api/admin/login` and `/api/front/login`.

## Error Responses

### Invalid credentials

```http
POST /api/admin/login
Content-Type: application/json

{"username": "wrong@example.com", "password": "wrong"}
```

```json
HTTP/1.1 401 Unauthorized
{
    "code": 401,
    "message": "Invalid credentials."
}
```

### Expired token

```json
HTTP/1.1 401 Unauthorized
{
    "code": 401,
    "message": "Expired JWT Token"
}
```

### Missing token

```json
HTTP/1.1 401 Unauthorized
{
    "code": 401,
    "message": "JWT Token not found"
}
```
