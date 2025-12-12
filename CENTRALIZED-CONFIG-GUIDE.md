# Руководство по централизованной конфигурации MikroTik

**Дата:** 12 декабря 2025
**Версия:** 1.0
**Статус:** Ready for deployment

---

## 📋 Содержание

1. [Обзор новой структуры](#обзор-новой-структуры)
2. [Преимущества централизованного подхода](#преимущества-централизованного-подхода)
3. [Структура файлов](#структура-файлов)
4. [Пошаговое руководство по внедрению](#пошаговое-руководство-по-внедрению)
5. [Обновленные файлы](#обновленные-файлы)
6. [Файлы требующие обновления](#файлы-требующие-обновления)
7. [Troubleshooting](#troubleshooting)
8. [Best Practices](#best-practices)

---

## Обзор новой структуры

Все переменные конфигурации вынесены в два централизованных файла:

```
00-config.rsc    → Все параметры инфраструктуры (IP, VLAN, интерфейсы)
00-secrets.rsc   → ТОЛЬКО credentials (пароли, ключи)
```

Остальные файлы (01-14.rsc) используют переменные из этих файлов.

## Преимущества централизованного подхода

✅ **Один источник истины** - все параметры в одном месте
✅ **Безопасность** - credentials в отдельном файле, удаляется после импорта
✅ **Легко адаптировать** - изменил IP в 00-config.rsc, применилось везде
✅ **Переиспользование** - разные 00-config-R1.rsc, 00-config-R2.rsc для роутеров
✅ **Версионирование** - легко отследить изменения
✅ **Решает CRIT-01** - credentials больше не в plain text в модулях!

---

## Структура файлов

### Новые файлы

```
00-config.rsc          ← Все переменные конфигурации
00-secrets.rsc         ← Credentials (удалить после импорта!)
```

### Обновлённые файлы (используют переменные)

```
✅ 01-base.rsc         - Базовая конфигурация
✅ 02-wan-pppoe-ipv4.rsc - WAN PPPoE
✅ 03-ipv6-HE-tunnel.rsc - IPv6 туннель
✅ 04-lan-dhcp.rsc - LAN DHCP
✅ 05-vlan-mgmt.rsc - Management VLAN
```

### Файлы требующие обновления

```
⏳ 06-wifi-capsman-core.rsc
⏳ 07-wifi-guest.rsc
⏳ 08-containers.rsc
⏳ 09-bgp-proxy.rsc
⏳ 10-vpn-sstp.rsc
⏳ 11-vpn-site2site.rsc
⏳ 12-dns-doh.rsc
⏳ 12a-dns-doh-ca.rsc
⏳ 13-ntp.rsc
⏳ 14-cert-renew.rsc
```

---

## Пошаговое руководство по внедрению

### Шаг 1: Подготовка (15 минут)

#### 1.1 Backup текущей конфигурации

```routeros
# На роутере
/system backup save name=before-centralized-config \
    encryption=aes-sha256 \
    password="YourStrongBackupPassword123!"

/export file=before-centralized-config
```

```bash
# На локальной машине
scp admin@192.168.1.1:/before-centralized-config.backup ./backups/
scp admin@192.168.1.1:/before-centralized-config.rsc ./backups/
```

#### 1.2 Редактировать 00-config.rsc

Откройте `00-config.rsc` и замените плейсхолдеры на реальные значения:

```routeros
# ОБЯЗАТЕЛЬНО ИЗМЕНИТЬ:
:global cfgWANPublicIP "101.102.103.104"  # Ваш WAN IP
:global cfgHELocalIPv6 "2001:470:xxxx::2/64"  # Ваш IPv6
:global cfgBGPPeerIP "211.212.213.214"  # Ваш BGP peer
:global cfgWDSRB2011MAC "AA:BB:CC:DD:EE:FF"  # MAC RB2011
```

#### 1.3 Редактировать 00-secrets.rsc

Откройте `00-secrets.rsc` и заполните ВСЕ пароли:

```routeros
:global secPPPoEUser "your_real_pppoe_user"
:global secPPPoEPass "your_real_pppoe_password"
:global secWiFiMainPass "ReallyStrongPassword123!"
:global secWiFiGuestPass "AnotherStrongPassword456!"
# ... и все остальные
```

**ВАЖНО:** Используйте сильные случайные пароли (минимум 20 символов)!

Генерация на Linux/macOS:
```bash
openssl rand -base64 32
```

### Шаг 2: Загрузка на роутер (5 минут)

```bash
# Загрузить новые файлы
scp 00-config.rsc admin@192.168.1.1:/
scp 00-secrets.rsc admin@192.168.1.1:/

# Загрузить обновлённые модули
scp 01-base.rsc admin@192.168.1.1:/
scp 02-wan-pppoe-ipv4.rsc admin@192.168.1.1:/
scp 03-ipv6-HE-tunnel.rsc admin@192.168.1.1:/
scp 04-lan-dhcp.rsc admin@192.168.1.1:/
scp 05-vlan-mgmt.rsc admin@192.168.1.1:/
```

### Шаг 3: Применение конфигурации (10 минут)

```routeros
# Подключиться к роутеру
ssh admin@192.168.1.1

# ВАЖНО: Импортировать в правильном порядке!

# 1. ПЕРВЫМ импортировать конфигурацию
/import 00-config.rsc

# 2. ВТОРЫМ импортировать credentials
/import 00-secrets.rsc

# 3. Затем импортировать модули в порядке
/import 01-base.rsc
/import 02-wan-pppoe-ipv4.rsc
/import 03-ipv6-HE-tunnel.rsc
/import 04-lan-dhcp.rsc
/import 05-vlan-mgmt.rsc

# ... остальные модули когда обновите

# 4. УДАЛИТЬ файл с паролями (КРИТИЧЕСКИ ВАЖНО!)
/file remove 00-secrets.rsc

# 5. Проверить что всё работает
/interface print
/ip address print
/ip route print
```

### Шаг 4: Проверка (5 минут)

```routeros
# Проверить интерфейсы
/interface print where !disabled

# Проверить IP адреса
/ip address print

# Проверить маршруты
/ip route print where active

# Проверить PPPoE
/interface pppoe-client print

# Проверить что пароль работает
# Попробовать подключиться к WiFi с новым паролем
```

### Шаг 5: Безопасность (10 минут)

```routeros
# 1. Создать encrypted backup с новой конфигурацией
/system backup save name=after-centralized-config \
    encryption=aes-sha256 \
    password="YourStrongBackupPassword123!"

# 2. Экспорт (пароли будут видны в реальных значениях)
/export file=after-centralized-config

# 3. Скачать backup на безопасное хранилище
```

```bash
# На локальной машине
scp admin@192.168.1.1:/after-centralized-config.backup ./backups/
scp admin@192.168.1.1:/after-centralized-config.rsc ./backups/

# Сохранить в password manager
# - PPPoE user/password
# - WiFi passwords
# - VPN credentials
# - BGP MD5 key
```

---

## Обновленные файлы

### ✅ 01-base.rsc
- Использует `$cfgHostname`, `$cfgBridgeLAN`, `$cfgBridgeContainers`
- Автоматически добавляет порты из `$cfgLANPorts`
- ACL из `$cfgMgmtAllowedNets`

### ✅ 02-wan-pppoe-ipv4.rsc
- PPPoE credentials из `$secPPPoEUser` и `$secPPPoEPass`
- Интерфейсы из `$cfgWanInterface` и `$cfgWanPPPoE`

### ✅ 03-ipv6-HE-tunnel.rsc
- Все HE параметры из `00-config.rsc`
- `$cfgHELocalIPv6`, `$cfgHERemoteIP`, `$cfgHERemoteGW`

### ✅ 04-lan-dhcp.rsc
- LAN сеть из `$cfgLANNetwork`, `$cfgLANGateway`
- DHCP pool из `$cfgLANPoolStart` - `$cfgLANPoolEnd`

### ✅ 05-vlan-mgmt.rsc
- Management VLAN из `$cfgMgmtVLAN`
- Сеть из `$cfgMgmtNetwork`, `$cfgMgmtGateway`
- DHCP pool из `$cfgMgmtPoolStart` - `$cfgMgmtPoolEnd`

---

## Файлы требующие обновления

Используйте шаблон для обновления оставшихся файлов:

### Шаблон обновления

```routeros
# XX-module-name.rsc - Module description
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# Module configuration using centralized variables
############################################################

# Замените hardcoded значения на переменные:
# БЫЛО:
# :local WAN_IF "ether1"
#
# СТАЛО:
# (используется $cfgWanInterface из 00-config.rsc)

# БЫЛО:
# :local WIFI_PASS "MyPassword"
#
# СТАЛО:
# (используется $secWiFiMainPass из 00-secrets.rsc)

############################################################
# END OF MODULE CONFIGURATION
############################################################

:log info "Module XX applied from XX-module-name.rsc"
```

### Пример: 08-containers.rsc

```routeros
# Было:
:local CONTAINER_BRIDGE "bridge-containers"
:local XRAY_IP "10.11.0.10"
:local NGINX_IP "10.11.0.11"

# Стало:
# (используем переменные)
/interface bridge port
add bridge=$cfgBridgeContainers interface=$cfgVethContainers

/ip address
add address=$cfgContainerGateway interface=$cfgBridgeContainers

# Container xRay
/container add name=xray \
    interface=containers \
    root-dir=($cfgContainerImagesRoot . "/xray") \
    remote-image=$cfgDockerXRayImage

# NAT to nginx
/ip firewall nat
add chain=dstnat in-interface=$cfgWanPPPoE \
    protocol=tcp dst-port=80,443 \
    action=dst-nat to-addresses=$cfgContainerNginxIP
```

---

## Troubleshooting

### Проблема: "Invalid syntax" при импорте

**Причина:** Не импортирован `00-config.rsc` перед модулем

**Решение:**
```routeros
/import 00-config.rsc
/import 00-secrets.rsc
# Затем импортировать модуль
```

### Проблема: PPPoE не подключается

**Причина:** Неправильные credentials в `00-secrets.rsc`

**Решение:**
```routeros
# Проверить credentials
/interface pppoe-client print detail

# Переимпортировать с правильными данными
/import 00-secrets.rsc
/import 02-wan-pppoe-ipv4.rsc
```

### Проблема: После перезагрузки ничего не работает

**Причина:** Переменные не сохраняются после reboot. Это нормально!

**Объяснение:** RouterOS сохранил РЕАЛЬНЫЕ значения при импорте.
Переменные были нужны только один раз.

**Проверка:**
```routeros
/export
# Вы увидите реальные значения, не переменные
```

---

## Best Practices

### ✅ DO

1. **Всегда создавайте backup перед изменениями**
   ```routeros
   /system backup save encryption=aes-sha256 password="..."
   ```

2. **Удаляйте 00-secrets.rsc после импорта**
   ```routeros
   /file remove 00-secrets.rsc
   ```

3. **Используйте разные 00-config.rsc для разных роутеров**
   ```
   00-config-R1-Core.rsc
   00-config-R2-Branch.rsc
   00-config-R3-Remote.rsc
   ```

4. **Храните пароли в password manager**
   - KeePassXC (open source)
   - Bitwarden
   - 1Password

5. **Версионируйте 00-config.rsc в Git**
   ```bash
   git add 00-config.rsc
   git commit -m "Updated LAN subnet"
   ```

### ❌ DON'T

1. **НЕ коммитьте 00-secrets.rsc в Git!**
   ```bash
   # Добавьте в .gitignore
   echo "00-secrets.rsc" >> .gitignore
   echo "**/secrets*.rsc" >> .gitignore
   ```

2. **НЕ оставляйте 00-secrets.rsc на роутере**
   ```routeros
   # Удалить СРАЗУ после импорта!
   /file remove 00-secrets.rsc
   ```

3. **НЕ используйте слабые пароли**
   ```
   ❌ BAD: "password123", "admin", "12345678"
   ✅ GOOD: "xK9m$nP2vL#qR8wT5yU7iO0pA3sD6fG"
   ```

4. **НЕ делайте /export в публичные места**
   - Export содержит реальные пароли!
   - Используйте encrypted backup вместо export

---

## Следующие шаги

1. **Обновить оставшиеся модули (06-14.rsc)**
   - Используйте шаблон выше
   - Замените hardcoded значения на переменные

2. **Обновить WiFi модули** (`wifi/*.rsc`)
   - Используйте `$secWiFiMainPass`, `$secWiFiGuestPass`, `$secWDSPass`

3. **Обновить документацию**
   - Добавить в `docs/RECOMMENDATIONS.md` что CRIT-01 решена
   - Обновить `docs/SECURITY_AUDIT.md`

4. **Создать automation script**
   ```bash
   #!/bin/bash
   # deploy-config.sh
   scp 00-config.rsc admin@$ROUTER:/
   scp 00-secrets.rsc admin@$ROUTER:/
   ssh admin@$ROUTER "/import 00-config.rsc && /import 00-secrets.rsc"
   # ... import other modules
   ssh admin@$ROUTER "/file remove 00-secrets.rsc"
   ```

---

## Поддержка

Если возникли вопросы:
1. Проверьте этот гайд
2. Проверьте `00-config.rsc` комментарии
3. Создайте encrypted backup перед экспериментами
4. Используйте `/log print` для диагностики

**Удачного внедрения! 🚀**

---

**Документация создана:** 12 декабря 2025
**Версия:** 1.0
**Решает:** CRIT-01 (Credentials in plain text)
