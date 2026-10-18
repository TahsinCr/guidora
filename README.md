# Guidora — Enterprise Developer Tools & Governance Platform

[![Docker Compose](https://img.shields.io/badge/Docker_Compose-v2.20+-2496ED?style=for-the-badge&logo=docker&logoColor=white)](docker-compose.yml)
[![.NET 10](https://img.shields.io/badge/.NET_10-WebAPI_Onion_Arch-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)](backend/)
[![React 18](https://img.shields.io/badge/React_18-Vite_SPA_Resilient-61DAFB?style=for-the-badge&logo=react&logoColor=black)](frontend/)
[![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL_18-Alpine_xmin_ACID-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](docker-compose.yml)
[![Redis 8](https://img.shields.io/badge/Redis_8-volatile--lfu_Bounded-DC382D?style=for-the-badge&logo=redis&logoColor=white)](docker-compose.yml)
[![Nginx](https://img.shields.io/badge/Nginx_1.27-Zero--CORS_Proxy-009639?style=for-the-badge&logo=nginx&logoColor=white)](frontend/infra/nginx/default.conf)

> **Guidora** is a high-performance, enterprise-grade developer tool discovery, catalog curation, and community governance platform. Designed as a unified, production-ready monorepo, it orchestrates a clean **.NET 10 Onion Architecture WebAPI** backend and an optimized **React 18 Single-Page Application (SPA)** frontend behind an automated **Zero-CORS Nginx reverse proxy**.

---

## 🌐 Architectural Overview

Guidora enforces a strict **Zero-CORS** deployment topology. External browsers and clients communicate exclusively through the Nginx reverse proxy on standard HTTP port 80. Nginx hosts pre-compressed static assets and transparently proxies `/api/*` and `/health/*` routes to the internal container bridge network. The backend WebAPI, PostgreSQL database, and Redis cache remain completely isolated from public exposure.

```text
[ Browser / Public Client ]
            │
            │ HTTP :80 (SPA & /api/*)
            ▼
┌────────────────────────────────────────────────────────┐
│  frontend (Nginx 1.27 Reverse Proxy & Static Host)    │
│  - /         ──► Static SPA Assets (Brotli / Gzip)     │
│  - /api/*    ──► proxy_pass http://backend:8080/api/*   │
│  - /health/* ──► proxy_pass http://backend:8080/health  │
└────────────────────────────────────────────────────────┘
            │
            │ Docker Internal Bridge (`guidora-net`)
            ▼
┌────────────────────────────────────────────────────────┐
│  backend (.NET 10 WebAPI - Clean Onion Architecture)   │
│  - REST Controllers, Aspect Interception               │
│  - Unit of Work, FluentValidation, Rate Limiting       │
└───────────────────────┬────────────────────────────────┘
                        │
         ┌──────────────┴──────────────┐
         ▼                             ▼
┌──────────────────┐          ┌──────────────────┐
│  postgres (v18)  │          │   redis (v8)     │
│  - Single Truth  │          │  - volatile-lfu  │
│  - citext, xmin  │          │  - Bounded 256MB │
└──────────────────┘          └──────────────────┘
```

---

## 🏛️ Monorepo & Submodule Structure

This root repository acts as the **master orchestrator and container boundary** for Guidora. Application source code is decoupled into two independent Git submodules with their own versioning, issue tracking, and test suites:

- **[`backend/`](backend/)** (`git@github.com:TahsinCr/guidora-backend.git`): .NET 10 Clean Onion Architecture WebAPI.
- **[`frontend/`](frontend/)** (`git@github.com:TahsinCr/guidora-frontend.git`): React 18 Enterprise SPA with Nginx.

```text
guidora/
├── backend/                  # [Submodule] .NET 10 WebAPI Onion Architecture
│   ├── Core/                 # Cross-cutting concerns, aspects, pipeline behaviors
│   ├── Entities/             # Domain entities, DTOs, audit schemas
│   ├── DataAccess/           # EF Core 10, migrations, PostgreSQL repositories
│   ├── Business/             # Domain rules, validation, security managers
│   ├── WebAPI/               # REST API controllers, filters, rate limiters
│   └── Tests/                # Single unified test suite (270+ tests)
├── frontend/                 # [Submodule] React 18 Enterprise SPA
│   ├── src/                  # React components, hooks, services, contexts
│   ├── infra/nginx/          # Hardened Nginx production configuration
│   ├── infra/mock-server/    # Zero-dependency local mock server & Vite plugin
│   └── tests/                # Vitest & Happy-DOM test suites (80+ tests)
├── docker-compose.yml        # Unified production stack orchestration
├── .env.example              # Comprehensive environment configuration template
├── start-docker.sh           # Automated production deployment & health verification
├── stop-docker.sh            # Graceful shutdown & volume cleanup utility
└── Makefile                  # Standard DevOps & operational shortcuts
```

> **Note**: As an orchestrator repository framing independent submodules, this root repository does not track an application changelog. Versioning and detailed changelogs are maintained directly within each respective submodule repository.

---

## 🚀 Key Architectural Highlights

### 1. Robust Zero-CORS Network Isolation
- External clients never interact directly with database, cache, or raw WebAPI ports.
- Internal container networking (`guidora-net`) prevents port exposure. Host port bindings (`BACKEND_PORT`, `POSTGRES_PORT`, `REDIS_PORT`) bind to `127.0.0.1` by default for local debugging only.

### 2. High-Concurrency PostgreSQL 18
- Case-insensitive URL and slug uniqueness enforced via PostgreSQL `citext` extension.
- Race conditions and lost updates eliminated via optimistic concurrency checks on PostgreSQL's internal `xmin` system column.
- Append-only `AuditLogs` with native JSONB diff tracking and one-click rollback (`Audit.Revert`).

### 3. Bounded Distributed Caching (Redis 8)
- Memory ceiling strictly bounded at `256mb` (`REDIS_MAXMEMORY`) with `volatile-lfu` eviction policy.
- Cache stampede prevention with pattern-based atomic invalidation.

### 4. Enterprise Security & Session Governance
- **In-Memory JWT Access Tokens**: Tokens exist solely in memory (`tokenManager.js`), completely immune to `localStorage` XSS extraction.
- **HttpOnly Cookies**: Refresh sessions are handled via strict `HttpOnly; SameSite=Lax` cookies.
- **401 Mutex Queue**: Simultaneous 401 Unauthorized responses trigger exactly one silent refresh request while queuing other requests.
- **Zero-Template Keys**: Startup validation rejects placeholder or default secrets in production.
- **Granular Rate Limiting**: Per-endpoint ASP.NET Core rate limiters protect login, registration, email confirmation, comments, votes, and catalog mutations.

### 5. Resilient Frontend Architecture
- **Circuit Breaker**: Trips to `OPEN` after 5 consecutive 5xx errors, preventing cascading overload and fast-failing client requests for 20 seconds.
- **Ambient Health Awareness**: Real-time status indicators monitor API latency, circuit state, and background recovery.
- **Concurrent Transitions**: Route changes utilize React 18 `startTransition` to eliminate layout shift and visual hitching.

---

## 🛠️ Quickstart: Production Server Deployment

### Prerequisites
- **Docker Engine** `24.0.0+`
- **Docker Compose** `v2.20.0+`
- (Optional for standalone local development: .NET 10 SDK, Node.js 22 LTS)

### Step 1: Clone Repository with Submodules

```bash
git clone --recurse-submodules https://github.com/TahsinCr/guidora.git
cd guidora
```

*If cloned without `--recurse-submodules`, initialize them immediately:*
```bash
git submodule update --init --recursive
```

### Step 2: Configure Environment Secrets

Copy the provided environment template:
```bash
cp .env.example .env
chmod 600 .env
```

Generate cryptographically secure secrets for production:
```bash
# Generate random 32-character secrets
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=$(openssl rand -base64 32)|" .env
sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=$(openssl rand -base64 32)|" .env
```

### Step 3: Launch the Stack

Start all containers and verify healthy status:
```bash
# Using the production orchestrator script:
./start-docker.sh

# Or using Make:
make up

# Or directly via Docker Compose:
docker compose up -d --build --wait
```

### Step 4: Verify Deployment Health

```bash
# Verify all containers are healthy
docker compose ps

# Check backend readiness probe through Nginx proxy
curl --fail http://localhost/health/ready

# Check API catalog endpoint
curl --fail http://localhost/api/products
```

---

## 🌐 Service Matrix & Port Mapping

| Service | Container Image | Internal Port | Host Binding (Default) | Health Check | Purpose |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`frontend`** | `nginx:1.27-alpine-slim` | `80` | `0.0.0.0:80` | `GET /healthz` | SPA host & Zero-CORS reverse proxy |
| **`backend`** | `.NET 10 SDK / Runtime` | `8080` | `127.0.0.1:8080` | `GET /health/ready` | Core Onion-Architecture REST API |
| **`postgres`** | `postgres:18.6-alpine` | `5432` | `127.0.0.1:5432` | `pg_isready` | ACID persistence with `citext` & `xmin` |
| **`redis`** | `redis:8.10.1-alpine` | `6379` | `127.0.0.1:6379` | `redis-cli ping` | Distributed cache (`volatile-lfu`) |
| **`rabbitmq`** | `rabbitmq:4.3.6-alpine` | `5672`, `15672` | `127.0.0.1:5672` | `ping` | Optional broker (`--profile messaging`) |

---

## 💻 Submodule Development Workflows

### Standalone Frontend Development
The frontend can run independently in two distinct modes:

```bash
cd frontend

# 1. Zero-dependency development (in-process mock API, no backend required)
npm run dev

# 2. Live backend integration (proxies to http://localhost:8080)
npm run dev:real

# Run frontend test suite
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

### Submodule Synchronization Workflow
When contributing to submodules:
1. Make and test changes within the submodule folder (`backend` or `frontend`).
2. Commit and push changes to the submodule repository first.
3. In the root repository, stage the updated submodule pointer and commit:
   ```bash
   git add backend frontend
   git commit -m "chore(submodules): update backend and frontend pointers"
   ```

---

## ⚙️ Environment Configuration Reference

| Variable | Default | Required in Production | Description |
| :--- | :--- | :---: | :--- |
| `FRONTEND_PORT` | `80` | No | Public HTTP port exposed by Nginx |
| `BACKEND_PORT` | `8080` | No | Direct backend port (bound to 127.0.0.1) |
| `INFRA_BIND_ADDRESS` | `127.0.0.1` | No | Binding IP for internal DB/cache ports |
| `POSTGRES_DB` | `guidora` | No | PostgreSQL database name |
| `POSTGRES_USER` | `guidora` | No | PostgreSQL user |
| `POSTGRES_PASSWORD` | - | **YES** | Strong PostgreSQL password |
| `REDIS_PASSWORD` | - | **YES** | Strong Redis authentication password |
| `TOKEN_OPTIONS__SECURITYKEY` | - | **YES** | Cryptographic key for JWT signing (>= 32 chars) |
| `COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY` | - | **YES** | Cryptographic key for vote hash verification |
| `BOOTSTRAP_ADMIN_ENABLED` | `false` | No | Enables provisioning of first admin user |
| `BOOTSTRAP_ADMIN_USERNAME` | - | If enabled | Bootstrap admin username |
| `BOOTSTRAP_ADMIN_EMAIL` | - | If enabled | Bootstrap admin email address |
| `BOOTSTRAP_ADMIN_PASSWORD` | - | If enabled | Bootstrap admin password |
| `RATE_LIMIT_LOGIN_PERMIT_LIMIT` | `10` | No | Max login attempts per window |
| `RATE_LIMIT_LOGIN_WINDOW_SECONDS` | `60` | No | Login rate limiting window in seconds |

---

## 📋 Operational Runbook & Maintenance

### Common DevOps Commands

```bash
# Start all containers in background
make up           # or ./start-docker.sh

# Follow live container logs
make logs         # or docker compose logs -f

# Check container health status
make ps           # or docker compose ps

# Run tests across entire stack
make test

# Graceful shutdown (retaining database data)
make down         # or ./stop-docker.sh

# Complete purge of containers and database volumes
make clean        # or ./stop-docker.sh --clean
```

### Database Backup & Restore

```bash
# Create a timestamped SQL backup:
docker compose exec -T postgres pg_dump -U guidora guidora > "guidora_backup_$(date +%Y%m%d_%H%M%S).sql"

# Restore database from backup:
cat guidora_backup_*.sql | docker compose exec -T postgres psql -U guidora guidora
```

---

## 📄 License

This monorepo orchestrator and its constituent submodules are distributed under the **MIT License**.
See the respective submodules for additional third-party dependencies and notices.
