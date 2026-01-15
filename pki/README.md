# MikroTik PKI Infrastructure
## Certificate Authority для 4-10 роутеров

**Версия:** 1.0
**Создано:** 17 декабря 2025
**Статус:** Production Ready

---

## 📋 EXECUTIVE SUMMARY

Полноценная PKI (Public Key Infrastructure) для MikroTik сети с:
- **Certificate Authority на R1-Core** (главный роутер)
- **Автоматическое распространение** сертификатов через FTP
- **ECDSA P-256** ключи (современная криптография)
- **Auto-renewal** за 30 дней до истечения (срок действия: 2 года)
- **VPN Bootstrap support** для роутеров за VPN (PSK → Certificates migration)

### Применение сертификатов

1. ✅ **IPsec IKEv2 Site-to-Site** - замена PSK на certificate auth
2. ✅ **SSTP VPN** - remote access VPN
3. ✅ **HTTPS WebFig/API** - secure management interface

---

## 🎯 KEY FEATURES

### Cryptography

**Certificate Authority (CA):**
- Key Type: ECDSA P-384 (эллиптическая кривая)
- Validity: 10 years (3650 days)
- Self-signed root certificate

**Router Certificates:**
- Key Type: ECDSA P-256
- Validity: 2 years (730 days)
- Subject Alternative Names (SAN): DNS + IP addresses
- Key Usage: tls-server, tls-client, ipsec-tunnel

### Distribution

**FTP Auto-Distribution:**
- CA runs FTP server (port 21)
- CSR upload: роутеры → CA
- Certificate download: CA → роутеры
- Access control:
  - ✅ LAN (192.168.1.0/24)
  - ✅ VPN tunnels (VTI интерфейсы)
  - ❌ WAN (blocked)

### Auto-Renewal

- Daily check (at 03:00)
- Renewal trigger: 30 days before expiry
- Zero-downtime certificate rotation
- Automatic service reconfiguration

### VPN Bootstrap Support

**Problem:** Роутеры за VPN нуждаются в сертификатах, но для IPsec с сертификатами нужны... сертификаты!

**Solution:** PSK → Certificate Migration
1. Initial VPN setup с PSK
2. Certificate acquisition через VPN tunnel (FTP over VPN)
3. Dual auth setup (PSK + Cert)
4. Migration к certificate-only auth
5. Optional PSK cleanup

---

## 🏗️ ARCHITECTURE

```
┌─────────────────────────────────────────────────────────────────┐
│    R1-Core (192.168.1.1) - CERTIFICATE AUTHORITY                │
│                                                                  │
│  • Root CA Certificate (ECDSA P-384, 10 years)                  │
│  • FTP Server (port 21)                                         │
│    - LAN access: 192.168.1.1:21                                 │
│    - VPN access: через VTI IPs                                  │
│  • Auto-signing scheduler (каждые 5 минут)                      │
│  • Encrypted CA backup                                          │
└────────────┬────────────────────────────┬───────────────────────┘
             │                            │
   ┌─────────┴──────────┐    ┌───────────┴────────────┐
   │ LAN (direct)       │    │ VPN (IPsec/WireGuard)  │
   ▼                    ▼    ▼                        ▼
┌────────────┐   ┌──────────────────┐       ┌──────────────────┐
│ R1-Self    │   │  R2-Branch       │◄─VPN─►│  R3-Branch       │
│ (local)    │   │  (10.21.0.0/24)  │(PSK→  │  (10.22.0.0/24)  │
│            │   │  VTI: 10.12.0.2  │Cert)  │  VTI: 10.13.0.2  │
│ Direct     │   │                  │       │                  │
│ FTP access │   │ • ECDSA P-256    │       │ • ECDSA P-256    │
└────────────┘   │ • FTP via VPN    │       │ • FTP via VPN    │
                 │ • Auto-renewal   │       │ • Auto-renewal   │
                 └──────────────────┘       └──────────────────┘
```

---

## 📂 FILE STRUCTURE

