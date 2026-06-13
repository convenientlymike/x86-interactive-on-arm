# Security Policy

## Reporting a Vulnerability

Please report security issues privately via email rather than opening a public issue.
Contact the maintainer at the email on the GitHub profile.

## Secrets & Credentials

**Never put secrets, credentials, API keys, or tokens in `docker-compose.yml` or any
file tracked by git.** The compose template in this repo is intentionally credential-free.
Inject real credentials from environment variables or a secret store at runtime — for example:

```bash
APP_TOKEN=... docker compose up
```

or via Docker secrets / your platform's secret manager.
