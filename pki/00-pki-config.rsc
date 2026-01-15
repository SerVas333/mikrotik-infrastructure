############################################################
# 00-pki-config.rsc - PKI SPECIFIC CONFIGURATION
#
# ВАЖНО: Этот файл ОПЦИОНАЛЕН!
# Все PKI переменные уже определены в 00-config.rsc
#
# Этот файл предназначен для:
# 1. Router-specific PKI overrides (если нужно)
# 2. Документации PKI configuration
# 3. Future extensibility
#
# Использование: /import pki/00-pki-config.rsc (optional)
############################################################

############################################################
# ROUTER-SPECIFIC OVERRIDES (опционально)
############################################################

# Пример: Переопределить Common Name для этого роутера
# :global cfgRouterCertName "site-b-router-cert"

# Пример: Переопределить validity для тестирования
# :global cfgRouterCertValidityDays 30  # 30 days для тестов

############################################################
# CERTIFICATE SUBJECT FIELDS
############################################################

# Subject fields для роутер сертификатов
# Эти значения будут использоваться в CSR generation

# Country (2-letter code)
:global cfgCertCountry "UA"

# State or Province
:global cfgCertState "Kyiv"

# Locality / City
:global cfgCertLocality "Kyiv"

# Organization
:global cfgCertOrganization "HomeNetwork"

# Organizational Unit
:global cfgCertOrganizationalUnit "Network Infrastructure"

# Email (optional, для CA contact)
:global cfgCertEmail "admin@example.local"

############################################################
# SUBJECT ALTERNATIVE NAME (SAN) CONFIGURATION
############################################################

# SAN будет генерироваться автоматически на основе:
# - Hostname ($cfgHostname)
# - LAN Gateway IP ($cfgLANGateway)
# - VTI IPs (если есть)
#
# Дополнительные SAN entries можно добавить здесь:
# :global cfgCertAdditionalSAN [:toarray "extra-dns-name.local,10.99.99.99"]

############################################################
# KEY USAGE CONFIGURATION
############################################################

# Key usage для router certificates
# - tls-server: Для HTTPS WebFig/API
# - tls-client: Для SSTP VPN client auth
# - ipsec-tunnel: Для IPsec IKEv2 authentication
# - ipsec-end-entity: Для IPsec end entity

:global cfgCertKeyUsage [:toarray "tls-server,tls-client,ipsec-tunnel"]

############################################################
# FTP CONNECTION SETTINGS
############################################################

# FTP timeout для upload/download операций
:global cfgFTPTimeout 60  # seconds

# FTP retry attempts
:global cfgFTPRetries 3

# Interval между retries
:global cfgFTPRetryInterval 10  # seconds

############################################################
# CERTIFICATE RENEWAL NOTIFICATIONS
############################################################

# Enable logging для renewal events
:global cfgCertRenewalLogging yes

# Enable logging для CA backup events
:global cfgCABackupLogging yes

# Log topics
:global cfgCertLogTopics "certificate,info"

############################################################
# CRL (CERTIFICATE REVOCATION LIST) ADVANCED
############################################################

# CRL update interval (если enabled)
:global cfgCRLUpdateInterval "7d"  # Weekly

# CRL distribution point (URL)
# :global cfgCRLDistributionPoint "http://192.168.1.1/pki/crl.pem"

############################################################
# DEBUGGING OPTIONS
############################################################

# Verbose logging для troubleshooting
:global cfgPKIDebugMode no

# Keep CSR files after signing
:global cfgPKIKeepCSRFiles no

############################################################
# END OF PKI CONFIGURATION
############################################################

:log info "PKI configuration loaded (pki/00-pki-config.rsc)"
:log info "PKI settings can be overridden on per-router basis"