```
pki/
├── README.md                          # This file
├── 00-pki-config.rsc                  # PKI configuration variables
│
├── ca/                                # CA-specific (R1-Core only)
│   ├── 01-ca-setup.rsc                # Root CA creation
│   ├── 02-ca-ftp-server.rsc           # FTP server + firewall
│   └── 03-ca-auto-sign.rsc            # Auto-signing scheduler
│
├── router/                            # Router-specific (all routers)
│   ├── 10-router-cert-gen.rsc         # CSR generation (ECDSA P-256)
│   ├── 11-router-ftp-upload.rsc       # FTP upload CSR / download cert
│   ├── 12-router-cert-import.rsc      # Import signed certificate
│   └── 13-router-auto-renewal.rsc     # Auto-renewal scheduler
│
└── services/                          # Service configuration
    ├── 20-ipsec-cert-auth.rsc         # IPsec with certificates
    └── 25-ipsec-psk-to-cert-migration.rsc  # PSK → Cert migration
```

---

## 🚀 DEPLOYMENT GUIDE

### Prerequisites

1. **RouterOS 7.x** на всех роутерах
2. **00-config.rsc и 00-secrets.rsc** настроены
3. **Network connectivity** между роутерами:
   - LAN роутеры: прямой доступ к R1-Core
   - VPN роутеры: IPsec или WireGuard tunnel с PSK (для bootstrap)

### Phase 1: CA Setup на R1-Core

**На R1-Core (192.168.1.1):**

```routeros
# 1. Import configuration files
/import 00-config.rsc
/import 00-secrets.rsc
/import pki/00-pki-config.rsc

# 2. Create Root CA
/import pki/ca/01-ca-setup.rsc

# ВАЖНО: Немедленно скачать CA backup!
```

**На локальной машине:**

```bash
# Download CA backup (КРИТИЧЕСКИ ВАЖНО!)
scp admin@192.168.1.1:ca-root-backup.p12 ~/secure-backup/

# Download CA root certificate для distribution
scp admin@192.168.1.1:ca-root.crt ~/pki-distribution/
```

**На R1-Core (продолжение):**

```routeros
# 3. Setup FTP server
/import pki/ca/02-ca-ftp-server.rsc

# 4. Setup auto-signing
/import pki/ca/03-ca-auto-sign.rsc

# 5. Generate R1-Core own certificate
/import pki/router/10-router-cert-gen.rsc
/import pki/router/11-router-ftp-upload.rsc
/import pki/router/12-router-cert-import.rsc
/import pki/router/13-router-auto-renewal.rsc
```

### Phase 2: LAN Routers Deployment

**Для роутеров с прямым LAN доступом к R1-Core:**

**На локальной машине:**

```bash
# Copy PKI modules to router
scp -r pki/ admin@192.168.1.x:/
scp ~/pki-distribution/ca-root.crt admin@192.168.1.x:/
```

**На роутере:**

```routeros
# 1. Import CA root certificate
/certificate import file-name=ca-root.crt
/certificate set ca-root trusted=yes

# 2. Import PKI config
/import pki/00-pki-config.rsc

# 3. Certificate workflow
/import pki/router/10-router-cert-gen.rsc   # Generate CSR
/import pki/router/11-router-ftp-upload.rsc # Upload & download
/import pki/router/12-router-cert-import.rsc # Import certificate
/import pki/router/13-router-auto-renewal.rsc # Setup auto-renewal

# 4. Configure services (optional)
/import pki/services/20-ipsec-cert-auth.rsc  # If using IPsec
```

### Phase 3: VPN Routers Deployment (Site B, Site C, etc.)

**КРИТИЧЕСКИ ВАЖНО:** VPN tunnel с PSK должен быть уже установлен!

**Verify VPN connectivity:**

```routeros
# На VPN роутере (Site B)
/ip ipsec active-peers print
# Должно быть: ph2-state=established

/ping 192.168.1.1 count=5
# Должно быть: 0% loss
```

**Bootstrap workflow:**

```bash
# На локальной машине: Copy files через VPN
scp -r pki/ admin@10.21.0.1:/
scp ~/pki-distribution/ca-root.crt admin@10.21.0.1:/
```

**На VPN роутере:**

