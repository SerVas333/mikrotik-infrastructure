############################################################
# pki/ca/04-ca-backup.rsc - CA BACKUP & RECOVERY
# ТРЕБУЕТ: 00-config.rsc, CA должен быть создан!
#
# НАЗНАЧЕНИЕ:
# - Encrypted backup CA private key
# - Automatic scheduled backups
# - Export CA root certificate for distribution
# - Recovery procedures
#
# ЗАПУСКАТЬ ТОЛЬКО НА R1-Core (CA server)
############################################################

:log info "===== PKI: CA Backup & Recovery Setup ====="

############################################################
# STEP 1: Verify CA Certificate Exists
############################################################

:log info "Verifying CA certificate..."

:local caExists [:len [/certificate find name=$cfgCACommonName where trusted=yes]]

:if ($caExists = 0) do={
    :log error "ERROR: CA certificate not found: $cfgCACommonName"
    :log error "Create CA first: /import pki/ca/01-ca-setup.rsc"
    :error "CA certificate missing"
}

:log info "CA certificate verified: $cfgCACommonName"

############################################################
# STEP 2: Export CA Root Certificate (for distribution)
############################################################

:log info "Exporting CA root certificate..."

# Export public CA certificate (PEM format)
:local caExportName "ca-root"
/certificate export-certificate $cfgCACommonName type=pem file-name=$caExportName

:log info "CA root certificate exported: $caExportName.crt"

############################################################
# STEP 3: Create Encrypted CA Backup
############################################################

:log info "Creating encrypted CA backup..."

# Export CA with private key (encrypted PKCS12)
:local caBackupName "ca-root-backup"

:if ([:typeof $secCAKeyPassphrase] = "nothing") do={
    :log error "ERROR: CA passphrase not configured!"
    :log error "Set secCAKeyPassphrase in 00-secrets.rsc"
    :error "CA passphrase missing"
}

# Check passphrase strength
:if ([:len $secCAKeyPassphrase] < 16) do={
    :log warning "WARNING: CA passphrase is weak (< 16 characters)"
    :log warning "Consider using a stronger passphrase (32+ characters recommended)"
}

:do {
    /certificate export-certificate $cfgCACommonName \
        type=pkcs12 \
        export-passphrase=$secCAKeyPassphrase \
        file-name=$caBackupName
    :log info "CA backup created: $caBackupName.p12 (encrypted)"
} on-error={
    :log error "ERROR: CA backup export failed"
    :error "CA backup creation failed"
}

############################################################
# STEP 4: Display Backup Information
############################################################

:log info "Listing CA backup files..."
/file print where name~"ca-root"

############################################################
# STEP 5: Create Backup Script for Scheduler
############################################################

:log info "Creating scheduled CA backup script..."

/system script
:if ([:len [find name="ca-backup-scheduler"]] > 0) do={
    :log warning "Script 'ca-backup-scheduler' already exists, removing..."
    remove [find name="ca-backup-scheduler"]
}

add name="ca-backup-scheduler" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    source={
# PKI CA Backup Script
# Automatic backup of CA certificate and private key

:global cfgCACommonName
:global secCAKeyPassphrase
:global cfgCABackupLogging

# Verify CA exists
:local caExists [:len [/certificate find name=$cfgCACommonName where trusted=yes]]
:if ($caExists = 0) do={
    :log error "CA Backup: CA certificate not found: $cfgCACommonName"
    :return
}

# Create timestamped backup filename
:local timestamp [/system clock get date]
:set timestamp ([:pick $timestamp 7 11] . [:pick $timestamp 0 3] . [:pick $timestamp 4 6])
:local backupName ("ca-backup-" . $timestamp)

# Export encrypted backup
:do {
    /certificate export-certificate $cfgCACommonName \
        type=pkcs12 \
        export-passphrase=$secCAKeyPassphrase \
        file-name=$backupName

    :if ($cfgCABackupLogging = yes) do={
        :log info "CA Backup: Created $backupName.p12"
    }
} on-error={
    :log error "CA Backup: Export failed"
}

# Cleanup old backups (keep last 7 days)
:local oldBackups [/file find where name~"ca-backup-" and creation-time<([:timestamp] - 7d)]
:if ([:len $oldBackups] > 0) do={
    :foreach backup in=$oldBackups do={
        :local fileName [/file get $backup name]
        /file remove $backup
        :if ($cfgCABackupLogging = yes) do={
            :log info "CA Backup: Removed old backup $fileName"
        }
    }
}
}

