############################################################
# pki/ca/03-ca-auto-sign.rsc - AUTO-SIGNING CSR SCHEDULER
# ТРЕБУЕТ: 00-config.rsc, CA должен быть уже создан!
#
# ВАЖНО: Запускать ТОЛЬКО на R1-Core (главный роутер с CA)!
#
# НАЗНАЧЕНИЕ:
# - Автоматическое подписание CSR файлов из $cfgPKICSRPath/
# - Экспорт подписанных сертификатов в $cfgPKICertPath/
# - Scheduler запускает проверку каждые $cfgCAAutoSignInterval
#
# WORKFLOW:
# 1. Сканирование $cfgPKICSRPath/ для новых CSR файлов
# 2. Импорт каждого CSR
# 3. Подписание CSR с CA
# 4. Экспорт signed certificate
# 5. Cleanup CSR files (опционально)
############################################################

:log info "===== PKI: Auto-Signing CSR Setup ====="

############################################################
# STEP 1: Проверка что это R1-Core
############################################################

:if ($cfgHostname != "R1-Core") do={
    :log error "ERROR: Auto-signing должен запускаться ТОЛЬКО на R1-Core!"
    :error "Auto-signing setup aborted"
}

:log info "Hostname verification passed: $cfgHostname"

############################################################
# STEP 2: Verify CA Exists
############################################################

:local caExists [:len [/certificate find name=$cfgCACommonName where trusted=yes]]
:if ($caExists = 0) do={
    :log error "ERROR: CA certificate не найден или не trusted!"
    :log error "Сначала выполните: /import pki/ca/01-ca-setup.rsc"
    :error "CA not found - aborting"
}

:log info "CA certificate verified: $cfgCACommonName"

############################################################
# STEP 3: Create Auto-Signing Script
############################################################

:log info "Creating auto-signing script..."

# Create the script that will be run by scheduler
/system script
:if ([:len [find name="ca-auto-sign-csr"]] > 0) do={
    :log warning "Script 'ca-auto-sign-csr' already exists, removing..."
    remove [find name="ca-auto-sign-csr"]
}

add name="ca-auto-sign-csr" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    source={
# PKI CA Auto-Signing Script
# Automatically signs CSR files and exports signed certificates

:local cfgPKICSRPath
:local cfgPKICertPath
:local cfgCACommonName
:local cfgRouterCertValidityDays
:local cfgPKIKeepCSRFiles

# Scan for CSR files in inbox
:local csrFiles [/file find where type="file" name~"^$cfgPKICSRPath/.+\\.(csr|req)\$"]

:if ([:len $csrFiles] = 0) do={
    # No CSR files found, exit silently
    :return
}

:log info "CA Auto-Sign: Found $([:len $csrFiles]) CSR file(s) to process"

# Process each CSR file
:foreach csrFile in=$csrFiles do={
    :local csrFileName [/file get $csrFile name]
    :log info "CA Auto-Sign: Processing $csrFileName"

    :do {
        # Import CSR
        :log info "CA Auto-Sign: Importing $csrFileName"
        /certificate import file-name=$csrFileName passphrase=""

        # Get the imported CSR name (it will be the filename without extension)
        :local csrName [:pick $csrFileName ([:find $csrFileName "/" end] + 1) [:find $csrFileName "." end]]

        # Wait for import to complete
        :delay 2s

        # Sign the CSR with CA
        :log info "CA Auto-Sign: Signing $csrName with CA $cfgCACommonName"
        /certificate sign $csrName \
            ca=$cfgCACommonName \
            name=($csrName . "-signed")

        # Wait for signing to complete
        :local signTimeout 30
        :local signCounter 0
        :while ([:len [/certificate find name=($csrName . "-signed") where !invalid]] = 0) do={
            :delay 1s
            :set signCounter ($signCounter + 1)
            :if ($signCounter > $signTimeout) do={
                :log error "CA Auto-Sign: Signing timeout for $csrName"
                :error "Signing timeout"
            }
        }

        :log info "CA Auto-Sign: Certificate signed successfully: $csrName-signed"

        # Export signed certificate to outbox
        :local certFileName ("$cfgPKICertPath/" . $csrName . ".crt")
        :log info "CA Auto-Sign: Exporting to $certFileName"
        /certificate export-certificate ($csrName . "-signed") file-name=$certFileName

        :log info "CA Auto-Sign: Certificate exported: $certFileName"

        # Cleanup: Remove CSR file (if configured)
        :if ($cfgPKIKeepCSRFiles != true) do={
            :log info "CA Auto-Sign: Removing processed CSR file: $csrFileName"
            /file remove $csrFile
        }

        # Remove the CSR from certificate store (not the signed cert)
        :if ([:len [/certificate find name=$csrName]] > 0) do={
            /certificate remove [find name=$csrName]
        }

        :log info "CA Auto-Sign: Processing complete for $csrName"

    } on-error={
        :log error "CA Auto-Sign: Error processing $csrFileName"
    }
}

:log info "CA Auto-Sign: Batch processing complete"
}

:log info "Auto-signing script created: ca-auto-sign-csr"

############################################################
# STEP 4: Create Scheduler
############################################################

:log info "Creating auto-signing scheduler..."

/system scheduler
:if ([:len [find name="pki-ca-auto-sign"]] > 0) do={
    :log warning "Scheduler 'pki-ca-auto-sign' already exists, removing..."
    remove [find name="pki-ca-auto-sign"]
}

add name="pki-ca-auto-sign" \
    interval=$cfgCAAutoSignInterval \
    on-event="ca-auto-sign-csr" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    comment="PKI: Automatic CSR signing every $cfgCAAutoSignInterval"

:log info "Scheduler created: pki-ca-auto-sign (runs every $cfgCAAutoSignInterval)"

############################################################
# STEP 5: Test Run (optional)
############################################################

:log info "Performing initial test run of auto-signing script..."
/system script run ca-auto-sign-csr

############################################################
# STEP 6: Display Summary
############################################################

:log info "============================================"
:log info "AUTO-SIGNING SETUP COMPLETE"
:log info "============================================"
:log info ""
:log info "Script: ca-auto-sign-csr"
:log info "Scheduler: pki-ca-auto-sign"
:log info "Interval: $cfgCAAutoSignInterval"
:log info ""
:log info "Workflow:"
:log info "  1. Scan $cfgPKICSRPath/ for *.csr or *.req files"
:log info "  2. Import each CSR"
:log info "  3. Sign with CA: $cfgCACommonName"
:log info "  4. Export to $cfgPKICertPath/"
:log info "  5. Cleanup CSR files (if enabled)"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Generate router certificate on R1-Core:"
:log info "     /import pki/router/10-router-cert-gen.rsc"
:log info "  2. Upload CSR and download cert:"
:log info "     /import pki/router/11-router-ftp-upload.rsc"
:log info "  3. Import certificate:"
:log info "     /import pki/router/12-router-cert-import.rsc"
:log info ""
:log info "MONITORING:"
:log info "  Check scheduler: /system scheduler print"
:log info "  Check script: /system script print where name=\"ca-auto-sign-csr\""
:log info "  Check logs: /log print where message~\"CA Auto-Sign\""
:log info "============================================"

:log info "PKI: Auto-signing setup completed successfully"