```routeros
# 1. Import CA root
/certificate import file-name=ca-root.crt
/certificate set ca-root trusted=yes

# 2. Import PKI config
/import pki/00-pki-config.rsc

# 3. Certificate workflow (через VPN tunnel!)
/import pki/router/10-router-cert-gen.rsc
/import pki/router/11-router-ftp-upload.rsc   # FTP через VPN
/import pki/router/12-router-cert-import.rsc

# 4. MIGRATION: PSK → Certificate
/import pki/services/25-ipsec-psk-to-cert-migration.rsc

# Verify tunnel с certificate auth
/ip ipsec active-peers print
/ip ipsec identity print

# 5. Setup auto-renewal
/import pki/router/13-router-auto-renewal.rsc
```

---

## ✅ VERIFICATION & TESTING

### Test 1: CA Functionality

**На R1-Core:**

```routeros
# Check CA certificate
/certificate print where name~"MikroTik-Root-CA"
# Expected: status=valid, trusted=yes

# Check auto-signing scheduler
/system scheduler print where name~"pki-ca-auto-sign"
# Expected: interval=5m, next-run=...

# Check auto-signing logs
/log print where message~"CA Auto-Sign"
```

### Test 2: Router Certificate

**На любом роутере:**

```routeros
# Check router certificate
/certificate print detail where name~"router-cert"
# Expected:
# - Key type: ECDSA P-256
# - Issuer: MikroTik-Root-CA
# - Status: valid
# - Days left: ~730

# Check certificate chain
/certificate print
# Expected: Both CA and router cert present, both valid
```

### Test 3: IPsec с Certificates

**Между двумя роутерами с certificates:**

```routeros
# Check IPsec identity
/ip ipsec identity print
# Expected: auth-method=rsa-signature

# Check active tunnel
/ip ipsec active-peers print
# Expected: uptime=..., ph2-state=established

# Ping remote VTI
/ping 10.12.0.2 count=5
# Expected: 0% packet loss

# Check logs
/log print where topics~"ipsec"
# Expected: No authentication errors
```

### Test 4: HTTPS WebFig

**В браузере:**

```
https://192.168.1.1/
```

**Expected:**
- ✅ No browser warning (если CA root установлен на клиенте)
- ✅ Certificate issued by "MikroTik-Root-CA"
- ✅ Algorithm: ECDSA P-256

**Install CA root на клиенте (для no warnings):**

**Windows:**
1. Download `ca-root.crt` from R1-Core
2. Double-click → Install Certificate
3. Store Location: Local Machine
4. Place in: Trusted Root Certification Authorities

**macOS:**
1. Double-click `ca-root.crt`
2. Keychain Access → System
3. Trust → Always Trust

**Linux:**
```bash
sudo cp ca-root.crt /usr/local/share/ca-certificates/mikrotik-ca.crt
sudo update-ca-certificates
```

### Test 5: Auto-Renewal

**Manual trigger test:**

```routeros
# Trigger renewal script manually
/system script run cert-auto-renewal

# Check logs
/log print where message~"Renewal"

# For full test: temporarily reduce certificate validity
# (not recommended for production)
```

### Test 6: FTP Distribution

**На любом роутере:**

```routeros
# Test FTP access to CA
/tool fetch mode=ftp address=192.168.1.1 \
    user=pki-admin password=<ftp-pass> \
    src-path=/ dst-path=ftp-test.txt

# Expected: Success (or list of files)
```

---

## 🐛 TROUBLESHOOTING

### Problem: CA setup fails

**Symptoms:** CA certificate не создается или invalid

**Checks:**
```routeros
/log print where topics~"certificate,error"
/certificate print
```

**Solutions:**
1. Verify `00-config.rsc` imported correctly
2. Check `secCAKeyPassphrase` in `00-secrets.rsc`
3. Ensure ECDSA support (RouterOS 7.x)
4. Delete existing CA and recreate:
   ```routeros
   /certificate remove [find name~"MikroTik-Root-CA"]
   /import pki/ca/01-ca-setup.rsc
   ```

### Problem: FTP upload fails

**Symptoms:** CSR не загружается на CA

