# Guidora — Kurumsal Geliştirici Araçları & Yönetişim Platformu

[![Docker Compose](https://img.shields.io/badge/Docker_Compose-v2.20+-2496ED?style=for-the-badge&logo=docker&logoColor=white)](docker-compose.yml)
[![.NET 10](https://img.shields.io/badge/.NET_10-WebAPI_Onion_Arch-512BD4?style=for-the-badge&logo=dotnet&logoColor=white)](backend/)
[![React 18](https://img.shields.io/badge/React_18-Vite_SPA_Resilient-61DAFB?style=for-the-badge&logo=react&logoColor=black)](frontend/)
[![PostgreSQL 18](https://img.shields.io/badge/PostgreSQL_18-Alpine_xmin_ACID-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](docker-compose.yml)
[![Redis 8](https://img.shields.io/badge/Redis_8-volatile--lfu_Bounded-DC382D?style=for-the-badge&logo=redis&logoColor=white)](docker-compose.yml)
[![Nginx](https://img.shields.io/badge/Nginx_1.27-Zero--CORS_Proxy-009639?style=for-the-badge&logo=nginx&logoColor=white)](frontend/infra/nginx/default.conf)

> **Guidora**, geliştirici araçları, kütüphaneler ve açık kaynak yazılımlar için tasarlanmış kurumsal seviyede bir katalog keşif, topluluk kürasyonu ve yönetişim platformudur. Tekil ve üretime hazır (production-ready) bir monorepo yapısında kurgulanmış olup; **.NET 10 Onion Architecture WebAPI** arka ucu ile **React 18 Single-Page Application (SPA)** ön yüzünü **Sıfır-CORS Nginx Ters Proxy** mimarisiyle tek bir orkestrasyonda buluşturur.

---

## 🌐 Sistem Mimarisi & Sıfır-CORS Modeli

Guidora, kurumsal güvenlik gereği katı bir **Sıfır-CORS (Zero-CORS)** topolojisi uygular. Dış istemciler ve tarayıcılar yalnızca 80 portundaki Nginx ters proxy ile haberleşir. Nginx, derlenmiş statik arayüz varlıklarını (Brotli/Gzip) doğrudan sunarken; `/api/*` ve `/health/*` rotalarını iç Docker köprü ağı (`guidora-net`) üzerinden backend servisine aktarır. Veritabanı ve önbellek katmanı dış dünyaya tamamen kapalıdır.

```text
[ Tarayıcı / Dış İstemci ]
            │
            │ HTTP :80 (SPA & /api/*)
            ▼
┌────────────────────────────────────────────────────────┐
│  frontend (Nginx 1.27 Ters Proxy & Statik SPA Sunucu) │
│  - /         ──► Statik Varlıklar (Brotli / Gzip)      │
│  - /api/*    ──► proxy_pass http://backend:8080/api/*   │
│  - /health/* ──► proxy_pass http://backend:8080/health  │
└────────────────────────────────────────────────────────┘
            │
            │ Docker İç Ağı (`guidora-net`)
            ▼
┌────────────────────────────────────────────────────────┐
│  backend (.NET 10 WebAPI - Onion Architecture)         │
│  - REST Denetleyiciler, Aspect Interception            │
│  - Unit of Work, FluentValidation, Hız Sınırları       │
└───────────────────────┬────────────────────────────────┘
                        │
         ┌──────────────┴──────────────┐
         ▼                             ▼
┌──────────────────┐          ┌──────────────────┐
│  postgres (v18)  │          │   redis (v8)     │
│  - Single Truth  │          │  - volatile-lfu  │
│  - citext, xmin  │          │  - 256MB Sınırlı │
└──────────────────┘          └──────────────────┘
```

---

## 🏛️ Monorepo & Git Submodule Mimarisi

Kök depo, Guidora ekosisteminin **ana orkestratörü ve konteyner çerçevesidir**. Kod tabanı, kendi Git geçmişleri, sürümlemeleri ve test paketleri bulunan iki bağımsız alt modül (submodule) olarak yönetilir:

- **[`backend/`](backend/)** (`git@github.com:TahsinCr/guidora-backend.git`): .NET 10 Clean Onion Architecture WebAPI.
- **[`frontend/`](frontend/)** (`git@github.com:TahsinCr/guidora-frontend.git`): React 18 Kurumsal SPA ve Nginx.

```text
guidora/
├── backend/                  # [Submodule] .NET 10 WebAPI Onion Architecture
│   ├── Core/                 # Aspect'ler, interceptor'lar, cross-cutting kütüphanesi
│   ├── Entities/             # Varlık modelleri, DTO'lar, denetim şemaları
│   ├── DataAccess/           # EF Core 10, migration'lar, PostgreSQL repository'leri
│   ├── Business/             # İş kuralları, doğrulama yöneticileri
│   ├── WebAPI/               # REST API uçları, middleware'ler, filtreler
│   └── Tests/                # Tekil test paketi (270+ test)
├── frontend/                 # [Submodule] React 18 Kurumsal SPA
│   ├── src/                  # React bileşenleri, kancalar, servisler, context'ler
│   ├── infra/nginx/          # Güçlendirilmiş Nginx üretim yapılandırması
│   ├── infra/mock-server/    # Sıfır bağımlılıklı mock sunucu & Vite eklentisi
│   └── tests/                # Vitest & Happy-DOM test paketleri (80+ test)
├── docker-compose.yml        # Birleşik üretim Docker orkestrasyonu
├── .env.example              # Kapsamlı ortam değişkenleri şablonu
├── start-docker.sh           # Otomatik üretim başlatıcı ve sağlık doğrulayıcı
├── stop-docker.sh            # Güvenli durdurma ve temizleme aracı
└── Makefile                  # Standart DevOps ve geliştirici kısayolları
```

> **Not**: Kök depo, bağımsız alt modülleri çerçeveleyen ana orkestratör olduğundan bir `CHANGELOG.md` içermez. Sürüm kayıtları ve detaylı değişiklikler doğrudan ilgili alt modül depolarında tutulur.

---

## 🚀 Önemli Mimari Prensipler

### 1. Sıfır-CORS Güvenlik Yalıtımı
- Dış istemciler doğrudan veritabanı, redis veya doğrudan backend portuyla iletişim kurmaz.
- İç ağ (`guidora-net`) dış müdahaleleri engeller. Host portları (`BACKEND_PORT`, `POSTGRES_PORT`, `REDIS_PORT`) yalnızca yerel hata ayıklama amacıyla `127.0.0.1` adresine kilitlenir.

### 2. Yüksek Eşzamanlı PostgreSQL 18
- URL ve slug tekilliği büyük/küçük harf duyarsız `citext` eklentisiyle korunur.
- Çakışan güncellemeler ve veri kaybı, PostgreSQL'in dahili `xmin` sistem kolonu tabanlı iyimser eşzamanlılık (optimistic concurrency) kontrolleriyle engellenir.
- Append-only `AuditLogs` tablosu üzerinde JSONB delta takibi ve tek tıkla geri alma (`Audit.Revert`) desteği mevcuttur.

### 3. Sınırlandırılmış Dağıtık Önbellek (Redis 8)
- Bellek tüketimi `256mb` (`REDIS_MAXMEMORY`) ile sınırlandırılmış olup `volatile-lfu` tahliye politikası kullanılır.
- Desen tabanlı atomik anahtar geçersiz kılma ile önbellek yığılmaları önlenir.

### 4. Kurumsal Güvenlik & Oturum Yönetimi
- **Hafızada (In-Memory) JWT**: Access Token yalnızca bellek içinde saklanır; `localStorage` sızıntılarına karşı tam korumalıdır.
- **HttpOnly Çerezler**: Yenileme oturumları `HttpOnly; SameSite=Lax` çerezleriyle yürütülür.
- **401 Mutex Kuyruğu**: Eşzamanlı 401 Unauthorized durumlarında sunucuya yalnızca tek bir refresh isteği atılır; diğer istekler kuyrukta bekletilir.
- **Sıfır Varsayılan Parola**: Üretim ortamında şablon veya varsayılan parolalarla başlangıç yapılması engellenir.
- **Ayrıntılı Hız Sınırları**: Giriş, kayıt, doğrulama, yorum, oy ve içerik ekleme için uç nokta bazlı hız limitleri aktiftir.

### 5. Dayanıklı İstemci Mimarisi (Resilience)
- **Devre Kesici (Circuit Breaker)**: 5 ardışık 5xx hatasında devre `OPEN` moduna geçer, çöken servise 20 saniye boyunca sorgu göndermeyerek fast-fail uygular.
- **Ortam Durum Farkındalığı (Ambient Awareness)**: Gerçek zamanlı durum çubuğu ile API gecikmesi, devre kesici durumu ve arka plan iyileşmesi kesintisiz izlenir.
- **Eşzamanlı Geçişler (Concurrent Transitions)**: Sayfa ve görünüm geçişleri React 18 `startTransition` ile yürütülür, arayüz sıçramaları önlenir.

---

## 🛠️ Hızlı Kurulum & Sunucu Dağıtımı

### Gereksinimler
- **Docker Engine** `24.0.0+`
- **Docker Compose** `v2.20.0+`
- (İsteğe bağlı bağımsız geliştirme: .NET 10 SDK, Node.js 22 LTS)

### Adım 1: Depoyu Alt Modülleriyle Klonlayın

```bash
git clone --recurse-submodules https://github.com/TahsinCr/guidora.git
cd guidora
```

*Eğer `--recurse-submodules` olmadan klonladıysanız hemen eşitleyin:*
```bash
git submodule update --init --recursive
```

### Adım 2: Çevre Değişkenlerini Yapılandırın

Şablonu kopyalayın:
```bash
cp .env.example .env
chmod 600 .env
```

Kriptografik güvenli üretim parolaları üretin:
```bash
# 32 karakterlik güvenli rastgele anahtarlar atayın
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=$(openssl rand -base64 32)|" .env
sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=$(openssl rand -base64 32)|" .env
```

### Adım 3: Yığını Başlatın

```bash
# Otomatik başlatıcı betiği ile:
./start-docker.sh

# Veya Make komutu ile:
make up

# Veya doğrudan Docker Compose ile:
docker compose up -d --build --wait
```

### Adım 4: Sistem Sağlığını Doğrulayın

```bash
# Konteyner çalışma ve sağlık durumlarını listeleyin
docker compose ps

# Nginx üzerinden backend hazırlık sondasını (readiness probe) denetleyin
curl --fail http://localhost/health/ready

# Ürün katalog API'sini denetleyin
curl --fail http://localhost/api/products
```

---

## 🌐 Servis Tablosu & Port Eşleştirmeleri

| Servis | Konteyner İmajı | İç Port | Host Port (Varsayılan) | Sağlık Denetimi | Görev |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`frontend`** | `nginx:1.27-alpine-slim` | `80` | `0.0.0.0:80` | `GET /healthz` | SPA sunumu ve Sıfır-CORS ters proxy |
| **`backend`** | `.NET 10 SDK / Runtime` | `8080` | `127.0.0.1:8080` | `GET /health/ready` | Çekirdek Onion Architecture REST API |
| **`postgres`** | `postgres:18.6-alpine` | `5432` | `127.0.0.1:5432` | `pg_isready` | `citext` ve `xmin` ile ACID veritabanı |
| **`redis`** | `redis:8.10.1-alpine` | `6379` | `127.0.0.1:6379` | `redis-cli ping` | `volatile-lfu` dağıtık önbellek |
| **`rabbitmq`** | `rabbitmq:4.3.6-alpine` | `5672`, `15672` | `127.0.0.1:5672` | `ping` | İsteğe bağlı kuyruk (`--profile messaging`) |

---

## 💻 Alt Modül Geliştirme İş Akışları

### Bağımsız Frontend Geliştirme
```bash
cd frontend

# 1. Sıfır bağımlılıklı mod (arka uçsuz, süreç içi mock veriler)
npm run dev

# 2. Canlı backend bağlantılı mod (http://localhost:8080'e yönlenir)
npm run dev:real

# Frontend testlerini çalıştır
npm test
```

### Bağımsız Backend Geliştirme
```bash
cd backend

# Projeyi derle
dotnet build NetCoreBackend.sln

# Tüm test paketini çalıştır
dotnet test Tests/Tests.csproj
```

---

## 📋 İşletim & Bakım Kılavuzu

### Temel Komutlar

```bash
# Servisleri arka planda başlat
make up           # veya ./start-docker.sh

# Canlı konteyner loglarını izle
make logs         # veya docker compose logs -f

# Durumları listele
make ps           # veya docker compose ps

# Tüm testleri çalıştır
make test

# Servisleri güvenle kapat (veritabanını koruyarak)
make down         # veya ./stop-docker.sh

# Konteynerleri ve veritabanı birimlerini tamamen temizle
make clean        # veya ./stop-docker.sh --clean
```

### Veritabanı Yedekleme & Geri Yükleme

```bash
# Zaman damgalı SQL yedeği alma:
docker compose exec -T postgres pg_dump -U guidora guidora > "guidora_yedek_$(date +%Y%m%d_%H%M%S).sql"

# Yedeği geri yükleme:
cat guidora_yedek_*.sql | docker compose exec -T postgres psql -U guidora guidora
```

---

## 📄 Lisans

Bu monorepo orkestratörü ve alt modülleri **MIT Lisansı** ile lisanslanmıştır.
