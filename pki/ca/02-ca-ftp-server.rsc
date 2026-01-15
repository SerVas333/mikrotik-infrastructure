############################################################
# pki/ca/02-ca-ftp-server.rsc - FTP SERVER SETUP FOR PKI
# ТРЕБУЕТ: 00-config.rsc и 00-secrets.rsc должны быть импортированы!
#
# ВАЖНО: Запускать ТОЛЬКО на R1-Core (главный роутер с CA)!
#
# НАЗНАЧЕНИЕ:
# - Настройка FTP server для automatic CSR/certificate distribution
# - Создание директорий для PKI workflow
# - Firewall rules для безопасного доступа
#
# ОСОБЕННОСТИ:
# - FTP доступен из LAN (192.168.1.0/24)
# - FTP доступен через VPN (VTI интерфейсы)
# - FTP ЗАБЛОКИРОВАН от WAN
############################################################

:log info "===== PKI: Starting FTP Server Setup ====="

############################################################
# STEP 1: Проверка что это R1-Core
############################################################

:if ($cfgHostname != "R1-Core") do={
    :log error "ERROR: FTP server setup должен запускаться ТОЛЬКО на R1-Core!"
    :error "FTP setup aborted"
}

:log info "Hostname verification passed: $cfgHostname"

############################################################
# STEP 2: Configure FTP Service
############################################################

:log info "Configuring FTP service..."

# Enable FTP service
/ip service set ftp \
    disabled=no \
    port=$cfgFTPPort

:log info "FTP service enabled on port $cfgFTPPort"

############################################################
# STEP 3: Create FTP User
############################################################

:log info "Creating FTP user for PKI..."

# Check if user already exists
:local userExists [:len [/user find name=$secFTPUser]]
:if ($userExists > 0) do={
    :log warning "WARNING: FTP user already exists: $secFTPUser"
    :log warning "Updating password..."
    /user set $secFTPUser password=$secFTPPass
} else={
    :log info "Creating new FTP user: $secFTPUser"
    /user add \
        name=$secFTPUser \
        password=$secFTPPass \
        group=read \
        comment="PKI FTP user (CSR upload/cert download)"
}

:log info "FTP user configured: $secFTPUser"

############################################################
# STEP 4: Create PKI Directories
############################################################

:log info "Creating PKI directories..."

# RouterOS не имеет команды mkdir, директории создаются автоматически
# при записи файлов. Используем /file print для проверки.

# Note: Директории будут созданы при первом FTP upload
# Но мы можем создать placeholder файлы для создания структуры

:log info "PKI directories will be created automatically on first use:"
:log info "  $cfgPKICSRPath/ - for incoming CSR files"
:log info "  $cfgPKICertPath/ - for outgoing signed certificates"

# Optional: Create .placeholder files to ensure directory structure
# (This would require /tool fetch or another mechanism)

############################################################
# STEP 5: Firewall Rules для FTP Access
############################################################

:log info "Configuring firewall rules for FTP access..."

# Rule 1: Allow FTP from LAN
:local ruleLAN [:len [/ip firewall filter find \
    chain=input protocol=tcp dst-port=$cfgFTPPort \
    src-address=($cfgLANNetwork) comment~"PKI FTP from LAN"]]

:if ($ruleLAN = 0) do={
    :log info "Adding firewall rule: Allow FTP from LAN"
    /ip firewall filter add \
        chain=input \
        protocol=tcp \
        dst-port=$cfgFTPPort \
        src-address=($cfgLANNetwork) \
        action=accept \
        place-before=0 \
        comment="PKI FTP from LAN (192.168.1.0/24)"
} else={
    :log info "FTP rule for LAN already exists"
}

# Rule 2: Allow FTP from IPsec VTI interface
:local ruleIPsec [:len [/ip firewall filter find \
    chain=input protocol=tcp dst-port=$cfgFTPPort \
    in-interface=$cfgIPsecInterface comment~"PKI FTP from IPsec VPN"]]