**Checks:**
```routeros
# On router
/ping 192.168.1.1 count=5

# On CA
/ip service print where name=ftp
/ip firewall filter print where dst-port=21
/user print where name~"pki-admin"
```

**Solutions:**
1. Check network connectivity
2. Verify FTP service enabled on CA
3. Check firewall allows FTP from router
4. Verify FTP credentials in `00-secrets.rsc`
5. For VPN routers: ensure VPN tunnel active

### Problem: Auto-signing не работает

**Symptoms:** Signed certificate не появляется

**Checks:**
```routeros
# On CA
/system scheduler print where name~"pki-ca-auto-sign"
/log print where message~"CA Auto-Sign"
/file print where name~"pki/csr-inbox"
```

**Solutions:**
1. Verify scheduler running: `/system scheduler print`
2. Check CSR uploaded correctly: `/file print`
3. Manual trigger: `/system script run ca-auto-sign-csr`
4. Check logs for errors

### Problem: IPsec tunnel не устанавливается с certificates

**Symptoms:** `ph2-state` не `established`

**Checks:**
```routeros
/ip ipsec identity print
/ip ipsec peer print
/log print where topics~"ipsec,error"
/certificate print
```

**Solutions:**
1. Verify both sides have valid certificates
2. Check certificate chain: CA cert trusted on both sides
3. Verify identity uses `auth-method=rsa-signature`
4. Check firewall allows UDP 500, 4500, ESP
5. Rollback to PSK if needed:
   ```routeros
   /ip ipsec identity add peer=<peer-name> \
       auth-method=pre-shared-key secret=<psk>
   ```

### Problem: Auto-renewal fails

**Symptoms:** Certificate expires, renewal не срабатывает

**Checks:**
```routeros
/system scheduler print where name~"pki-cert-renewal-check"
/log print where message~"Renewal"
/certificate print where name~"router-cert"
```

**Solutions:**
1. Verify scheduler running daily
2. Check FTP access to CA
3. Manual renewal: `/system script run cert-auto-renewal`
4. Check certificate days-valid threshold

### Problem: VPN bootstrap fails (PSK → Cert migration)

**Symptoms:** Tunnel drops после migration

**Checks:**
```routeros
/ip ipsec active-peers print
/ip ipsec identity print
/log print where topics~"ipsec"
```

**Solutions:**
1. **Rollback immediately:**
   ```routeros
   /ip ipsec identity remove [find where auth-method=rsa-signature]
   ```
2. Wait 30-60 seconds for tunnel re-establishment with PSK
3. Verify certificate valid before retry
4. Use dual auth (keep both PSK and Cert) until verified

---

## 🔐 SECURITY CONSIDERATIONS

### CA Private Key Protection

**КРИТИЧЕСКИ ВАЖНО:**
- ✅ CA private key - единственная копия для всей сети
- ✅ Encrypted backup с сильной passphrase (min 32 chars)
- ✅ Offline storage (USB drive, safe location)
- ✅ НЕ хранить на роутере после backup
- ✅ Passphrase в password manager (KeePass, 1Password)

**CA Backup Location:**
```
~/secure-backup/ca-root-backup.p12
```

**Recovery Procedure:**
```routeros
# If CA lost, import backup
/certificate import file-name=ca-root-backup.p12 \
    passphrase=<secCAKeyPassphrase>

# Set as trusted
/certificate set ca-root trusted=yes
```

### FTP Security

**Current Implementation:**
- ✅ FTP only for LAN + VPN interfaces
- ✅ Firewall blocks WAN access
- ✅ Credentials in `00-secrets.rsc` (not plain text)
- ⚠️ FTP is plain text protocol

**Recommendations:**
1. Use FTP only for PKI distribution
2. Regular password rotation (quarterly)
3. Monitor FTP access logs
4. **Future:** Migrate to SFTP (more secure)

**Firewall Rules:**
```routeros
# Allow FTP from LAN
/ip firewall filter add chain=input protocol=tcp dst-port=21 \
    src-address=192.168.1.0/24 action=accept

# Allow FTP from VPN
/ip firewall filter add chain=input protocol=tcp dst-port=21 \
    in-interface=ipsec-s2s action=accept

# Block FTP from WAN
/ip firewall filter add chain=input protocol=tcp dst-port=21 \
    in-interface=ether1 action=drop
```

