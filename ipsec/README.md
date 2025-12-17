# IPsec IKEv2 Site-to-Site VPN (VTI)

**Версия:** 1.3
**Протокол:** IKEv2 (RFC 7296)
**Тип:** Route-based IPsec с VTI (Virtual Tunnel Interface)
**Криптография:** Современный стек с AEAD шифрованием

---

## 🔐 Криптографические параметры

### Phase 1 (IKE)
- **Алгоритм шифрования:** AES-128-GCM (AEAD)
- **PRF (Pseudo-Random Function):** SHA-256
- **Обмен ключами:** ECDH P-256 (эллиптическая кривая)
- **Lifetime:** 8 часов
- **Режим:** IKEv2 (aggr mode не требуется)

### Phase 2 (ESP)
- **Алгоритм шифрования:** AES-128-GCM (AEAD)
- **PFS (Perfect Forward Secrecy):** ECP256
- **Lifetime:** 1 час

### Преимущества выбранной криптографии

✅ **AES-128-GCM:**
- AEAD (Authenticated Encryption with Associated Data)
- Встроенная аутентификация (не нужен отдельный HMAC)
- Высокая производительность (аппаратное ускорение на современных CPU)
- Безопасность эквивалентна AES-256 для большинства применений

✅ **SHA-256:**
- Безопасная хеш-функция (collision-resistant)
- Широко тестирована и стандартизирована
- Аппаратное ускорение на современных процессорах

✅ **ECDH P-256:**
- Меньший размер ключей при той же безопасности (256-bit ECC ≈ 3072-bit RSA)
- Быстрый обмен ключами
- Стандартизирована NIST (FIPS 186-4)

---

## 📐 Архитектура VTI (Route-Based IPsec)

### Что такое VTI?

VTI (Virtual Tunnel Interface) создает виртуальный интерфейс для IPsec туннеля, что позволяет использовать его как обычный сетевой интерфейс.

### Преимущества VTI vs Policy-Based IPsec

| Feature | VTI (Route-Based) | Policy-Based |
|---------|-------------------|--------------|
| **Routing** | Динамическая маршрутизация (OSPF, BGP) | Только статические policy |
| **Множественные подсети** | ✅ Простая маршрутизация | ❌ Нужна policy на каждую пару сетей |
| **QoS** | ✅ Полная поддержка | ⚠️ Ограничена |
| **Мониторинг** | ✅ Как обычный интерфейс | ⚠️ Сложнее |
| **Failover** | ✅ Поддержка routing protocols | ⚠️ Ручная настройка |
| **Конфигурация** | ✅ Проще и понятнее | ⚠️ Сложнее при множестве подсетей |

### Схема VTI туннеля

```
Site A (Main Office)                          Site B (Branch)
┌──────────────────────┐                      ┌──────────────────────┐
│ LAN: 192.168.1.0/24  │                      │ LAN: 10.21.0.0/24    │
│ Gateway: 192.168.1.1 │                      │ Gateway: 10.21.0.1   │
└──────────┬───────────┘                      └──────────┬───────────┘
           │                                             │
┌──────────▼───────────┐                      ┌──────────▼───────────┐
│  MikroTik Router A   │                      │  MikroTik Router B   │
│                      │                      │                      │
│ VTI: ipsec-s2s       │                      │ VTI: ipsec-s2s       │
│   IP: 10.12.0.1/30   │◄────IPsec IKEv2────►│   IP: 10.12.0.2/30   │
│                      │   (AES-128-GCM)      │                      │
│ WAN: 203.0.113.10    │                      │ WAN: 198.51.100.20   │
└──────────────────────┘                      └──────────────────────┘

Трафик:
192.168.1.0/24 ──► VTI (10.12.0.1) ──► IPsec Tunnel ──► VTI (10.12.0.2) ──► 10.21.0.0/24
```

---

## ⚙️ Конфигурация

### Site A (Main Office) - 192.168.1.0/24

**В файле `00-config.rsc` на Site A:**

