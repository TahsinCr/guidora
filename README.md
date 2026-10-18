# Guidora

Guidora is a developer tools discovery, catalog curation, and community governance platform. The project is structured as a production monorepo that orchestrates a .NET 10 Onion Architecture WebAPI backend and a React 18 Single-Page Application (SPA) frontend behind an automated Nginx reverse proxy.

---

## Architectural Overview

Guidora employs a Zero-CORS network topology. Client browsers connect exclusively to the Nginx reverse proxy on standard HTTP port 80. Nginx hosts pre-compressed static application assets and proxies `/api/*` and `/health/*` routes across the internal container bridge network (`guidora-net`). The backend WebAPI, PostgreSQL database, and Redis cache do not expose public host ports in production.

```text
[ Client Browser ]
        |
        | HTTP :80 (SPA & /api/*)
        v
+--------------------------------------------------------+
| frontend (Nginx 1.27 Reverse Proxy & Static Host)      |
| - /         -> Static SPA Assets (Brotli / Gzip)       |
| - /api/*    -> proxy_pass http://backend:8080/api/*    |
| - /health/* -> proxy_pass http://backend:8080/health   |
+--------------------------------------------------------+
        |
        | Docker Internal Bridge (guidora-net)
        v
+--------------------------------------------------------+
| backend (.NET 10 WebAPI - Clean Onion Architecture)    |
| - REST Controllers, Aspect Interception                |
| - Unit of Work, FluentValidation, Rate Limiting        |
+---------------------------+----------------------------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
+--------------------------+  +--------------------------+
| postgres (PostgreSQL 18) |  | redis (Redis 8)          |
| - Single Source of Truth |  | - volatile-lfu Cache     |
| - citext, xmin locking   |  | - 256MB Hard Bound       |
+--------------------------+  +--------------------------+
```

---

## Repository Structure

The root repository serves as the orchestration and container deployment boundary. Application code is organized into two independent Git submodules with their own revision history and test suites:

- `backend/`: .NET 10 WebAPI implementing Onion Architecture (Domain, Application, Infrastructure, Presentation).
- `frontend/`: React 18 SPA built with Vite, utilizing React Query, accessible UI components, and an automated Nginx production server.

```text
guidora/
├── backend/                  # Git Submodule (.NET 10 WebAPI)
│   ├── Core/                 # Aspects, security utilities, cross-cutting concerns
│   ├── Entities/             # Concrete domain entities and DTOs
│   ├── DataAccess/           # EF Core context, migrations, repository implementations
│   ├── Business/             # Domain logic, validation rules, service interfaces
│   ├── WebAPI/               # HTTP controllers, middleware, rate limiting policies
│   └── Tests/                # Unified test suite (270+ unit and integration tests)
├── frontend/                 # Git Submodule (React 18 SPA)
│   ├── src/                  # React components, custom hooks, API clients, contexts
│   ├── infra/nginx/          # Hardened Nginx production configuration
│   ├── infra/mock-server/    # In-process mock API handler for standalone development
│   └── tests/                # Vitest and Happy-DOM test suite (80+ test cases)
├── docker-compose.yml        # Production multi-container orchestration definition
├── .env.example              # Canonical environment template with configuration documentation
├── start-docker.sh           # Automated deployment and health verification script
├── stop-docker.sh            # Graceful stack shutdown and cleanup script
└── Makefile                  # DevOps and developer operational targets
```

Note: Because the root repository acts purely as a frame orchestrating independent submodules, it does not maintain an application changelog. Change history and version tags are maintained within each submodule repository.

---

## Core Technical Invariants

### Zero-CORS Network Topology
External clients interact solely through port 80. Internal communication between Nginx, the WebAPI, PostgreSQL, and Redis occurs across the private Docker bridge network. Infrastructure ports (`5432`, `6379`, `8080`) bind to `127.0.0.1` by default and are intended for local administrative access only.

### High-Concurrency PostgreSQL 18
- Case-insensitive uniqueness for URLs and slugs is enforced via the PostgreSQL `citext` extension.
- Optimistic concurrency control is implemented using PostgreSQL's internal `xmin` system column, preventing lost updates during concurrent mutations.
- The `AuditLogs` table provides an append-only ledger tracking entity state changes in JSONB format with support for one-click rollbacks (`Audit.Revert`).

### Bounded Distributed Caching
- Cache memory is strictly capped at `256mb` (`REDIS_MAXMEMORY`) with a `volatile-lfu` (Least Frequently Used) eviction policy.
- Cache keys use structured prefixes, and invalidations execute atomically to prevent cache stampedes.

### Security and Session Management
- Access Tokens are stored solely in memory (`tokenManager.js`), mitigating `localStorage` credential exfiltration risks.
- Refresh Tokens are transmitted in `HttpOnly; SameSite=Lax` cookies.
- A 401 Mutex Queue serializes token refresh attempts: when multiple concurrent requests encounter an expired access token, exactly one refresh request is dispatched while pending calls wait for completion.
- Startup validation rejects empty, placeholder, or default secrets when running in production mode.
- Fine-grained rate limiters protect authentication, user registration, voting, comments, and catalog submissions.

### Frontend Resilience
- Circuit Breaker pattern: Trips to `OPEN` status after 5 consecutive 5xx errors or network timeouts, fast-failing outbound requests for 20 seconds to protect upstream infrastructure.
- Background health probes monitor `/health/live` to automatically recover and transition the circuit back to `CLOSED`.
- Route and modal transitions utilize React 18 `startTransition` to eliminate layout shift and unnecessary loading indicators.

