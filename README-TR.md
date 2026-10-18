# Guidora

Guidora, yazılım geliştirici araçları, kütüphaneler ve açık kaynak projeler için tasarlanmış kurumsal düzeyde bir katalog keşif ve yönetişim platformudur. Proje; .NET 10 Onion Architecture WebAPI arka ucu ile React 18 Tek Sayfa Uygulaması (SPA) ön yüzünü Nginx ters proxy arkasında birleştiren üretime hazır bir monorepo olarak yapılandırılmıştır.

---

## Mimari Genel Bakış

Guidora, kurumsal güvenlik gereği Sıfır-CORS (Zero-CORS) ağ modeli uygular. İstemci tarayıcıları yalnızca standart 80 portundaki Nginx ters proxy ile iletişim kurar. Nginx, önceden sıkıştırılmış statik SPA dosyalarını sunar ve `/api/*` ile `/health/*` isteklerini dahili Docker köprü ağı (`guidora-net`) üzerinden backend servisine yönlendirir. WebAPI, PostgreSQL veritabanı ve Redis önbellek portları üretim ortamında dış ağa açık değildir.

```text
[ İstemci Tarayıcı ]
        |
        | HTTP :80 (SPA & /api/*)
        v
+--------------------------------------------------------+
| frontend (Nginx 1.27 Ters Proxy & Statik Sunucu)       |
| - /         -> Statik SPA Varlıkları (Brotli / Gzip)   |
| - /api/*    -> proxy_pass http://backend:8080/api/*    |
| - /health/* -> proxy_pass http://backend:8080/health   |
+--------------------------------------------------------+
        |
        | Docker İç Köprü Ağı (guidora-net)
        v
+--------------------------------------------------------+
| backend (.NET 10 WebAPI - Onion Architecture)          |
| - REST Denetleyicileri, Aspect Interception            |
| - Unit of Work, FluentValidation, Hız Limitleri        |
+---------------------------+----------------------------+
                            |
             +--------------+--------------+
             |                             |
             v                             v
+--------------------------+  +--------------------------+
| postgres (PostgreSQL 18) |  | redis (Redis 8)          |
| - Tekil Doğruluk Kaynağı |  | - volatile-lfu Önbellek  |
| - citext, xmin kilitleme |  | - 256MB Kesin Sınır      |
+--------------------------+  +--------------------------+
```

---

## Depo Yapısı

Kök depo, orkestrasyon ve konteyner dağıtım sınırını oluşturur. Uygulama kaynak kodları, kendi Git geçmişleri ve test paketleri bulunan iki bağımsız alt modül (submodule) olarak yönetilir:

- `backend/`: Onion Architecture (Domain, Application, Infrastructure, Presentation) uygulayan .NET 10 WebAPI.
- `frontend/`: Vite ile derlenen, React Query ve Nginx üretim sunucusu içeren React 18 SPA.

```text
guidora/
├── backend/                  # Git Submodule (.NET 10 WebAPI)
│   ├── Core/                 # Aspect'ler, güvenlik araçları, ortak altyapı
│   ├── Entities/             # Varlık modelleri ve DTO'lar
│   ├── DataAccess/           # EF Core context, migration'lar, repository uygulamaları
│   ├── Business/             # İş kuralları, doğrulama yöneticileri
│   ├── WebAPI/               # HTTP denetleyicileri, middleware'ler, rate limit politikaları
│   └── Tests/                # Tekil test paketi (270+ birim ve entegrasyon testi)
├── frontend/                 # Git Submodule (React 18 SPA)
│   ├── src/                  # React bileşenleri, özel kancalar, API istemcileri
│   ├── infra/nginx/          # Güçlendirilmiş Nginx üretim yapılandırması
│   ├── infra/mock-server/    # Bağımsız geliştirme için süreç içi mock işleyici
│   └── tests/                # Vitest ve Happy-DOM test paketi (80+ test)
├── docker-compose.yml        # Üretim konteyner orkestrasyon dosyası
├── .env.example              # Ortam değişkenleri şablonu ve açıklamaları
├── start-docker.sh           # Otomatik dağıtım ve sağlık doğrulama betiği
├── stop-docker.sh            # Güvenli kapatma ve temizleme betiği
└── Makefile                  # Geliştirici ve DevOps komut hedefleri
```

Not: Kök depo yalnızca alt modülleri birleştiren bir orkestratör olduğundan bir changelog dosyası içermez. Sürüm geçmişi doğrudan alt modül depolarında tutulur.

---

## Temel Teknik Standartlar

