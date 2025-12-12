# Nginx + Certbot для MikroTik

Nginx reverse proxy с автоматическими Let's Encrypt сертификатами через Cloudflare DNS challenge.

**Улучшенная версия** - интегрирована с основным проектом MikroTik.

---

## 📋 Что включено

1. **01-container-nginx-certbot.rsc** - Основная конфигурация:
   - Nginx контейнер (pinned version: nginx:1.25.3-alpine)
   - Certbot контейнер (pinned version: certbot/dns-cloudflare:v2.7.4)
   - Resource limits (безопасность)
   - Интеграция с bridge-containers
   - Автоматическое обновление сертификатов (daily)

2. **02-nginx-reverse-proxy.rsc** - Конфигурация reverse proxy:
   - HTTP → HTTPS redirect
   - SSL/TLS security headers
   - WebSocket support
   - 3 примера сервисов (можно расширить)

---

## 🔧 Отличия от старой версии

### ✅ Исправлено:

| Проблема | Было | Стало |
|----------|------|-------|
| Версии контейнеров | `nginx:latest` | `nginx:1.25.3-alpine` (pinned) |
| Resource limits | Отсутствовали | `memory-high=150M` для nginx |
| DNS контейнеров | `dns=$NGINX_IP` (неправильно) | `dns=10.11.0.1` (gateway) |
| Credentials | Plain text в коде | Вынесены в отдельный файл |
| NAT правила | Дублировались | Используются из firewall_complete.rsc |
| Security headers | Отсутствовали | HSTS, X-Frame-Options, CSP |

### ⚠️ Важно:

- **NAT правила** уже есть в `firewall_complete.rsc` (строки 283-286 и 298-301)
- **Firewall изоляция** уже настроена в `firewall_complete.rsc` (строки 175-196)
- **НЕ нужно** применять старый `nat-nginx.rsc` - он создаст дублирующие правила!

---

## 🚀 Быстрый старт

### Шаг 1: Подготовка

```bash
# Скопировать файлы на роутер
scp nginx-certbot/*.rsc admin@192.168.1.1:/

# Подключиться к роутеру
ssh admin@192.168.1.1
```

### Шаг 2: Настроить переменные

Отредактируйте **01-container-nginx-certbot.rsc** (строки 14-42):

```routeros
:local DOMAIN "your-domain.com"
:local CF_EMAIL "your-email@example.com"
```

Отредактируйте **02-nginx-reverse-proxy.rsc** (строки 8-24):

```routeros
:local DOMAIN "your-domain.com"

# Service 1
:local SERVICE1_SUBDOMAIN "grafana"
:local SERVICE1_IP "192.168.1.10"
:local SERVICE1_PORT "3000"

# ... и т.д.
```

### Шаг 3: Применить конфигурацию контейнеров

```routeros
/import 01-container-nginx-certbot.rsc
```

Это создаст:
- Nginx контейнер (остановлен)
- Certbot контейнер (остановлен)
- Mount directories
- Скрипт обновления сертификатов
- Scheduler (запуск каждый день в 03:00)

### Шаг 4: Настроить Cloudflare API