:if ($ruleIPsec = 0) do={
    :log info "Adding firewall rule: Allow FTP from IPsec VPN"
    /ip firewall filter add \
        chain=input \
        protocol=tcp \
        dst-port=$cfgFTPPort \
        in-interface=$cfgIPsecInterface \
        action=accept \
        place-before=0 \
        comment="PKI FTP from IPsec VPN (VTI)"
} else={
    :log info "FTP rule for IPsec VPN already exists"
}

# Rule 3: Allow FTP from WireGuard VTI interface
:local ruleWG [:len [/ip firewall filter find \
    chain=input protocol=tcp dst-port=$cfgFTPPort \
    in-interface=$cfgWGInterface comment~"PKI FTP from WireGuard VPN"]]

:if ($ruleWG = 0) do={
    :log info "Adding firewall rule: Allow FTP from WireGuard VPN"
    /ip firewall filter add \
        chain=input \
        protocol=tcp \
        dst-port=$cfgFTPPort \
        in-interface=$cfgWGInterface \
        action=accept \
        place-before=0 \
        comment="PKI FTP from WireGuard VPN (VTI)"
} else={
    :log info "FTP rule for WireGuard VPN already exists"
}

# Rule 4: Block FTP from WAN (explicit drop)
:local ruleWAN [:len [/ip firewall filter find \
    chain=input protocol=tcp dst-port=$cfgFTPPort \
    in-interface=$cfgWanInterface comment~"PKI FTP block WAN"]]

:if ($ruleWAN = 0) do={
    :log info "Adding firewall rule: Block FTP from WAN"
    /ip firewall filter add \
        chain=input \
        protocol=tcp \
        dst-port=$cfgFTPPort \
        in-interface=$cfgWanInterface \
        action=drop \
        comment="PKI FTP block from WAN (security)"
} else={
    :log info "FTP block rule for WAN already exists"
}

:log info "Firewall rules configured for FTP access"

############################################################
# STEP 6: Verify FTP Configuration
############################################################

:log info "Verifying FTP configuration..."

/ip service print where name=ftp

:log info "FTP users:"
/user print where name=$secFTPUser

############################################################
# STEP 7: Security Warnings
############################################################

:log warning "============================================"
:log warning "FTP SERVER SECURITY CONSIDERATIONS"
:log warning "============================================"
:log warning ""
:log warning "FTP доступен от:"
:log warning "  ✅ LAN: $cfgLANNetwork"
:log warning "  ✅ IPsec VPN: через $cfgIPsecInterface"
:log warning "  ✅ WireGuard VPN: через $cfgWGInterface"
:log warning "  ❌ WAN: ЗАБЛОКИРОВАН"
:log warning ""
:log warning "FTP credentials:"
:log warning "  User: $secFTPUser"
:log warning "  Password: (в 00-secrets.rsc)"
:log warning ""
:log warning "РЕКОМЕНДАЦИИ:"
:log warning "  1. FTP - plain text protocol (не encrypted)"
:log warning "  2. Используйте только для PKI distribution"
:log warning "  3. Рассмотрите SFTP для production (будущее улучшение)"
:log warning "  4. Регулярно меняйте FTP password"
:log warning "============================================"

############################################################
# STEP 8: Display Summary
############################################################

:log info "============================================"
:log info "FTP SERVER SETUP COMPLETE"
:log info "============================================"
:log info ""
:log info "FTP Service: ENABLED on port $cfgFTPPort"
:log info "FTP User: $secFTPUser"
:log info ""
:log info "PKI Directories:"
:log info "  CSR Inbox: $cfgPKICSRPath/"
:log info "  Cert Outbox: $cfgPKICertPath/"
:log info ""
:log info "Access Control:"
:log info "  LAN: ALLOWED ($cfgLANNetwork)"
:log info "  IPsec VPN: ALLOWED ($cfgIPsecInterface)"
:log info "  WireGuard VPN: ALLOWED ($cfgWGInterface)"
:log info "  WAN: BLOCKED"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Test FTP access from LAN:"
:log info "     ftp admin@192.168.1.1 (or use FTP client)"
:log info "  2. Import pki/ca/03-ca-auto-sign.rsc (auto-signing)"
:log info "  3. Generate router certificates"
:log info "============================================"

:log info "PKI: FTP server setup completed successfully"