### Sıfır-CORS Ağ İzolasyonu
Dış istemciler yalnızca 80 portu ile haberleşir. Nginx, WebAPI, PostgreSQL ve Redis arasındaki iletişim tamamen izole Docker iç ağı üzerinden yürütülür. Altyapı portları (`5432`, `6379`, `8080`) varsayılan olarak `127.0.0.1` adresine bağlanır ve yalnızca yerel yönetim içindir.

### Yüksek Eşzamanlı PostgreSQL 18
- URL ve slug tekilliği büyük/küçük harf duyarsız `citext` eklentisiyle sağlanır.
- Eşzamanlı güncellemelerde veri kaybını önlemek amacıyla PostgreSQL'in dahili `xmin` sistem kolonu üzerinden iyimser eşzamanlılık denetimi (optimistic concurrency control) uygulanır.
- `AuditLogs` tablosu, tüm varlık değişimlerini JSONB biçiminde tutar ve tek tıkla geri alma (`Audit.Revert`) desteği sunar.

### Sınırlandırılmış Dağıtık Önbellek
- Bellek tavanı kesin olarak `256mb` (`REDIS_MAXMEMORY`) ile sınırlandırılmıştır ve `volatile-lfu` tahliye politikası kullanılır.
- Önbellek anahtarları desen tabanlı geçersiz kılınarak yığılma (cache stampede) engellenir.

### Güvenlik ve Oturum Yönetimi
- Access Token değerleri yalnızca bellekte (`tokenManager.js`) saklanır; `localStorage` tabanlı XSS sızıntılarına kapalıdır.
- Refresh Token oturumları `HttpOnly; SameSite=Lax` çerezleri üzerinden iletilir.
- 401 Mutex Kuyruğu: Eşzamanlı isteklerde token süresi bittiğinde yalnızca tek bir refresh isteği tetiklenir, diğer çağrılar bekletilir.
- Üretim ortamında varsayılan veya şablon anahtarlarla sistemin başlaması engellenir.
- Giriş, kayıt, oylama, yorum ve ürün ekleme uç noktaları için ayrıntılı hız sınırları uygulanır.

### Dayanıklı Ön Yüz Mimarisi
- Devre Kesici (Circuit Breaker): Üst üste 5 sunucu hatası (5xx) veya zaman aşımında `OPEN` durumuna geçer; 20 saniye boyunca dış istekleri hızlıca keserek (fast-fail) altyapıyı korur.
- Arka plan sağlık sondası (`/health/live`) yanıt verdiğinde devre otomatik olarak `CLOSED` konumuna döner.
- Sayfa ve görünüm geçişleri React 18 `startTransition` ile yürütülerek arayüz sıçramaları önlenir.

---

## Hızlı Başlangıç: Sunucu Dağıtımı

### Ön Gereksinimler
- Docker Engine 24.0.0 veya üzeri
- Docker Compose v2.20.0 veya üzeri
- (İsteğe bağlı yerel geliştirme: .NET 10 SDK, Node.js 22 LTS)

### 1. Depoyu Alt Modülleriyle Klonlayın

```bash
git clone --recurse-submodules https://github.com/TahsinCr/guidora.git
cd guidora
```

Alt modüller olmadan klonlandıysa:

```bash
git submodule update --init --recursive
```

### 2. Ortam Değişkenlerini Yapılandırın

```bash
cp .env.example .env
chmod 600 .env
```

Kriptografik güvenli anahtarlar üretin:

```bash
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(openssl rand -hex 16)|" .env
sed -i "s|^TOKEN_OPTIONS__SECURITYKEY=.*|TOKEN_OPTIONS__SECURITYKEY=$(openssl rand -base64 32)|" .env
sed -i "s|^COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=.*|COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY=$(openssl rand -base64 32)|" .env
```

### 3. Yığını Başlatın

```bash
# Başlatma betiği ile:
./start-docker.sh

# Veya Make ile:
make up

# Veya doğrudan Docker Compose ile:
docker compose up -d --build --wait
```

### 4. Sağlık Durumunu Doğrulayın

```bash
# Konteyner durumlarını listele
docker compose ps

# Nginx üzerinden backend hazırlık sondasını denetle
curl --fail http://localhost/health/ready

# Katalog API uç noktasını sorgula
curl --fail http://localhost/api/products
```

---

## Servis Tablosu