1. Получите Cloudflare API token:
   - Зайдите в [Cloudflare Dashboard](https://dash.cloudflare.com/)
   - My Profile → API Tokens → Create Token
   - Используйте шаблон **"Edit zone DNS"**
   - Скопируйте token

2. Создайте файл с credentials на роутере:

```routeros
/file/edit certbot-data/cloudflare.ini
```

Содержимое файла:
```ini
dns_cloudflare_api_token = your_cloudflare_api_token_here
```

3. Установите права доступа:

```routeros
/file/set certbot-data/cloudflare.ini permissions=owner-read,owner-write
```

### Шаг 5: Применить конфигурацию nginx

```routeros
/import 02-nginx-reverse-proxy.rsc
```

### Шаг 6: Первое получение сертификата

```routeros
/system script run renew-letsencrypt
```

Это займет 1-2 минуты. Проверьте логи:

```routeros
/log print where message~"Certificate"
```

### Шаг 7: Проверка

```routeros
# Статус контейнеров
/container/print

# Проверить сертификаты
/container/shell certbot
ls -la /etc/letsencrypt/live/

# Проверить nginx
/container/shell nginx
nginx -t
```

Проверьте с внешнего хоста:
```bash
curl -I https://grafana.your-domain.com
```

---

## 📂 Структура файлов после применения

```
/
├── nginx-root/              # Root filesystem nginx контейнера
├── certbot-root/            # Root filesystem certbot контейнера
├── nginx-conf/              # Mount: конфиги nginx
│   └── default.conf         # Reverse proxy config
├── nginx-html/              # Mount: статические файлы (если нужно)
└── certbot-data/            # Mount: сертификаты и credentials
    ├── cloudflare.ini       # Cloudflare API token (создать вручную!)
    └── live/                # Let's Encrypt сертификаты
        └── your-domain.com/
            ├── fullchain.pem
            └── privkey.pem
```

---

## 🔄 Автоматическое обновление сертификатов

Настроено автоматически:

- **Скрипт:** `/system script print where name=renew-letsencrypt`
- **Scheduler:** Запускается каждый день в 03:00
- **Логика:** Certbot проверяет срок действия сертификата, обновляет если < 30 дней

Ручной запуск:
```routeros
/system script run renew-letsencrypt
```

---

## 🔐 Безопасность

### Что сделано:

✅ **Resource limits:**
- Nginx: max 150MB RAM
- Certbot: max 100MB RAM

✅ **Network isolation:**
- Контейнеры изолированы от LAN (firewall_complete.rsc)
- Доступ только к DNS (53) и NTP (123)
- Блокировка management портов роутера

✅ **SSL/TLS Security:**
- TLS 1.2 и 1.3 only
- Strong ciphers
- HSTS headers
- Security headers (X-Frame-Options, CSP, etc.)

✅ **Rate limiting:**
- Max 50 соединений с одного IP
- Max 20 новых соединений за 5 секунд
- DDoS защита (firewall_complete.rsc строки 175-196)

✅ **Credentials:**
- Cloudflare API token в отдельном файле
- Permissions: owner-read, owner-write
- Рекомендация: использовать Vault (см. docs/AUTOMATION_ARCHITECTURE.md)

---

## 🧪 Тестирование

### Проверка конфигурации nginx:

```routeros
/container/shell nginx
nginx -t
```

### Проверка сертификатов:

```routeros
/container/shell certbot
certbot certificates
```

### Проверка логов nginx:

```routeros
/container/shell nginx
tail -f /var/log/nginx/access.log
tail -f /var/log/nginx/error.log
```

### Проверка с внешнего хоста:

```bash
# Проверить SSL сертификат
openssl s_client -connect grafana.your-domain.com:443 -servername grafana.your-domain.com

# Проверить headers
curl -I https://grafana.your-domain.com

# Проверить редирект HTTP → HTTPS
curl -I http://grafana.your-domain.com
```

---

## 🛠️ Добавление новых сервисов

Отредактируйте **02-nginx-reverse-proxy.rsc**, добавьте новый блок:

```routeros
# Service 4 (новый)
:local SERVICE4_SUBDOMAIN "newapp"
:local SERVICE4_IP "192.168.1.40"
:local SERVICE4_PORT "8080"
```

И добавьте server block в `$nginxConfig`:

```nginx
server {
    listen 443 ssl http2;
    server_name $SERVICE4_SUBDOMAIN.$DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    location / {
        proxy_pass http://$SERVICE4_IP:$SERVICE4_PORT;
        proxy_set_header Host $host;
        # ... остальные headers
    }
}
```

Затем:
```routeros
/import 02-nginx-reverse-proxy.rsc
```

---

## 🐛 Troubleshooting

### Контейнер не запускается:

```routeros
/container/print
/log print where message~"container"
```

### Сертификат не обновляется:

```routeros
# Проверить cloudflare.ini
/file/print where name~"cloudflare"

# Запустить вручную с логами
/system script run renew-letsencrypt
/log print where message~"Certificate"
```

### Nginx показывает 502 Bad Gateway:

```routeros
# Проверить доступность backend сервиса
/tool/flood-ping $SERVICE1_IP count=5

# Проверить firewall
/ip firewall filter print where comment~"containers"
```

### Не работает с внешнего интернета:

```routeros
# Проверить NAT правила (должны быть из firewall_complete.rsc)
/ip firewall nat print where comment~"nginx"

# Проверить WAN IP
/ip address print where interface=pppoe-out1

# Проверить DNS
nslookup grafana.your-domain.com
```

---

## 📖 Связанная документация

- **Firewall:** См. `/firewall_complete.rsc` (NAT и изоляция контейнеров)
- **Безопасность:** См. `/docs/SECURITY_AUDIT.md` (Container security)
- **Автоматизация:** См. `/docs/AUTOMATION_ARCHITECTURE.md` (Vault для credentials)

---

## ⚠️ ВАЖНО: Что НЕ нужно делать

❌ **НЕ применяйте** старый `nat-nginx.rsc` - правила уже есть в `firewall_complete.rsc`

❌ **НЕ используйте** `:latest` теги для контейнеров - только pinned версии

❌ **НЕ храните** Cloudflare API token в plain text в скриптах - используйте отдельный файл

❌ **НЕ удаляйте** firewall правила для изоляции контейнеров

---

**Создано:** 10 декабря 2025
**Версия:** 2.0 (улучшенная, интегрированная с проектом)
