# Рекомендации по устранению проблем безопасности

**Дата:** 10 декабря 2025
**Последнее обновление:** 12 декабря 2025
**Версия:** 1.2
**Предназначение:** Детальные инструкции по устранению найденных проблем
**Предварительное чтение:** SECURITY_AUDIT.md

**Новое в v1.2:**
- ✅ Доступен готовый `firewall_complete.rsc` (IPv4 + IPv6, 500+ строк)
- ✅ Модуль `nginx-certbot/` с улучшенной безопасностью
- ✅ WiFi CAPsMAN модуль (dual-stack, роуминг, client isolation)
- ✅ WDS Bridge модуль (12 исправленных проблем безопасности)

---

## Оглавление

1. [Критические исправления (P0)](#критические-исправления-p0)
2. [Важные исправления (P1)](#важные-исправления-p1)
3. [Средние исправления (P2)](#средние-исправления-p2)
4. [Дополнительные улучшения](#дополнительные-улучшения)
5. [Best Practices MikroTik RouterOS 7.x](#best-practices-mikrotik-routeros-7x)
6. [Чек-лист безопасности](#чек-лист-безопасности)

---

## Критические исправления (P0)

### ✅ CRIT-02: Создание IPv6 Firewall [SOLVED ✓]

**Приоритет:** P0 (критический)
**Время на внедрение:** 30 минут
**Риск внедрения:** Низкий

**✅ Готовое решение:** Используйте `firewall_complete.rsc` (IPv4 + IPv6, 500+ строк)
- Файл: `/firewall_complete.rsc`
- Включает полный IPv6 firewall с rate limiting, logging, ND security

#### Или создайте отдельный файл: `03a-ipv6-firewall.rsc`

```routeros
# ===================================================================
# 03a-ipv6-firewall.rsc
# IPv6 Firewall Configuration
# Based on MikroTik best practices 2025
# ===================================================================

# ===================================================================
# INPUT Chain (traffic to the router itself)
# ===================================================================

# Accept established and related connections
/ipv6 firewall filter
add chain=input connection-state=established,related \
    action=accept comment="Accept established/related"

# Drop invalid connections
add chain=input connection-state=invalid \
    action=drop comment="Drop invalid"

# Accept ICMPv6 (with rate limit to prevent flood)
add chain=input protocol=icmpv6 \
    limit=50/5s,10:packet action=accept \
    comment="Accept ICMPv6 (rate limited)"

add chain=input protocol=icmpv6 \
    action=drop comment="Drop ICMPv6 flood"

# Accept DHCPv6-Client prefix delegation
add chain=input protocol=udp dst-port=546 src-address=fe80::/10 \
    action=accept comment="Accept DHCPv6-Client"

# Allow management from LAN (adjust prefix to your actual LAN)
# Replace with your delegated IPv6 prefix if needed
add chain=input in-interface-list=LAN \
    action=accept comment="Accept from LAN"

# Allow management from specific management subnet (if using IPv6)
# add chain=input src-address=YOUR_IPV6_MGMT_PREFIX::/64 \
#     action=accept comment="Accept from IPv6 Management"

# Log and drop everything else
add chain=input action=log log-prefix="IPv6-INPUT-DROP: " \
    comment="Log other input"
add chain=input action=drop comment="Drop all other input"

# ===================================================================
# FORWARD Chain (traffic through the router)
# ===================================================================

# Accept established and related
add chain=forward connection-state=established,related \
    action=accept comment="Accept established/related"

# Drop invalid
add chain=forward connection-state=invalid \
    action=drop comment="Drop invalid"

# Accept ICMPv6 for forward (needed for ND, path MTU discovery)
add chain=forward protocol=icmpv6 \
    limit=100/5s,20:packet action=accept \
    comment="Accept ICMPv6 forward (rate limited)"

add chain=forward protocol=icmpv6 \
    action=drop comment="Drop ICMPv6 forward flood"

# Block private IPv6 addresses from WAN (RFC 4193, link-local)
add chain=forward in-interface-list=WAN src-address=fc00::/7 \
    action=drop comment="Drop ULA from WAN"
add chain=forward in-interface-list=WAN src-address=fe80::/10 \
    action=drop comment="Drop link-local from WAN"

# Allow LAN to WAN
add chain=forward in-interface-list=LAN out-interface-list=WAN \
    action=accept comment="Allow LAN to WAN"

# Drop WAN to LAN by default (unless you have specific services)
add chain=forward in-interface-list=WAN out-interface-list=LAN \
    action=drop comment="Drop WAN to LAN by default"

# Log and drop everything else
add chain=forward action=log log-prefix="IPv6-FORWARD-DROP: " \
    comment="Log other forward"
add chain=forward action=drop comment="Drop all other forward"

# ===================================================================
# Interface Lists (if not already defined)
# ===================================================================

# Create interface lists if they don't exist
:if ([:len [/interface list find name=LAN]] = 0) do={
    /interface list add name=LAN comment="LAN interfaces"
    /interface list member add list=LAN interface=bridge-lan
}

:if ([:len [/interface list find name=WAN]] = 0) do={
    /interface list add name=WAN comment="WAN interfaces"
    /interface list member add list=WAN interface=pppoe-out1
    /interface list member add list=WAN interface=sit1
}

# ===================================================================
# IPv6 ND (Router Advertisement) Security
# ===================================================================

# Limit who can send Router Advertisements (prevent rogue RAs)
/ipv6 nd
set [find interface=bridge-lan] ra-interval=1m-5m \
    ra-lifetime=30m managed-address-configuration=yes \
    other-configuration-flag=yes

# ===================================================================
# Additional IPv6 Security
# ===================================================================

# Disable IPv6 neighbor discovery on WAN (if not needed)
/ipv6 nd set [find interface=pppoe-out1] disabled=yes
/ipv6 nd set [find interface=sit1] disabled=yes

:log info "IPv6 Firewall configured successfully"
```

#### Порядок применения:

1. **Backup текущей конфигурации:**
   ```routeros
   /system backup save name=before-ipv6-fw encryption=aes-sha256 password="YourBackupPassword"
   /export file=before-ipv6-fw
   ```

2. **Загрузить файл на роутер:**
   ```bash
   scp 03a-ipv6-firewall.rsc admin@192.168.1.1:/
   ```

3. **Применить:**
   ```routeros
   /import 03a-ipv6-firewall.rsc
   ```

4. **Проверить:**
   ```routeros
   /ipv6 firewall filter print
   /ipv6 firewall filter print statistics
   ```

5. **Протестировать с внешнего IPv6 хоста:**
   ```bash
   # Должно быть заблокировано:
   ssh -6 admin@2001:470:6e:2b7::2
   nmap -6 -p 22,8291 2001:470:6e:2b7::2
   ```

#### Что это даёт:

- ✅ Защита management интерфейсов через IPv6
- ✅ Предотвращение IPv6 сканирования
- ✅ Защита от rogue RA атак
- ✅ Логирование подозрительной активности
- ✅ Rate limiting для ICMP flood

---

### ✅ CRIT-03: Изоляция контейнеров от роутера [SOLVED ✓]

**Приоритет:** P0 (критический)
**Время на внедрение:** 20 минут
**Риск внедрения:** Средний (может нарушить работу контейнеров)

**✅ Готовое решение:** Используйте модуль `nginx-certbot/`
- Файлы: `/nginx-certbot/01-nginx-certbot-deploy.rsc` + `02-nginx-certbot-renew.rsc`
- Включает: pinned версии, resource limits, firewall изоляцию, rate limiting

#### Или внесите изменения в существующий `08-containers.rsc`

**Заменить строки 58-60 на:**

```routeros
# ===================================================================
# Container Network Security (CRITICAL)
# ===================================================================

# УДАЛИТЬ старое правило:
# /ip firewall filter remove [find comment="Allow container internal management"]

# Добавить новые правила с принципом least privilege:

# 1. DNS: контейнерам нужен резолвинг
/ip firewall filter
add chain=input src-address=10.11.0.0/24 protocol=udp dst-port=53 \
    action=accept comment="Containers: DNS UDP"

add chain=input src-address=10.11.0.0/24 protocol=tcp dst-port=53 \
    action=accept comment="Containers: DNS TCP"

# 2. NTP: синхронизация времени (опционально)
add chain=input src-address=10.11.0.0/24 protocol=udp dst-port=123 \
    action=accept comment="Containers: NTP"

# 3. Syslog: централизованное логирование (опционально)
add chain=input src-address=10.11.0.0/24 protocol=udp dst-port=514 \
    action=accept comment="Containers: Syslog"

# 4. БЛОКИРОВАТЬ management порты от контейнеров
add chain=input src-address=10.11.0.0/24 protocol=tcp \
    dst-port=22,8291,80,443,8728,8729,21,23 \
    action=drop comment="Block containers -> router management"

# 5. БЛОКИРОВАТЬ всё остальное от контейнеров к роутеру
add chain=input src-address=10.11.0.0/24 \
    action=drop comment="Block containers -> router (default deny)"

# ===================================================================
# Container Network Isolation (FORWARD chain)
# ===================================================================

# Блокировать доступ контейнеров к внутренним сетям
add chain=forward src-address=10.11.0.0/24 dst-address=192.168.1.0/24 \
    action=drop comment="Block containers -> LAN"

add chain=forward src-address=10.11.0.0/24 dst-address=172.16.99.0/24 \
    action=drop comment="Block containers -> Management VLAN"

add chain=forward src-address=10.11.0.0/24 dst-address=10.30.0.0/24 \
    action=drop comment="Block containers -> Guest WiFi"

# Разрешить контейнерам доступ в интернет (всё остальное)
# Handled by existing established/related rules and NAT

# ===================================================================
# Rate Limiting для публичных сервисов (nginx)
# ===================================================================

# Connection limit: максимум 50 соединений с одного IP, burst 32
add chain=forward dst-address=10.11.0.11 protocol=tcp \
    dst-port=80,443 connection-state=new \
    connection-limit=50,32 action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: connection limit per IP"

# Rate limit: максимум 20 новых соединений за 5 секунд
add chain=forward dst-address=10.11.0.11 protocol=tcp \
    dst-port=80,443 connection-state=new \
    limit=20,5:packet action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: rate limit new connections"

# Drop превышение лимитов
add chain=forward dst-address=10.11.0.11 protocol=tcp \
    dst-port=80,443 connection-state=new \
    action=drop \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: drop flood"

# ===================================================================
# Resource Limits для контейнеров
# ===================================================================

# Ограничить потребление памяти
/container config set tmpdir=/disk1/tmp registry-url=https://registry-1.docker.io

# Установить memory limits для каждого контейнера
/container set xray envlist="" memory-high=200M
/container set nginx envlist="" memory-high=150M
/container set certbot envlist="" memory-high=100M

:log info "Container security applied: isolation + rate limiting + resource limits"
```

#### Дополнительно: Pinned версии образов

**Заменить в `08-containers.rsc:41-45`:**

```routeros
# БЫЛО:
# remote-image=teddysun/xray:latest
# remote-image=nginx:stable-alpine
# remote-image=certbot/certbot:latest

# СТАЛО (pinned versions):
/container set xray remote-image=teddysun/xray:1.8.4
/container set nginx remote-image=nginx:1.25.3-alpine
/container set certbot remote-image=certbot/certbot:v2.7.4

# После изменения - пересоздать контейнеры:
/container stop xray
/container stop nginx
/container remove xray
/container remove nginx

# Добавить заново с pinned версиями
/container add name=xray interface=containers \
    root-dir=/disk1/images/xray \
    mounts=mount-xray-conf \
    start-on-boot=yes \
    remote-image=teddysun/xray:1.8.4 \
    memory-high=200M

/container add name=nginx interface=containers \
    root-dir=/disk1/images/nginx \
    mounts=mount-nginx-conf,mount-lets \
    start-on-boot=yes \
    remote-image=nginx:1.25.3-alpine \
    memory-high=150M

/container start xray
/container start nginx
```

#### Проверка после внедрения:

```routeros
# 1. Проверить firewall правила
/ip firewall filter print where chain=input and src-address~"10.11.0"

# 2. Проверить, что контейнеры могут резолвить DNS
/container shell nginx
# Внутри контейнера:
nslookup google.com

# 3. Проверить, что контейнеры НЕ могут подключиться к управлению
/container shell nginx
# Внутри контейнера (должно быть заблокировано):
telnet 10.11.0.1 22     # Должен timeout
telnet 10.11.0.1 8291   # Должен timeout

# 4. Проверить rate limiting
# С внешнего хоста сделать много запросов:
ab -n 1000 -c 100 http://YOUR_PUBLIC_IP/
# Должны появиться дропы в статистике
/ip firewall filter print stats where comment~"Nginx"
```

---

### ✅ CRIT-04: Закрытие открытого DNS Resolver [SOLVED ✓]

**Приоритет:** P0 (критический)
**Время на внедрение:** 5 минут
**Риск внедрения:** Низкий

**✅ Готовое решение:** Используйте `firewall_complete.rsc`
- Включает блокировку DNS от внешних источников
- Разрешает DNS только для локальных сетей (address-list)

#### Вариант 1: Полностью отключить remote requests (рекомендуется)

**Изменить в `12-dns-doh.rsc`:**

```routeros
# БЫЛО:
:local ALLOW_REMOTE_DNS yes;

/ip dns set allow-remote-requests=$ALLOW_REMOTE_DNS \
    use-doh-server=$DOH_URL verify-doh-cert=yes max-udp-packet-size=4096

# СТАЛО:
:local ALLOW_REMOTE_DNS no;

/ip dns set allow-remote-requests=$ALLOW_REMOTE_DNS \
    use-doh-server=$DOH_URL verify-doh-cert=yes max-udp-packet-size=4096

:log info "DNS remote requests disabled - no longer open resolver"
```

#### Вариант 2: Разрешить только для локальных сетей (через firewall)

Если вам нужен DNS для guest сети или других VLAN:

```routeros
# Оставить allow-remote-requests=yes, но добавить в firewall:

# Создать address-list с локальными сетями
/ip firewall address-list
add list=local-nets address=192.168.1.0/24 comment="LAN"
add list=local-nets address=172.16.99.0/24 comment="Management"
add list=local-nets address=10.30.0.0/24 comment="Guest WiFi"
add list=local-nets address=10.11.0.0/24 comment="Containers"

# Блокировать DNS запросы НЕ из локальных сетей
/ip firewall filter
add chain=input protocol=udp dst-port=53 \
    src-address-list=!local-nets \
    action=drop \
    comment="Block DNS from external sources"

add chain=input protocol=tcp dst-port=53 \
    src-address-list=!local-nets \
    action=drop \
    comment="Block DNS TCP from external sources"
```

#### Проверка:

```bash
# С внешнего хоста (должно НЕ отвечать):
dig @YOUR_PUBLIC_IP example.com

# С локального хоста (должно отвечать):
dig @192.168.1.1 example.com
```

---

### ✅ CRIT-05: Исправление ACL управления

**Приоритет:** P0 (критический)
**Время на внедрение:** 5 минут
**Риск внедрения:** Низкий

#### Изменить в `01-base.rsc`:

```routeros
# БЫЛО:
/ip service
set ssh address=192.168.1.0/24
set winbox address=192.168.1.0/24

# СТАЛО (включить Management VLAN):
/ip service
set ssh address=192.168.1.0/24,172.16.99.0/24 \
    comment="SSH from LAN and Management VLAN"
set winbox address=192.168.1.0/24,172.16.99.0/24 \
    comment="Winbox from LAN and Management VLAN"

# Ещё лучше - ТОЛЬКО Management VLAN (best practice):
# set ssh address=172.16.99.0/24
# set winbox address=172.16.99.0/24

# Если используете WebFig HTTPS:
set www-ssl disabled=no address=172.16.99.0/24 \
    certificate=router-cert \
    comment="WebFig HTTPS only from Management VLAN"
```

#### Проверка:

```routeros
/ip service print
# Должно показать правильные адреса
```

```bash
# С хоста в Management VLAN (должно работать):
ssh admin@172.16.99.1

# С хоста в Guest VLAN (должно быть заблокировано):
ssh admin@10.30.0.1  # connection refused
```

---

## Важные исправления (P1)

### ✅ CRIT-01: Безопасное хранение Credentials

**Приоритет:** P1 (высокий)
**Время на внедрение:** 2-3 часа
**Риск внедрения:** Высокий (требует тестирования)

#### Проблема:

RouterOS **не имеет** встроенного безопасного хранилища секретов. Любой credential, доступный скрипту, может быть извлечён администратором.

#### Рекомендуемый подход (многоуровневый):

**Уровень 1: Вынести credentials в отдельные файлы**

Создайте файлы на роутере (через SFTP, не через команды):

```bash
# На локальной машине создать файлы:
echo "your_pppoe_user" > ppp-user.txt
echo "your_pppoe_password" > ppp-pass.txt
echo "StrongWiFiPassword123!" > wifi-pass.txt
echo "VeryStrongGuestPass456!" > wifi-guest-pass.txt

# Загрузить на роутер через SFTP (не оставит в истории):
sftp admin@192.168.1.1
put ppp-user.txt /
put ppp-pass.txt /
put wifi-pass.txt /
put wifi-guest-pass.txt /
quit

# Удалить локальные копии:
shred -u ppp-user.txt ppp-pass.txt wifi-pass.txt wifi-guest-pass.txt
```

**Изменить скрипты для чтения из файлов:**

```routeros
# 02-wan-pppoe-ipv4.rsc
# БЫЛО:
# :local PPP_USER "<PPPOE_USER>";
# :local PPP_PASS "<PPPOE_PASS>";

# СТАЛО:
:local PPP_USER [/file get "ppp-user.txt" contents]
:local PPP_PASS [/file get "ppp-pass.txt" contents]
# Убрать trailing newline если есть:
:set PPP_USER [:pick $PPP_USER 0 ([:len $PPP_USER]-1)]
:set PPP_PASS [:pick $PPP_PASS 0 ([:len $PPP_PASS]-1)]

/interface pppoe-client
add name=$WAN_PPP interface=$WAN_IF \
    user=$PPP_USER password=$PPP_PASS \
    add-default-route=yes disabled=no
```

```routeros
# 06-wifi-capsman-core.rsc
# БУЛО:
# :local PASS "SuperSecretWiFi";

# СТАЛО:
:local PASS [/file get "wifi-pass.txt" contents]
:set PASS [:pick $PASS 0 ([:len $PASS]-1)]

# Или ещё лучше - генерировать случайный пароль:
:if ([:len [/file find name="wifi-pass.txt"]] = 0) do={
    :local randPass [/certificate scep-server otp generate minutes-valid=0 as-value]->"password"
    /file print file="wifi-pass.txt" where name="none"
    /file set wifi-pass.txt contents=$randPass
    :log warning "Generated new WiFi password: $randPass - SAVE IT!"
    :set PASS $randPass
} else={
    :set PASS [/file get "wifi-pass.txt" contents]
    :set PASS [:pick $PASS 0 ([:len $PASS]-1)]
}
```

**Уровень 2: Encrypted Backups**

```routeros
# Создать скрипт для encrypted backup
/system script add name=secure-backup policy=read,write,ftp,sensitive source={
    :local backupName ("backup-" . [/system clock get date] . "-" . [/system clock get time])
    :local backupPass "VeryStrongBackupPassword123!ChangeMe"

    # Создать encrypted backup
    /system backup save name=$backupName \
        encryption=aes-sha256 \
        password=$backupPass

    # Экспортировать конфигурацию (НО credentials в файлах, не в export)
    /export file=$backupName

    :log info "Encrypted backup created: $backupName"

    # Отправить на удалённый сервер (опционально)
    # /tool fetch url="sftp://backup-server/$backupName.backup" \
    #     src-path="$backupName.backup" \
    #     user=backup password=backup-pass upload=yes
}

# Scheduler для автоматических backup
/system scheduler add name=daily-backup \
    interval=1d start-time=03:00:00 \
    on-event=secure-backup
```

**Уровень 3: SSH Keys вместо паролей (для управления)**

```routeros
# 1. На локальной машине сгенерировать ключ:
ssh-keygen -t ed25519 -f ~/.ssh/mikrotik-admin

# 2. Загрузить публичный ключ на роутер:
scp ~/.ssh/mikrotik-admin.pub admin@192.168.1.1:/

# 3. На роутере импортировать:
/user ssh-keys import user=admin public-key-file=mikrotik-admin.pub

# 4. Отключить password auth для SSH (опционально):
# /ip service set ssh disabled=yes
# Создать отдельный SSH сервис только с keys
```

**Уровень 4: Использование Environment Variables (для автоматизации)**

```routeros
# Для automation container (будет в AUTOMATION_ARCHITECTURE.md)
# Credentials хранятся ВНЕ роутера, в Vault контейнере
```

#### Что НЕ делать:

❌ Не хранить credentials в:
- `/system script` source
- `/system scheduler` on-event (inline)
- Комментариях
- Названиях объектов

❌ Не использовать:
- Простые пароли
- Повторяющиеся пароли
- Credentials в Winbox "Save Password"

---

### ✅ MED-05: SSH Hardening [SOLVED ✓]

**Приоритет:** P1
**Время:** 2 минуты

**✅ Готовое решение:** Включено в `firewall_complete.rsc` (строка 421)

```routeros
# Добавить в 01-base.rsc:
/ip ssh set strong-crypto=yes \
    host-key-size=4096

:log info "SSH hardening applied: strong-crypto enabled"
```

---

### ✅ MED-06: SYN Flood Protection [SOLVED ✓]

**Приоритет:** P1
**Время:** 2 минуты

**✅ Готовое решение:** Включено в `firewall_complete.rsc` (строка 418)

```routeros
# Добавить в 01-base.rsc:
/ip settings set tcp-syncookies=yes

:log info "TCP SYN cookies enabled for flood protection"
```

---

### ✅ SSH Brute-Force Protection [SOLVED ✓]

**Приоритет:** P1
**Время:** 10 минут

**✅ Готовое решение:** Используйте `firewall_complete.rsc`
- Файл: `/firewall_complete.rsc` (строки 240-283)
- Включает: Progressive blocking (4 стадии), blacklist на 1 неделю
- Защита SSH (22), Telnet (23) с автоматическим blocking

#### Или создайте отдельный файл: `15-brute-force-protection.rsc`

```routeros
# ===================================================================
# 15-brute-force-protection.rsc
# Brute-Force Protection for SSH, Winbox, WebFig
# Based on progressive blocking algorithm
# ===================================================================

# Создать address-lists для tracking
/ip firewall address-list
# Эти списки будут заполняться динамически

# ===================================================================
# SSH Protection (port 22)
# ===================================================================

/ip firewall filter

# Whitelist: администраторы, которым можно всегда
# add chain=input src-address-list=ssh-whitelist protocol=tcp dst-port=22 \
#     action=accept comment="SSH: whitelist"

# Stage 4: Permanent blacklist (1 день)
add chain=input protocol=tcp dst-port=22 \
    src-address-list=ssh_blacklist \
    action=drop \
    comment="SSH: blacklist (1 day)"

# Stage 3: 3 попытки за минуту -> blacklist
add chain=input protocol=tcp dst-port=22 \
    connection-state=new \
    src-address-list=ssh_stage3 \
    action=add-src-to-address-list \
    address-list=ssh_blacklist \
    address-list-timeout=1d \
    comment="SSH: stage3 -> blacklist"

# Stage 2: 2 попытки за минуту -> stage3
add chain=input protocol=tcp dst-port=22 \
    connection-state=new \
    src-address-list=ssh_stage2 \
    action=add-src-to-address-list \
    address-list=ssh_stage3 \
    address-list-timeout=1m \
    comment="SSH: stage2 -> stage3"

# Stage 1: 1 попытка -> stage2
add chain=input protocol=tcp dst-port=22 \
    connection-state=new \
    src-address-list=ssh_stage1 \
    action=add-src-to-address-list \
    address-list=ssh_stage2 \
    address-list-timeout=1m \
    comment="SSH: stage1 -> stage2"

# Stage 0: Первая попытка -> stage1
add chain=input protocol=tcp dst-port=22 \
    connection-state=new \
    action=add-src-to-address-list \
    address-list=ssh_stage1 \
    address-list-timeout=1m \
    comment="SSH: track new connections"

# ===================================================================
# Winbox Protection (port 8291)
# ===================================================================

add chain=input protocol=tcp dst-port=8291 \
    src-address-list=winbox_blacklist \
    action=drop \
    comment="Winbox: blacklist"

add chain=input protocol=tcp dst-port=8291 \
    connection-state=new \
    src-address-list=winbox_stage3 \
    action=add-src-to-address-list \
    address-list=winbox_blacklist \
    address-list-timeout=1d \
    comment="Winbox: stage3 -> blacklist"

add chain=input protocol=tcp dst-port=8291 \
    connection-state=new \
    src-address-list=winbox_stage2 \
    action=add-src-to-address-list \
    address-list=winbox_stage3 \
    address-list-timeout=1m \
    comment="Winbox: stage2 -> stage3"

add chain=input protocol=tcp dst-port=8291 \
    connection-state=new \
    src-address-list=winbox_stage1 \
    action=add-src-to-address-list \
    address-list=winbox_stage2 \
    address-list-timeout=1m \
    comment="Winbox: stage1 -> stage2"

add chain=input protocol=tcp dst-port=8291 \
    connection-state=new \
    action=add-src-to-address-list \
    address-list=winbox_stage1 \
    address-list-timeout=1m \
    comment="Winbox: track new connections"

# ===================================================================
# API Protection (port 8728, 8729)
# ===================================================================

add chain=input protocol=tcp dst-port=8728,8729 \
    src-address-list=api_blacklist \
    action=drop \
    comment="API: blacklist"

add chain=input protocol=tcp dst-port=8728,8729 \
    connection-state=new \
    src-address-list=api_stage3 \
    action=add-src-to-address-list \
    address-list=api_blacklist \
    address-list-timeout=1d \
    comment="API: stage3 -> blacklist"

add chain=input protocol=tcp dst-port=8728,8729 \
    connection-state=new \
    src-address-list=api_stage2 \
    action=add-src-to-address-list \
    address-list=api_stage3 \
    address-list-timeout=1m

add chain=input protocol=tcp dst-port=8728,8729 \
    connection-state=new \
    src-address-list=api_stage1 \
    action=add-src-to-address-list \
    address-list=api_stage2 \
    address-list-timeout=1m

add chain=input protocol=tcp dst-port=8728,8729 \
    connection-state=new \
    action=add-src-to-address-list \
    address-list=api_stage1 \
    address-list-timeout=1m

:log info "Brute-force protection configured for SSH, Winbox, API"

# ===================================================================
# Monitoring Script
# ===================================================================

/system script add name=bf-monitor policy=read,test source={
    :local sshCount [/ip firewall address-list print count-only where list="ssh_blacklist"]
    :local apiCount [/ip firewall address-list print count-only where list="api_blacklist"]

    :if ($sshCount > 0) do={
        :log warning "SSH blacklist has $sshCount IPs"
    }

    :if ($apiCount > 0) do={
        :log warning "API blacklist has $apiCount IPs"
    }
}

/system scheduler add name=bf-monitor-job interval=1h on-event=bf-monitor
```

#### Применение:

```routeros
/import 15-brute-force-protection.rsc

# Проверить:
/ip firewall filter print where comment~"SSH:"
```

#### Тестирование:

```bash
# Попытаться подключиться 4 раза с неправильным паролем:
for i in {1..4}; do ssh test@192.168.1.1; done

# После 4-й попытки - должен быть заблокирован
```

#### Мониторинг:

```routeros
# Посмотреть заблокированные IP:
/ip firewall address-list print where list~"blacklist"

# Вручную разблокировать IP (если нужно):
/ip firewall address-list remove [find address=1.2.3.4]

# Посмотреть статистику:
/ip firewall filter print stats where comment~"blacklist"
```

---

## Средние исправления (P2)

### ✅ MED-01: WiFi Security Upgrade [SOLVED ✓]

**Приоритет:** P2
**Время:** 15 минут

**✅ Готовое решение:** Используйте модуль `wifi/`
- Файлы: `wifi/01-wifi-capsman.rsc` (dual-stack CAPsMAN)
- Включает: WPA2+WPA3, 802.11w, client isolation, roaming (802.11r)
- WDS Bridge: `wifi/04-r2-wds-ap-bridge.rsc` + `wifi/05-rb2011-wds-station-bridge.rsc`

#### Или обновите вручную до WPA3 + 802.11w

```routeros
# Изменить в 06-wifi-capsman-core.rsc:

# WifiWave2 (новые устройства):
/wifi security
remove [find name=sec-w2]
add name=sec-w2 \
    authentication-types=wpa3-psk \
    wpa2-pre-shared-key=[/file get "wifi-pass.txt" contents] \
    group-encryption=aes-ccm \
    management-protection=required \
    ft=yes \
    ft-preserve-vlanid=yes \
    comment="WPA3-only with 802.11w required"

# Legacy CAPsMAN (старые устройства):
/caps-man security
remove [find name=sec-l]
add name=sec-l \
    authentication-types=wpa2-psk,wpa3-psk \
    passphrase=[/file get "wifi-pass.txt" contents] \
    group-encryption=aes-ccm \
    encryption=aes-ccm \
    comment="WPA2/WPA3 transition mode"
```

#### Client Isolation для Guest WiFi

```routeros
# В 07-wifi-guest.rsc добавить:

# WifiWave2:
/wifi configuration
set [find name=cfg-w2-guest] \
    datapath.client-to-client-forwarding=no

# Legacy:
/caps-man configuration
set [find name=cfg-l-guest] \
    datapath.client-to-client-forwarding=no
```

---

### ✅ MED-02: BGP Security

**Приоритет:** P2
**Время:** 10 минут

```routeros
# В 09-bgp-proxy.rsc добавить:

# Generate strong BGP password
:local bgpPass [/certificate scep-server otp generate minutes-valid=0 as-value]->"password"

/routing bgp connection
set [find name=$BGP_CONN_NAME] \
    tcp-md5-key=$bgpPass \
    ttl=255 \
    multihop=no \
    input.limit-prefixes=100 \
    input.limit-prefixes-action=restart \
    output.keep-sent-attributes=no

:log warning "BGP MD5 password: $bgpPass - SAVE IT and configure on peer!"

# TTL Security (RFC 5082):
# Защита от BGP hijacking с удалённых хостов
```

---

### ✅ MED-03: Упорядочивание Firewall правил

**Приоритет:** P2
**Время:** 10 минут

```routeros
# В 07-wifi-guest.rsc изменить:

# Удалить старые правила:
/ip firewall filter
remove [find comment="Guest -> LAN block"]
remove [find comment="Guest -> containers block"]
remove [find comment="Guest -> mgmt block"]
remove [find comment="Guest -> router block"]

# Добавить заново с правильным порядком:
add chain=forward src-address=10.30.0.0/24 dst-address=192.168.1.0/24 \
    action=drop \
    place-before=[find chain=forward and action=accept and connection-state~"established"] \
    comment="Guest -> LAN block"

add chain=forward src-address=10.30.0.0/24 dst-address=10.11.0.0/16 \
    action=drop \
    place-before=[find comment="Guest -> LAN block"] \
    comment="Guest -> containers block"

add chain=forward src-address=10.30.0.0/24 dst-address=172.16.99.0/24 \
    action=drop \
    place-before=[find comment="Guest -> LAN block"] \
    comment="Guest -> mgmt block"

add chain=input src-address=10.30.0.0/24 dst-port=22,8291,80,443,8728,8729 \
    protocol=tcp action=drop \
    place-before=[find chain=input and comment="allow LAN to router"] \
    comment="Guest -> router block"
```

---

## Дополнительные улучшения

### ✅ Fasttrack для производительности

```routeros
# Создать файл: 16-performance-optimizations.rsc

/ip firewall filter

# Fasttrack для established соединений (огромный прирост производительности)
add chain=forward action=fasttrack-connection \
    connection-state=established,related \
    hw-offload=yes \
    place-before=0 \
    comment="Fasttrack established (huge performance gain)"

# После fasttrack - обычный accept
add chain=forward connection-state=established,related \
    action=accept place-before=1 \
    comment="Accept established/related"

:log info "Fasttrack enabled - expect 5-10x throughput increase"
```

**Внимание:** Fasttrack пропускает некоторые firewall правила для скорости. Не используйте если нужен deep packet inspection.

---

### ✅ Централизованное логирование

```routeros
# Создать файл: 17-centralized-logging.rsc

# Настроить remote syslog server (например, в automation container)
/system logging action
add name=remote-syslog target=remote \
    remote=10.11.0.20 \
    remote-port=514 \
    src-address=10.11.0.1

# Отправлять важные события на remote server
/system logging
add topics=error,critical,warning action=remote-syslog
add topics=firewall,info prefix="FW: " action=remote-syslog
add topics=account prefix="AUTH: " action=remote-syslog
add topics=script prefix="SCRIPT: " action=remote-syslog

:log info "Centralized logging configured to 10.11.0.20:514"
```

---

### ✅ Health Monitoring

```routeros
# Создать файл: 18-health-monitoring.rsc

/system script add name=health-check policy=read,test source={
    :local alerts ""

    # Check CPU load
    :local cpuLoad [/system resource get cpu-load]
    :if ($cpuLoad > 80) do={
        :set alerts ($alerts . "CPU=$cpuLoad%; ")
    }

    # Check memory
    :local freeMem [/system resource get free-memory]
    :if ($freeMem < 20000000) do={
        :set alerts ($alerts . "LowMem; ")
    }

    # Check WAN connectivity
    :if ([/ping 1.1.1.1 count=3] = 0) do={
        :set alerts ($alerts . "WAN-DOWN; ")
    }

    # Check disk space (if using containers)
    :local diskFree [/disk get 0 free]
    :if ($diskFree < 1000000000) do={
        :set alerts ($alerts . "Disk<1GB; ")
    }

    # Check container health
    :if ([:len [/container find status!="running"]] > 0) do={
        :set alerts ($alerts . "Container-DOWN; ")
    }

    # Send alerts
    :if ([:len $alerts] > 0) do={
        :log error "HEALTH-CHECK: $alerts"
        # TODO: Send to Telegram/Slack/Email
    } else={
        :log info "Health check: All systems OK"
    }
}

/system scheduler add name=health-monitor \
    interval=5m on-event=health-check \
    start-time=startup
```

---

## Best Practices MikroTik RouterOS 7.x

### Чек-лист безопасности

#### Management Access
- [ ] SSH: `strong-crypto=yes`
- [ ] Telnet: `disabled=yes`
- [ ] FTP: `disabled=yes`
- [ ] WWW: `disabled=yes`
- [ ] API: Ограничен по IP или отключён
- [ ] Winbox: Ограничен по IP + VPN
- [ ] Services: Доступны только из Management VLAN
- [ ] SSH keys вместо паролей
- [ ] Brute-force protection активна

#### Firewall
- [ ] IPv4 firewall: Default DROP policy
- [ ] IPv6 firewall: Default DROP policy
- [ ] Connection tracking: established/related accept
- [ ] Invalid packets: DROP
- [ ] Rate limiting для ICMP
- [ ] SYN flood protection: `tcp-syncookies=yes`
- [ ] Port scan detection
- [ ] Fasttrack для производительности

#### Network Segmentation
- [ ] Management VLAN отделён от пользователей
- [ ] Guest WiFi изолирован от LAN
- [ ] Контейнеры изолированы (whitelist доступ)
- [ ] VLAN filtering включён на bridge
- [ ] Firewall между VLANs

#### Credentials & Secrets
- [ ] Нет hardcoded credentials в конфигах
- [ ] Credentials в отдельных файлах
- [ ] Encrypted backups (AES-256)
- [ ] Уникальные пароли на каждом роутере
- [ ] Регулярная ротация паролей
- [ ] Backup паролей в password manager

#### WiFi Security
- [ ] WPA3-PSK (или минимум WPA2-PSK)
- [ ] 802.11w (Management Frame Protection)
- [ ] Strong passphrase (> 20 символов)
- [ ] Client isolation для guest
- [ ] Hidden SSID (опционально)
- [ ] MAC filtering (опционально)

#### Container Security
- [ ] Pinned image versions (не :latest)
- [ ] Memory limits установлены
- [ ] Whitelist сетевого доступа
- [ ] Не имеют доступа к management портам
- [ ] Логи отправляются на syslog
- [ ] Регулярные обновления образов

#### Monitoring & Logging
- [ ] Централизованное логирование
- [ ] Health check скрипты
- [ ] Alerts при критических событиях
- [ ] Firewall статистика мониторится
- [ ] Регулярный review логов

#### Backup & Recovery
- [ ] Ежедневные автоматические backups
- [ ] Encrypted backups
- [ ] Offsite backup storage
- [ ] Протестирован restore процесс
- [ ] Documented recovery процедура

#### Updates & Patches
- [ ] RouterOS обновлён до latest stable
- [ ] Packages обновлены
- [ ] Firmware обновлён
- [ ] Security advisory мониторится
- [ ] Change management процесс

#### Documentation
- [ ] Сетевая диаграмма актуальна
- [ ] IP addressing план
- [ ] VLAN таблица
- [ ] Firewall политики документированы
- [ ] Credentials в password manager
- [ ] Runbooks для типичных задач

---

## Порядок внедрения рекомендаций

### Неделя 1: Критические исправления (P0)

**День 1:**
- ✅ Backup текущей конфигурации
- ✅ Создать IPv6 firewall (`03a-ipv6-firewall.rsc`)
- ✅ Закрыть DNS resolver
- ✅ Исправить ACL управления

**День 2:**
- ✅ Изолировать контейнеры от роутера
- ✅ Добавить rate limiting для портов 80/443
- ✅ Установить resource limits для контейнеров

**День 3:**
- ✅ Тестирование критических изменений
- ✅ Мониторинг логов
- ✅ Rollback план если проблемы

### Неделя 2: Важные исправления (P1)

**День 1:**
- ✅ Вынести credentials в файлы
- ✅ Настроить encrypted backups
- ✅ SSH hardening + SYN flood protection

**День 2:**
- ✅ Brute-force protection (`15-brute-force-protection.rsc`)
- ✅ Pinned versions для контейнеров

**День 3:**
- ✅ Тестирование и мониторинг

### Неделя 3: Средние исправления (P2)

- ✅ WiFi upgrade (WPA3 + 802.11w)
- ✅ BGP security
- ✅ Упорядочивание firewall правил
- ✅ Fasttrack оптимизация

### Неделя 4: Дополнительные улучшения

- ✅ Централизованное логирование
- ✅ Health monitoring
- ✅ Automation container (см. AUTOMATION_ARCHITECTURE.md)
- ✅ Documentation update

---

## 📝 Changelog

### Version 1.2 (12 декабря 2025)
- ✅ Отмечены решённые критические проблемы P0: CRIT-02, CRIT-03, CRIT-04
- ✅ Отмечены решённые важные проблемы P1: MED-05, MED-06, SSH Brute-Force
- ✅ Отмечены решённые средние проблемы P2: MED-01 (WiFi Security)
- ✅ Добавлены ссылки на готовые модули: `firewall_complete.rsc`, `nginx-certbot/`, `wifi/`
- ✅ Обновлён раздел WiFi Security с учётом WDS Bridge модуля
- ✅ **Итого решено: 7 проблем** (3 P0 + 3 P1 + 1 P2)

### Version 1.1 (10 декабря 2025)
- ✅ Добавлены рекомендации по nginx-certbot модулю
- ✅ Все примеры переведены на :local переменные

### Version 1.0 (10 декабря 2025)
- ✅ Первая версия с детальными рекомендациями по устранению 23 проблем
- ✅ Пошаговые инструкции для P0, P1, P2 приоритетов
- ✅ Best Practices чек-лист
- ✅ План внедрения (4 недели)

---

**Следующий документ:** AUTOMATION_ARCHITECTURE.md
*Архитектура автоматизации с контейнером на роутере*
