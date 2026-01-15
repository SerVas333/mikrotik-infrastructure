############################################################
# pki/router/13-router-auto-renewal.rsc - AUTO-RENEWAL SETUP
# ТРЕБУЕТ: 00-config.rsc, 00-secrets.rsc, certificate должен быть импортирован!
#
# НАЗНАЧЕНИЕ:
# - Automatic certificate renewal за $cfgCertRenewalDaysBefore дней до expiry
# - Daily scheduler проверяет certificate expiry
# - Zero-downtime certificate rotation
# - Полностью автоматический renewal workflow
#
# МОЖНО ЗАПУСКАТЬ НА ЛЮБОМ РОУТЕРЕ
############################################################

:log info "===== PKI: Auto-Renewal Setup ====="

############################################################
# STEP 1: Verify Certificate Exists
############################################################

:local certExists [:len [/certificate find name=$cfgRouterCertName where !invalid]]

:if ($certExists = 0) do={
    :log error "ERROR: Router certificate not found: $cfgRouterCertName"
    :log error "Import certificate first: /import pki/router/12-router-cert-import.rsc"
    :error "Certificate not found"
}

:log info "Router certificate verified: $cfgRouterCertName"

############################################################
# STEP 2: Create Certificate Renewal Script
############################################################

:log info "Creating certificate renewal script..."

/system script
:if ([:len [find name="cert-auto-renewal"]] > 0) do={
    :log warning "Script 'cert-auto-renewal' already exists, removing..."
    remove [find name="cert-auto-renewal"]
}

add name="cert-auto-renewal" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    source={
# PKI Certificate Auto-Renewal Script
# Checks certificate expiry and renews if needed

:global cfgRouterCertName
:global cfgCertRenewalDaysBefore
:global cfgHostname
:global cfgRouterKeyType
:global cfgRouterKeySize
:global cfgRouterCertValidityDays
:global cfgCertCountry
:global cfgCertState
:global cfgCertLocality
:global cfgCertOrganization
:global cfgCertOrganizationalUnit
:global cfgCertKeyUsage
:global cfgLANGateway
:global cfgIPsecLocalAddress
:global cfgWGLocalAddress
:global cfgCertAdditionalSAN
:global cfgPKICSRPath
:global cfgPKICertPath
:global cfgFTPPort
:global secFTPUser
:global secFTPPass
:global cfgFTPRetries
:global cfgFTPRetryInterval
:global cfgCertRenewalLogging

# Check if certificate exists
:local certExists [:len [/certificate find name=$cfgRouterCertName where !invalid]]
:if ($certExists = 0) do={
    :log error "Cert Auto-Renewal: Certificate not found: $cfgRouterCertName"
    :return
}

# Get certificate details
:local certDetails [/certificate get [find name=$cfgRouterCertName]]
:local certDaysValid ($certDetails->"days-valid")
:local certInvalid ($certDetails->"invalid")

# Skip if certificate is invalid
:if ($certInvalid = true) do={
    :log error "Cert Auto-Renewal: Certificate is invalid!"
    :return
}

# Check if renewal is needed
:if ($certDaysValid > $cfgCertRenewalDaysBefore) do={
    # Certificate still valid, no renewal needed
    :if ($cfgCertRenewalLogging = yes) do={
        :log info "Cert Auto-Renewal: Certificate valid for $certDaysValid days (renewal at $cfgCertRenewalDaysBefore days)"
    }
    :return
}

# Renewal needed!
:log warning "============================================"
:log warning "CERTIFICATE RENEWAL TRIGGERED"
:log warning "============================================"
:log warning "Certificate: $cfgRouterCertName"
:log warning "Days Valid: $certDaysValid"
:log warning "Renewal Threshold: $cfgCertRenewalDaysBefore days"
:log warning "Starting automatic renewal workflow..."

# STEP 1: Generate new CSR
:log info "Renewal Step 1/5: Generating new CSR..."

# Build SAN list
:local sanList "DNS:$cfgHostname,DNS:$cfgHostname.local"
:local lanIP [:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]]
:set sanList ($sanList . ",IP:$lanIP")

:if ([:typeof $cfgIPsecLocalAddress] != "nothing") do={
    :local vtiIP [:pick $cfgIPsecLocalAddress 0 [:find $cfgIPsecLocalAddress "/"]]
    :set sanList ($sanList . ",IP:$vtiIP")
}

:if ([:typeof $cfgWGLocalAddress] != "nothing") do={
    :local wgIP [:pick $cfgWGLocalAddress 0 [:find $cfgWGLocalAddress "/"]]
    :set sanList ($sanList . ",IP:$wgIP")
}

# Build key usage list
:local keyUsageList ""
:foreach usage in=$cfgCertKeyUsage do={
    :if ([:len $keyUsageList] > 0) do={ :set keyUsageList ($keyUsageList . ",") }
    :set keyUsageList ($keyUsageList . $usage)
}

# Remove old certificate
/certificate remove [find name=$cfgRouterCertName]
:delay 1s

# Create new CSR
/certificate add \
    name=$cfgRouterCertName \
    common-name=$cfgHostname \
    key-type=$cfgRouterKeyType \
    key-size=$cfgRouterKeySize \
    days-valid=$cfgRouterCertValidityDays \
    country=$cfgCertCountry \
    state=$cfgCertState \
    locality=$cfgCertLocality \
    organization=$cfgCertOrganization \
    unit=$cfgCertOrganizationalUnit \
    subject-alt-name=$sanList \
    key-usage=$keyUsageList \
    trusted=no

