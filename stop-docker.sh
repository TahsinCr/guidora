#!/usr/bin/env bash
# ==============================================================================
# Guidora Platform - Docker Services Shutdown Script
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

DOWN_ARGS=()
REMOVE_VOLUMES=false

for arg in "$@"; do
    case "$arg" in
        --clean|-v|--volumes)
            REMOVE_VOLUMES=true
            ;;
        --help|-h)
            echo "Usage: ./stop-docker.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --clean, -v, --volumes   Remove named volumes (PostgreSQL and Redis persistent data)"
            echo "  --rmi all|local          Remove images used by services"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            DOWN_ARGS+=("$arg")
            ;;
    esac
done

if [ "$REMOVE_VOLUMES" = true ]; then
    echo -e "${RED}[WARN] Volume removal requested. Database and cache data will be deleted.${NC}"
    DOWN_ARGS+=(--volumes)
fi

echo -e "${CYAN}[1/2] Stopping Guidora containers and networks...${NC}"
docker compose --profile messaging down "${DOWN_ARGS[@]}"

echo -e "${CYAN}[2/2] Checking shutdown status...${NC}"
RUNNING=$(docker compose ps -q 2>/dev/null || true)

if [ -z "$RUNNING" ]; then
    echo -e "${GREEN}[OK] All Guidora services stopped successfully.${NC}"
else
    echo -e "${YELLOW}[WARN] Some containers may still be active:${NC}"
    docker compose ps
fi
