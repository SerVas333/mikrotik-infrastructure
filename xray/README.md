# xRay VPN Integration для MikroTik

xRay proxy в контейнере на MikroTik для маршрутизации трафика через VPN.

**Версия:** 2.0 (улучшенная, интегрированная с проектом)

---

## 📋 Что включено

1. **01-xray-integration.rsc** - Основная конфигурация:
   - xRay контейнер (pinned version: teddysun/xray:1.8.4)
   - Отдельная таблица маршрутизации (xray-table)
   - Resource limits (max 200MB RAM)
   - Healthcheck и auto-restart
   - Интеграция с bridge-containers

2. **02-xray-config-example.json** - Пример конфигурации xRay:
   - VLESS протокол с XTLS
   - SOCKS5 и HTTP прокси (порты 1080, 8080)
   - Transparent proxy (port 12345)
   - Routing rules (блокировка рекламы, обход локальных IP)

3. **04-bgp-proxy.rsc** - BGP маршрутизация через xRay:
   - BGP instance с routing filter
   - Автоматический импорт префиксов в xray-table
   - Community-based routing (65999:100 → xRay)
   - Готовая работающая конфигурация

---

## 🔧 Отличия от старой версии

| Проблема | Было | Стало |
|----------|------|-------|
| Версия контейнера | `teddysun/xray` (latest) | `teddysun/xray:1.8.4` (pinned) |
| Resource limits | Отсутствовали | `memory-high=200M` |
| DNS контейнера | `dns=$XRAY_IP` (неправильно) | `dns=10.11.0.1` (gateway) |
| Интерфейс | `interface=container` | `interface=bridge-containers` |
| Healthcheck | Каждые 30 сек | Каждую 1 минуту + улучшенная логика |
| Firewall правила | Дублировались | Используются из firewall_complete.rsc |
| Конфигурация xRay | Отсутствовала | Полный пример config.json |

---

## 🚀 Быстрый старт

### Шаг 1: Подготовка

```bash
# Скопировать файлы на роутер
scp xray/*.rsc xray/*.json admin@192.168.1.1:/

# Подключиться к роутеру
ssh admin@192.168.1.1
```

### Шаг 2: Настроить переменные

Отредактируйте **01-xray-integration.rsc** (строки 16-43):

```routeros
# xRay server settings (ваш VPN сервер)
:local XRAY_REMOTE_SERVER "your-server.com"
:local XRAY_REMOTE_PORT "443"
:local XRAY_UUID "your-uuid-here"
:local XRAY_PROTOCOL "vless"
```

### Шаг 3: Применить конфигурацию

```routeros
/import 01-xray-integration.rsc
```

Это создаст:
- xRay контейнер (остановлен)
- Routing table `xray-table`
- Mount directories (xray-config, xray-logs)
- Healthcheck script
- Default route через xRay в таблице `xray-table`

### Шаг 4: Создать конфигурационный файл xRay

#### Вариант A: Через SSH (рекомендуется)

```bash
# Подключитесь к роутеру
ssh admin@192.168.1.1

# Создайте config.json на основе примера
cat > xray-config/config.json << 'EOF'
{
  "log": {
    "loglevel": "warning",
    "access": "/xray-logs/access.log",
    "error": "/xray-logs/error.log"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": 1080,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "YOUR_SERVER_HERE",
            "port": 443,
            "users": [
              {
                "id": "YOUR_UUID_HERE",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "YOUR_SERVER_SNI",
          "allowInsecure": false
        }
      }
    }
  ]
}
EOF
```

**ВАЖНО:** Замените:
- `YOUR_SERVER_HERE` - адрес вашего xRay сервера
- `YOUR_UUID_HERE` - ваш UUID (получите от VPN провайдера)
- `YOUR_SERVER_SNI` - SNI для TLS (обычно совпадает с адресом сервера)

#### Вариант B: Через файловую систему MikroTik

1. Скопируйте `02-xray-config-example.json` на роутер
2. Переименуйте в `config.json`
3. Отредактируйте параметры через `/file/edit`
4. Переместите в `xray-config/`:

```routeros
/file/move config.json xray-config/config.json
```

### Шаг 5: Запустить контейнер

```routeros
/container/start xray
```

Проверьте статус:

```routeros
/container/print
# Должен показать status=running

/container/shell xray
# Внутри контейнера:
ps aux | grep xray
cat /xray-logs/error.log
```

### Шаг 6: Настроить маршрутизацию

Выберите один из вариантов:

#### Вариант A: Статические маршруты (просто)

