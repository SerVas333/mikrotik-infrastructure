# Архитектура автоматизации управления MikroTik

**Дата:** 10 декабря 2025
**Последнее обновление:** 12 декабря 2025
**Версия:** 1.2 (проверено на совместимость)
**Подход:** Container-based automation на Core роутере
**Предварительное чтение:** SECURITY_AUDIT.md, RECOMMENDATIONS.md

**Статус v1.2:**
- ✅ Архитектура актуальна и совместима с новыми модулями
- ✅ Интеграция с `nginx-certbot/` модулем
- ✅ Поддержка WiFi CAPsMAN и WDS Bridge автоматизации

---

## Оглавление

1. [Обзор архитектуры](#обзор-архитектуры)
2. [Компоненты системы](#компоненты-системы)
3. [Automation Container](#automation-container)
4. [Управление несколькими роутерами](#управление-несколькими-роутерами)
5. [Безопасность automation](#безопасность-automation)
6. [Примеры автоматизации](#примеры-автоматизации)

---

## Обзор архитектуры

### Концепция

Один из роутеров (R1-Core) становится **automation hub**, запуская специальный контейнер с инструментами управления для всей сети MikroTik.

```
┌────────────────────────────────────────────────────────────────┐
│ R1-Core Router (192.168.1.1)                                  │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Automation Container (10.11.0.20)                       │ │
│  │                                                          │ │
│  │  ┌──────────┬───────────┬──────────┬─────────────────┐ │ │
│  │  │ Ansible  │  Python   │   Git    │  HashiCorp      │ │ │
│  │  │  Core    │  Scripts  │   Repo   │   Vault         │ │ │
│  │  └──────────┴───────────┴──────────┴─────────────────┘ │ │
│  │                                                          │ │
│  │  ┌──────────┬───────────┬──────────┬─────────────────┐ │ │
│  │  │ Grafana  │Prometheus │  Syslog  │  Notification   │ │ │
│  │  │  Dash    │  Metrics  │  Server  │    Bot          │ │ │
│  │  └──────────┴───────────┴──────────┴─────────────────┘ │ │
│  └──────────────────────────────────────────────────────────┘ │
│                          ↓ API (8728/8729)                     │
└────────────────────────────────────────────────────────────────┘
              │                   │                    │
              ↓                   ↓                    ↓
    ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
    │  R2-Branch      │  │  R3-Remote      │  │  R4-Backup      │
    │  (via VPN/API)  │  │  (via VPN/API)  │  │  (via VPN/API)  │
    └─────────────────┘  └─────────────────┘  └─────────────────┘
```

### Преимущества Container-based подхода

✅ **Простота развёртывания** - всё в одном месте
✅ **Низкая стоимость** - не требует отдельного сервера
✅ **Централизованное управление** - один контейнер контролирует все роутеры
✅ **Интеграция** - контейнер работает в той же сети

⚠️ **Компромиссы по безопасности:**
- Контейнер на том же устройстве, которым управляет
- Требует тщательной изоляции
- Не подходит для enterprise (там нужен dedicated server)

---

## Компоненты системы

### 1. Automation Container

**Образ:** Custom Alpine Linux с предустановленными инструментами

**Включает:**
- Ansible + RouterOS collection
- Python 3.11 + librouteros
- HashiCorp Vault (secret management)
- Git (версионирование конфигов)
- Prometheus + Grafana (мониторинг)
- Rsyslog (централизованные логи)
- Telegram Bot (уведомления)

**Ресурсы:**
- Memory limit: 512MB
- CPU: не ограничен
- Storage: `/disk1/automation` (5GB+)

### 2. Хранилище секретов (Vault)

**HashiCorp Vault** - индустриальный стандарт для управления секретами.

**Хранит:**
- Пароли для всех роутеров (API access)
- SSH ключи
- WiFi паролей
- Сертификаты

**Интеграция:**
- Ansible читает credentials из Vault
- Python скрипты используют Vault API
- Автоматическая ротация секретов

### 3. Configuration Repository (Git)

**GitLab/GitHub** - версионирование конфигураций

**Структура репозитория:**
```
mikrotik-configs/
├── inventory/
│   ├── production.yml          # Список роутеров
│   └── group_vars/
│       ├── all.yml              # Общие переменные
│       ├── core_routers.yml     # Переменные для core роутеров
│       └── branch_routers.yml
├── playbooks/
│   ├── deploy-firewall.yml      # Обновление firewall
│   ├── update-certificates.yml  # Обновление сертификатов
│   ├── backup-all.yml           # Backup всех роутеров
│   └── emergency-lockdown.yml   # Emergency security
├── roles/
│   ├── base-security/
│   ├── firewall/
│   ├── wifi/
│   └── monitoring/
├── configs/
│   ├── r1-core/
│   ├── r2-branch/
│   ├── r3-remote/
│   └── r4-backup/
└── scripts/
    ├── cert-renewal.py
    ├── health-check.py
    └── alert-handler.py
```

### 4. Monitoring Stack

**Prometheus** - сбор метрик
**Grafana** - визуализация
**MikroTik Exporter** - экспорт метрик из RouterOS

**Метрики:**
- CPU/Memory/Disk
- Network throughput
- Firewall packet counts
- BGP session status
- VPN tunnels status
- Container health

### 5. Notification System

**Telegram Bot** - уведомления в реальном времени

**Типы уведомлений:**
- 🔴 CRITICAL: Роутер недоступен, VPN down
- 🟡 WARNING: Высокая CPU нагрузка, disk space < 1GB
- 🟢 INFO: Backup завершён, сертификаты обновлены
- 📊 REPORT: Ежедневный summary

---

## Automation Container

### Конфигурация роутера для Automation

**Файл: `08b-automation-container.rsc`**

```routeros
# ===================================================================
# 08b-automation-container.rsc
# Automation & Management Container
# Manages all MikroTik routers in the network
# ===================================================================

:local AUTOMATION_IP "10.11.0.20"
:local AUTOMATION_GW "10.11.0.1"
:local CONTAINER_NET "containers"
:local AUTOMATION_ROOT "/disk1/automation"
:local VAULT_DATA "/disk1/vault-data"
:local CONFIGS_REPO "/disk1/git-configs"

# ===================================================================
# Create mounts for automation container
# ===================================================================

/container mount
add name=mount-automation-data \
    src=$AUTOMATION_ROOT dst=/automation \
    comment="Automation scripts and data"

add name=mount-vault \
    src=$VAULT_DATA dst=/vault/data \
    comment="Vault secret storage"

add name=mount-configs \
    src=$CONFIGS_REPO dst=/configs \
    comment="Git repository with configs"

# ===================================================================
# Create automation container
# ===================================================================

# Custom image with all tools pre-installed
# Build instructions in /disk1/automation/Dockerfile
/container add name=automation \
    interface=$CONTAINER_NET \
    root-dir=$AUTOMATION_ROOT/root \
    mounts=mount-automation-data,mount-vault,mount-configs \
    start-on-boot=yes \
    remote-image=localhost/mikrotik-automation:latest \
    memory-high=512M \
    comment="Automation & Management Container"

# ===================================================================
# Network configuration for automation container
# ===================================================================

# Static IP via container network
# (Automation container будет получать 10.11.0.20)

# ===================================================================
# Firewall rules for automation container
# ===================================================================

/ip firewall filter

# 1. Разрешить automation container доступ к API ВСЕХ роутеров
add chain=forward src-address=$AUTOMATION_IP \
    protocol=tcp dst-port=8728,8729 \
    action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Automation: API access to routers"

# 2. Разрешить SSH для git operations
add chain=forward src-address=$AUTOMATION_IP \
    protocol=tcp dst-port=22,443 \
    action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Automation: Git/HTTPS access"

# 3. Разрешить Prometheus scraping (если exporters на роутерах)
add chain=forward src-address=$AUTOMATION_IP \
    protocol=tcp dst-port=9436 \
    action=accept \
    place-before=[find comment="Block containers -> LAN"] \
    comment="Automation: Prometheus scraping"

# 4. Разрешить получение syslog от других роутеров
add chain=input protocol=udp dst-port=514 \
    dst-address=$AUTOMATION_IP \
    action=accept \
    comment="Allow syslog to automation container"

# 5. Разрешить доступ к Grafana dashboard из Management VLAN
/ip firewall nat
add chain=dstnat in-interface=bridge-lan \
    src-address=172.16.99.0/24 \
    protocol=tcp dst-port=3000 \
    action=dst-nat to-addresses=$AUTOMATION_IP to-ports=3000 \
    comment="Grafana dashboard for management"

:log info "Automation container configured"

# ===================================================================
# API User для automation на ЭТОМ роутере
# ===================================================================

# Создать dedicated automation user с минимальными правами
/user group add name=automation-api \
    policy=api,read,write,policy,test,ftp,reboot

/user add name=automation-bot \
    group=automation-api \
    password="CHANGE_ME_FROM_VAULT" \
    comment="Ansible automation account (password from Vault)"

# ===================================================================
# Start automation container
# ===================================================================

/container start automation

:delay 10s

# Проверить статус
:if ([/container get automation status] = "running") do={
    :log info "Automation container started successfully"
} else={
    :log error "Automation container failed to start!"
}
```

### Dockerfile для Automation Container

**Файл: `/disk1/automation/Dockerfile`**

```dockerfile
FROM alpine:3.19

# Install base packages
RUN apk add --no-cache \
    python3 \
    py3-pip \
    ansible \
    git \
    openssh-client \
    curl \
    bash \
    ca-certificates \
    tzdata

# Install Python packages
RUN pip3 install --no-cache-dir \
    librouteros \
    hvac \
    prometheus-client \
    python-telegram-bot \
    requests \
    pyyaml

# Install Ansible RouterOS collection
RUN ansible-galaxy collection install \
    community.routeros

# Install HashiCorp Vault
RUN wget https://releases.hashicorp.com/vault/1.15.4/vault_1.15.4_linux_amd64.zip && \
    unzip vault_1.15.4_linux_amd64.zip && \
    mv vault /usr/local/bin/ && \
    rm vault_1.15.4_linux_amd64.zip

# Install Prometheus & Grafana (via Docker-in-Docker or separate containers)
# Или использовать отдельные контейнеры для Grafana/Prometheus

# Setup automation user
RUN adduser -D -h /automation automation

# Setup directories
RUN mkdir -p /vault/data /configs /automation/scripts /automation/playbooks

# Copy automation scripts
COPY scripts/ /automation/scripts/
COPY playbooks/ /automation/playbooks/
COPY ansible.cfg /automation/

# Setup cron jobs
COPY crontab /etc/crontabs/automation

WORKDIR /automation
USER automation

# Entrypoint script
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

# Default: keep container running
CMD ["tail", "-f", "/dev/null"]
```

**Файл: `/disk1/automation/entrypoint.sh`**

```bash
#!/bin/bash
set -e

echo "[$(date)] Starting Automation Container..."

# Start Vault server (if not using separate container)
if [ -f /vault/config.hcl ]; then
    echo "[$(date)] Starting Vault..."
    vault server -config=/vault/config.hcl &
    sleep 5
fi

# Start rsyslog for centralized logging
if [ -f /etc/rsyslog.conf ]; then
    echo "[$(date)] Starting rsyslog..."
    rsyslogd
fi

# Initialize Git repository (if not exists)
if [ ! -d /configs/.git ]; then
    echo "[$(date)] Initializing Git repository..."
    cd /configs
    git init
    git config user.name "Automation Bot"
    git config user.email "automation@mikrotik.local"
fi

# Run startup health check
echo "[$(date)] Running startup health check..."
python3 /automation/scripts/health-check.py || true

# Start cron daemon
crond -l 2 -f &

echo "[$(date)] Automation container ready!"

# Execute CMD from Dockerfile
exec "$@"
```

---

## Управление несколькими роутерами

### Inventory файл

**`/disk1/automation/inventory/production.yml`**

```yaml
all:
  children:
    core_routers:
      hosts:
        r1-core:
          ansible_host: 192.168.1.1
          router_id: 1.1.1.1
          location: datacenter
          role: core

        r2-branch:
          ansible_host: 192.168.1.2  # через VPN/local network
          router_id: 2.2.2.2
          location: branch-office
          role: branch

    edge_routers:
      hosts:
        r3-remote:
          ansible_host: 10.200.200.2  # через WireGuard VPN
          router_id: 3.3.3.3
          location: remote-site
          role: edge

        r4-backup:
          ansible_host: 192.168.1.4
          router_id: 4.4.4.4
          location: datacenter
          role: backup

  vars:
    # Ansible connection settings
    ansible_connection: local  # Используем Python API, не SSH
    ansible_python_interpreter: /usr/bin/python3

    # RouterOS API settings
    routeros_api_port: 8728
    routeros_api_ssl: false  # Или 8729 с SSL

    # Credentials from Vault
    ansible_user: "{{ lookup('hashi_vault', 'secret=mikrotik/data/{{ inventory_hostname }}:username') }}"
    ansible_password: "{{ lookup('hashi_vault', 'secret=mikrotik/data/{{ inventory_hostname }}:password') }}"
```

### Ansible Playbook: Backup всех роутеров

**`/disk1/automation/playbooks/backup-all.yml`**

```yaml
---
- name: Backup all MikroTik routers
  hosts: all
  gather_facts: no

  tasks:
    - name: Create backup filename
      set_fact:
        backup_name: "{{ inventory_hostname }}-{{ ansible_date_time.iso8601_basic_short }}"

    - name: Create encrypted backup
      community.routeros.command:
        commands:
          - /system backup save name={{ backup_name }} encryption=aes-sha256 password={{ vault_backup_password }}

    - name: Export configuration
      community.routeros.command:
        commands:
          - /export file={{ backup_name }}

    - name: Download backup file
      community.routeros.api:
        path: /file
        query: ".id name={{ backup_name }}.backup"
      register: backup_file

    - name: Fetch backup to automation container
      ansible.builtin.fetch:
        src: "{{ backup_name }}.backup"
        dest: "/automation/backups/{{ inventory_hostname }}/"
        flat: yes

    - name: Send success notification
      ansible.builtin.uri:
        url: "{{ telegram_webhook_url }}"
        method: POST
        body_format: json
        body:
          chat_id: "{{ telegram_chat_id }}"
          text: "✅ Backup успешно создан для {{ inventory_hostname }}"
```

### Python скрипт: Автоматическое обновление сертификатов

**`/disk1/automation/scripts/cert-renewal.py`**

```python
#!/usr/bin/env python3
"""
Автоматическое обновление сертификатов на всех роутерах
Запускается по cron ежедневно
"""

import librouteros
from librouteros import connect
import hvac
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class CertificateManager:
    def __init__(self, vault_url='http://127.0.0.1:8200', vault_token=None):
        """Initialize with Vault connection"""
        self.vault = hvac.Client(url=vault_url, token=vault_token)
        self.routers = self.get_router_list()

    def get_router_list(self):
        """Get list of routers from inventory"""
        # В production: парсить Ansible inventory
        return [
            {'name': 'r1-core', 'host': '192.168.1.1'},
            {'name': 'r2-branch', 'host': '192.168.1.2'},
            {'name': 'r3-remote', 'host': '10.200.200.2'},
        ]

    def get_credentials(self, router_name):
        """Get credentials from Vault"""
        secret = self.vault.secrets.kv.v2.read_secret_version(
            path=f'mikrotik/data/{router_name}'
        )
        return secret['data']['data']

    def check_certificate(self, router_name, router_host):
        """Check certificate expiry on router"""
        creds = self.get_credentials(router_name)

        try:
            api = connect(
                host=router_host,
                username=creds['username'],
                password=creds['password'],
                port=int(creds.get('api_port', 8728))
            )

            # Get certificates
            cert_path = api.path('/certificate')
            for cert in cert_path:
                if cert.get('name', '').startswith('letsencrypt'):
                    days_left = int(cert.get('days-to-expiry', 999))

                    logger.info(f"{router_name}: Certificate {cert['name']} expires in {days_left} days")

                    # Обновить если осталось меньше 30 дней
                    if days_left < 30:
                        logger.warning(f"{router_name}: Certificate needs renewal!")
                        self.renew_certificate(api, router_name)
                        return True

            api.close()
            return False

        except Exception as e:
            logger.error(f"{router_name}: Failed to check certificate: {e}")
            self.send_alert(f"❌ {router_name}: Не удалось проверить сертификат")
            return False

    def renew_certificate(self, api, router_name):
        """Trigger certificate renewal"""
        logger.info(f"{router_name}: Triggering certificate renewal...")

        try:
            # Запустить скрипт обновления на роутере
            script_path = api.path('/system/script')
            script_path('run', **{'_name': 'certbot-renew'})

            logger.info(f"{router_name}: Certificate renewal triggered successfully")
            self.send_alert(f"✅ {router_name}: Сертификат обновлён")

        except Exception as e:
            logger.error(f"{router_name}: Failed to renew certificate: {e}")
            self.send_alert(f"❌ {router_name}: Ошибка обновления сертификата")

    def send_alert(self, message):
        """Send Telegram alert"""
        # Implement Telegram bot notification
        logger.info(f"ALERT: {message}")

    def run(self):
        """Main execution"""
        logger.info("Starting certificate check for all routers...")

        renewed = 0
        failed = 0

        for router in self.routers:
            try:
                if self.check_certificate(router['name'], router['host']):
                    renewed += 1
            except Exception as e:
                logger.error(f"{router['name']}: Error: {e}")
                failed += 1

        logger.info(f"Certificate check complete: {renewed} renewed, {failed} failed")

if __name__ == '__main__':
    # Get Vault token from environment
    import os
    vault_token = os.getenv('VAULT_TOKEN')

    manager = CertificateManager(vault_token=vault_token)
    manager.run()
```

### Crontab для автоматизации

**`/disk1/automation/crontab`**

```cron
# MikroTik Automation Cron Jobs

# Daily backup at 03:00
0 3 * * * cd /automation && ansible-playbook playbooks/backup-all.yml >> /automation/logs/backup.log 2>&1

# Certificate check daily at 04:00
0 4 * * * python3 /automation/scripts/cert-renewal.py >> /automation/logs/cert-renewal.log 2>&1

# Health check every 5 minutes
*/5 * * * * python3 /automation/scripts/health-check.py >> /automation/logs/health.log 2>&1

# Sync configs to Git every hour
0 * * * * cd /configs && git add . && git commit -m "Auto-sync $(date)" && git push >> /automation/logs/git-sync.log 2>&1

# Weekly security audit
0 2 * * 0 python3 /automation/scripts/security-audit.py >> /automation/logs/security.log 2>&1

# Daily report at 09:00
0 9 * * * python3 /automation/scripts/daily-report.py >> /automation/logs/report.log 2>&1
```

---

## Безопасность Automation

### Принципы безопасной автоматизации

1. **Least Privilege**
   - Automation user имеет только необходимые права
   - Разные пользователи для разных задач (backup, deploy, monitoring)

2. **Network Segmentation**
   - Automation container изолирован firewall
   - Доступ ТОЛЬКО к API портам роутеров
   - НЕ имеет доступа к пользовательским VLAN

3. **Secret Management**
   - Все credentials в Vault
   - Ротация паролей каждые 90 дней
   - Audit log всех обращений к секретам

4. **Audit & Logging**
   - Все действия логируются
   - Централизованный syslog
   - Алерты на подозрительную активность

5. **Change Management**
   - Все изменения через Git (GitOps)
   - Review process для critical changes
   - Rollback plan для каждого деплоя

### Firewall для Automation Container

```routeros
# Детальные правила для automation container

# Разрешить ТОЛЬКО API доступ к роутерам
/ip firewall filter
add chain=forward src-address=10.11.0.20 \
    dst-address-list=mikrotik-routers \
    protocol=tcp dst-port=8728,8729 \
    action=accept \
    comment="Automation: API to routers ONLY"

# Создать address-list со всеми роутерами
/ip firewall address-list
add list=mikrotik-routers address=192.168.1.1 comment="R1-Core"
add list=mikrotik-routers address=192.168.1.2 comment="R2-Branch"
add list=mikrotik-routers address=10.200.200.2 comment="R3-Remote (via VPN)"
add list=mikrotik-routers address=192.168.1.4 comment="R4-Backup"

# Разрешить Git/HTTPS
add chain=forward src-address=10.11.0.20 \
    protocol=tcp dst-port=22,443 \
    dst-address-list=!mikrotik-routers \
    action=accept \
    comment="Automation: Git/HTTPS (external only)"

# Блокировать всё остальное
add chain=forward src-address=10.11.0.20 \
    action=drop \
    comment="Automation: block all other"

# Логировать попытки доступа к чему-то ещё
add chain=forward src-address=10.11.0.20 \
    action=log log-prefix="AUTOMATION-BLOCK: " \
    place-before=[find comment="Automation: block all other"]
```

---

## 📝 Changelog

### Version 1.2 (12 декабря 2025)
- ✅ Проверена совместимость с новыми модулями (firewall_complete.rsc, nginx-certbot/, wifi/)
- ✅ Добавлена информация о поддержке WiFi CAPsMAN и WDS Bridge
- ✅ Архитектура остаётся актуальной

### Version 1.0 (10 декабря 2025)
- ✅ Первая версия архитектуры container-based автоматизации
- ✅ Интеграция с Vault, Ansible, Prometheus, Grafana
- ✅ Примеры Dockerfile и Python скриптов

---

**Продолжение в IMPLEMENTATION_GUIDE.md**

*Следующий документ: пошаговое руководство по внедрению автоматизации*
