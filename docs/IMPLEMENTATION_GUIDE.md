# Руководство по внедрению улучшений

**Дата:** 10 декабря 2025
**Последнее обновление:** 12 декабря 2025
**Версия:** 1.2
**Аудитория:** Системные администраторы
**Предварительное чтение:** SECURITY_AUDIT.md, RECOMMENDATIONS.md

**Новое в v1.2:**
- ✅ Готовые модули: `firewall_complete.rsc`, `nginx-certbot/`, `wifi/`
- ✅ 3 критические проблемы (CRIT-02, 03, 04) решены готовыми файлами
- ✅ Добавлен WiFi CAPsMAN и WDS Bridge deployment
- ✅ Упрощённый процесс внедрения благодаря готовым модулям

---

## Краткий план внедрения

### Фаза 0: Подготовка (1 день)
- ✅ Полный backup текущей конфигурации
- ✅ Документирование текущего состояния
- ✅ Подготовка rollback плана
- ✅ Тестовое окружение (если возможно)

### Фаза 1: Критические исправления - P0 (1 день - упрощено в v1.2!)
- ✅ IPv6 Firewall - **используйте `firewall_complete.rsc`**
- ✅ Изоляция контейнеров - **используйте `nginx-certbot/` модуль**
- ✅ Закрытие DNS resolver - **включено в `firewall_complete.rsc`**
- ✅ Исправление ACL управления
- ✅ WiFi CAPsMAN - **используйте `wifi/01-wifi-capsman.rsc`** (опционально)

### Фаза 2: Важные исправления - P1 (1 неделя)
- ✅ Управление credentials
- ✅ SSH hardening + brute-force protection
- ✅ Rate limiting для публичных портов

### Фаза 3: Автоматизация (2 недели)
- ✅ Развёртывание automation container
- ✅ Настройка Vault для секретов
- ✅ Ansible playbooks для всех роутеров

### Фаза 4: Мониторинг (1 неделя)
- ✅ Prometheus + Grafana
- ✅ Централизованное логирование
- ✅ Telegram уведомления

### Фаза 5: WiFi CAPsMAN и WDS Bridge (опционально, 1-2 дня)
- ✅ Развёртывание CAPsMAN (dual-stack: wifiwave2 + legacy)
- ✅ Настройка WDS Bridge для расширения Guest VLAN
- ✅ Интеграция с Management VLAN 99
- ✅ См. `wifi/README.md` и `wifi/WDS-DEPLOYMENT-GUIDE.md`

---

## День 1: Backup и подготовка

### 1.1 Создание encrypted backup

```routeros
# Подключитесь к роутеру
ssh admin@192.168.1.1

# Создать encrypted backup
/system backup save name=before-security-upgrade \
    encryption=aes-sha256 \
    password="VeryStrongBackupPassword123!"

# Экспортировать конфигурацию
/export file=before-security-upgrade

# Скачать backup на локальную машину
```

```bash
# На локальной машине
scp admin@192.168.1.1:/before-security-upgrade.backup ./backups/
scp admin@192.168.1.1:/before-security-upgrade.rsc ./backups/

# Сохранить в безопасном месте
```

### 1.2 Документирование текущего состояния

```routeros
# Собрать информацию о системе
/system resource print
/system routerboard print
/interface print
/ip address print
/ip route print
/ip firewall filter print
/ip firewall nat print
```

Сохраните вывод каждой команды.

### 1.3 Подготовка rollback плана

Создайте документ `ROLLBACK_PLAN.md`:

```markdown
# Rollback Plan

## Если что-то пошло не так:

### Вариант 1: Откат через backup (рекомендуется)
1. Загрузить backup файл на роутер
2. /system backup load name=before-security-upgrade
3. Роутер перезагрузится с предыдущей конфигурацией

### Вариант 2: Откат конкретных изменений
1. Удалить новые правила firewall
2. Восстановить старые настройки из export файла

### Emergency Access
- Console cable: всегда должен быть доступен
- Reset button: последний вариант (сброс к заводским)

### Контакты
- Backup админ: ...
- Поддержка MikroTik: support@mikrotik.com
```

---

## День 2-3: Критические исправления (P0)

### 2.1 IPv6 Firewall

