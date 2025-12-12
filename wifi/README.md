# WiFi CAPsMAN для MikroTik

Dual-stack CAPsMAN конфигурация для централизованного управления WiFi.

**Версия:** 2.1 (улучшенная, модульная)

---

## 📋 Что включено

### CAPsMAN (Централизованное управление WiFi)

1. **01-wifi-capsman.rsc** - CAPsMAN конфигурация:
   - Dual-stack: wifiwave2 (ax3) + legacy (ac2)
   - Main SSID "SV5G" с роумингом (802.11k/r/v)
   - Guest SSID "SVGuest" с client isolation
   - Bridge VLAN filtering
   - Provisioning для автоматического создания AP интерфейсов

2. **02-wifi-network.rsc** - Network конфигурация:
   - VLAN интерфейсы (20 - Main, 30 - Guest)
   - IP адреса на VLAN интерфейсах
   - DHCP серверы для клиентов
   - DNS настройки

3. **03-wifi-channels.rsc** - Оптимизация каналов (ОПЦИОНАЛЬНО):
   - Неперекрывающиеся каналы для multi-AP
   - Избегание DFS каналов
   - Оптимизация для 3 точек доступа (R1, R2, R3)
   - Рекомендации по настройке каналов

4. **FIREWALL_ADDITIONS.txt** - Firewall правила:
   - Инструкции для добавления в firewall_complete.rsc
   - Guest network isolation
   - CAPsMAN discovery правила
   - Порядок применения

### WDS Bridge (Беспроводное расширение сети)

5. **04-r2-wds-ap-bridge.rsc** - WDS AP сторона (на R2):
   - Virtual AP для WDS-моста R2 ↔ RB2011
   - Расширение Guest VLAN 30 на удаленную локацию
   - WPA2+WPA3 encryption
   - MAC filtering (whitelist)
   - Firewall isolation
   - Rate limiting
   - Автоматический мониторинг

6. **05-rb2011-wds-station-bridge.rsc** - WDS Station сторона (на RB2011):
   - Station-bridge подключение к R2
   - Прозрачный L2 bridge на LAN порты
   - Выделенный management VLAN 99
   - Безопасная firewall конфигурация
   - Auto-recovery мониторинг
   - IPv6 firewall support

7. **WDS-DEPLOYMENT-GUIDE.md** - Полное руководство по WDS:
   - Архитектура решения
   - Анализ безопасности (12 исправленных проблем)
   - Пошаговое развертывание
   - Troubleshooting
   - Performance optimization
   - Security checklist

---

## 🔄 Улучшения по сравнению со старыми файлами

### Заменяет:
- ❌ `06-wifi-capsman-core.rsc` (базовая конфигурация)
- ❌ `07-wifi-guestю.rsc` (guest network)
- ❌ `capsman-channel-plan.rsc` (план каналов)

### Добавляет:
- ✅ Roaming support (802.11k/r/v) для Main SSID
- ✅ Client isolation для Guest SSID
- ✅ Bridge VLAN filtering
- ✅ Uplink ports конфигурация
- ✅ Band steering (предпочтение 5GHz)
- ✅ Provisioning для CAPs
- ✅ Все на :local переменных
- ✅ Модульная структура (WiFi + Network + Channels + Firewall разделены)
- ✅ Оптимизация каналов (non-DFS, неперекрывающиеся)

---

## 🚀 Быстрый старт

### Шаг 1: Подготовка

```bash
# Скопировать файлы на роутер
scp wifi/*.rsc wifi/*.txt admin@192.168.1.1:/

# Подключиться к роутеру
ssh admin@192.168.1.1
```

### Шаг 2: Настроить переменные

Отредактируйте **01-wifi-capsman.rsc** (строки 10-43):

```routeros
# SSIDs и пароли
:local SSID_MAIN "YourMainSSID"
:local SSID_GUEST "YourGuestSSID"
:local MAIN_PASS "YourMainPassword"
:local GUEST_PASS "YourGuestPassword"

# Access Points
:local AP_R2_IP "192.168.1.2"
:local AP_R3_IP "192.168.1.3"
```

