# Project README Template

```markdown
# {Project name}

{Description in 1-2 sentences}

## Requirements

- PHP {version}+
- Composer
- DDEV (optional)

## Installation

```bash
git clone {repo}
cd {project}
composer install
cp .env.example .env
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Database connection | - |
| `APP_ENV` | Environment | `dev` |

## Usage

```bash
# Start
ddev start

# Console
ddev exec bin/console {command}
```

## Tests

```bash
composer test
```

## Contributing

1. Fork the project
2. Create a branch (`git checkout -b feature/my-feature`)
3. Commit (`git commit -m 'feat: description'`)
4. Push and open a Pull Request

## License

{License}
```