---

## Quickstart: Production Deployment

### Prerequisites
- Docker Engine 24.0.0 or higher
- Docker Compose v2.20.0 or higher
- (Optional for local development: .NET 10 SDK, Node.js 22 LTS)

### 1. Clone Repository with Submodules

```bash
git clone --recurse-submodules https://github.com/TahsinCr/guidora.git
cd guidora
```

If cloned without `--recurse-submodules`, initialize submodules manually:

```bash
git submodule update --init --recursive
```

### 2. Configure Environment

Copy the configuration template and set permissions:

```bash
cp .env.example .env
chmod 600 .env
```

Generate cryptographically secure secrets:

```bash
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=$(openssl rand -base64 32)|" .env
sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=$(openssl rand -base64 32)|" .env
```

### 3. Start the Stack

```bash
# Using the startup script:
./start-docker.sh

# Or using Make:
make up

# Or directly via Docker Compose:
docker compose up -d --build --wait
```

### 4. Verify System Health

```bash
# Check container status
docker compose ps

# Verify backend readiness probe via Nginx
curl --fail http://localhost/health/ready

# Query catalog API
curl --fail http://localhost/api/products
```

---

## Service Matrix

| Service | Image / Build Context | Internal Port | Host Binding (Default) | Health Check | Role |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `frontend` | `./frontend/dockerfile` | 80 | `0.0.0.0:80` | `GET /healthz` | Static SPA host and Zero-CORS reverse proxy |
| `backend` | `./backend/dockerfile` | 8080 | `127.0.0.1:8080` | `GET /health/ready` | Onion Architecture REST API |
| `postgres` | `postgres:18.6-alpine` | 5432 | `127.0.0.1:5432` | `pg_isready` | ACID persistence with `citext` and `xmin` |
| `redis` | `redis:8.10.1-alpine` | 6379 | `127.0.0.1:6379` | `redis-cli ping` | Distributed cache with `volatile-lfu` |
| `rabbitmq` | `rabbitmq:4.3.6-alpine` | 5672, 15672 | `127.0.0.1:5672` | `ping` | Optional broker (`--profile messaging`) |

---

## Development Workflows

### Standalone Frontend Development

```bash
cd frontend

# Zero-dependency development with in-process mock handler
npm run dev

# Integration mode connected to a live backend (http://localhost:8080)
npm run dev:real

# Run test suite
npm test
```

### Standalone Backend Development

```bash
cd backend

# Build solution
dotnet build NetCoreBackend.sln

# Run comprehensive test suite
dotnet test Tests/Tests.csproj
```

### Submodule Synchronization

When making changes to submodules:
1. Implement and test changes inside the submodule directory (`backend/` or `frontend/`).
2. Commit and push directly to the submodule repository.
3. In the root directory, stage and commit the updated submodule commit pointer:

```bash
git add backend frontend
git commit -m "chore(submodules): update backend and frontend references"
```

---

## Configuration Reference

| Variable | Default | Required in Production | Description |
| :--- | :--- | :---: | :--- |
| `FRONTEND_PORT` | `80` | No | Public HTTP port exposed by Nginx |
| `BACKEND_PORT` | `8080` | No | Direct backend port (bound to 127.0.0.1) |
| `INFRA_BIND_ADDRESS` | `127.0.0.1` | No | Binding IP for internal DB and cache ports |
| `POSTGRES_DB` | `guidora` | No | PostgreSQL database name |
| `POSTGRES_USER` | `guidora` | No | PostgreSQL user |
| `POSTGRES_PASSWORD` | - | **Yes** | Database user password |
| `REDIS_PASSWORD` | - | **Yes** | Redis authentication password |
| `TOKEN_OPTIONS__SECURITYKEY` | - | **Yes** | Cryptographic key for signing JWTs (>= 32 chars) |
| `COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY` | - | **Yes** | Key for community vote integrity verification |
| `BOOTSTRAP_ADMIN_ENABLED` | `false` | No | Enables provisioning of initial admin account |
| `BOOTSTRAP_ADMIN_USERNAME` | - | Conditional | Username for initial admin |
| `BOOTSTRAP_ADMIN_EMAIL` | - | Conditional | Email address for initial admin |
| `BOOTSTRAP_ADMIN_PASSWORD` | - | Conditional | Password for initial admin |
| `RATE_LIMIT_LOGIN_PERMIT_LIMIT` | `10` | No | Maximum login attempts per window |
| `RATE_LIMIT_LOGIN_WINDOW_SECONDS` | `60` | No | Window duration in seconds for login rate limit |

---

## Operations and Maintenance

### Standard Commands

```bash
# Start all containers in background
make up

# Follow container logs
make logs

# Inspect container status
make ps

# Run tests across all submodules
make test

# Stop stack while preserving persistent data
make down

# Stop stack and purge database volumes
make clean
```

### Database Backup and Recovery

```bash
# Export timestamped SQL dump
docker compose exec -T postgres pg_dump -U guidora guidora > "guidora_backup_$(date +%Y%m%d_%H%M%S).sql"

# Restore database from SQL dump
cat guidora_backup_*.sql | docker compose exec -T postgres psql -U guidora guidora
```

---

## License

This project and its submodules are licensed under the MIT License.