Отредактируйте **02-wifi-network.rsc** (строки 10-35):

```routeros
# Настройте IP адреса и DHCP ranges под вашу сеть
```

### Шаг 3: Применить конфигурацию WiFi

```routeros
/import 01-wifi-capsman.rsc
```

Это создаст:
- Security profiles для Main и Guest
- WiFi configurations (wifiwave2 + legacy)
- CAPsMAN manager
- Provisioning rules
- Bridge VLAN table entries

### Шаг 4: Применить конфигурацию Network

```routeros
/import 02-wifi-network.rsc
```

Это создаст:
- VLAN интерфейсы
- IP адреса
- DHCP серверы и pools
- DHCP networks

### Шаг 4.5: Оптимизация каналов (ОПЦИОНАЛЬНО)

```routeros
/import 03-wifi-channels.rsc
```

Это настроит:
- 5GHz: Channel 36 (5180 MHz) - non-DFS
- 2.4GHz: Channel 1 (2412 MHz)
- Избегание DFS каналов
- Рекомендации для multi-AP deployment

**Примечание**: Этот шаг опциональный. CAPsMAN может автоматически выбирать оптимальные каналы.

### Шаг 5: Добавить Firewall правила

**ВАЖНО:** Не применяйте автоматически! Редактируйте вручную.

Откройте `FIREWALL_ADDITIONS.txt` и добавьте правила в `firewall_complete.rsc` **в правильном порядке**.

Секции для добавления:
1. Переменные (WiFi VLANs, AP IPs)
2. INPUT chain (CAPsMAN discovery, AP allowances)
3. FORWARD chain (Main WiFi → WAN)
4. FORWARD chain (Guest isolation - заменить существующие)
5. IPv6 FORWARD (опционально)

### Шаг 6: Настроить Access Points (CAPs)

На каждом CAP (R2, R3) выполните:

```routeros
# Для legacy CAPsMAN (hAP ac2, ac3):
/caps-man cap set enabled=yes \
    discovery-interfaces=bridge-lan \
    caps-man-addresses=192.168.1.1

# Перезагрузить CAP
/system reboot
```

### Шаг 7: Проверка

```routeros
# Проверить CAPsMAN manager
/caps-man manager print
/wifi caps-man manager print

# Проверить зарегистрированные CAPs
/caps-man registration-table print
/wifi caps-man registration-table print

# Проверить WiFi интерфейсы
/interface wifi print
/interface wireless print

# Проверить DHCP leases
/ip dhcp-server lease print

# Проверить VLAN интерфейсы
/interface vlan print

# Проверить назначенные каналы
/caps-man registration-table print detail
/wifi registration-table print detail
```

---

## 🌉 WDS Bridge (опционально)

Если у вас есть удаленная локация (например, RB2011), где невозможно проложить кабель, но нужно расширить Guest VLAN 30, используйте WDS-мост.

### Когда использовать WDS:
- ✅ Невозможно проложить кабель к удаленной локации
- ✅ Нужно расширить существующую VLAN на удаленные LAN порты
- ✅ Есть прямая видимость между R2 и RB2011 (или расстояние < 50м)
- ❌ НЕ используйте для критичных сервисов (WDS медленнее проводного)

### Быстрый старт WDS:

**1. Подготовка:**
```bash
# Узнать MAC адреса
# На RB2011:
ssh admin@<rb2011-ip>
/interface wireless print detail where default-name=wlan1
# Записать MAC address

# На R2:
ssh admin@192.168.1.2
# MAC wds-ap будет известен после применения конфига
```

**2. Применить на R2 (WDS AP):**
```bash
# Отредактировать переменные в 04-r2-wds-ap-bridge.rsc:
# - WDS_PASS (минимум 20 символов)
# - RB2011_WLAN_MAC (MAC wlan1 на RB2011)
# - CHANNEL (рекомендуется CH11, если Guest WiFi на CH1/CH6)

scp wifi/04-r2-wds-ap-bridge.rsc admin@192.168.1.2:/
ssh admin@192.168.1.2
/import 04-r2-wds-ap-bridge.rsc

# Записать MAC адрес wds-ap для RB2011
/interface wireless print detail where name=wds-ap
```

