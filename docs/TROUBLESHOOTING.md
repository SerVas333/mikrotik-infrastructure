# Руководство по устранению проблем - MikroTik Infrastructure v1.3

**Версия:** 1.3
**Дата:** 15 декабря 2025

---

## 📋 Содержание

1. [Общие рекомендации](#общие-рекомендации)
2. [Проблемы импорта конфигурации](#проблемы-импорта-конфигурации)
3. [Проблемы с сетевым подключением](#проблемы-с-сетевым-подключением)
4. [Проблемы с Firewall](#проблемы-с-firewall)
5. [Проблемы с DHCP](#проблемы-с-dhcp)
6. [Проблемы с DNS](#проблемы-с-dns)
7. [Проблемы с WiFi](#проблемы-с-wifi)
8. [Проблемы с VPN](#проблемы-с-vpn)
9. [Проблемы с контейнерами](#проблемы-с-контейнерами)
10. [Проблемы производительности](#проблемы-производительности)
11. [Диагностические команды](#диагностические-команды)

---

## Общие рекомендации

### Прежде чем начать

1. **Создайте резервную копию**
   ```routeros
   /system backup save name=troubleshoot-backup
   /export file=troubleshoot-export
   ```

2. **Проверьте логи**
   ```routeros
   /log print where topics~"error|critical|warning"
   ```

3. **Используйте Safe Mode**
   - Нажмите `Ctrl+X` в терминале
   - Все изменения откатятся при потере соединения
   - Индикатор: `[Safe Mode taken]`

4. **Читайте сообщения об ошибках**
   - RouterOS показывает точную строку и позицию ошибки
   - Ищите: `syntax error (line X column Y)`

---

## Проблемы импорта конфигурации

### Ошибка: "syntax error"

**Симптомы:**
```
failure: syntax error (line 5 column 10)
```

**Возможные причины и решения:**

#### Причина 1: Не импортирован 00-config.rsc

**Ошибка:**
```routeros
/import 01-base.rsc
# failure: bad command name cfgHostname (line 15)
```

**Решение:**
```routeros
# СНАЧАЛА импортируйте конфигурацию
/import 00-config.rsc
/import 00-secrets.rsc

# ПОТОМ импортируйте модули
/import 01-base.rsc
```

---

#### Причина 2: Не импортирован 00-secrets.rsc

**Ошибка:**
```routeros
/import 01-base.rsc
# failure: bad command name secAdminPassword (line 20)
```

**Решение:**
```routeros
# Убедитесь что 00-secrets.rsc существует
/file print where name="00-secrets.rsc"

# Если нет - создайте из template
# scp 00-secrets.rsc admin@192.168.88.1:/

# Импортируйте
/import 00-secrets.rsc
```

---

#### Причина 3: Неправильный синтаксис в файле

**Ошибка:**
```routeros
# Забыли закрыть кавычки
:global cfgHostname "R1-Core
                           ^
                  syntax error
```

**Решение:**
```routeros
# Проверьте синтаксис:
# - Все строки в кавычках закрыты
# - Скобки сбалансированы
# - Нет спецсимволов без экранирования

:global cfgHostname "R1-Core"  # ✅ Правильно
```

---

### Ошибка: "file not found"

**Симптомы:**
```routeros
/import 01-base.rsc
# failure: file not found (01-base.rsc)
```

**Решение:**

1. **Проверьте наличие файла:**
   ```routeros
   /file print
   # Убедитесь что 01-base.rsc присутствует
   ```

2. **Если файла нет - загрузите:**
   ```bash
   scp 01-base.rsc admin@192.168.88.1:/
   ```

3. **Проверьте имя файла:**
   ```routeros
   # Регистр имеет значение!
   /import 01-base.rsc  # ✅ Правильно
   /import 01-Base.rsc  # ❌ Неправильно (если файл 01-base.rsc)
   ```

---

### Ошибка: "already have interface with such name"

**Симптомы:**
```routeros
/import 02-network.rsc
# failure: already have interface with such name (bridge-lan)
```

**Причина:** Попытка создать интерфейс который уже существует

**Решение:**

1. **Проверьте существующие интерфейсы:**
   ```routeros
   /interface print where name="bridge-lan"
   ```

2. **Удалите старый (если нужно):**
   ```routeros
   # ОСТОРОЖНО: это удалит интерфейс и его конфигурацию
   /interface bridge remove [find name="bridge-lan"]
   ```

3. **Или пропустите создание:**
   - Отредактируйте модуль перед импортом
   - Закомментируйте создание интерфейса

---

## Проблемы с сетевым подключением

### Проблема: Нет интернета на клиентах

**Диагностика:**

```bash
# С клиента
ping 192.168.1.1        # Ping роутера
ping 1.1.1.1            # Ping публичного DNS
ping google.com         # DNS резолвинг
```

#### Сценарий 1: Не пингается роутер (192.168.1.1)

**Причина:** Проблема на L2 (канальном уровне)

**Решение:**

1. **Проверьте физическое подключение:**
   - Кабель подключён к LAN порту (не WAN!)
   - Индикатор линка горит на обоих концах
   - Проверьте кабель (замените если есть подозрения)

2. **Проверьте получение IP адреса:**
   ```bash
   # Windows
   ipconfig /all

   # Linux/Mac
   ip addr show
   ```

   **Если IP 169.254.x.x (APIPA):**
   - DHCP не работает (см. раздел [Проблемы с DHCP](#проблемы-с-dhcp))

3. **Проверьте VLAN (если используется):**
   ```routeros
   /interface vlan print
   /interface bridge port print where interface~"ether"
   ```

---

#### Сценарий 2: Роутер пингается, но не пингается 1.1.1.1

**Причина:** Проблема с WAN подключением или маршрутизацией

**Решение:**

1. **Проверьте WAN интерфейс:**
   ```routeros
   # Для PPPoE
   /interface pppoe-client print
   # Статус должен быть "connected"

   # Для статического IP
   /ip address print where interface=$cfgWanInterface
   # Должен быть публичный IP
   ```

2. **Проверьте маршрут по умолчанию:**
   ```routeros
   /ip route print where dst-address=0.0.0.0/0
   # Должен быть route через WAN gateway
   # Active должно быть "yes"
   ```

3. **Проверьте NAT:**
   ```routeros
   /ip firewall nat print where chain=srcnat
   # Должно быть правило masquerade для WAN
   ```

4. **Тест с роутера:**
   ```routeros
   # Ping с роутера
   /ping 1.1.1.1 count=10
   # Если работает - проблема в firewall
   # Если не работает - проблема с WAN
   ```

---

#### Сценарий 3: Ping 1.1.1.1 работает, но не работает google.com

**Причина:** Проблема с DNS

**Решение:** См. раздел [Проблемы с DNS](#проблемы-с-dns)

---

### Проблема: Потерян доступ к роутеру после изменений

**Сценарий 1: Изменили IP адрес роутера**

**Решение:**

1. **Узнайте новый IP через DHCP:**
   ```bash
   # Windows
   ipconfig /all
   # Gateway = новый IP роутера

   # Linux/Mac
   ip route show default
   ```

2. **Подключитесь к новому IP:**
   ```bash
   ssh admin@<новый-IP>
   ```

---

**Сценарий 2: Firewall заблокировал доступ**

**Решение:**

1. **Если есть физический доступ:**
   - Подключитесь через Serial Console
   - Или используйте WinBox в режиме MAC-connect

2. **Временно отключите firewall:**
   ```routeros
   /ip firewall filter disable [find]
   ```

3. **Или разрешите ваш IP:**
   ```routeros
   /ip service set ssh address=0.0.0.0/0
   /ip service set winbox address=0.0.0.0/0
   ```

4. **После восстановления доступа - верните настройки:**
   ```routeros
   /ip service set ssh address=$cfgMgmtAllowedNets
   /ip service set winbox address=$cfgMgmtAllowedNets
   /ip firewall filter enable [find]
   ```

---

**Сценарий 3: Safe Mode откатил изменения**

**Что произошло:** Вы потеряли соединение, Safe Mode откатил изменения

**Решение:**

1. **Переподключитесь:**
   ```bash
   ssh admin@192.168.88.1  # или старый IP
   ```

2. **Внесите изменения заново:**
   - Используйте Safe Mode снова (Ctrl+X)
   - Вносите изменения постепенно
   - Тестируйте после каждого шага
   - Подтвердите Safe Mode (Ctrl+X снова) если всё работает

---

## Проблемы с Firewall

### Проблема: Firewall блокирует весь трафик

**Симптомы:**
- Нет интернета на клиентах
- Не могу подключиться к роутеру

**Диагностика:**

```routeros
# Проверьте счётчики firewall
/ip firewall filter print stats

# Найдите правило с большим количеством drop
# Пример вывода:
#  0  chain=input action=drop ... packets=1234 bytes=567890
```

**Решение:**

1. **Временно отключите firewall:**
   ```routeros
   /ip firewall filter disable [find]
   ```

2. **Проверьте работу сети:**
   - Если заработало - проблема в firewall
   - Если не заработало - проблема в другом

3. **Включите firewall постепенно:**
   ```routeros
   # Включите только input chain
   /ip firewall filter enable [find chain=input]

   # Проверьте
   # Если работает - продолжайте

   # Включите forward chain
   /ip firewall filter enable [find chain=forward]
   ```

4. **Проверьте порядок правил:**
   ```routeros
   /ip firewall filter print
   # Убедитесь что:
   # - Accept established/related РАНЬШЕ drop
   # - Accept нужного трафика РАНЬШЕ drop all
   ```

---

### Проблема: Guest сеть имеет доступ к LAN

**Симптомы:**
```bash
# С клиента в guest сети (10.30.0.x)
ping 192.168.1.10  # ❌ Должно блокироваться, но работает
```

**Причина:** Firewall правила в неправильном порядке

**Решение:**

1. **Проверьте правила изоляции:**
   ```routeros
   /ip firewall filter print where comment~"Guest"

   # Должно быть:
   # action=drop src-address=10.30.0.0/24 dst-address=192.168.1.0/24
   ```

2. **Проверьте позицию правила:**
   ```routeros
   /ip firewall filter print
   # Правило drop guest→LAN должно быть РАНЬШЕ accept guest→internet
   ```

3. **Если порядок неправильный - исправьте:**
   ```routeros
   # Удалите и пересоздайте правила в правильном порядке
   # Или используйте place-before

   /ip firewall filter move [find comment="Guest isolation"] \
       destination=[find comment="Accept guest to internet"]
   ```

---

### Проблема: Не могу подключиться к роутеру по SSH/Winbox

**Симптомы:**
```bash
ssh admin@192.168.1.1
# Connection refused или Connection timeout
```

**Диагностика:**

```routeros
# Проверьте сервисы
/ip service print

# SSH должен быть:
# enabled: yes
# port: 22
# address: <ваша подсеть>
```

**Решение:**

#### Причина 1: Сервис отключён

```routeros
/ip service set ssh disabled=no
```

---

#### Причина 2: ACL блокирует ваш IP

```routeros
# Проверьте текущий ACL
/ip service print detail

# Если ваш IP не в списке - добавьте
/ip service set ssh address=192.168.1.0/24,172.16.99.0/24

# Или временно разрешите все (НЕБЕЗОПАСНО!)
/ip service set ssh address=0.0.0.0/0
```

---

#### Причина 3: Firewall блокирует

```routeros
# Проверьте input chain
/ip firewall filter print where chain=input

# Должно быть правило accept для SSH
# Если нет - добавьте:
/ip firewall filter add \
    chain=input \
    protocol=tcp \
    dst-port=22 \
    src-address=192.168.1.0/24 \
    action=accept \
    place-before=0 \
    comment="Allow SSH from LAN"
```

---

## Проблемы с DHCP

### Проблема: Клиенты не получают IP адрес

**Симптомы:**
- IP адрес 169.254.x.x (APIPA) на Windows
- Нет IP адреса на Linux/Mac

**Диагностика:**

```routeros
# Проверьте DHCP серверы
/ip dhcp-server print
# Убедитесь что сервер enabled и interface правильный

# Проверьте DHCP leases
/ip dhcp-server lease print
# Должны видеть lease для клиента (или попытки)

# Проверьте alerts
/ip dhcp-server alert print
# Покажет проблемы (например, pool исчерпан)
```

**Решение:**

#### Причина 1: DHCP сервер отключён

```routeros
/ip dhcp-server print
# disabled: yes

/ip dhcp-server enable [find name="dhcp-lan"]
```

---

#### Причина 2: Неправильный интерфейс

```routeros
/ip dhcp-server print detail
# Убедитесь что interface соответствует bridge-lan (или нужному VLAN)

# Если неправильный - исправьте
/ip dhcp-server set [find name="dhcp-lan"] interface=bridge-lan
```

---

#### Причина 3: IP pool исчерпан

```routeros
/ip dhcp-server alert print
# address pool exhausted

# Расширьте pool
/ip pool set [find name="pool-lan"] \
    ranges=192.168.1.50-192.168.1.250
```

---

#### Причина 4: Нет gateway в network

```routeros
/ip dhcp-server network print
# Должен быть gateway

# Если нет - добавьте
/ip dhcp-server network set [find] \
    gateway=192.168.1.1 \
    dns-server=192.168.1.1
```

---

### Проблема: DHCP даёт IP, но неправильный DNS

**Симптомы:**
```bash
ipconfig /all  # Windows
# DNS Server: 0.0.0.0 или неправильный IP
```

**Решение:**

```routeros
# Проверьте network настройки
/ip dhcp-server network print detail

# Установите DNS
/ip dhcp-server network set [find] \
    dns-server=192.168.1.1
```

---

## Проблемы с DNS

### Проблема: DNS не резолвит имена

**Симптомы:**
```bash
ping 1.1.1.1          # ✅ Работает
ping google.com       # ❌ Не работает (unknown host)
```

**Диагностика:**

```routeros
# Проверьте DNS настройки
/ip dns print
# servers: должны быть DNS серверы (1.1.1.1, 1.0.0.1)
# allow-remote-requests: должно быть yes (для локальных клиентов)

# Тест резолвинга с роутера
:resolve google.com
```

**Решение:**

#### Причина 1: DNS серверы не настроены

```routeros
/ip dns set servers=1.1.1.1,1.0.0.1
```

---

#### Причина 2: allow-remote-requests=no

```routeros
# Для локальных клиентов это нужно
/ip dns set allow-remote-requests=yes

# ⚠️ ВАЖНО: Firewall должен блокировать DNS извне!
/ip firewall filter add \
    chain=input \
    protocol=udp \
    dst-port=53 \
    src-address=!192.168.0.0/16 \
    action=drop \
    comment="Block external DNS"
```

---

#### Причина 3: Firewall блокирует DNS

```routeros
# Проверьте forward chain для UDP 53
/ip firewall filter print where protocol=udp and dst-port=53

# Должно быть правило accept для DNS
# Если нет - добавьте:
/ip firewall filter add \
    chain=forward \
    protocol=udp \
    dst-port=53 \
    action=accept \
    place-before=0 \
    comment="Allow DNS"
```

---

### Проблема: DoH не работает

**Симптомы:**
```routeros
/ip dns print
# use-doh-server: https://cloudflare-dns.com/dns-query
# doh-server-verified-count: 0
```

**Решение:**

1. **Проверьте время:**
   ```routeros
   /system clock print
   # DoH требует правильного времени для SSL сертификатов

   # Если время неправильное - синхронизируйте NTP
   /system ntp client set enabled=yes
   ```

2. **Проверьте связность с DoH сервером:**
   ```routeros
   /tool fetch url=https://cloudflare-dns.com/dns-query mode=https
   # Должно быть успешно
   ```

3. **Fallback на обычный DNS:**
   ```routeros
   # DoH серверы недоступны - используйте обычный DNS
   /ip dns set use-doh-server=""
   /ip dns set servers=1.1.1.1,1.0.0.1
   ```

---

## Проблемы с WiFi

### Проблема: WiFi сеть не видна

**Диагностика:**

```routeros
# Проверьте WiFi интерфейсы
/interface wireless print
# disabled: должно быть no

# Проверьте registration table
/interface wireless registration-table print
# Должны видеть подключенные клиенты
```

**Решение:**

#### Причина 1: Интерфейс отключён

```routeros
/interface wireless enable [find]
```

---

#### Причина 2: Неправильная страна

```routeros
/interface wireless print detail
# country: должна соответствовать вашей стране

/interface wireless set [find] country=ukraine
```

---

#### Причина 3: Неправильный канал

```routeros
# Проверьте доступные каналы
/interface wireless info hw-info [find name=wlan0]

# Смените канал если текущий недоступен
/interface wireless set wlan0 frequency=2462  # Channel 11
```

---

### Проблема: WiFi подключается, но нет интернета

**Диагностика:**

```bash
# С клиента WiFi
ip addr show    # Проверьте IP
ping 192.168.1.1    # Ping роутера
```

**Решение:**

#### Причина 1: WiFi в неправильном VLAN

```routeros
# Проверьте VLAN для WiFi
/interface wireless print detail
# vlan-mode: должно быть настроено если используется

# Проверьте bridge
/interface bridge port print where interface~"wlan"
# Должен быть в правильном bridge (bridge-lan) с нужным VLAN
```

---

#### Причина 2: Firewall блокирует WiFi клиентов

```routeros
# Проверьте firewall forward chain
/ip firewall filter print where chain=forward

# Добавьте правило если нужно
/ip firewall filter add \
    chain=forward \
    in-interface=wlan0 \
    action=accept \
    place-before=0
```

---

### Проблема: Слабый сигнал WiFi

**Диагностика:**

```routeros
/interface wireless monitor [find name=wlan0]
# Смотрите signal strength для клиентов

/interface wireless registration-table print
# signal-strength: должен быть > -70 dBm
```

**Решение:**

1. **Увеличьте TX power (осторожно!):**
   ```routeros
   /interface wireless set wlan0 tx-power=20
   # Не превышайте разрешённые значения для вашей страны!
   ```

2. **Смените канал (избегайте интерференции):**
   ```routeros
   /interface wireless frequency-monitor wlan0
   # Найдите канал с минимальной загрузкой

   /interface wireless set wlan0 frequency=<лучший-канал>
   ```

3. **Проверьте антенны:**
   - Антенны надёжно подключены?
   - Правильная ориентация антенн?

---

## Проблемы с VPN

### Проблема: SSTP VPN не подключается

**Диагностика:**

```routeros
# Проверьте SSTP сервер
/interface sstp-server server print
# enabled: yes

# Проверьте активные соединения
/interface sstp-server print
```

**Решение:**

#### Причина 1: Сервер отключён

```routeros
/interface sstp-server server set enabled=yes
```

---

#### Причина 2: Неправильный сертификат

```routeros
# Проверьте сертификат
/certificate print

# Сертификат должен быть valid и trusted

# Если нет - создайте новый
/certificate add name=router-cert common-name=router.local \
    key-size=2048 days-valid=3650

/certificate sign router-cert

/interface sstp-server server set certificate=router-cert
```

---

#### Причина 3: Firewall блокирует

```routeros
# SSTP использует TCP 443
/ip firewall filter add \
    chain=input \
    protocol=tcp \
    dst-port=443 \
    action=accept \
    comment="Allow SSTP VPN"
```

---

### Проблема: WireGuard не подключается

**Диагностика:**

```routeros
# Проверьте WireGuard интерфейс
/interface wireguard print

# Проверьте peers
/interface wireguard peers print
# Должны видеть peer с endpoint

# Проверьте handshake
/interface wireguard peers print detail
# last-handshake: должно быть недавним (<2 минут)
```

**Решение:**

#### Причина 1: Неправильные ключи

```bash
# Сгенерируйте новые ключи
wg genkey | tee privatekey | wg pubkey > publickey

# Обновите в 00-secrets.rsc
:global secWGPrivateKey "<новый-приватный-ключ>"
:global secWGPublicKey "<новый-публичный-ключ>"

# Импортируйте заново
/import 00-secrets.rsc
/import wireguard-s2s.rsc
```

---

#### Причина 2: Firewall блокирует UDP порт

```routeros
# WireGuard использует UDP (по умолчанию 13231)
/ip firewall filter add \
    chain=input \
    protocol=udp \
    dst-port=13231 \
    action=accept \
    comment="Allow WireGuard"
```

---

#### Причина 3: NAT проблемы

```routeros
# Если роутер за NAT - настройте port forwarding на вышестоящем роутере
# UDP 13231 → <ваш-роутер-IP>:13231
```

---

## Проблемы с контейнерами

### Проблема: Контейнер не запускается

**Диагностика:**

```routeros
/container print
# status: должно быть "running"

# Проверьте логи
/log print where topics~"container"
```

**Решение:**

#### Причина 1: Недостаточно RAM

```routeros
/system resource print
# free-memory: должно быть > 50MB для контейнера

# Если мало RAM - уменьшите другие процессы
# Или не используйте контейнеры на устройствах с малой RAM
```

---

#### Причина 2: Образ не загружен

```routeros
/container print
# Если нет root-dir - образ не загружен

# Загрузите образ заново
/container stop [find]
# ... выполните container-setup.rsc заново
```

---

#### Причина 3: Проблема с veth

```routeros
# Проверьте veth интерфейс
/interface veth print
# Должен быть veth-containers

# Проверьте bridge
/interface bridge port print where interface="veth-containers"
# Должен быть в bridge-containers
```

---

### Проблема: Контейнер не имеет доступа к интернету

**Диагностика:**

```routeros
# Проверьте IP адрес контейнера
/ip address print where interface=veth-containers
# Должен быть 10.11.0.1/24

# Проверьте NAT
/ip firewall nat print where out-interface=$cfgWanInterface
```

**Решение:**

#### Причина 1: Нет маршрута

```routeros
# Container сеть должна быть в NAT
/ip firewall nat add \
    chain=srcnat \
    src-address=10.11.0.0/24 \
    out-interface=$cfgWanInterface \
    action=masquerade
```

---

#### Причина 2: Firewall блокирует

```routeros
# Разрешите контейнерам доступ к интернету
/ip firewall filter add \
    chain=forward \
    src-address=10.11.0.0/24 \
    dst-address=!192.168.0.0/16 \
    action=accept \
    comment="Allow containers to internet"
```

---

## Проблемы производительности

### Проблема: Медленная скорость интернета

**Диагностика:**

```routeros
# Проверьте загрузку CPU
/system resource print
# cpu-load: не должно быть 100%

# Проверьте загрузку интерфейсов
/interface monitor-traffic ether1,bridge-lan
```

**Решение:**

#### Причина 1: Firewall перегружает CPU

```routeros
# Включите fasttrack
/ip firewall filter add \
    chain=forward \
    connection-state=established,related \
    action=fasttrack-connection \
    place-before=0 \
    comment="Fasttrack"

# Или через mangle
/ip firewall mangle add \
    chain=prerouting \
    connection-state=established,related \
    action=fasttrack-connection
```

---

#### Причина 2: Слишком много connection tracking

```routeros
# Проверьте количество tracked connections
/ip firewall connection print count-only

# Если > 10000 - уменьшите timeout
/ip firewall connection tracking set \
    tcp-established-timeout=1d \
    tcp-time-wait-timeout=10s \
    udp-timeout=30s
```

---

#### Причина 3: QoS/Queue ограничивает

```routeros
# Проверьте queues
/queue simple print

# Временно отключите
/queue simple disable [find]

# Проверьте скорость снова
```

---

### Проблема: Высокая загрузка CPU

**Диагностика:**

```routeros
/system resource print
# cpu-load: 100% постоянно - проблема

# Профилирование
/tool profile cpu=yes duration=10
# Покажет какие процессы нагружают CPU
```

**Решение:**

1. **Оптимизируйте firewall (используйте fasttrack)**
2. **Уменьшите логирование:**
   ```routeros
   /ip firewall filter set [find log=yes] log=no
   ```
3. **Отключите неиспользуемые функции:**
   ```routeros
   # Если не используете IPv6
   /ipv6 firewall filter disable [find]

   # Если не используете bandwidth monitoring
   /tool traffic-monitor stop [find]
   ```

---

## Диагностические команды

### Сеть

```routeros
# Ping
/ping 1.1.1.1 count=10

# Traceroute
/tool traceroute 1.1.1.1

# DNS resolve
:resolve google.com

# Bandwidth test (между двумя MikroTik)
/tool bandwidth-test <IP-другого-роутера>

# Packet sniffer
/tool sniffer quick interface=ether1 duration=10

# Torch (traffic monitor)
/tool torch interface=ether1
```

---

### Firewall

```routeros
# Показать статистику правил
/ip firewall filter print stats

# Connection tracking
/ip firewall connection print

# NAT stats
/ip firewall nat print stats

# Временно добавить лог
/ip firewall filter add \
    chain=forward \
    action=log \
    log-prefix="DEBUG" \
    place-before=0

# Потом проверить логи
/log print where message~"DEBUG"
```

---

### Система

```routeros
# Ресурсы системы
/system resource print

# Uptime
/system resource print

# Логи
/log print
/log print where topics~"error"
/log print follow  # real-time

# История команд
/system history print

# Лицензия и версия
/system license print
/system package print
```

---

### DHCP

```routeros
# DHCP серверы
/ip dhcp-server print detail

# Leases
/ip dhcp-server lease print

# Alerts
/ip dhcp-server alert print

# Мониторинг в реальном времени
/log print follow where topics~"dhcp"
```

---

### WiFi

```routeros
# Информация об интерфейсе
/interface wireless print detail

# Подключенные клиенты
/interface wireless registration-table print

# Мониторинг сигнала
/interface wireless monitor [find name=wlan0]

# Сканирование частот
/interface wireless frequency-monitor wlan0 duration=10
```

---

## Получение помощи

### Внутренние ресурсы:
- [README.md](../README.md) - Обзор проекта
- [QUICK_START.md](./QUICK_START.md) - Быстрый старт
- [DEPLOYMENT_GUIDE.md](./DEPLOYMENT_GUIDE.md) - Развёртывание
- [ARCHITECTURE.md](./ARCHITECTURE.md) - Архитектура

### Внешние ресурсы:
- [MikroTik Wiki](https://wiki.mikrotik.com)
- [MikroTik Documentation](https://help.mikrotik.com/docs/)
- [MikroTik Forum](https://forum.mikrotik.com)
- [Reddit r/mikrotik](https://reddit.com/r/mikrotik)

---

**Создано:** Claude Code (Sonnet 4.5)
**Дата:** 15 декабря 2025
**Версия:** 1.3