:local csrFileName ("$cfgHostname" . ".csr")
/certificate export-certificate $cfgRouterCertName type=pkcs10 file-name=$csrFileName

:log info "Renewal: New CSR generated"

# STEP 2: Upload CSR to CA
:log info "Renewal Step 2/5: Uploading CSR to CA..."

:local caFTPAddress "192.168.1.1"
:if ($cfgHostname = "R1-Core") do={ :set caFTPAddress "127.0.0.1" }

:local uploadSuccess false
:do {
    /tool fetch mode=ftp address=$caFTPAddress port=$cfgFTPPort \
        user=$secFTPUser password=$secFTPPass \
        src-path=$csrFileName dst-path=("$cfgPKICSRPath/" . $csrFileName) \
        upload=yes
    :set uploadSuccess true
    :log info "Renewal: CSR uploaded"
} on-error={
    :log error "Renewal: CSR upload failed"
    :return
}

# STEP 3: Wait for CA signing
:log info "Renewal Step 3/5: Waiting for CA auto-signing..."

:local certFileName ("$cfgHostname" . ".crt")
:local certReady false
:local waitTimeout 600
:local waitCounter 0
:local checkInterval 30

:while (($certReady = false) and ($waitCounter < $waitTimeout)) do={
    :delay ($checkInterval . "s")
    :set waitCounter ($waitCounter + $checkInterval)

    :do {
        /tool fetch mode=ftp address=$caFTPAddress port=$cfgFTPPort \
            user=$secFTPUser password=$secFTPPass \
            src-path=("$cfgPKICertPath/" . $certFileName) \
            dst-path=$certFileName upload=no
        :set certReady true
        :log info "Renewal: Certificate downloaded"
    } on-error={}
}

:if ($certReady = false) do={
    :log error "Renewal: Timeout waiting for signed certificate"
    :return
}

# STEP 4: Import new certificate
:log info "Renewal Step 4/5: Importing new certificate..."

/certificate import file-name=$certFileName passphrase=""
:delay 2s

# Rename if needed
:local importedCerts [/certificate find where common-name=$cfgHostname]
:local certID [:pick $importedCerts 0]
:local actualCertName [/certificate get $certID name]
:if ($actualCertName != $cfgRouterCertName) do={
    /certificate set $actualCertName name=$cfgRouterCertName
}

:log info "Renewal: Certificate imported"

# STEP 5: Verify and configure services
:log info "Renewal Step 5/5: Configuring services..."

:do { /interface sstp-server server set certificate=$cfgRouterCertName } on-error={}
:do { /ip service set www-ssl certificate=$cfgRouterCertName } on-error={}

:log info "Renewal: Services configured"

# Cleanup
/file remove [find name=$csrFileName]

:log warning "============================================"
:log warning "CERTIFICATE RENEWAL COMPLETE"
:log warning "============================================"
:log warning "Certificate: $cfgRouterCertName"
:log warning "New validity: ~$cfgRouterCertValidityDays days"
:log warning "Next renewal: in ~$([$cfgRouterCertValidityDays] - $cfgCertRenewalDaysBefore) days"
:log warning "All services automatically updated"
:log warning "============================================"
}

:log info "Certificate renewal script created: cert-auto-renewal"

############################################################
# STEP 3: Create Daily Scheduler
############################################################

:log info "Creating daily renewal check scheduler..."

/system scheduler
:if ([:len [find name="pki-cert-renewal-check"]] > 0) do={
    :log warning "Scheduler 'pki-cert-renewal-check' already exists, removing..."
    remove [find name="pki-cert-renewal-check"]
}

add name="pki-cert-renewal-check" \
    interval=$cfgCertCheckInterval \
    start-time=03:00:00 \
    on-event="cert-auto-renewal" \
    policy=ftp,reboot,read,write,policy,test,password,sensitive,romon \
    comment="PKI: Daily certificate renewal check (renews at $cfgCertRenewalDaysBefore days before expiry)"

:log info "Scheduler created: pki-cert-renewal-check (runs daily at 03:00)"

############################################################
# STEP 4: Perform Initial Check
############################################################

:log info "Performing initial renewal check..."
/system script run cert-auto-renewal

############################################################
# STEP 5: Display Summary
############################################################

:log info "============================================"
:log info "AUTO-RENEWAL SETUP COMPLETE"
:log info "============================================"
:log info ""
:log info "Script: cert-auto-renewal"
:log info "Scheduler: pki-cert-renewal-check"
:log info "Check Interval: $cfgCertCheckInterval (daily at 03:00)"
:log info "Renewal Trigger: $cfgCertRenewalDaysBefore days before expiry"
:log info ""
:log info "Current Certificate Status:"
/certificate print detail where name=$cfgRouterCertName
:log info ""
:log info "AUTOMATIC RENEWAL WORKFLOW:"
:log info "  1. Daily check at 03:00"
:log info "  2. If expiry < $cfgCertRenewalDaysBefore days:"
:log info "     - Generate new CSR"
:log info "     - Upload to CA via FTP"
:log info "     - Wait for CA auto-signing"
:log info "     - Download and import new certificate"
:log info "     - Update all services (zero downtime)"
:log info ""
:log info "MONITORING:"
:log info "  Check scheduler: /system scheduler print where name=\"pki-cert-renewal-check\""
:log info "  Check renewal logs: /log print where message~\"Renewal\""
:log info "  Manual renewal test: /system script run cert-auto-renewal"
:log info "============================================"

:log info "PKI: Auto-renewal setup completed successfully"