**3. Применить на RB2011 (WDS Station):**
```bash
# Отредактировать переменные в 05-rb2011-wds-station-bridge.rsc:
# - WDS_PASS (тот же что на R2)
# - R2_MAC (MAC wds-ap с предыдущего шага)
# - MGMT_IP (уникальный IP в VLAN 99)

scp wifi/05-rb2011-wds-station-bridge.rsc admin@<rb2011-ip>:/
ssh admin@<rb2011-ip>
/import 05-rb2011-wds-station-bridge.rsc
# У вас будет 10 секунд для отмены!
```

**4. Проверить VLAN 99 на R1:**
```routeros
# VLAN 99 должен быть уже настроен (см. 05-vlan-mgmt.rsc)
/interface vlan print where vlan-id=99
/ip dhcp-server print where interface~"vlan.*mgmt"

# Если не настроен, применить:
/import 05-vlan-mgmt.rsc
```

**5. Проверить WDS связь и найти IP RB2011:**
```routeros
# На R1 найти IP RB2011 в DHCP leases
/ip dhcp-server lease print where server=dhcp-mgmt
# Найти RB2011 по MAC адресу или hostname
# Записать полученный IP (например, 172.16.99.45)

# На RB2011 (подключиться через полученный IP)
ssh admin@172.16.99.45
/interface wireless registration-table print
# Должна быть запись с R2

# На R2
/interface wireless registration-table print where interface=wds-ap
# Должна быть запись с RB2011, wds=yes

# Проверить доступность с R1
/ping 172.16.99.45 count=10
```

### Полная документация WDS:
См. **WDS-DEPLOYMENT-GUIDE.md** для:
- Детальной архитектуры
- Анализа безопасности (12 исправленных проблем)
- Пошагового развертывания
- Troubleshooting
- Performance optimization
- Security checklist

---

## 🏗️ Архитектура сети

```
                      ┌───────────────┐
                      │   INTERNET    │
                      └───────┬───────┘
                              │
                      ┌───────▼────────┐
                      │  R1 (Manager)  │
                      │  hAP ax3       │
                      │  192.168.1.1   │
                      │                │
                      │  CAPsMAN:      │
                      │  - wifiwave2   │
                      │  - legacy      │
                      └──┬─────────┬───┘
                         │         │
            ┌────────────┴───┐ ┌──┴─────────────┐
            │                │ │                │
       ┌────▼─────┐     ┌────▼─────┐      ┌────▼─────┐
       │ R2 (CAP) │     │ R3 (CAP) │      │  Switch  │
       │ hAP ac2  │     │ hAP ac2  │      │          │
       │ .1.2     │     │ .1.3     │      └──────────┘
       └──────────┘     └──────────┘

WiFi Networks:
┌──────────────────────────────────────────┐
│ Main SSID: "SV5G"                        │
│ VLAN: 20                                 │
│ Network: 192.168.20.0/24                 │
│ Security: WPA2+WPA3                      │
│ Roaming: 802.11k/r/v enabled             │
│ Client Isolation: NO                     │
│ Band: 2.4GHz + 5GHz                      │
│ Channels: auto или CH36 (5GHz), CH1/6/11 │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ Guest SSID: "SVGuest"                    │
│ VLAN: 30                                 │
│ Network: 10.30.0.0/24                    │
│ Security: WPA2                           │
│ Roaming: Disabled                        │
│ Client Isolation: YES                    │
│ Isolated from: LAN, Main WiFi, Mgmt      │
│ Access: Internet only                    │
│ Channels: auto или CH1 (2.4GHz)          │
└──────────────────────────────────────────┘
```

---

## 🔐 Безопасность

### Main SSID:

✅ **WPA2-PSK + WPA3-PSK** (wifiwave2)
✅ **WPA2-PSK** (legacy)
✅ **AES-CCM encryption**
✅ **No client isolation** (клиенты могут общаться между собой)
✅ **Roaming support** (бесшовный переход между APs)
✅ **Access to LAN** (полный доступ к локальной сети)

