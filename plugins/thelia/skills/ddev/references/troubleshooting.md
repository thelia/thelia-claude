# DDEV Troubleshooting and Common Workflows

## Contents
- [Common workflows](#common-workflows)
- [Common pitfalls](#common-pitfalls)
- [Advanced commands](#advanced-commands)
- [New-install checklist](#new-install-checklist)

## Common workflows

### New developer on an existing project

```bash
git clone [repo]
cd project
ddev start         # Runs post-start hooks automatically
ddev describe      # See URLs and ports
```

### Full environment reset

```bash
ddev stop
ddev delete -O     # -O = omit snapshot
ddev start         # Rebuilds everything
```

### Test a schema migration

```bash
ddev snapshot --name=before-migration
# Run your migration here (Propel schema regeneration, custom scripts, etc.)

# If something goes wrong
ddev restore-snapshot before-migration
```

### Change PHP version

```yaml
# .ddev/config.yaml
php_version: "8.4"  # or "8.2", "8.3"
```

```bash
ddev restart
```

### Debug slow performance

```bash
# Check whether Mutagen is active (macOS/Windows)
ddev describe | grep -i mutagen

# Enable Xdebug temporarily
ddev xdebug on

# View PHP error logs
ddev logs | grep -i error

# Check container load
ddev exec top
```

## Common pitfalls

### Port already in use

Error: "port 80/443 already allocated"

```bash
# Identify the process
sudo lsof -i :80
sudo lsof -i :443

# Or stop all running DDEV projects
ddev poweroff
```

### Empty database after start

Cause: a command in the post-start hook failed silently.

```bash
# Check the logs
ddev logs

# Run the command manually with verbose output
ddev exec php Thelia cache:clear -vvv
```

### Composer out of memory

```bash
# Increase memory_limit in .ddev/php/custom.ini
# memory_limit = 512M
ddev restart
```

### DNS does not resolve

```yaml
# .ddev/config.yaml
use_dns_when_possible: false
```

```bash
ddev restart
```

Then access the site via `127.0.0.1:[port]` (see `ddev describe`).

### Symfony/Thelia cache not clearing

```bash
# Inside the container
ddev exec rm -rf var/cache/*

# Or with the Thelia CLI (preferred, clears more thoroughly)
ddev exec php Thelia cache:clear
```

### DB passwords with special characters

When a password contains `@`, `!`, `$`, or `#`, passing it as a `-p` argument breaks the shell. Use the `MYSQL_PWD` environment variable instead:

```bash
# Reading from a production host via SSH (read-only)
ssh user@host "MYSQL_PWD='nEBQv@4Dp88!' mysql -h db.host -u db_user db_name -e \"SELECT ... FROM ...;\""

# Locally, when a production dump with the original password is imported
MYSQL_PWD='secret$1' ddev exec mysql -u db db -e "..."
```

To retrieve credentials from a Thelia project on a server:
```bash
ssh user@host "grep -E '^(DATABASE_URL|DB_USER|DB_PASSWORD|DB_NAME|DB_HOST)' /path/to/project/.env.local"
```

## Advanced commands

```bash
# Open the site in a browser
ddev launch

# Share via ngrok (public tunnel)
ddev share

# Import uploaded files
ddev import-files --source=/path/to/files

# Export uploaded files
ddev export-files

# DDEV version
ddev version

# Update config after a DDEV upgrade
ddev config --update

# Stop all DDEV projects
ddev poweroff
```

## New-install checklist

- [ ] `ddev start` runs without errors
- [ ] `https://project.ddev.site` is accessible
- [ ] `ddev describe` shows all info
- [ ] `ddev exec bin/console debug:router` lists routes
- [ ] Mailpit is accessible on `:8026`
- [ ] Database created (`ddev mysql -e "SHOW DATABASES;"`)
- [ ] `.env.local` is correctly configured
- [ ] Post-start hooks execute without errors (check `ddev logs`)