| Servis | İmaj / Build Context | İç Port | Host Port (Varsayılan) | Sağlık Denetimi | Görev |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `frontend` | `./frontend/dockerfile` | 80 | `0.0.0.0:80` | `GET /healthz` | Statik SPA sunumu ve Sıfır-CORS ters proxy |
| `backend` | `./backend/dockerfile` | 8080 | `127.0.0.1:8080` | `GET /health/ready` | Onion Architecture REST API |
| `postgres` | `postgres:18.6-alpine` | 5432 | `127.0.0.1:5432` | `pg_isready` | `citext` ve `xmin` ile ACID veritabanı |
| `redis` | `redis:8.10.1-alpine` | 6379 | `127.0.0.1:6379` | `redis-cli ping` | `volatile-lfu` ile dağıtık önbellek |
| `rabbitmq` | `rabbitmq:4.3.6-alpine` | 5672, 15672 | `127.0.0.1:5672` | `ping` | İsteğe bağlı kuyruk (`--profile messaging`) |

---

## Geliştirme İş Akışları

### Bağımsız Frontend Geliştirme

```bash
cd frontend

# Süreç içi mock işleyici ile arka uçsuz geliştirme
npm run dev

# Canlı backend bağlantılı entegrasyon modu (http://localhost:8080)
npm run dev:real

# Test paketini çalıştır
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

### Alt Modül Senkronizasyonu

Alt modüllerde geliştirme yaparken:
1. Değişiklikleri alt modül dizininde (`backend/` veya `frontend/`) yapın ve test edin.
2. Doğrudan alt modülün kendi deposuna commit atıp pushlayın.
3. Kök dizinde güncellenen commit referansını sahneleyip commit atın:

```bash
git add backend frontend
git commit -m "chore(submodules): update backend and frontend references"
```

---

## Konfigürasyon Referansı

| Değişken | Varsayılan | Üretimde Zorunlu | Açıklama |
| :--- | :--- | :---: | :--- |
| `FRONTEND_PORT` | `80` | Hayır | Nginx tarafından dışarı açılan HTTP portu |
| `BACKEND_PORT` | `8080` | Hayır | Doğrudan backend portu (127.0.0.1) |
| `INFRA_BIND_ADDRESS` | `127.0.0.1` | Hayır | Veritabanı ve önbellek portlarının bağlanacağı IP |
| `POSTGRES_DB` | `guidora` | Hayır | PostgreSQL veritabanı adı |
| `POSTGRES_USER` | `guidora` | Hayır | PostgreSQL kullanıcı adı |
| `POSTGRES_PASSWORD` | - | **Evet** | Veritabanı parolası |
| `REDIS_PASSWORD` | - | **Evet** | Redis kimlik doğrulama parolası |
| `TOKEN_OPTIONS__SECURITYKEY` | - | **Evet** | JWT imzalama anahtarı (>= 32 karakter) |
| `COMMUNITY_VERIFICATION_SIGNAL_HASH_KEY` | - | **Evet** | Topluluk oy doğrulama anahtarı |
| `BOOTSTRAP_ADMIN_ENABLED` | `false` | Hayır | İlk yönetici hesabının oluşturulmasını açar |
| `BOOTSTRAP_ADMIN_USERNAME` | - | Koşullu | İlk yönetici kullanıcı adı |
| `BOOTSTRAP_ADMIN_EMAIL` | - | Koşullu | İlk yönetici e-posta adresi |
| `BOOTSTRAP_ADMIN_PASSWORD` | - | Koşullu | İlk yönetici parolası |
| `RATE_LIMIT_LOGIN_PERMIT_LIMIT` | `10` | Hayır | Pencere başına izin verilen giriş denemesi |
| `RATE_LIMIT_LOGIN_WINDOW_SECONDS` | `60` | Hayır | Giriş hız limiti pencere süresi (saniye) |

---

## İşletim ve Bakım

### Standart Komutlar

```bash
# Tüm konteynerleri arka planda başlat
make up

# Canlı konteyner loglarını takip et
make logs

# Konteyner durumlarını listele
make ps

# Tüm alt modül testlerini çalıştır
make test

# Verileri koruyarak servisleri durdur
make down

# Servisleri durdur ve veritabanı birimlerini temizle
make clean
```

### Veritabanı Yedekleme ve Geri Yükleme

```bash
# Zaman damgalı SQL yedeği al
docker compose exec -T postgres pg_dump -U guidora guidora > "guidora_backup_$(date +%Y%m%d_%H%M%S).sql"

# SQL yedeğinden geri yükle
cat guidora_backup_*.sql | docker compose exec -T postgres psql -U guidora guidora
```

---

## Lisans

Bu proje ve alt modülleri MIT Lisansı ile lisanslanmıştır.
