############################################################
# pki/router/11-router-ftp-upload.rsc - FTP CSR UPLOAD & CERT DOWNLOAD
# ТРЕБУЕТ: 00-config.rsc, 00-secrets.rsc, CSR должен быть сгенерирован!
#
# НАЗНАЧЕНИЕ:
# - Upload CSR файла на CA через FTP
# - Ожидание auto-signing на CA (polling)
# - Download подписанного сертификата
# - Retry logic и error handling
#
# ПОДДЕРЖКА:
# - LAN роутеры: прямой FTP доступ к 192.168.1.1
# - VPN роутеры: FTP через VPN tunnel
############################################################

:log info "===== PKI: FTP Upload CSR & Download Certificate ====="

############################################################
# STEP 1: Verify CSR File Exists
############################################################

:local csrFileName ("$cfgHostname" . ".csr")
:local csrFileExists [:len [/file find name=$csrFileName]]

:if ($csrFileExists = 0) do={
    :log error "ERROR: CSR file not found: $csrFileName"
    :log error "Generate CSR first: /import pki/router/10-router-cert-gen.rsc"
    :error "CSR file missing"
}

:log info "CSR file verified: $csrFileName"

############################################################
# STEP 2: Determine CA FTP Address
############################################################

:log info "Determining CA FTP address..."

# Default: R1-Core LAN IP
:local caFTPAddress [:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]]

# If this is not R1-Core, use LAN gateway
:if ($cfgHostname != "R1-Core") do={
    :set caFTPAddress "192.168.1.1"
    :log info "Remote router detected, using CA address: $caFTPAddress"
} else={
    :set caFTPAddress "127.0.0.1"
    :log info "Local R1-Core detected, using localhost: $caFTPAddress"
}

:log info "CA FTP Server: $caFTPAddress:$cfgFTPPort"

############################################################
# STEP 3: Upload CSR to CA via FTP
############################################################

:log info "Uploading CSR to CA..."

:local uploadSuccess false
:local uploadAttempts 0
:local maxUploadAttempts $cfgFTPRetries

:while (($uploadSuccess = false) and ($uploadAttempts < $maxUploadAttempts)) do={
    :set uploadAttempts ($uploadAttempts + 1)
    :log info "Upload attempt $uploadAttempts of $maxUploadAttempts"

    :do {
        /tool fetch \
            mode=ftp \
            address=$caFTPAddress \
            port=$cfgFTPPort \
            user=$secFTPUser \
            password=$secFTPPass \
            src-path=$csrFileName \
            dst-path=("$cfgPKICSRPath/" . $csrFileName) \
            upload=yes

        :set uploadSuccess true
        :log info "CSR uploaded successfully to CA:$cfgPKICSRPath/$csrFileName"

    } on-error={
        :log error "Upload attempt $uploadAttempts failed"
        :if ($uploadAttempts < $maxUploadAttempts) do={
            :log info "Retrying in $cfgFTPRetryInterval seconds..."
            :delay ($cfgFTPRetryInterval . "s")
        }
    }
}

:if ($uploadSuccess = false) do={
    :log error "ERROR: Failed to upload CSR after $maxUploadAttempts attempts"
    :log error "Check:"
    :log error "  1. FTP service running on CA: /ip service print where name=ftp"
    :log error "  2. Network connectivity: /ping $caFTPAddress"
    :log error "  3. FTP credentials in 00-secrets.rsc"
    :log error "  4. Firewall allows FTP from this router"
    :error "CSR upload failed"
}

############################################################
# STEP 4: Wait for CA Auto-Signing
############################################################

:log info "Waiting for CA to auto-sign CSR..."
:log info "CA auto-signing runs every $cfgCAAutoSignInterval"

:local certFileName ("$cfgHostname" . ".crt")
:local certReady false
:local waitTimeout 600
:local waitCounter 0
:local checkInterval 30

:log info "Checking for signed certificate every $checkInterval seconds..."
:log info "Maximum wait time: $waitTimeout seconds"

:while (($certReady = false) and ($waitCounter < $waitTimeout)) do={
    :delay ($checkInterval . "s")
    :set waitCounter ($waitCounter + $checkInterval)

    :log info "Checking for signed certificate... ($waitCounter/$waitTimeout seconds)"

    # Try to download certificate
    :do {
        /tool fetch \
            mode=ftp \
            address=$caFTPAddress \
            port=$cfgFTPPort \
            user=$secFTPUser \
            password=$secFTPPass \
            src-path=("$cfgPKICertPath/" . $certFileName) \
            dst-path=$certFileName \
            upload=no

        # If download succeeded, certificate is ready
        :set certReady true
        :log info "Signed certificate downloaded: $certFileName"

    } on-error={
        # Certificate not ready yet, continue waiting
        :log info "Certificate not ready yet, waiting..."
    }
}

:if ($certReady = false) do={
    :log error "ERROR: Timeout waiting for signed certificate after $waitTimeout seconds"
    :log error "Check:"
    :log error "  1. CA auto-signing is running: /system scheduler print where name=\"pki-ca-auto-sign\""
    :log error "  2. CA logs for errors: /log print where message~\"CA Auto-Sign\""
    :log error "  3. CSR was uploaded correctly to CA:$cfgPKICSRPath/"
    :error "Certificate signing timeout"
}

############################################################
# STEP 5: Verify Downloaded Certificate
############################################################

:log info "Verifying downloaded certificate file..."

:local certFileExists [:len [/file find name=$certFileName]]
:if ($certFileExists = 0) do={
    :log error "ERROR: Certificate file not found after download: $certFileName"
    :error "Certificate verification failed"
}

# Get file size to ensure it's not empty
:local certFileSize [/file get [find name=$certFileName] size]
:if ($certFileSize < 100) do={
    :log error "ERROR: Certificate file too small (possibly corrupted): $certFileSize bytes"
    :error "Certificate verification failed"
}

:log info "Certificate file verified: $certFileName ($certFileSize bytes)"

############################################################
# STEP 6: Display Summary
############################################################

:log info "============================================"
:log info "FTP UPLOAD/DOWNLOAD COMPLETE"
:log info "============================================"
:log info ""
:log info "CSR Uploaded: $csrFileName"
:log info "  Destination: $caFTPAddress:$cfgPKICSRPath/$csrFileName"
:log info ""
:log info "Certificate Downloaded: $certFileName"
:log info "  Source: $caFTPAddress:$cfgPKICertPath/$certFileName"
:log info "  Size: $certFileSize bytes"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Import signed certificate:"
:log info "     /import pki/router/12-router-cert-import.rsc"
:log info "  2. Configure services (IPsec, SSTP, HTTPS):"
:log info "     /import pki/services/20-ipsec-cert-auth.rsc"
:log info "  3. Setup auto-renewal:"
:log info "     /import pki/router/13-router-auto-renewal.rsc"
:log info ""
:log info "FILES:"
:log info "  CSR: $csrFileName (can be deleted after import)"
:log info "  Certificate: $certFileName (will be imported)"
:log info "============================================"

:log info "PKI: FTP upload/download completed successfully"
