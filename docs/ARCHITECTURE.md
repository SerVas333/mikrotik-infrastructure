# Архитектура решения - MikroTik Infrastructure v1.3

**Версия:** 1.3 (Централизованная конфигурация)
**Дата:** 15 декабря 2025
**Архитектурный паттерн:** Modular Configuration with Central Registry

---

## 📋 Содержание

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Принципы проектирования](#принципы-проектирования)
3. [Централизованная конфигурация](#централизованная-конфигурация)
4. [Структура модулей](#структура-модулей)
5. [Сетевая топология](#сетевая-топология)
6. [Диаграммы](#диаграммы)
7. [Технические решения](#технические-решения)

---

## Обзор архитектуры

### Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────────────┐
│                    MikroTik RouterOS                        │
│                                                             │
│  ┌────────────────────────────────────────────────────┐   │
│  │         Centralized Configuration Layer            │   │
│  │  (00-config.rsc + 00-secrets.rsc)                 │   │
│  │  - 130+ infrastructure variables                   │   │
│  │  - 40+ secret variables                           │   │
│  └────────────────────────────────────────────────────┘   │
│                          ▲                                  │
│                          │ Used by                          │
│  ┌───────────────────────┴──────────────────────────┐     │
│  │              Modular Configuration                │     │
│  │  ┌────────┐ ┌────────┐ ┌──────────┐ ┌─────────┐│     │
│  │  │  Base  │ │Network │ │ Firewall │ │  DHCP   ││     │
│  │  │01-base │ │02-net  │ │ complete │ │ 03-dhcp ││     │
│  │  └────────┘ └────────┘ └──────────┘ └─────────┘│     │
│  │  ┌────────┐ ┌────────┐ ┌──────────┐ ┌─────────┐│     │
│  │  │  VPN   │ │  WiFi  │ │   DNS    │ │Container││     │
│  │  │05-sstp │ │06-wifi │ │  doh     │ │  setup  ││     │
│  │  └────────┘ └────────┘ └──────────┘ └─────────┘│     │
│  └──────────────────────────────────────────────────┘     │
│                                                             │
│  ┌──────────────────────────────────────────────────┐     │
│  │              Infrastructure Layer                 │     │
│  │  - Bridge (LAN, Containers)                      │     │
│  │  - VLANs (Main, Guest, Management)               │     │
│  │  - Firewall (IPv4/IPv6)                          │     │
│  │  - NAT, Routing, QoS                             │     │
│  └──────────────────────────────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### Ключевые компоненты

1. **Centralized Configuration (00-config.rsc, 00-secrets.rsc)**
   - Single source of truth для всех параметров
   - Защита секретов от утечки в VCS

2. **Modular Configuration (01-*.rsc, 02-*.rsc, ...)**
   - Логическое разделение функциональности
   - Независимые, переиспользуемые модули
   - Простота обновления и обслуживания

3. **Infrastructure Services**
   - Firewall (IPv4/IPv6)
   - DHCP, DNS
   - VPN (SSTP, WireGuard)
   - Container runtime (Docker)

---

## Принципы проектирования

### 1. DRY (Don't Repeat Yourself)

**Проблема (до v1.3):**
```routeros
# 01-base.rsc
:local timezone "Europe/Kiev"

# 02-network.rsc
:local timezone "Europe/Kiev"

# ... повторяется в 19 файлах
```

**Решение (v1.3):**
```routeros
# 00-config.rsc (один раз)
:global cfgTimezone "Europe/Kiev"

# Все модули используют
/system clock set time-zone-name=$cfgTimezone
```

**Результат:**
- Изменение в одном месте вместо 19 файлов
- Нет рассинхронизации
- Легче поддерживать

---

### 2. Separation of Concerns

Каждый модуль отвечает за одну функциональную область:

| Модуль | Ответственность | Зависимости |
|--------|-----------------|-------------|
| `00-config.rsc` | Инфраструктурные переменные | Нет |
| `00-secrets.rsc` | Секретные переменные | Нет |
| `01-base.rsc` | Базовая система (users, NTP, services) | 00-config, 00-secrets |
| `02-network.rsc` | Сеть (bridge, VLAN, IPv6) | 00-config |
| `03-dhcp.rsc` | DHCP серверы | 00-config, 02-network |
| `firewall_complete.rsc` | Firewall (IPv4/IPv6) | 00-config, 02-network |
| `05-sstp-vpn.rsc` | SSTP VPN | 00-config, 00-secrets |
| `06-wifi-unified.rsc` | WiFi конфигурация | 00-config, 00-secrets |

**Преимущества:**
- Легко понять за что отвечает модуль
- Изменения изолированы
- Модули можно переиспользовать в других проектах

---

### 3. Security by Design

**Многоуровневая защита (Defense in Depth):**

```
Layer 1: Network Segmentation
  ├─ LAN (192.168.1.0/24)      - Trusted devices
  ├─ Guest (10.30.0.0/24)      - Isolated guests
  ├─ Management (172.16.99.0/24) - Admin access
  └─ Containers (10.11.0.0/24)  - Service isolation

Layer 2: Firewall
  ├─ Input chain   - Router protection
  ├─ Forward chain - Inter-VLAN rules
  └─ Output chain  - Egress control

Layer 3: Access Control
  ├─ SSH/Winbox ACL  - Management access only from allowed networks
  ├─ Service disable - HTTP/Telnet/FTP disabled
  └─ User auth      - Strong passwords (00-secrets.rsc)

Layer 4: Encryption
  ├─ DNS-over-HTTPS  - Encrypted DNS queries
  ├─ SSTP VPN       - Encrypted tunnel
  └─ WireGuard S2S  - Modern crypto
```

**Применение принципа Least Privilege:**
- Guest сеть не имеет доступа к LAN
- Containers изолированы от Management VLAN
- SSH/Winbox доступны только из разрешённых подсетей

---

### 4. Configuration as Code

**Все в Git:**
- ✅ Версионирование конфигурации
- ✅ История изменений (git log)
- ✅ Code review (pull requests)
- ✅ Rollback (git revert)
- ✅ Branches для экспериментов

**Защита секретов:**
```gitignore
# .gitignore
00-secrets.rsc
*.backup
```

**CI/CD готовность:**
- Валидация синтаксиса (можно добавить pre-commit hooks)
- Автоматическое тестирование (CHR + Vagrant)
- Автоматическое развёртывание (Ansible + MikroTik API)

---

### 5. Fail-Safe Defaults

**Безопасные настройки по умолчанию:**

```routeros
# Firewall: по умолчанию DROP (whitelist approach)
/ip firewall filter add chain=input action=drop comment="Drop all other"

# Services: опасные сервисы отключены
/ip service set www disabled=yes
/ip service set telnet disabled=yes

# DNS: не публичный resolver
/ip dns set allow-remote-requests=no
```

**Explicit over Implicit:**
- Явно разрешаем что нужно
- Всё остальное блокируется
- Нет "скрытых" разрешений

---

## Централизованная конфигурация

### Архитектурный паттерн

**Pattern Name:** Central Registry with Global Variables

**Intent:** Централизовать все конфигурационные параметры в одном месте для упрощения управления и предотвращения дублирования.

**Structure:**

```
┌──────────────────────┐
│   00-config.rsc      │
│  (Configuration)     │
│                      │
│  :global cfgHostname │
│  :global cfgLANNet   │
│  :global cfg...      │
└──────────┬───────────┘
           │ defines
           ▼
┌──────────────────────┐      ┌──────────────────────┐
│   00-secrets.rsc     │      │   Module Files       │
│   (Secrets)          │      │  (01-base.rsc, ...)  │
│                      │      │                      │
│  :global secAdmin    │◄─────┤  Use $cfgHostname    │
│  :global secWiFi     │ use  │  Use $cfgLANNetwork  │
│  :global sec...      │      │  Use $secAdminPass   │
└──────────────────────┘      └──────────────────────┘
```

**Participants:**

1. **Configuration Registry (00-config.rsc)**
   - Хранит infrastructure variables
   - Использует префикс `cfg*`
   - 130+ переменных

2. **Secrets Vault (00-secrets.rsc)**
   - Хранит sensitive data
   - Использует префикс `sec*`
   - 40+ переменных
   - Защищён .gitignore

3. **Consumer Modules (01-*.rsc, 02-*.rsc, ...)**
   - Используют переменные из registry
   - Не дублируют значения
   - Зависят от 00-config.rsc и 00-secrets.rsc

**Consequences:**

**Преимущества:**
- ✅ Single source of truth
- ✅ Легко изменять параметры (1 место вместо N)
- ✅ Защита секретов (00-secrets.rsc в .gitignore)
- ✅ Типизация через префиксы (cfg*, sec*)
- ✅ Самодокументируемость

**Недостатки:**
- ⚠️ Нужно импортировать в правильном порядке
- ⚠️ Больший initial setup (создание 00-secrets.rsc)

---

### Категории переменных

#### Infrastructure Variables (cfg*)

```routeros
# System
:global cfgHostname "R1-Core"
:global cfgTimezone "Europe/Kiev"

# Network
:global cfgWanInterface "ether1"
:global cfgLANNetwork "192.168.1.0/24"
:global cfgLANGateway "192.168.1.1/24"

# VLANs
:global cfgMgmtVLAN 99
:global cfgGuestVLAN 30

# Services
:global cfgDNSDoHURL "https://cloudflare-dns.com/dns-query"
:global cfgNTPServers [:toarray "time.cloudflare.com,pool.ntp.org"]
```

**130+ переменных** охватывают:
- System (hostname, timezone)
- Interfaces (WAN, LAN, bridge)
- IPv4/IPv6 addressing
- VLANs
- WiFi
- DNS, NTP
- VPN
- BGP
- Containers

#### Secret Variables (sec*)

```routeros
# System credentials
:global secAdminPassword "..."

# WiFi passwords
:global secWiFiMainPassword "..."
:global secWiFiGuestPassword "..."

# VPN credentials
:global secSSTPUsername "..."
:global secSSTPPassword "..."
:global secWGPrivateKey "..."

# Service credentials
:global secXRayUUID "..."
:global secDDNSPassword "..."
```

**40+ переменных** для:
- User passwords
- WiFi PSK
- VPN credentials
- API keys
- Certificates
- BGP secrets

---

## Структура модулей

### Модульная иерархия

```
mikrotik-infrastructure/
├── 00-config.rsc              # [CORE] Infrastructure variables
├── 00-secrets.rsc             # [CORE] Secrets (gitignored)
│
├── 01-base.rsc                # [FOUNDATION] Base system
├── 02-network.rsc             # [FOUNDATION] Network infrastructure
├── 03-dhcp.rsc                # [FOUNDATION] DHCP servers
├── firewall_complete.rsc      # [FOUNDATION] Firewall rules
│
├── dns-doh.rsc                # [SERVICES] DNS-over-HTTPS
├── 05-sstp-vpn.rsc            # [SERVICES] SSTP VPN
├── wireguard-s2s.rsc          # [SERVICES] WireGuard Site-to-Site
├── 06-wifi-unified.rsc        # [SERVICES] WiFi configuration
│
├── container-setup.rsc        # [ADVANCED] Container runtime
└── xray/                      # [ADVANCED] XRay proxy
    ├── 01-container-xray.rsc
    ├── 02-container-nginx.rsc
    ├── 03-container-certbot.rsc
    └── 04-bgp-proxy.rsc
```

### Зависимости модулей

```
Graph TD
    CONFIG[00-config.rsc]
    SECRETS[00-secrets.rsc]

    BASE[01-base.rsc]
    NETWORK[02-network.rsc]
    DHCP[03-dhcp.rsc]
    FIREWALL[firewall_complete.rsc]

    DOH[dns-doh.rsc]
    VPN[05-sstp-vpn.rsc]
    WG[wireguard-s2s.rsc]
    WIFI[06-wifi-unified.rsc]

    CONTAINER[container-setup.rsc]
    XRAY[xray/...]

    CONFIG --> BASE
    CONFIG --> NETWORK
    CONFIG --> DHCP
    CONFIG --> FIREWALL
    CONFIG --> DOH
    CONFIG --> VPN
    CONFIG --> WG
    CONFIG --> WIFI
    CONFIG --> CONTAINER

    SECRETS --> BASE
    SECRETS --> VPN
    SECRETS --> WG
    SECRETS --> WIFI
    SECRETS --> XRAY

    NETWORK --> DHCP
    NETWORK --> FIREWALL

    CONTAINER --> XRAY
```

**Порядок импорта:**
1. 00-config.rsc (обязательно первым)
2. 00-secrets.rsc (обязательно вторым)
3. Foundation modules (01-base, 02-network, 03-dhcp, firewall_complete)
4. Service modules (dns-doh, vpn, wifi)
5. Advanced modules (containers, xray)

---

### Детальное описание модулей

#### CORE: 00-config.rsc

**Назначение:** Централизованное хранилище всех инфраструктурных параметров

**Содержит:**
- System settings (hostname, timezone)
- Network interfaces
- IPv4/IPv6 addressing
- VLAN IDs
- WiFi configuration
- DNS, NTP servers
- VPN endpoints
- Container settings
- Management ACL

**Используется:** Всеми модулями

**Размер:** ~185 строк, 130+ переменных

---

#### CORE: 00-secrets.rsc

**Назначение:** Безопасное хранение секретов

**Содержит:**
- User passwords
- WiFi PSK
- VPN credentials
- API keys
- Certificates

**Защита:**
- Не попадает в git (.gitignore)
- Шаблон: 00-secrets.rsc.template

**Размер:** ~40 переменных

---

#### FOUNDATION: 01-base.rsc

**Назначение:** Базовая настройка системы

**Конфигурирует:**
- System identity (hostname)
- System clock (timezone, NTP)
- Users (admin password)
- IP services (SSH, Winbox, disable HTTP/Telnet)
- Management ACL

**Зависимости:** 00-config.rsc, 00-secrets.rsc

**Решает проблемы:**
- CRIT-05: Management ACL
- CRIT-06: HTTP disabled

---

#### FOUNDATION: 02-network.rsc

**Назначение:** Сетевая инфраструктура

**Конфигурирует:**
- Bridge (LAN, Containers)
- VLANs (Main VLAN 20, Guest VLAN 30, Management VLAN 99)
- IPv6 tunnel (Hurricane Electric)
- IPv6 prefix delegation

**Зависимости:** 00-config.rsc

**Решает проблемы:**
- Network segmentation
- IPv6 connectivity

---

#### FOUNDATION: 03-dhcp.rsc

**Назначение:** DHCP серверы для всех сетей

**Конфигурирует:**
- DHCP server для LAN (192.168.1.0/24)
- DHCP server для Management (172.16.99.0/24)
- DHCP server для Guest (10.30.0.0/24)
- IP pools
- DHCP options (gateway, DNS)

**Зависимости:** 00-config.rsc, 02-network.rsc

---

#### FOUNDATION: firewall_complete.rsc

**Назначение:** Полная конфигурация firewall (IPv4 + IPv6)

**Конфигурирует:**
- Input chain (защита роутера)
- Forward chain (контроль трафика между сетями)
- Output chain (контроль исходящего трафика роутера)
- NAT (masquerade для WAN)
- IPv6 firewall
- Mangle rules (fasttrack)

**Зависимости:** 00-config.rsc, 02-network.rsc

**Решает проблемы:**
- CRIT-02: IPv6 firewall
- CRIT-03: Container security
- Guest isolation
- Management access control

**Размер:** ~300 строк, 50+ правил

---

#### SERVICES: dns-doh.rsc

**Назначение:** DNS-over-HTTPS (encrypted DNS)

**Конфигурирует:**
- DoH сервер (CloudFlare)
- DNS settings (allow-remote-requests=no)
- Firewall правила для DNS

**Зависимости:** 00-config.rsc

**Решает проблемы:**
- CRIT-04: DNS security
- DNS privacy

---

#### SERVICES: 05-sstp-vpn.rsc

**Назначение:** SSTP VPN сервер

**Конфигурирует:**
- SSTP server
- PPP profile
- IP pool
- Certificate
- Firewall rules

**Зависимости:** 00-config.rsc, 00-secrets.rsc

---

#### SERVICES: wireguard-s2s.rsc

**Назначение:** WireGuard Site-to-Site VPN

**Конфигурирует:**
- WireGuard interface
- Peer configuration
- Static routes
- Firewall rules

**Зависимости:** 00-config.rsc, 00-secrets.rsc

---

#### SERVICES: 06-wifi-unified.rsc

**Назначение:** WiFi конфигурация (2.4GHz + 5GHz)

**Конфигурирует:**
- WiFi interfaces
- Security profiles
- SSIDs (Main, Guest)
- VLANs для WiFi
- Channel settings

**Зависимости:** 00-config.rsc, 00-secrets.rsc

---

#### ADVANCED: container-setup.rsc

**Назначение:** Docker container runtime

**Конфигурирует:**
- Container mounts
- Container network (veth, bridge)
- Registry settings
- Storage paths

**Зависимости:** 00-config.rsc

**Решает проблемы:**
- CRIT-03: Container network isolation

---

#### ADVANCED: xray/

**Назначение:** XRay proxy infrastructure

**Модули:**
- `01-container-xray.rsc` - XRay container
- `02-container-nginx.rsc` - Nginx reverse proxy
- `03-container-certbot.rsc` - Let's Encrypt certificates
- `04-bgp-proxy.rsc` - BGP routing для XRay

**Зависимости:** 00-config.rsc, 00-secrets.rsc, container-setup.rsc

---

## Сетевая топология

### Физическая топология

```
                 Internet
                    │
                    │ (WAN)
             ┌──────┴──────┐
             │   ether1    │
             │             │
             │  MikroTik   │
             │   Router    │
             │             │
             └─┬─┬─┬─┬─┬──┘
               │ │ │ │ │
        ether2─┘ │ │ │ └─ether5 (wlan1 - 5GHz WiFi)
                 │ │ │
        ether3───┘ │ └───ether4 (wlan0 - 2.4GHz WiFi)
                   │
            (LAN ports)
```

### Логическая топология (VLANs)

```
┌───────────────────────────────────────────────────────┐
│                   MikroTik Router                      │
│                                                        │
│  ┌────────────────────────────────────────────────┐  │
│  │          bridge-lan (Master Bridge)            │  │
│  │                                                 │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐    │  │
│  │  │ VLAN 20  │  │ VLAN 30  │  │ VLAN 99  │    │  │
│  │  │   Main   │  │  Guest   │  │   Mgmt   │    │  │
│  │  │192.168.1 │  │10.30.0.0 │  │172.16.99 │    │  │
│  │  └──────────┘  └──────────┘  └──────────┘    │  │
│  │      │              │              │          │  │
│  │      │              │              │          │  │
│  │  ┌───┴──────────────┴──────────────┴───┐    │  │
│  │  │     ether2, ether3, ether4,         │    │  │
│  │  │     wlan0, wlan1                    │    │  │
│  │  └─────────────────────────────────────┘    │  │
│  └────────────────────────────────────────────────┘  │
│                                                        │
│  ┌────────────────────────────────────────────────┐  │
│  │      bridge-containers (Isolated)              │  │
│  │              10.11.0.0/24                      │  │
│  │   ┌──────────┐ ┌──────────┐ ┌──────────┐     │  │
│  │   │  XRay    │ │  Nginx   │ │ Certbot  │     │  │
│  │   │10.11.0.10│ │10.11.0.11│ │10.11.0.12│     │  │
│  │   └──────────┘ └──────────┘ └──────────┘     │  │
│  └────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────┘
```

### IP Addressing Scheme

| Network | VLAN | IP Range | Gateway | DHCP Pool | Purpose |
|---------|------|----------|---------|-----------|---------|
| **LAN Main** | 20 | 192.168.1.0/24 | 192.168.1.1 | .50-.250 | Trusted devices |
| **Guest** | 30 | 10.30.0.0/24 | 10.30.0.1 | .100-.200 | Guest WiFi, isolated |
| **Management** | 99 | 172.16.99.0/24 | 172.16.99.1 | .20-.200 | Admin access |
| **Containers** | - | 10.11.0.0/24 | 10.11.0.1 | - (static) | Docker containers |
| **SSTP VPN** | - | 192.168.88.0/24 | - | .2-.10 | VPN clients |
| **WireGuard S2S** | - | 10.10.0.0/24 | - | - (static) | Site-to-Site |

### Traffic Flow

```
┌─────────────────────────────────────────────────────┐
│                    Traffic Flow                      │
└─────────────────────────────────────────────────────┘

LAN → Internet:
  192.168.1.0/24 → NAT (masquerade) → WAN (pppoe-out1)
  ✅ Allowed by firewall forward chain

Guest → Internet:
  10.30.0.0/24 → NAT (masquerade) → WAN
  ✅ Allowed, but blocked to LAN/Management

Guest → LAN:
  10.30.0.0/24 → 192.168.1.0/24
  ❌ BLOCKED by firewall (drop rule)

Guest → Management:
  10.30.0.0/24 → 172.16.99.0/24
  ❌ BLOCKED by firewall (drop rule)

Containers → Internet:
  10.11.0.0/24 → NAT → WAN
  ✅ Allowed for specific ports (HTTP/HTTPS)

Containers → LAN:
  10.11.0.0/24 → 192.168.1.0/24
  ⚠️ Limited (only established connections)

Internet → Router (input chain):
  ❌ BLOCKED by default (drop all)
  ✅ EXCEPT: established, related, ICMP ping

LAN/Management → Router (SSH/Winbox):
  ✅ Allowed from cfgMgmtAllowedNets
  ❌ Blocked from other networks
```

---

## Диаграммы

### Firewall Decision Tree

```
                    Packet arrives
                          │
                          ▼
                  ┌───────────────┐
                  │  Connection   │
                  │  Tracking     │
                  └───────┬───────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
   established       related           new/invalid
        │                 │                 │
     ACCEPT            ACCEPT            Continue
                                            │
                                            ▼
                                    ┌────────────┐
                                    │  Invalid?  │
                                    └─────┬──────┘
                                          │
                                    ┌─────┴─────┐
                                    │           │
                                   YES         NO
                                    │           │
                                  DROP     Continue
                                                │
                                                ▼
                                        ┌───────────────┐
                                        │ Match allow   │
                                        │ rules?        │
                                        └───────┬───────┘
                                                │
                                        ┌───────┴───────┐
                                       YES             NO
                                        │               │
                                     ACCEPT           DROP
```

### Module Loading Sequence

```
Time │
  ▼  │
     │ /import 00-config.rsc
     │  └─ Load 130+ infrastructure variables
     │     :global cfgHostname, cfgTimezone, ...
     │
     │ /import 00-secrets.rsc
     │  └─ Load 40+ secret variables
     │     :global secAdminPassword, secWiFi...
     │
     │ /import 01-base.rsc
     │  ├─ Read $cfgHostname, $secAdminPassword
     │  ├─ Set system identity
     │  ├─ Create admin user
     │  └─ Configure services
     │
     │ /import 02-network.rsc
     │  ├─ Read $cfgBridgeLAN, $cfgVLANs
     │  ├─ Create bridge-lan
     │  ├─ Create VLANs
     │  └─ Assign IPs
     │
     │ /import 03-dhcp.rsc
     │  ├─ Read $cfgLANNetwork, $cfgLANGateway
     │  ├─ Create DHCP servers
     │  └─ Create pools
     │
     │ /import firewall_complete.rsc
     │  ├─ Read $cfgLANNetwork, $cfgGuestNetwork
     │  ├─ Add input rules
     │  ├─ Add forward rules
     │  └─ Add NAT rules
     │
     │ ... (other modules)
     ▼
```

---

## Технические решения

### 1. Variable Scoping

**Global vs Local:**

```routeros
# ❌ BAD (v1.2 и ранее)
:local hostname "R1-Core"  # Локальная, умирает после скрипта
:local timezone "Europe/Kiev"  # Нужно переопределять в каждом файле

# ✅ GOOD (v1.3)
:global cfgHostname "R1-Core"  # Глобальная, доступна везде
:global cfgTimezone "Europe/Kiev"  # Определяется один раз
```

**Преимущества global:**
- Доступны из любого модуля
- Не нужно передавать параметры
- Единая точка изменения

**Недостатки global:**
- Потенциальные конфликты имён (решается префиксами cfg*, sec*)
- Сложнее тестировать изолированно

---

### 2. Array Variables

**RouterOS Script Arrays:**

```routeros
# Определение массива
:global cfgLANPorts [:toarray "ether2,ether3,ether4"]
:global cfgNTPServers [:toarray "time.cloudflare.com,pool.ntp.org"]

# Использование
:foreach port in=$cfgLANPorts do={
  /interface bridge port add bridge=$cfgBridgeLAN interface=$port
}
```

**Преимущества:**
- Легко добавлять/удалять элементы
- Итерация через :foreach
- Типобезопасность

---

### 3. Naming Conventions

**Prefixes:**

| Prefix | Type | Example | Purpose |
|--------|------|---------|---------|
| `cfg*` | Infrastructure variable | `cfgHostname` | Configuration parameters |
| `sec*` | Secret variable | `secAdminPassword` | Sensitive data |
| `bridge-*` | Bridge interface | `bridge-lan` | Bridge interfaces |
| `vlan-*` | VLAN interface | `vlan-main-20` | VLAN interfaces |
| `pool-*` | IP pool | `pool-lan` | DHCP pools |
| `dhcp-*` | DHCP server | `dhcp-lan` | DHCP servers |

**Consistency:**
- Lowercase с дефисами для интерфейсов
- camelCase для переменных
- Descriptive names (не `var1`, `var2`)

---

### 4. Firewall Ordering Strategy

**Sequential Ordering (v1.2+):**

```routeros
# Правила добавляются в ПРАВИЛЬНОМ порядке сверху вниз
# НЕ используется place-before

# 1. Fasttrack (performance optimization)
add chain=forward action=fasttrack-connection ...

# 2. Accept established/related
add chain=forward connection-state=established,related action=accept

# 3. Drop invalid
add chain=forward connection-state=invalid action=drop

# 4. Accept valid traffic
add chain=forward src-address=$LAN_MAIN_V4 action=accept

# 5. Isolation rules (BEFORE accepts for other networks)
add chain=forward src-address=$LAN_GUEST_V4 \
    dst-address=$LAN_MAIN_V4 action=drop comment="Guest isolation"

# 6. Accept guest to internet (AFTER isolation)
add chain=forward src-address=$LAN_GUEST_V4 action=accept

# 7. Drop all other
add chain=forward action=drop comment="Drop all other"
```

**Key principle:**
- Блокирующие правила (drop) должны идти РАНЬШЕ разрешающих (accept)
- Более специфичные правила раньше общих

---

### 5. Secrets Management

**Problem:** Secrets в git = security incident

**Solution:**

```bash
# .gitignore
00-secrets.rsc          # Real secrets (NEVER commit)
*.backup                # Backup files
*.rsc.old               # Old configs
```

**Workflow:**

1. Developer клонирует repo
2. Копирует `00-secrets.rsc.template` → `00-secrets.rsc`
3. Заполняет реальными паролями в `00-secrets.rsc`
4. `00-secrets.rsc` НЕ попадает в git
5. Template обновляется с новыми переменными (без значений)

**Alternative solutions (для production):**
- HashiCorp Vault
- AWS Secrets Manager
- Ansible Vault
- Encrypted git (git-crypt)

---

## Best Practices

### Development Workflow

1. **Перед изменением:**
   ```routeros
   /system backup save name=before-change
   /export file=before-change
   ```

2. **Во время изменения:**
   ```routeros
   # Используйте Safe Mode (Ctrl+X)
   # Изменения откатятся если потеряете соединение
   ```

3. **После изменения:**
   ```routeros
   /log print where topics~"error|critical"
   # Проверьте на ошибки
   ```

4. **Коммит в git:**
   ```bash
   git add 00-config.rsc
   git commit -m "feat: Add new VLAN for IoT devices"
   git push
   ```

### Testing Strategy

**Levels of testing:**

1. **Syntax validation**
   ```routeros
   # Импорт покажет syntax errors
   /import test-config.rsc
   ```

2. **Connectivity testing**
   ```bash
   # С клиента
   ping 192.168.1.1
   ping 1.1.1.1
   curl -I https://google.com
   ```

3. **Security testing**
   ```bash
   # Попытка доступа из guest к LAN (должна провалиться)
   ping 192.168.1.10  # from guest network

   # Сканирование портов
   nmap -sS 192.168.1.1  # from external
   ```

4. **Load testing**
   ```bash
   # Генерация трафика
   iperf3 -c 192.168.1.1 -t 60
   ```

---

## Расширение архитектуры

### Добавление нового модуля

**Example:** Добавление Captive Portal для Guest сети

1. **Создайте файл:**
   ```routeros
   # 07-captive-portal.rsc
   ```

2. **Используйте централизованную конфигурацию:**
   ```routeros
   # 00-config.rsc - добавьте переменные
   :global cfgCaptivePortalInterface "vlan-guest-30"
   :global cfgCaptivePortalIdleTimeout "5m"

   # 00-secrets.rsc - добавьте секреты
   :global secCaptivePortalAdminPassword "..."
   ```

3. **Напишите модуль:**
   ```routeros
   # 07-captive-portal.rsc
   /ip hotspot profile add name="guest-profile" \
       login-by=http-chap \
       idle-timeout=$cfgCaptivePortalIdleTimeout

   /ip hotspot add name="guest-hotspot" \
       interface=$cfgCaptivePortalInterface \
       profile=guest-profile
   ```

4. **Обновите документацию:**
   - README.md (структура проекта)
   - DEPLOYMENT_GUIDE.md (порядок импорта)
   - ARCHITECTURE.md (этот файл)

---

## Заключение

Архитектура v1.3 основана на проверенных принципах проектирования:
- **DRY** - централизованная конфигурация
- **Separation of Concerns** - модульная структура
- **Security by Design** - многоуровневая защита
- **Configuration as Code** - версионирование в git
- **Fail-Safe Defaults** - безопасные настройки по умолчанию

Это обеспечивает:
- ✅ **Легкость в управлении** - изменения в одном месте
- ✅ **Безопасность** - проверенные практики, 100% критических проблем решено
- ✅ **Масштабируемость** - легко добавлять новые модули
- ✅ **Поддерживаемость** - понятная структура, документация

---

**Создано:** Claude Code (Sonnet 4.5)
**Дата:** 15 декабря 2025
**Версия:** 1.3
