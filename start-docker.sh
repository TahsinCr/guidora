#!/usr/bin/env bash
# ==============================================================================
# Guidora Platform — Unified Production Docker Orchestrator
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

# 1. Early Help Check
for arg in "$@"; do
    case "$arg" in
        --help|-h)
            echo -e "${BLUE}${BOLD}================================================================${NC}"
            echo -e "${CYAN}${BOLD}       🧭 Guidora Platform — Production Stack Orchestrator     ${NC}"
            echo -e "${BLUE}${BOLD}================================================================${NC}"
            echo "Kullanım: ./start-docker.sh [SEÇENEKLER]"
            echo ""
            echo "Seçenekler:"
            echo "  --with-rabbitmq, --messaging  RabbitMQ mesaj kuyruğu servisini profil ile başlatır"
            echo "  --no-build                    İmajları yeniden derlemeden mevcutlarla başlatır"
            echo "  --no-wait                     Sağlık denetimlerinin (healthcheck) tamamlanmasını beklemez"
            echo "  --logs, -f                    Konteynerler açıldıktan sonra logları canlı takip eder"
            echo "  -h, --help                    Bu yardım mesajını gösterir"
            exit 0
            ;;
    esac
done

echo -e "${BLUE}${BOLD}================================================================${NC}"
echo -e "${CYAN}${BOLD}       🧭 Guidora Platform — Production Stack Orchestrator     ${NC}"
echo -e "${BLUE}${BOLD}================================================================${NC}"

# 2. Verify Git Submodules
if [ ! -f "backend/dockerfile" ] || [ ! -f "frontend/dockerfile" ]; then
    echo -e "${YELLOW}[SYNC] Alt modüller eksik tespit edildi. Submodule senkronizasyonu başlatılıyor...${NC}"
    git submodule update --init --recursive
    echo -e "${GREEN}[OK] Alt modüller başarıyla eşitlendi.${NC}"
fi

# 3. Verify Docker Daemon
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}[HATA] Docker servisi (daemon) çalışmıyor! Lütfen Docker daemon'ı başlatın.${NC}" >&2
    exit 1
fi

# 4. Verify .env File
if [ ! -f ".env" ]; then
    echo -e "${YELLOW}[UYARI] .env dosyası bulunamadı!${NC}"
    if [ -f ".env.example" ]; then
        echo -e "${CYAN}[BİLGİ] .env.example dosyasından .env oluşturuluyor...${NC}"
        cp .env.example .env
        chmod 600 .env

        # Otomatik güçlü anahtarlar üret
        if command -v openssl >/dev/null 2>&1; then
            DB_PASS=$(openssl rand -hex 16)
            REDIS_PASS=$(openssl rand -hex 16)
            JWT_KEY=$(openssl rand -base64 32 | tr -d '\n')
            SIG_KEY=$(openssl rand -base64 32 | tr -d '\n')

            sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${DB_PASS}|" .env
            sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=${REDIS_PASS}|" .env
            sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=${JWT_KEY}|" .env
            sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=${SIG_KEY}|" .env
            echo -e "${GREEN}[OK] .env dosyası üretildi ve rastgele kriptografik anahtarlar atandı.${NC}"
        else
            echo -e "${YELLOW}[DİKKAT] .env oluşturuldu ancak lütfen POSTGRES_PASSWORD, REDIS_PASSWORD ve JWT anahtarlarını elle doldurun.${NC}"
        fi
    else
        echo -e "${RED}[HATA] .env.example şablonu bulunamadı! İşlem durduruluyor.${NC}" >&2
        exit 1
    fi
fi

# 5. Check Mandatory Secrets in .env
MISSING_SECRETS=()
for key in POSTGRES_PASSWORD REDIS_PASSWORD TOKEN_OPTIONS__SECURITYKEY COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY; do
    VAL=$(grep -E "^${key}=" .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "')
    if [ -z "$VAL" ]; then
        MISSING_SECRETS+=("$key")
    fi
done

if [ ${#MISSING_SECRETS[@]} -gt 0 ]; then
    echo -e "${RED}[HATA] .env içinde zorunlu güvenlik parametreleri boş bırakılmış:${NC}"
    for sec in "${MISSING_SECRETS[@]}"; do
        echo -e "  - ${YELLOW}$sec${NC}"
    done
    echo -e "${RED}Lütfen .env dosyasını doldurun veya güvenli bir parola atayın.${NC}" >&2
    exit 1
fi

# 6. Argument Parsing
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

echo -e "\n${CYAN}[1/2] Docker Compose servisleri başlatılıyor...${NC}"
docker compose "${PROFILE_ARGS[@]}" up "${UP_FLAGS[@]}"

echo -e "\n${CYAN}[2/2] Konteyner sağlık ve çalışma durumları denetleniyor...${NC}"
docker compose ps

echo -e "\n${GREEN}${BOLD}================================================================${NC}"
echo -e "${GREEN}${BOLD}   ✓ Guidora Yığını Başarıyla Ayağa Kaldırıldı ve Sağlıklı!   ${NC}"
echo -e "${GREEN}${BOLD}================================================================${NC}"

# Read Port Settings
FRONTEND_PORT=$(grep -E '^FRONTEND_PORT=' .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || echo "80")
FRONTEND_PORT=${FRONTEND_PORT:-80}
BACKEND_PORT=$(grep -E '^BACKEND_PORT=' .env 2>/dev/null | cut -d '=' -f2- | tr -d ' "' || echo "8080")
BACKEND_PORT=${BACKEND_PORT:-8080}

echo -e "${BOLD}Erişim Noktaları & Servis Uçları:${NC}"
echo -e "  🌐 Web Arayüzü (Nginx SPA) : ${CYAN}http://localhost:${FRONTEND_PORT}${NC}"
echo -e "  🔌 Backend API (Doğrudan)  : ${CYAN}http://localhost:${BACKEND_PORT}/api${NC}"
echo -e "  🛡️  Admin Yönetim Konsolu   : ${CYAN}http://localhost:${FRONTEND_PORT}/?view=admin${NC}"
echo -e "  ❤️  Liveness Probe (Canlılık) : ${CYAN}http://localhost:${FRONTEND_PORT}/health/live${NC}"
echo -e "  🚀 Readiness Probe (Hazırlık): ${CYAN}http://localhost:${FRONTEND_PORT}/health/ready${NC}"
echo -e "  🗄️  PostgreSQL 18            : ${CYAN}localhost:5432${NC}"
echo -e "  ⚡ Redis Cache 8 (LFU)      : ${CYAN}localhost:6379${NC}"
if [[ " ${PROFILE_ARGS[*]} " =~ "messaging" ]]; then
    echo -e "  🐇 RabbitMQ Yönetim Paneli  : ${CYAN}http://localhost:15672${NC}"
fi
echo -e "----------------------------------------------------------------"
echo -e "Durdurmak için: ${YELLOW}./stop-docker.sh${NC}"
echo -e "Logları canlı izlemek için: ${YELLOW}docker compose logs -f${NC}\n"

if [ "$SHOW_LOGS" = true ]; then
    echo -e "${CYAN}Log takibi başlatılıyor (Çıkmak için Ctrl+C)...${NC}"
    docker compose logs -f
fi
