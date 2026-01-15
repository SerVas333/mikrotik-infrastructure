############################################################
# pki/ca/01-ca-setup.rsc - ROOT CERTIFICATE AUTHORITY SETUP
# ТРЕБУЕТ: 00-config.rsc и 00-secrets.rsc должны быть импортированы!
#
# ВАЖНО: Запускать ТОЛЬКО на R1-Core (главный роутер)!
# Этот скрипт создает Root CA для всей сети.
#
# ОСОБЕННОСТИ:
# - ECDSA P-384 ключ (более сильный чем P-256 для CA)
# - Self-signed certificate
# - Validity: 10 years
# - Encrypted backup CA private key
# - Export CA root для distribution на другие роутеры
############################################################

:log info "===== PKI: Starting Root CA Setup ====="

############################################################
# STEP 1: Проверка что это R1-Core
############################################################

:if ($cfgHostname != "R1-Core") do={
    :log error "ERROR: CA setup должен запускаться ТОЛЬКО на R1-Core!"
    :log error "Current hostname: $cfgHostname"
    :error "CA setup aborted"
}

:log info "Hostname verification passed: $cfgHostname"

############################################################
# STEP 2: Проверка существующего CA
############################################################

:local caExists [:len [/certificate find name=$cfgCACommonName]]
:if ($caExists > 0) do={
    :log warning "WARNING: CA certificate already exists: $cfgCACommonName"
    :log warning "Skipping CA creation. To recreate, delete existing CA first:"
    :log warning "  /certificate remove [find name=\"$cfgCACommonName\"]"
    :error "CA already exists - aborting to prevent duplicate"
}

:log info "No existing CA found. Creating new Root CA..."

############################################################
# STEP 3: Создание Root CA Certificate
############################################################

:log info "Creating Root CA certificate..."
:log info "  Common Name: $cfgCACommonName"
:log info "  Key Type: $cfgCAKeyType"
:log info "  Key Size: $cfgCAKeySize"
:log info "  Validity: $cfgCAValidityDays days (10 years)"

/certificate add \
    name=$cfgCACommonName \
    common-name=$cfgCACommonName \
    key-type=$cfgCAKeyType \
    key-size=$cfgCAKeySize \
    days-valid=$cfgCAValidityDays \
    country=$cfgCertCountry \
    state=$cfgCertState \
    locality=$cfgCertLocality \
    organization=$cfgCertOrganization \
    unit=$cfgCertOrganizationalUnit \
    key-usage=key-cert-sign,crl-sign \
    trusted=no

:log info "CA certificate request created"

############################################################
# STEP 4: Self-Sign CA Certificate
############################################################

:log info "Self-signing CA certificate..."

# Sign the CA certificate
/certificate sign $cfgCACommonName name=$cfgCACommonName

# Wait for signing to complete
:local signTimeout 30
:local signCounter 0
:while ([:len [/certificate find name=$cfgCACommonName where !invalid]] = 0) do={
    :delay 1s
    :set signCounter ($signCounter + 1)
    :if ($signCounter > $signTimeout) do={
        :log error "ERROR: CA signing timeout after $signTimeout seconds"
        :error "CA signing failed"
    }
}

:log info "CA certificate signed successfully"

############################################################
# STEP 5: Set CA as Trusted
############################################################

:log info "Setting CA as trusted..."
/certificate set $cfgCACommonName trusted=yes

:log info "CA marked as trusted"

############################################################
# STEP 6: Verify CA Certificate
############################################################

:log info "Verifying CA certificate..."

:local caDetails [/certificate get [find name=$cfgCACommonName]]
:local caStatus ($caDetails->"status")
:local caTrusted ($caDetails->"trusted")
:local caInvalid ($caDetails->"invalid")
:local caDaysValid ($caDetails->"days-valid")

:if ($caInvalid = true) do={
    :log error "ERROR: CA certificate is invalid!"
    :error "CA validation failed"
}

:if ($caTrusted != true) do={
    :log error "ERROR: CA certificate is not trusted!"
    :error "CA trust verification failed"
}

:log info "CA verification successful:"
:log info "  Status: $caStatus"
:log info "  Trusted: $caTrusted"
:log info "  Days Valid: ~$caDaysValid"

############################################################
# STEP 7: Export CA Root Certificate (для distribution)
############################################################

:log info "Exporting CA root certificate for distribution..."

# Export CA public certificate (без private key)
/certificate export-certificate $cfgCACommonName file-name=ca-root

:log info "CA root certificate exported: ca-root.crt"
:log info "THIS FILE MUST BE DISTRIBUTED TO ALL ROUTERS!"

############################################################
# STEP 8: Export Encrypted CA Backup
############################################################

:log info "Creating encrypted backup of CA (includes private key)..."

# Export CA с private key и encryption
/certificate export-certificate $cfgCACommonName \
    export-passphrase=$secCAKeyPassphrase \
    file-name=ca-root-backup

:log info "Encrypted CA backup created: ca-root-backup.p12"
:log warning "КРИТИЧЕСКИ ВАЖНО:"
:log warning "  1. Скачать ca-root-backup.p12 в БЕЗОПАСНОЕ место (offline storage)"
:log warning "  2. НЕ ХРАНИТЬ на роутере!"
:log warning "  3. Passphrase: (из secCAKeyPassphrase)"
:log warning "  4. Это единственная копия CA private key!"

############################################################
# STEP 9: Display CA Information
############################################################

:log info "============================================"
:log info "ROOT CA SETUP COMPLETE"
:log info "============================================"
:log info ""
:log info "CA Certificate: $cfgCACommonName"
:log info "Key Type: $cfgCAKeyType P-$cfgCAKeySize"
:log info "Validity: $cfgCAValidityDays days (10 years)"
:log info ""
:log info "FILES CREATED:"
:log info "  1. ca-root.crt - Public CA certificate (distribute to all routers)"
:log info "  2. ca-root-backup.p12 - Encrypted backup (store offline securely)"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Download ca-root-backup.p12 to secure offline storage"
:log info "  2. scp admin@192.168.1.1:ca-root-backup.p12 ~/secure-backup/"
:log info "  3. scp admin@192.168.1.1:ca-root.crt ~/pki-distribution/"
:log info "  4. Import pki/ca/02-ca-ftp-server.rsc (FTP server setup)"
:log info "  5. Import pki/ca/03-ca-auto-sign.rsc (auto-signing)"
:log info ""
:log info "SECURITY REMINDER:"
:log info "  - CA private key is IRREPLACEABLE"
:log info "  - Keep offline backup in safe location"
:log info "  - Passphrase is in 00-secrets.rsc"
:log info "============================================"

:log info "PKI: Root CA setup completed successfully"