:log info "CA backup script created: ca-backup-scheduler"

############################################################
# STEP 6: Create Weekly Backup Scheduler
############################################################

:log info "Creating weekly CA backup scheduler..."

/system scheduler
:if ([:len [find name="pki-ca-backup-weekly"]] > 0) do={
    :log warning "Scheduler 'pki-ca-backup-weekly' already exists, removing..."
    remove [find name="pki-ca-backup-weekly"]
}

add name="pki-ca-backup-weekly" \
    interval=7d \
    start-date=jan/01/2025 \
    start-time=04:00:00 \
    on-event="ca-backup-scheduler" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    comment="PKI: Weekly CA backup (encrypted PKCS12)"

:log info "Scheduler created: pki-ca-backup-weekly (runs weekly at 04:00)"

############################################################
# STEP 7: Perform Initial Backup
############################################################

:log info "Performing initial CA backup..."
/system script run ca-backup-scheduler

############################################################
# STEP 8: Display Summary and Recovery Instructions
############################################################

:log info "============================================"
:log info "CA BACKUP SETUP COMPLETE"
:log info "============================================"
:log info ""
:log info "BACKUP FILES CREATED:"
/file print where name~"ca-"
:log info ""
:log info "CRITICAL SECURITY INSTRUCTIONS:"
:log info "  ⚠️  IMMEDIATELY download CA backup files to secure location!"
:log info "  ⚠️  Store offline (USB drive, safe, etc.)"
:log info "  ⚠️  NEVER lose the passphrase: $[:len $secCAKeyPassphrase]-character"
:log info ""
:log info "DOWNLOAD COMMANDS:"
:log info "  scp admin@192.168.1.1:ca-root.crt /secure-backup/"
:log info "  scp admin@192.168.1.1:ca-root-backup.p12 /secure-backup/"
:log info ""
:log info "DISTRIBUTION:"
:log info "  ca-root.crt → Distribute to all routers (public CA cert)"
:log info "  ca-root-backup.p12 → SECURE OFFLINE STORAGE (private key backup)"
:log info ""
:log info "SCHEDULED BACKUPS:"
:log info "  Frequency: Weekly (every 7 days)"
:log info "  Time: 04:00"
:log info "  Retention: Last 7 backups"
:log info "  Format: Encrypted PKCS12"
:log info ""
:log info "============================================"
:log info "CA RECOVERY PROCEDURE"
:log info "============================================"
:log info ""
:log info "If CA is lost or router is replaced:"
:log info ""
:log info "1. Upload backup to new router:"
:log info "   scp /secure-backup/ca-root-backup.p12 admin@192.168.1.1:/"
:log info ""
:log info "2. Import CA backup:"
:log info "   /certificate import file-name=ca-root-backup.p12 \\"
:log info "       passphrase=\"YOUR-PASSPHRASE\""
:log info ""
:log info "3. Set CA as trusted:"
:log info "   /certificate set $cfgCACommonName trusted=yes"
:log info ""
:log info "4. Verify CA:"
:log info "   /certificate print detail where name=\"$cfgCACommonName\""
:log info ""
:log info "5. Re-run CA setup scripts:"
:log info "   /import pki/ca/02-ca-ftp-server.rsc"
:log info "   /import pki/ca/03-ca-auto-sign.rsc"
:log info "   /import pki/ca/04-ca-backup.rsc"
:log info ""
:log info "⚠️  IMPORTANT: All existing certificates remain valid!"
:log info "⚠️  No need to re-issue certificates to routers"
:log info "============================================"

:log info "PKI: CA backup setup completed successfully"