**Время:** 30 минут
**Риск:** Низкий
**Rollback:** Удалить правила `/ipv6 firewall filter remove`

```bash
# 1. Создать файл 03a-ipv6-firewall.rsc локально
# (содержимое см. в RECOMMENDATIONS.md)

# 2. Загрузить на роутер
scp 03a-ipv6-firewall.rsc admin@192.168.1.1:/

# 3. Применить
ssh admin@192.168.1.1
/import 03a-ipv6-firewall.rsc

# 4. Проверить
/ipv6 firewall filter print
/ipv6 firewall filter print statistics

# 5. Тестирование с внешнего IPv6 хоста
```

```bash
# На внешнем хосте с IPv6
nmap -6 -p 22,8291,8728 YOUR_IPV6_ADDRESS
# Все порты должны быть filtered/closed
```

**✅ Критерии успеха:**
- IPv6 firewall правила созданы
- Management порты недоступны из интернета
- ICMP работает (ping6)
- LAN клиенты могут выходить в IPv6 интернет

---

### 2.2 Изоляция контейнеров

**Время:** 20 минут
**Риск:** Средний (может нарушить работу контейнеров)
**Rollback:** Восстановить правило `action=accept`

```routeros
# 1. Удалить старое небезопасное правило
/ip firewall filter
remove [find comment="Allow container internal management"]

# 2. Добавить новые правила (из RECOMMENDATIONS.md)
# DNS
add chain=input src-address=10.11.0.0/24 protocol=udp dst-port=53 \
    action=accept comment="Containers: DNS UDP"

add chain=input src-address=10.11.0.0/24 protocol=tcp dst-port=53 \
    action=accept comment="Containers: DNS TCP"

# NTP
add chain=input src-address=10.11.0.0/24 protocol=udp dst-port=123 \
    action=accept comment="Containers: NTP"

# Блокировать management
add chain=input src-address=10.11.0.0/24 protocol=tcp \
    dst-port=22,8291,80,443,8728,8729 \
    action=drop comment="Block containers -> router management"

# Блокировать всё остальное
add chain=input src-address=10.11.0.0/24 \
    action=drop comment="Block containers -> router (default deny)"

# 3. Изоляция от внутренних сетей (FORWARD chain)
add chain=forward src-address=10.11.0.0/24 dst-address=192.168.1.0/24 \
    action=drop comment="Block containers -> LAN"

add chain=forward src-address=10.11.0.0/24 dst-address=172.16.99.0/24 \
    action=drop comment="Block containers -> Management"

# 4. Rate limiting для nginx
add chain=forward dst-address=10.11.0.11 protocol=tcp \
    dst-port=80,443 connection-state=new \
    connection-limit=50,32 action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Nginx: connection limit"

# 5. Resource limits
/container set xray memory-high=200M
/container set nginx memory-high=150M
/container set certbot memory-high=100M

# 6. Проверка
/container shell nginx
# Внутри контейнера:
nslookup google.com  # Должно работать (DNS)
telnet 10.11.0.1 22   # Должен быть timeout (blocked)
```

**✅ Критерии успеха:**
- Контейнеры могут резолвить DNS
- Контейнеры НЕ могут подключиться к SSH/Winbox роутера
- Nginx отвечает на HTTP/HTTPS запросы
- Rate limiting работает (проверить с `ab` или аналогом)

---

### 2.3 Закрытие DNS Resolver

**Время:** 5 минут
**Риск:** Низкий

```routeros
# Вариант 1: Полностью отключить remote requests
/ip dns set allow-remote-requests=no

# Проверка с внешнего хоста
```

```bash
dig @YOUR_PUBLIC_IP example.com
# Должно быть: connection refused или timeout
```

**✅ Критерии успеха:**
- Внешние хосты не могут запрашивать DNS
- Локальные клиенты продолжают работать

---

### 2.4 Исправление ACL управления

**Время:** 5 минут
**Риск:** Низкий

```routeros
/ip service
set ssh address=192.168.1.0/24,172.16.99.0/24
set winbox address=192.168.1.0/24,172.16.99.0/24

# Проверка
/ip service print
```

**✅ Критерии успеха:**
- SSH/Winbox доступны из Management VLAN
- SSH/Winbox доступны из LAN (опционально)