```routeros
# IPsec IKEv2 Site-to-Site (VTI route-based)
:global cfgIPsecInterface "ipsec-s2s"
:global cfgIPsecLocalAddress "10.12.0.1/30"           # VTI tunnel IP (SITE A)
:global cfgIPsecRemoteAddress "10.12.0.2/30"          # VTI tunnel IP (SITE B)
:global cfgIPsecRemoteEndpoint "198.51.100.20"        # WAN IP SITE B
:global cfgIPsecRemoteNetwork "10.21.0.0/24"          # LAN SITE B
:global cfgIPsecLocalNetwork "192.168.1.0/24"         # LAN SITE A
:global cfgIPsecProposalName "ike2-aes128gcm"
:global cfgIPsecPolicyGroup "ipsec-s2s-group"
:global cfgIPsecPeerName "remote-site"
```

**В файле `00-secrets.rsc` на Site A:**

```routeros
# IPsec IKEv2 Site-to-Site
:global secIPsecPSK "MyVeryStrongSharedSecret123!@#"
```

**Импорт на Site A:**

```routeros
/import 00-config.rsc
/import 00-secrets.rsc
/import 11a-ipsec-ikev2-s2s.rsc
```

---

### Site B (Branch Office) - 10.21.0.0/24

**В файле `00-config.rsc` на Site B:**

```routeros
# IPsec IKEv2 Site-to-Site (VTI route-based)
:global cfgIPsecInterface "ipsec-s2s"
:global cfgIPsecLocalAddress "10.12.0.2/30"           # VTI tunnel IP (SITE B) - SWAPPED!
:global cfgIPsecRemoteAddress "10.12.0.1/30"          # VTI tunnel IP (SITE A) - SWAPPED!
:global cfgIPsecRemoteEndpoint "203.0.113.10"         # WAN IP SITE A - SWAPPED!
:global cfgIPsecRemoteNetwork "192.168.1.0/24"        # LAN SITE A - SWAPPED!
:global cfgIPsecLocalNetwork "10.21.0.0/24"           # LAN SITE B - SWAPPED!
:global cfgIPsecProposalName "ike2-aes128gcm"
:global cfgIPsecPolicyGroup "ipsec-s2s-group"
:global cfgIPsecPeerName "remote-site"
```

**В файле `00-secrets.rsc` на Site B:**

```routeros
# IPsec IKEv2 Site-to-Site
:global secIPsecPSK "MyVeryStrongSharedSecret123!@#"  # ТОТ ЖЕ ключ!
```

**Импорт на Site B:**

```routeros
/import 00-config.rsc
/import 00-secrets.rsc
/import 11a-ipsec-ikev2-s2s.rsc
```

---

## 🔍 Проверка и тестирование

### 1. Проверка установления туннеля

```routeros
# Показать активные IPsec пиры
/ip ipsec active-peers print

# Должны увидеть:
# 0   id=remote-site uptime=... ph2-state=established

# Показать установленные SA (Security Associations)
/ip ipsec installed-sa print

# Показать статус VTI интерфейса
/interface ipsec print detail

# Показать IPsec policies
/ip ipsec policy print
```

### 2. Проверка связности

```routeros
# Ping удаленного VTI IP
/ping 10.12.0.2 count=5

# Ping удаленной LAN сети
/ping 10.21.0.100 count=5 src-address=192.168.1.1

# Traceroute через туннель
/tool traceroute 10.21.0.100
```

### 3. Мониторинг трафика

```routeros
# Мониторинг VTI интерфейса
/interface monitor-traffic ipsec-s2s

# Статистика IPsec
/ip ipsec statistics print
```

### 4. Проверка маршрутизации

```routeros
# Показать маршрут к удаленной сети
/ip route print where dst-address=10.21.0.0/24

# Должны увидеть:
# dst-address=10.21.0.0/24 gateway=ipsec-s2s
```

---

## 🐛 Troubleshooting

### Проблема: Туннель не устанавливается

**Проверьте логи:**
```routeros
/log print where topics~"ipsec"
```

**Частые причины:**
1. ❌ **Разные PSK на обеих сторонах** - проверьте `secIPsecPSK`
2. ❌ **Неправильный remote endpoint** - проверьте `cfgIPsecRemoteEndpoint`
3. ❌ **Firewall блокирует IPsec** - проверьте UDP 500, UDP 4500, ESP
4. ❌ **NAT между роутерами** - убедитесь что NAT-T работает (UDP 4500)