### Guest SSID:

✅ **WPA2-PSK only**
✅ **Client isolation** (клиенты не видят друг друга)
✅ **Isolated from LAN** (нет доступа к 192.168.1.0/24)
✅ **Isolated from Main WiFi** (нет доступа к 192.168.20.0/24)
✅ **Isolated from Management** (нет доступа к 172.16.99.0/24)
✅ **Isolated from Containers** (нет доступа к 10.11.0.0/24)
✅ **Internet only** (только выход в интернет)
✅ **Router access blocked** (нет доступа к management роутера)

### CAPsMAN Security:

✅ **Firewall allowances** для discovery (UDP 5246/5247)
✅ **Firewall allowances** для control (TCP 5246/5247)
✅ **Specific AP allowances** (только R2 и R3 могут подключиться)

---

## 🧪 Тестирование

### Проверка CAPsMAN:

```routeros
# Manager статус
/caps-man manager print
/wifi caps-man manager print

# Зарегистрированные CAPs
/caps-man registration-table print
/wifi caps-man registration-table print

# Remote CAPs
/caps-man remote-cap print
/wifi caps-man remote-cap print
```

### Проверка WiFi клиентов:

```routeros
# Активные клиенты (wifiwave2)
/wifi registration-table print

# Активные клиенты (legacy)
/caps-man registration-table print detail

# DHCP leases
/ip dhcp-server lease print where server~"wifi"
```

### Проверка Guest isolation:

С устройства на Guest WiFi:

```bash
# Должен работать (интернет)
ping 8.8.8.8

# Должны быть timeout (изоляция)
ping 192.168.1.1      # router
ping 192.168.20.1     # main wifi gateway
ping 192.168.1.10     # LAN device
```

### Проверка роуминга (Main SSID):

Подключитесь к Main SSID и перемещайтесь между зонами покрытия CAPs:

```routeros
# На Manager (R1) смотрите переключения:
/log print where message~"roam"
```

Клиент должен бесшовно переключаться между CAPs без разрыва соединения.

---

## 🎛️ Настройка каналов и мощности

### Автоматический выбор каналов (рекомендуется):

CAPsMAN автоматически выбирает оптимальные неперекрывающиеся каналы для всех CAPs.

```routeros
# Проверить назначенные каналы:
/caps-man registration-table print detail
/wifi registration-table print detail
```

### Ручная настройка каналов:

Если применили `03-wifi-channels.rsc`, каналы уже настроены:
- **5GHz**: Channel 36 (5180 MHz) - non-DFS
- **2.4GHz**: Channel 1 (2412 MHz)

Для разных каналов на разных AP:

```routeros
# Вариант 1: Создать provisioning rules с фильтрацией по MAC
/caps-man provisioning
add radio-mac=AA:BB:CC:DD:EE:FF \
    master-configuration=cfg-custom-r2 \
    action=create-enabled

# Вариант 2: Настроить вручную на каждом CAP
# (отключить CAPsMAN на интерфейсе и настроить локально)
```

### Рекомендации для 2.4GHz:

```routeros
# На каждом CAP настроить разные каналы:
# R1: channel 1 (2412 MHz)
# R2: channel 6 (2437 MHz)
# R3: channel 11 (2462 MHz)

/caps-man configuration
set cfg-l-guest channel.frequency=2437 channel.width=20mhz
```

### Рекомендации для 5GHz:

```routeros
# Использовать DFS каналы для меньших помех
# Или non-DFS для стабильности:
# R1: channel 36 (5180 MHz)
# R2: channel 40 (5200 MHz)
# R3: channel 44 (5220 MHz)

/caps-man configuration
set cfg-l-main channel.frequency=5180 channel.width=20mhz
```

### Настройка TX power:

```routeros
# Уменьшить мощность для лучшего роуминга
/caps-man configuration
set cfg-l-main channel.tx-power=17

# Для wifiwave2:
/wifi configuration
set cfg-w2-main channel.tx-power=17
```

---

## 🔧 Troubleshooting

### CAP не регистрируется:

