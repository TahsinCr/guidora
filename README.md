# Guidora

The root Compose stack runs the React frontend, the real .NET backend, PostgreSQL 18, and Redis. Backend and frontend sources are Git submodules in `backend/` and `frontend/`.

## Setup

```sh
git submodule update --init --recursive
cp .env.example .env
chmod 600 .env
```

Set independent random `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `TOKEN_OPTIONS__SECURITYKEY`, and `COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY` values. JWT and signal keys must contain at least 32 characters. Configure bootstrap administrator credentials only if provisioning the first administrator. Existing database credentials must match the existing volume; changing `.env` does not reset PostgreSQL passwords.

```sh
docker compose config --quiet
docker compose up -d --build --wait
```

Open http://localhost (or `FRONTEND_PORT`). The frontend proxies `/api` and `/health` to `backend:8080`; production builds disable mock mode and offline authentication fallback. An empty database displays an empty catalog, never demo products. The live admin view reads backend records; demo-only administrative mutations are unavailable.

Backend and infrastructure ports bind to `127.0.0.1` by default. Override `INFRA_BIND_ADDRESS` only when external access is required. Match `WEB_CLIENT_ORIGIN` to the frontend origin when using a custom port. File mounts fail if their source is missing instead of creating directories. Redis is disposable; PostgreSQL data persists in the `guidora_guidora-postgres-data` volume at `/var/lib/postgresql`.

```sh
docker compose ps
curl --fail http://localhost/health/ready
curl --fail http://localhost/api/products
# Stop this stack, retaining database contents:
docker compose down
```

RabbitMQ is optional: set `RABBITMQ_PASSWORD`, then use `docker compose --profile messaging up -d --wait`. It is not required for the current synchronous backend.

For frontend development, `cd frontend && npm run dev` connects to the real backend on port 8080 by default. Mock development must be explicitly enabled with `VITE_USE_MOCK=true`; the frontend Compose entry point includes this root stack. The optional demo stack is explicitly named `frontend/docker-compose.mock.yml`.