Добавьте конкретные IP/подсети, которые должны идти через xRay:

```routeros
# Пример: Google DNS через xRay
/ip route add \
    dst-address=8.8.8.8/32 \
    gateway=10.11.0.10 \
    routing-table=xray-table \
    comment="Google DNS via xRay"

# Пример: Весь трафик с определённой подсети через xRay
/ip route add \
    dst-address=0.0.0.0/0 \
    gateway=10.11.0.10 \
    routing-table=main \
    routing-mark=xray-mark \
    comment="Default route for marked traffic"

# Маркировка трафика от клиента 192.168.1.100
/ip firewall mangle add \
    chain=prerouting \
    src-address=192.168.1.100 \
    action=mark-routing \
    new-routing-mark=xray-mark \
    comment="Route 192.168.1.100 via xRay"
```

#### Вариант B: BGP маршрутизация (автоматическая)

Если у вас есть BGP upstream, используйте `04-bgp-proxy.rsc`:

```bash
# Отредактируйте переменные в файле:
# - BGP_PEER_IP (адрес вашего BGP peer)
# - ROUTER_ID (ваш router ID)

# Примените конфигурацию:
/import xray/04-bgp-proxy.rsc
```

**Как это работает:**
- BGP peer анонсирует префиксы с community `65999:100`
- Эти префиксы автоматически попадают в `xray-table`
- Трафик на эти префиксы идёт через xRay контейнер (10.11.0.10)
- Остальные BGP префиксы идут в main table (обычный маршрут)

---

## 🔐 Безопасность

### Что сделано:

✅ **Resource limits:**
- xRay: max 200MB RAM

✅ **Network isolation:**
- Контейнер изолирован от LAN (firewall_complete.rsc)
- Доступ только к DNS (53) и NTP (123)
- Блокировка management портов

✅ **Firewall rules (из firewall_complete.rsc):**
- Строки 161-164: LAN/MGMT → xRay разрешено
- Строки 167-170: xRay → Internet разрешено
- Строка 293: NAT masquerade для контейнеров

✅ **Healthcheck:**
- Автоматический перезапуск при падении
- Проверка каждую минуту
- Логирование событий

---

## 📂 Структура файлов после применения

```
/
├── xray-root/              # Root filesystem xRay контейнера
├── xray-config/            # Mount: конфигурация
│   └── config.json        # Конфиг xRay (создать вручную!)
└── xray-logs/             # Mount: логи
    ├── access.log         # Access log
    └── error.log          # Error log
```

---

## 🧪 Тестирование

### Проверка статуса контейнера:

```routeros
/container/print
# Должен показать status=running

/log/print where message~"xRay"
# Проверить логи запуска
```

### Проверка конфигурации xRay:

```routeros
/container/shell xray

# Внутри контейнера:
cat /xray-config/config.json
tail -f /xray-logs/error.log
```

### Проверка маршрутизации:

```routeros
# Таблица маршрутизации xRay
/ip/route/print where routing-table=xray-table

# Должен быть маршрут по умолчанию:
# dst-address=0.0.0.0/0 gateway=10.11.0.10 routing-table=xray-table
```

### Проверка подключения к xRay:

```routeros
# Ping xRay контейнера
/ping 10.11.0.10 count=5

# Проверка SOCKS proxy
/tool/fetch mode=http \
    url="http://httpbin.org/ip" \
    http-method=get \
    http-proxy=10.11.0.10:1080
```

### Проверка трафика через xRay:

Если настроен policy routing для клиента 192.168.1.100:

```bash
# С клиента 192.168.1.100:
curl http://httpbin.org/ip
# Должен показать IP вашего xRay сервера

# С другого клиента:
curl http://httpbin.org/ip
# Должен показать ваш обычный WAN IP
```

---

## 🔧 Использование xRay

### Вариант 1: Policy Routing (для определённых клиентов)

```routeros
# Весь трафик от 192.168.1.100 через xRay
/ip firewall mangle add \
    chain=prerouting \
    src-address=192.168.1.100 \
    action=mark-routing \
    new-routing-mark=xray-mark

/ip route add \
    dst-address=0.0.0.0/0 \
    gateway=10.11.0.10 \
    routing-table=main \
    routing-mark=xray-mark
```

### Вариант 2: Определённые сайты через xRay

```routeros
# Создайте address-list для сайтов
/ip firewall address-list add \
    list=xray-sites \
    address=blocked-site.com

# Маркируйте трафик на эти сайты
/ip firewall mangle add \
    chain=prerouting \
    dst-address-list=xray-sites \
    action=mark-routing \
    new-routing-mark=xray-mark

# Маршрутизируйте через xRay
/ip route add \
    dst-address=0.0.0.0/0 \
    gateway=10.11.0.10 \
    routing-table=main \
    routing-mark=xray-mark
```