```routeros
# На CAP проверить:
/caps-man cap print
# enabled должен быть yes
# caps-man-addresses должен содержать IP manager

# Проверить связность:
/ping 192.168.1.1 count=10

# Проверить firewall:
/ip firewall filter print where dst-port~"524"

# Логи:
/log print where message~"caps-man"
```

### Клиенты не получают IP:

```routeros
# Проверить DHCP server
/ip dhcp-server print
# Должны быть: dhcp-main-wifi, dhcp-guest-wifi

# Проверить DHCP leases
/ip dhcp-server lease print

# Проверить VLAN интерфейсы
/interface vlan print
/ip address print where interface~"vlan.*wifi"
```

### Guest изоляция не работает:

```routeros
# Проверить порядок firewall правил!
/ip firewall filter print

# Guest isolation правила должны быть ПЕРЕД общих allow правил
# Проверить логи:
/log print where message~"Guest"
```

### Роуминг не работает:

```routeros
# Проверить roaming настройки (только wifiwave2):
/wifi configuration print detail where name=cfg-w2-main

# Должно быть:
# roaming.enabled=yes
# roaming.k-enabled=yes
# roaming.r-enabled=yes
# roaming.v-enabled=yes

# На legacy CAPsMAN роуминг не поддерживается полноценно
```

### Каналы конфликтуют:

```routeros
# Проверить назначенные каналы на всех APs:
/caps-man registration-table print detail
/wifi registration-table print detail

# Если каналы перекрываются:
# - Применить 03-wifi-channels.rsc
# - Или настроить вручную на каждом CAP
# - Или увеличить расстояние между APs
```

---

## 📚 Связанная документация

- **Firewall:** См. `/firewall_complete.rsc` (добавить правила из FIREWALL_ADDITIONS.txt)
- **Network:** См. `/04-lan-dhcp.rsc` (базовая DHCP конфигурация)
- **VLANs:** См. `/05-vlan-mgmt.rsc` (management VLAN пример)

---

## 🔗 Полезные ссылки

### MikroTik Official
- [CAPsMAN Documentation](https://help.mikrotik.com/docs/display/ROS/CAPsMAN)
- [wifiwave2 Documentation](https://help.mikrotik.com/docs/display/ROS/WiFi+package)
- [Bridge VLAN Filtering](https://help.mikrotik.com/docs/display/ROS/Bridging+and+Switching#BridgingandSwitching-BridgeVLANFiltering)
- [WiFi Channels and Frequencies](https://help.mikrotik.com/docs/display/ROS/Channels)

### Best Practices
- [CAPsMAN Best Practices](https://forum.mikrotik.com/viewtopic.php?t=154559)
- [WiFi Roaming](https://en.wikipedia.org/wiki/IEEE_802.11r-2008)
- [Channel Planning](https://www.metageek.com/training/resources/design-dual-band-wifi.html)

---

## ⚠️ ВАЖНО

1. **Firewall правила критичны:**
   - НЕ применяйте автоматически из FIREWALL_ADDITIONS.txt
   - Добавляйте вручную в firewall_complete.rsc
   - Соблюдайте правильный порядок!

2. **Порядок применения:**
   - Сначала 01-wifi-capsman.rsc (WiFi конфигурация)
   - Затем 02-wifi-network.rsc (Network конфигурация)
   - Опционально 03-wifi-channels.rsc (оптимизация каналов)
   - Затем firewall правила (вручную!)
   - Последними настраивайте CAPs

3. **Пароли:**
   - Измените MAIN_PASS и GUEST_PASS перед применением
   - Используйте сильные пароли (мин. 12 символов)
   - НЕ храните пароли в plain text в скриптах

4. **Band steering:**
   - Настроено автоматически для wifiwave2
   - Для legacy нужно вручную настраивать TX power

5. **Оптимизация каналов:**
   - 03-wifi-channels.rsc - опциональный файл
   - CAPsMAN может автоматически выбирать оптимальные каналы
   - Ручная настройка нужна только для fine-tuning
   - Избегайте DFS каналов для стабильности

---

**Создано:** 10 декабря 2025
**Версия:** 2.1 (модульная, интегрированная с оптимизацией каналов)
