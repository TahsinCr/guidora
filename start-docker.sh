#!/usr/bin/env bash
# ==============================================================================
# Guidora Platform - Docker Services Startup Script
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ANSI Color definitions
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Early Help Check
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo "Usage: ./start-docker.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-rabbitmq, --messaging  Start the optional RabbitMQ message broker service"
            echo "  --no-build                    Start containers without rebuilding images"
            echo "  --no-wait                     Do not wait for healthcheck validation"
            echo "  --logs, -f                    Follow container logs after startup"
            echo "  -h, --help                    Show this help message"
            exit 0
            ;;
    esac
done

echo -e "${BOLD}Starting Guidora deployment stack...${NC}"

# 1. Verify Git Submodules
if [ ! -f "backend/dockerfile" ] || [ ! -f "frontend/dockerfile" ]; then
    echo -e "${YELLOW}[SYNC] Submodule sources missing. Initializing git submodules...${NC}"
    git submodule update --init --recursive
    echo -e "${GREEN}[OK] Git submodules initialized.${NC}"
fi

# 2. Verify Docker Daemon
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[ERROR] Docker daemon is not running. Please start Docker first.${NC}" >&2
    exit 1
fi

# 3. Verify .env File
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}[WARN] .env file not found.${NC}"
    if [ -f ".env.example" ]; then
        echo -e "${CYAN}[INFO] Creating .env from .env.example...${NC}"
        cp .env.example .env
        chmod 600 .env

        if command -v openssl >/dev/null 2>&1; then
            DB_PASS=$(openssl rand -hex 16)
            REDIS_PASS=$(openssl rand -hex 16)
            JWT_KEY=$(openssl rand -base64 32 | tr -d '\n')
            SIG_KEY=$(openssl rand -base64 32 | tr -d '\n')

            sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASS}|" .env
            sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASS}|" .env
            sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=${JWT_KEY}|" .env
            sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=${SIG_KEY}|" .env
            echo -e "${GREEN}[OK] Generated secure random secrets in .env${NC}"
        else
            echo -e "${YELLOW}[WARN] .env created. Please set POSTGRES_PASSWORD, REDIS_PASSWORD, and JWT keys manually.${NC}"
        fi
    else
        echo -e "${RED}[ERROR] .env.example template not found.${NC}" >&2
        exit 1
    fi
fi

# 4. Check Mandatory Secrets in .env
MISSING_SECRETS=()
for key in POSTGRES_PASSWORD REDIS_PASSWORD TOKEN_OPTIONS__SECURITYKEY COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY; do
    VAL=$(grep -E "^${key}=" .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "')
    if [ -z "$VAL" ]; then
        MISSING_SECRETS+=("$key")
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo -e "${RED}[ERROR] Mandatory secrets are missing in .env:${NC}"
    for sec in "${MISSING_SECRETS[@]}"; do
        echo -e "  - ${YELLOW}$sec${NC}"
    done
    echo -e "${RED}Please populate required values in .env before running.${NC}" >&2
    exit 1
fi

# 5. Argument Parsing
PROFILE_ARGS=()
UP_FLAGS=("-d" "--build" "--wait")
SHOW_LOGS=false

for arg in "$@"; do
    case "$arg" in
        --with-rabbitmq|--messaging)
            PROFILE_ARGS+=(--profile messaging)
            ;;
        --no-build)
            UP_FLAGS=("${UP_FLAGS[@]/--build/}")
            ;;
        --no-wait)
            UP_FLAGS=("${UP_FLAGS[@]/--wait/}")
            ;;
        --logs|-f)
            SHOW_LOGS=true
            ;;
        *)
            UP_FLAGS+=("$arg")
            ;;
    esac
done

echo -e "${CYAN}[1/2] Launching container services...${NC}"
docker compose "${PROFILE_ARGS[@]}" up "${UP_FLAGS[@]}"

echo -e "${CYAN}[2/2] Checking container status...${NC}"
docker compose ps

# Read Port Settings
FRONTEND_PORT=$(grep -E '^FRONTEND_PORT=' .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || echo "80")
FRONTEND_PORT=${FRONTEND_PORT:-80}
BACKEND_PORT=$(grep -E '^BACKEND_PORT=' .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || echo "8080")
BACKEND_PORT=${BACKEND_PORT:-8080}

echo -e "\n${GREEN}[OK] Guidora stack is up and running.${NC}"
echo -e "${BOLD}Service Endpoints:${NC}"
echo -e "  Frontend Web UI    : http://localhost:${FRONTEND_PORT}"
echo -e "  Backend API direct : http://localhost:${BACKEND_PORT}/api"
echo -e "  Admin Dashboard    : http://localhost:${FRONTEND_PORT}/?view=admin"
echo -e "  Liveness Probe     : http://localhost:${FRONTEND_PORT}/health/live"
echo -e "  Readiness Probe    : http://localhost:${FRONTEND_PORT}/health/ready"
echo -e "  PostgreSQL         : localhost:5432"
echo -e "  Redis Cache        : localhost:6379"
if [[ " ${PROFILE_ARGS[*]} " =~ "messaging" ]]; then
    echo -e "  RabbitMQ Admin     : http://localhost:15672"
fi
echo -e "\nTo stop services: ./stop-docker.sh"
echo -e "To follow logs  : docker compose logs -f\n"

if [ "$SHOW_LOGS" = true ]; then
    echo -e "${CYAN}Following logs (Ctrl+C to exit)...${NC}"
    docker compose logs -f
fi