### Вариант 3: Прокси на клиентских устройствах

Настройте SOCKS5 прокси на клиентских устройствах:
- **Server:** 10.11.0.10
- **Port:** 1080
- **Type:** SOCKS5
- **Auth:** None

---

## 🛠️ Настройка конфигурации xRay

### Минимальная конфигурация (VLESS):

```json
{
  "inbounds": [{
    "port": 1080,
    "protocol": "socks",
    "settings": {"auth": "noauth"}
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "your-server.com",
        "port": 443,
        "users": [{
          "id": "your-uuid",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "tls"
    }
  }]
}
```

### Добавление блокировки рекламы:

```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["geosite:category-ads-all"],
        "outboundTag": "block"
      }
    ]
  },
  "outbounds": [
    {"tag": "proxy", "protocol": "vless", ...},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
```

### Протоколы кроме VLESS:

#### VMess:
```json
{
  "protocol": "vmess",
  "settings": {
    "vnext": [{
      "address": "server",
      "port": 443,
      "users": [{
        "id": "uuid",
        "alterId": 0,
        "security": "auto"
      }]
    }]
  }
}
```

#### Trojan:
```json
{
  "protocol": "trojan",
  "settings": {
    "servers": [{
      "address": "server",
      "port": 443,
      "password": "your-password"
    }]
  }
}
```

---

## 🐛 Troubleshooting

### Контейнер не запускается:

```routeros
/container/print detail
/log/print where message~"container"

# Проверить конфиг xRay
/container/shell xray
cat /xray-config/config.json
```

### Нет подключения к серверу:

```routeros
# Ping xRay сервера с роутера
/ping your-server.com count=5

# Проверить DNS в контейнере
/container/shell xray
nslookup your-server.com

# Проверить логи xRay
cat /xray-logs/error.log
```

### Трафик не идёт через xRay:

```routeros
# Проверить маршруты
/ip/route/print where routing-table=xray-table

# Проверить mangle rules
/ip/firewall/mangle/print where new-routing-mark=xray-mark

# Проверить firewall
/ip/firewall/filter/print where comment~"xRay"

# Traceroute от клиента
/tool/traceroute 8.8.8.8 src-address=192.168.1.100
```

### Healthcheck постоянно перезапускает контейнер:

```routeros
# Отключить healthcheck временно
/system/scheduler/disable xray-healthcheck-scheduler

# Проверить логи
/log/print where message~"xRay"

# Проверить config.json
/container/shell xray
xray test -config /xray-config/config.json
```

---

## 📖 Связанная документация

- **Firewall:** См. `/firewall_complete.rsc` (правила для xRay строки 161-171)
- **Безопасность:** См. `/docs/SECURITY_AUDIT.md` (Container security)
- **BGP:** См. `xray/04-bgp-proxy.rsc` (BGP маршрутизация через xRay)

---

## 🔗 Полезные ссылки

### xRay Documentation
- [xRay Official](https://github.com/XTLS/Xray-core)
- [xRay Configuration](https://xtls.github.io/en/config/)
- [Docker Image](https://hub.docker.com/r/teddysun/xray)

### Protocols
- [VLESS Protocol](https://xtls.github.io/en/config/protocols/vless.html)
- [VMess Protocol](https://xtls.github.io/en/config/protocols/vmess.html)
- [Trojan Protocol](https://xtls.github.io/en/config/protocols/trojan.html)

---

## ⚠️ ВАЖНО

1. **Firewall правила уже включены:**
   - НЕ нужно добавлять дополнительные правила, если применён `firewall_complete.rsc`
   - Проверьте строки 161-171 в firewall_complete.rsc

2. **NAT уже настроен:**
   - Masquerade для контейнеров есть в firewall_complete.rsc (строка 293)
   - НЕ нужно добавлять отдельные NAT правила

3. **Конфигурация xRay критична:**
   - Неправильный config.json = контейнер не запустится
   - Проверяйте JSON syntax перед применением
   - Тестируйте конфиг: `xray test -config /path/to/config.json`

4. **UUID безопасность:**
   - НЕ используйте слабые UUID
   - Генерируйте через: `uuidgen` (Linux/Mac) или онлайн генератор
   - НЕ храните в plain text в скриптах

---

**Создано:** 10 декабря 2025
**Версия:** 2.0 (интегрированная с проектом MikroTik)