### Certificate Validation

- ✅ CRL (Certificate Revocation List) support (optional)
- ✅ Auto-renewal 30 days before expiry
- ✅ Logging всех PKI операций

### Operational Security

**Best Practices:**
1. ✅ Regular CA backups (automated scheduler)
2. ✅ Git version control для configuration files
3. ✅ Documented recovery procedures (this README)
4. ✅ Monitor certificate expiry
5. ✅ Audit PKI logs monthly

**Monitoring Commands:**
```routeros
# Certificate expiry dashboard
/certificate print where days-valid<60

# Auto-renewal logs
/log print where message~"Renewal"

# CA auto-signing activity
/log print where message~"CA Auto-Sign"
```

---

## 📊 MAINTENANCE

### Daily

Automated (schedulers):
- ✅ Certificate expiry check (03:00)
- ✅ Auto-renewal if needed
- ✅ CA auto-signing (every 5min)

### Weekly

Manual checks:
```routeros
# Check all certificates
/certificate print

# Check auto-renewal scheduler
/system scheduler print where name~"renewal"

# Review logs
/log print where topics~"certificate"
```

### Monthly

1. Review FTP access logs
2. Verify CA backup exists and accessible
3. Test certificate renewal on one router
4. Update documentation if needed

### Quarterly

1. Rotate FTP password:
   ```routeros
   /user set pki-admin password=<new-password>
   ```
2. Review firewall rules
3. Audit certificate usage
4. Verify backup restoration procedure

---

## 🔄 OPERATIONAL PROCEDURES

### Adding New Router to Network

1. Setup basic connectivity (LAN or VPN with PSK)
2. Copy PKI modules and CA root to router
3. Follow deployment guide (Phase 2 or Phase 3)
4. Verify certificate obtained and services configured
5. Document in network inventory

### Certificate Revocation

**If certificate compromised:**

```routeros
# On CA (R1-Core)
# 1. Remove certificate
/certificate remove [find name="compromised-router-cert"]

# 2. Update CRL (if enabled)
# (Manual CRL management - future enhancement)

# 3. On compromised router: generate new certificate
/import pki/router/10-router-cert-gen.rsc
/import pki/router/11-router-ftp-upload.rsc
/import pki/router/12-router-cert-import.rsc
```

### CA Certificate Renewal (10 years)

**Before expiry (1 year warning):**

1. Generate new CA certificate
2. Dual CA setup (old + new)
3. Gradual migration всех роутеров
4. Retire old CA after все migrated

**Detailed procedure:** (Future documentation)

### Disaster Recovery

**If CA server (R1-Core) lost:**

1. Restore CA from backup:
   ```routeros
   /certificate import file-name=ca-root-backup.p12 \
       passphrase=<secCAKeyPassphrase>
   /certificate set ca-root trusted=yes
   ```

2. Re-deploy FTP server and auto-signing
3. All router certificates remain valid
4. Auto-renewal continues working

---

## 📚 REFERENCES

- [MikroTik IPsec Documentation](https://help.mikrotik.com/docs/display/ROS/IPsec)
- [MikroTik Certificate Management](https://help.mikrotik.com/docs/display/ROS/Certificates)
- [RFC 7296 - IKEv2](https://www.rfc-editor.org/rfc/rfc7296)
- [RFC 5280 - X.509 PKI](https://www.rfc-editor.org/rfc/rfc5280)
- [NIST SP 800-77 - IPsec VPN Guide](https://csrc.nist.gov/publications/detail/sp/800-77/rev-1/final)

---

## 📞 SUPPORT & CONTACT

**Documentation:** This file
**Configuration:** `00-config.rsc`, `pki/00-pki-config.rsc`
**Logs:** `/log print where topics~"certificate"`

**Created by:** Claude Code (Sonnet 4.5)
**Date:** 17 декабря 2025
**Version:** 1.0
**Status:** Production Ready

---

**END OF PKI DOCUMENTATION**
