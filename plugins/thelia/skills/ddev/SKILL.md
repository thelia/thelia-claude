---
name: ddev
description: "Manage a local DDEV environment for PHP/Symfony/Thelia projects. Use when setting up a local dev environment, running ddev commands (start, stop, ssh, exec, composer, mysql), configuring post-start hooks, managing databases (import, export, snapshot), debugging containers, configuring Xdebug, checking logs. Also triggers on: docker local, web container, dev environment, project setup, database, mailpit email, redis, nginx, mariadb, php.ini, ddev config, ddev describe, ddev launch, ddev share, ddev poweroff, Thelia cache clear."
---

# DDEV - Local environment

## Quick Reference

| Task | Command |
|------|---------|
| Start project | `ddev start` |
| Stop project | `ddev stop` |
| Shell into web container | `ddev ssh` |
| Run a command | `ddev exec [command]` |
| Composer | `ddev composer [cmd]` |
| Project info | `ddev describe` |
| Logs | `ddev logs` |
| Export DB | `ddev export-db > backup.sql` |
| Import DB | `ddev import-db < backup.sql` |
| Restart | `ddev restart` |

## Before configuring

**Required:** before configuring DDEV for a project, run an exploration check:

```
Before configuring DDEV for this project, verify:

1. EXISTING CONFIGURATION:
   - Is there already a .ddev/ directory?
   - What PHP version is required (composer.json)?
   - What database engine is used?

2. EXISTING HOOKS:
   - Are there post-start hooks?
   - What initialization commands are needed?

3. ADDITIONAL SERVICES:
   - Is Redis used?
   - Elasticsearch?
   - Other Docker services?
```

## Initial project setup

### 1. Clone and start

```bash
git clone git@github.com:org/project.git
cd project

# First start (creates containers, installs dependencies)
ddev start
```

### 2. Install dependencies

```bash
ddev composer install
```

### 3. Environment configuration

```bash
cp .env .env.local
```

Edit `.env.local`:

```bash
# Database (standard DDEV configuration)
DATABASE_URL="mysql://db:db@db:3306/db?serverVersion=mariadb-10.11&charset=utf8"

# Mailer (Mailpit is included with DDEV)
MAILER_DSN=smtp://localhost:1025
```

### 4. Generate secrets (JWT, etc.)

```bash
ddev exec bin/console lexik:jwt:generate-keypair --skip-if-exists
```

### 5. Access

- Application: `https://project-name.ddev.site`
- Mailpit: `https://project-name.ddev.site:8026`
- Database: see `ddev describe`

## Typical DDEV configuration

```yaml
# .ddev/config.yaml
name: project-name
type: symfony
docroot: public
php_version: "8.3"
webserver_type: nginx-fpm
xdebug_enabled: false

database:
  type: mariadb
  version: "10.11"

composer_version: "2"

hooks:
  post-start:
    - composer: install
    - exec-host: ddev mysql -uroot -proot -e "CREATE DATABASE IF NOT EXISTS db_test; GRANT ALL PRIVILEGES ON db_test.* TO 'db'@'%'; FLUSH PRIVILEGES;"
    - exec: php Thelia cache:clear
    - exec: bin/console sass:build
    - exec: symfony run --daemon bin/console messenger:consume async -vv
```

Key points:
- `hooks.post-start`: automates tasks after startup
- `exec-host`: runs on the host machine
- `exec`: runs inside the web container
- `composer`: shorthand for `ddev composer`

## Common commands

### Project lifecycle

```bash
ddev start       # Start
ddev stop        # Stop (keeps containers)
ddev restart     # Restart (reloads config)
ddev delete      # Remove project (containers and volumes)
ddev describe    # Full info (ports, URLs, status)
```

### Running commands

```bash
# Interactive shell in the web container
ddev ssh

# Single command
ddev exec [command]

# Thelia CLI
ddev exec php Thelia cache:clear
ddev exec php Thelia module:list
ddev exec php Thelia admin:create

# Symfony console
ddev exec bin/console debug:router
ddev exec bin/console lint:twig

# Composer
ddev composer install
ddev composer require symfony/maker-bundle --dev
ddev composer update

# Tests and quality
ddev exec vendor/bin/phpunit
ddev exec vendor/bin/phpstan analyze
```

### Database

```bash
# MySQL CLI
ddev mysql

# Run a query
ddev mysql -e "SELECT * FROM customer LIMIT 5;"

# Export and import
ddev export-db > backup.sql
ddev export-db --gzip > backup.sql.gz
ddev import-db < backup.sql
ddev import-db --file=backup.sql.gz

# Snapshots (fast save/restore for testing migrations)
ddev snapshot
ddev snapshot --name=before-migration
ddev restore-snapshot before-migration
ddev snapshot --list
ddev snapshot --cleanup
```

### Debug and logs

```bash
# Container logs
ddev logs
ddev logs -f          # Follow
ddev logs web         # Web only
ddev logs db          # Database only

# Xdebug (on-demand is faster than xdebug_enabled: true)
ddev xdebug on
ddev xdebug off
ddev xdebug status

# Check PHP configuration
ddev exec php -i
ddev exec php -m     # Loaded modules
```

## Daily workflow

```bash
# Start of day
ddev start

# During the day
ddev ssh                              # Interactive shell
ddev exec php Thelia [command]        # Thelia CLI commands
ddev exec bin/console [command]       # Symfony console
ddev composer require [package]       # Add dependencies

# Tests
ddev exec vendor/bin/phpunit
ddev exec vendor/bin/phpstan analyze

# End of day
ddev stop  # Or leave running
```

## Anti-patterns

| Anti-pattern | Problem | Solution |
|--------------|---------|----------|
| **Reconfiguring an existing setup** | Overwrites a working DDEV config | Check `.ddev/config.yaml` first |
| **Port conflicts** | Multiple DDEV projects on the same ports | Run `ddev poweroff` or change ports |
| **Running commands outside the container** | PHP/Composer version mismatch | Always use `ddev exec` or `ddev ssh` |
| **Forgetting hooks** | Repeating manual steps after every start | Automate in `hooks.post-start` |
| **Editing var/ locally** | Corrupted cache between host and container | Always manage cache inside the container |
| **Missing test DB** | Tests fail without the test database | Add a hook to create db_test |

## References

See `references/hooks-et-services.md` before configuring post-start hooks, adding Mailpit, Redis, Elasticsearch, or customizing php.ini.

See `references/troubleshooting.md` before diagnosing a DDEV problem (ports, DNS, cache, empty DB, memory), for common workflows (reset, PHP version change, onboarding), advanced commands, and the new-install checklist.