---

## День 4-5: Важные исправления (P1)

### 3.1 Безопасное хранение Credentials

**Время:** 2-3 часа
**Риск:** Высокий (требует тщательного тестирования)

**Шаг 1: Создать файлы с credentials локально**

```bash
# На локальной машине
echo "your_pppoe_user" > ppp-user.txt
echo "your_pppoe_password" > ppp-pass.txt

# Генерировать сильные пароли для WiFi
openssl rand -base64 24 > wifi-pass.txt
openssl rand -base64 24 > wifi-guest-pass.txt

# Загрузить через SFTP (не оставит в истории)
sftp admin@192.168.1.1
put ppp-user.txt /
put ppp-pass.txt /
put wifi-pass.txt /
put wifi-guest-pass.txt /
quit

# Удалить локальные копии безопасно
shred -u ppp-user.txt ppp-pass.txt wifi-pass.txt wifi-guest-pass.txt
```

**Шаг 2: Изменить скрипты**

Для каждого файла с credentials, заменить hardcoded значения на чтение из файлов (см. детали в RECOMMENDATIONS.md).

**Шаг 3: Encrypted Backups**

```routeros
# Создать скрипт для автоматического encrypted backup
/system script add name=secure-backup \
    policy=read,write,ftp,sensitive \
    source={
        :local backupName ("backup-" . [/system clock get date])
        :local backupPass "YourVeryStrongBackupPassword123!"

        /system backup save name=$backupName \
            encryption=aes-sha256 \
            password=$backupPass

        /export file=$backupName

        :log info "Encrypted backup created: $backupName"
    }

# Scheduler
/system scheduler add name=daily-backup \
    interval=1d start-time=03:00:00 \
    on-event=secure-backup
```

---

### 3.2 SSH Hardening + Brute-Force Protection

```routeros
# SSH hardening
/ip ssh set strong-crypto=yes host-key-size=4096

# SYN flood protection
/ip settings set tcp-syncookies=yes

# Brute-force protection
# Загрузить 15-brute-force-protection.rsc (из RECOMMENDATIONS.md)
scp 15-brute-force-protection.rsc admin@192.168.1.1:/
/import 15-brute-force-protection.rsc

# Проверка
/ip firewall filter print where comment~"SSH:"
```

**Тестирование brute-force protection:**

```bash
# Попробовать неправильный пароль 4 раза
for i in {1..4}; do ssh wronguser@192.168.1.1; done

# После 4-й попытки - должен быть заблокирован
ssh admin@192.168.1.1  # Должен быть timeout
```

```routeros
# Проверить blacklist
/ip firewall address-list print where list="ssh_blacklist"

# Разблокировать свой IP если заблокировали случайно
/ip firewall address-list remove [find address=YOUR_IP]
```

---

## Неделя 2: Автоматизация

### 4.1 Подготовка Automation Container

**Шаг 1: Создать директории**

```routeros
# На роутере
/disk format-drive 0
# После перезагрузки:
/file print where type="directory"

# Создать структуру
:foreach dir in=("automation","automation/root","automation/scripts",\
"automation/playbooks","vault-data","git-configs") do={
    /file print file=("/disk1/$dir") where name="none"
}
```

**Шаг 2: Подготовить Dockerfile и скрипты**

См. AUTOMATION_ARCHITECTURE.md для полного содержимого.

**Шаг 3: Собрать образ**

```bash
# На машине с Docker
cd /path/to/automation-container
docker build -t mikrotik-automation:latest .

# Сохранить в tar
docker save mikrotik-automation:latest -o mikrotik-automation.tar

# Загрузить на роутер через USB или SFTP
scp mikrotik-automation.tar admin@192.168.1.1:/disk1/automation/
```

**Шаг 4: Загрузить образ в RouterOS**

```routeros
/container config set tmpdir=/disk1/tmp \
    registry-url=https://registry-1.docker.io

# Импортировать локальный образ
# (или использовать remote-image если образ в registry)
```

**Шаг 5: Создать container**

```routeros
# Загрузить 08b-automation-container.rsc
/import 08b-automation-container.rsc
```

---

### 4.2 Настройка Vault

**Внутри automation container:**