**Решения:**
```routeros
# Проверьте конфигурацию peer
/ip ipsec peer print detail

# Проверьте identity
/ip ipsec identity print detail

# Проверьте firewall
/ip firewall filter print where protocol~"udp|esp"
```

### Проблема: Ping VTI IP работает, но ping LAN не работает

**Причины:**
1. ❌ **Неправильная маршрутизация на удаленной стороне**
2. ❌ **Firewall на удаленной стороне блокирует**
3. ❌ **NAT exemption не настроен**

**Решение:**
```routeros
# Проверьте NAT exemption
/ip firewall nat print where comment~"IPsec"

# Проверьте маршруты
/ip route print

# На удаленной стороне проверьте firewall forward chain
/ip firewall filter print where chain=forward
```

### Проблема: Туннель периодически падает

**Причины:**
1. ⚠️ **DPD (Dead Peer Detection) таймаут**
2. ⚠️ **Нестабильное интернет-соединение**
3. ⚠️ **MTU проблемы**

**Решение:**
```routeros
# Включите DPD на peer
/ip ipsec peer set $cfgIPsecPeerName dpd-interval=30s dpd-maximum-failures=5

# Уменьшите MTU на VTI интерфейсе
/interface ipsec set $cfgIPsecInterface mtu=1400

# Проверьте MTU path discovery
/ping 10.21.0.100 size=1400 dont-fragment
```

---

## 🔐 Безопасность

### Рекомендации по PSK

**Генерация надежного PSK:**

```bash
# Linux/macOS
openssl rand -base64 32

# PowerShell (Windows)
-join ((48..57)+(65..90)+(97..122) | Get-Random -Count 32 | % {[char]$_})
```

**Требования к PSK:**
- ✅ Минимум 32 символа
- ✅ Случайная генерация (не словарные слова)
- ✅ Уникальный для каждого туннеля
- ✅ Хранить в зашифрованном виде (password manager)

### Альтернатива: Сертификаты (более безопасно)

Для production-среды рекомендуется использовать **RSA или ECDSA сертификаты** вместо PSK.

Пример конфигурации с сертификатами будет добавлен в будущих версиях.

---

## 📊 Производительность

### Ожидаемая пропускная способность

| Устройство | CPU | Throughput (AES-128-GCM) |
|------------|-----|--------------------------|
| hEX S (RB760iGS) | MIPS 880MHz | ~250 Mbps |
| hAP ac2 | IPQ-4018 716MHz | ~300-400 Mbps |
| CCR1009 | 9x Tilera 1.2GHz | ~1-2 Gbps |
| CCR2004 | 4x ARM 1.7GHz | ~4-6 Gbps |

**Примечание:** Производительность зависит от CPU и наличия hardware crypto acceleration.

### Оптимизация производительности

```routeros
# Включите hardware offloading (если поддерживается)
/interface ethernet
set [find] l2mtu=1600

# Используйте jumbo frames на LAN (если возможно)
/interface ethernet
set [find where name~"ether"] mtu=9000

# Проверьте CPU load
/system resource print
```

---

## 🚀 Расширенные возможности

### Динамическая маршрутизация через VTI

VTI позволяет использовать routing протоколы через IPsec туннель:

**OSPF через IPsec:**
```routeros
/routing ospf instance
add name=default router-id=192.168.1.1

/routing ospf interface-template
add area=backbone interfaces=ipsec-s2s cost=10
```

**BGP через IPsec:**
```routeros
/routing bgp connection
add name=ipsec-bgp \
    remote.address=10.12.0.2 \
    remote.as=65001 \
    local.role=ebgp
```

### Failover с несколькими туннелями

Можно создать несколько VTI туннелей к разным провайдерам для отказоустойчивости.

---

## 📚 Полезные ссылки

- [MikroTik IPsec Documentation](https://help.mikrotik.com/docs/display/ROS/IPsec)
- [RFC 7296 - IKEv2](https://www.rfc-editor.org/rfc/rfc7296)
- [RFC 5282 - Using AES-GCM in IPsec](https://www.rfc-editor.org/rfc/rfc5282)
- [NIST SP 800-77 - IPsec VPN Guide](https://csrc.nist.gov/publications/detail/sp/800-77/rev-1/final)

---

**Создано:** Claude Code (Sonnet 4.5)
**Дата:** 17 декабря 2025
**Версия:** 1.0
