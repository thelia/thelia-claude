# DDEV Hooks and Additional Services

## Contents
- [Post-start hooks in detail](#post-start-hooks-in-detail)
- [Mailpit (email testing)](#mailpit-email-testing)
- [Multi-container services (Redis, Elasticsearch, etc.)](#multi-container-services)
- [PHP customization](#php-customization)

## Post-start hooks in detail

Hooks automate repetitive tasks after `ddev start`.

### Hook: Create a test database

```yaml
hooks:
  post-start:
    - exec-host: ddev mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS db_test; GRANT ALL PRIVILEGES ON db_test.* TO 'db'@'%'; FLUSH PRIVILEGES;"
```

### Hook: Clear the Thelia cache

```yaml
hooks:
  post-start:
    - exec: php Thelia cache:clear
```

### Hook: Install dependencies

```yaml
hooks:
  post-start:
    - composer: install  # Shorthand for ddev composer install
```

### Hook: Compile assets

```yaml
hooks:
  post-start:
    - exec: bin/console sass:build
    - exec: npm run build
```

### Hook: Start Messenger

```yaml
hooks:
  post-start:
    - exec: symfony run --daemon bin/console messenger:consume async -vv
```

**Note:** `exec` commands run inside the web container. `exec-host` commands run on the host machine.

## Mailpit (email testing)

DDEV includes Mailpit to capture outgoing emails.

### Configuration

```bash
# .env.local
MAILER_DSN=smtp://localhost:1025
```

### Web interface

```
https://project-name.ddev.site:8026
```

All emails sent by the application are captured and visible in Mailpit.

## Multi-container services

### Adding a service (Redis, Elasticsearch, etc.)

```yaml
# .ddev/docker-compose.redis.yaml
version: '3.6'
services:
  redis:
    image: redis:7-alpine
    container_name: ddev-${DDEV_SITENAME}-redis
    labels:
      com.ddev.site-name: ${DDEV_SITENAME}
      com.ddev.approot: $DDEV_APPROOT
    volumes:
      - redis-data:/data
    restart: unless-stopped

volumes:
  redis-data:
```

Usage:

```bash
# .env.local
REDIS_URL=redis://redis:6379
```

```bash
# Test the connection
ddev exec redis-cli -h redis ping
```

## PHP customization

### Custom php.ini

```ini
; .ddev/php/custom.ini
memory_limit = 512M
upload_max_filesize = 100M
post_max_size = 100M
max_execution_time = 300
```

Restart after any modification:

```bash
ddev restart
```