```bash
# Войти в контейнер
/container shell automation

# Инициализировать Vault
vault operator init

# Сохранить unseal keys и root token!!!

# Unseal Vault
vault operator unseal <KEY1>
vault operator unseal <KEY2>
vault operator unseal <KEY3>

# Войти
vault login <ROOT_TOKEN>

# Включить KV secrets engine
vault secrets enable -path=mikrotik kv-v2

# Сохранить credentials для роутеров
vault kv put mikrotik/r1-core \
    username="automation-bot" \
    password="$(openssl rand -base64 24)" \
    api_port="8728"

vault kv put mikrotik/r2-branch \
    username="automation-bot" \
    password="$(openssl rand -base64 24)"

# Создать automation policy
vault policy write automation - <<EOF
path "mikrotik/*" {
  capabilities = ["read", "list"]
}
EOF

# Создать token для Ansible
vault token create -policy=automation
# Сохранить токен для использования в Ansible!
```

---

### 4.3 Ansible Inventory и Playbooks

**Создать inventory файл** (см. AUTOMATION_ARCHITECTURE.md)

**Тестовый playbook:**

```yaml
# test-connection.yml
---
- name: Test connection to all routers
  hosts: all
  gather_facts: no

  tasks:
    - name: Get system resource
      community.routeros.command:
        commands:
          - /system resource print

    - name: Display result
      debug:
        var: ansible_facts
```

**Запуск:**

```bash
# Внутри automation container
cd /automation
ansible-playbook -i inventory/production.yml playbooks/test-connection.yml
```

---

## Неделя 3-4: Мониторинг и финализация

### 5.1 Prometheus + Grafana

См. AUTOMATION_ARCHITECTURE.md для docker-compose setup.

### 5.2 Telegram Bot для уведомлений

```python
# /automation/scripts/telegram-bot.py
import telegram
import os

TOKEN = os.getenv('TELEGRAM_BOT_TOKEN')
CHAT_ID = os.getenv('TELEGRAM_CHAT_ID')

def send_alert(message):
    bot = telegram.Bot(token=TOKEN)
    bot.send_message(chat_id=CHAT_ID, text=message)

if __name__ == '__main__':
    send_alert("✅ Automation system initialized!")
```

---

## Проверочный чек-лист

После завершения всех этапов проверьте:

### Безопасность
- [ ] IPv4 и IPv6 firewall настроены
- [ ] SSH strong-crypto включён
- [ ] Brute-force protection работает
- [ ] Контейнеры изолированы
- [ ] DNS resolver закрыт
- [ ] Credentials не в plain text
- [ ] Encrypted backups настроены

### Автоматизация
- [ ] Automation container запущен
- [ ] Vault работает и unseal
- [ ] Ansible может подключиться к всем роутерам
- [ ] Backup playbook работает
- [ ] Cert renewal работает

### Мониторинг
- [ ] Grafana показывает метрики
- [ ] Syslog собирает логи
- [ ] Telegram уведомления работают
- [ ] Health check скрипты запущены

### Документация
- [ ] Все пароли в password manager
- [ ] Runbooks обновлены
- [ ] Сетевая диаграмма актуальна
- [ ] Rollback план готов

---

## 📝 Changelog

### Version 1.2 (12 декабря 2025)
- ✅ Добавлен раздел "Фаза 5: WiFi CAPsMAN и WDS Bridge"
- ✅ Обновлены ссылки на готовые модули: `firewall_complete.rsc`, `nginx-certbot/`, `wifi/`
- ✅ Фаза 1 упрощена до 1 дня (вместо недели) благодаря готовым модулям
- ✅ Отмечено решение 3 критических проблем (CRIT-02, 03, 04)

### Version 1.0 (10 декабря 2025)
- ✅ Первая версия с пошаговым планом внедрения (4 недели)
- ✅ Детальные инструкции для каждой фазы
- ✅ Rollback планы для каждого этапа
- ✅ Проверочный чек-лист после завершения

---

**Следующие шаги:**
- См. `CONFIG_EXAMPLES/` для готовых конфигураций
- См. `README.md` для навигации по документации
- Для WiFi/WDS: см. `wifi/README.md` и `wifi/WDS-DEPLOYMENT-GUIDE.md`

**Конец руководства по внедрению**
