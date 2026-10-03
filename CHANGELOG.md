# Changelog

## Unreleased

- Configure a unified Compose stack with the real backend, PostgreSQL 18, and disposable Redis.
- Align the root environment template and local port names, retaining existing secrets and database volumes.
- Require existing file-mount sources to prevent accidental directories and use backend readiness checks.
- Document startup, health checks, optional messaging, real frontend development, and explicit demo mode.
