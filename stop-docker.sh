#!/usr/bin/env bash
# ==============================================================================
# Guidora Platform — Unified Docker Shutdown & Cleanup Utility
# ==============================================================================
set -e

# Resolve script directory (works from any working directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Color definitions
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${CYAN}${BOLD}       🧭 Guidora Platform — Docker Kapatıcı & Temizleyici     ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"

DOWN_ARGS=()
REMOVE_VOLUMES=false

for arg in "$@"; do
    case "$arg" in
        --clean|-v|--volumes)
            REMOVE_VOLUMES=true
            ;;
        --help|-h)
            echo "Kullanım: ./stop-docker.sh [SEÇENEKLER]"
            echo ""
            echo "Seçenekler:"
            echo "  --clean, -v, --volumes   Konteynerlerle birlikte veri birimlerini (PostgreSQL & Redis verilerini) de siler"
            echo "  --rmi all|local          Konteynerlerle birlikte derlenmiş imajları da kaldırır"
            echo "  -h, --help               Bu yardım mesajını gösterir"
            exit 0
            ;;
        *)
            DOWN_ARGS+=("$arg")
            ;;
    esac
done

if [ "$REMOVE_VOLUMES" = true ]; then
    echo -e "${RED}${BOLD}[DİKKAT] Veri birimleri (--volumes / --clean) silinecek!${NC}"
    echo -e "${YELLOW}PostgreSQL ve Redis'teki tüm kalıcı veriler temizlenecektir.${NC}"
    DOWN_ARGS+=(--volumes)
fi

echo -e "\n${CYAN}[1/2] Çalışan tüm Guidora servisleri ve ağları kapatılıyor...${NC}"
docker compose --profile messaging down "${DOWN_ARGS[@]}"

echo -e "\n${CYAN}[2/2] Kapanış durumu denetleniyor...${NC}"
RUNNING=$(docker compose ps -q 2>/dev/null || true)

if [ -z "$RUNNING" ]; then
    echo -e "\n${GREEN}${BOLD}================================================================${NC}"
    echo -e "${GREEN}${BOLD}   ✓ Tüm Guidora Servisleri Güvenle Kapatıldı!                   ${NC}"
    echo -e "${GREEN}${BOLD}================================================================${NC}"
    echo -e "Yeniden başlatmak için: ${CYAN}./start-docker.sh${NC}\n"
else
    echo -e "\n${YELLOW}[UYARI] Bazı konteynerler henüz kapanmamış olabilir:${NC}"
    docker compose ps
fi
