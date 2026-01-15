############################################################
# pki/router/10-router-cert-gen.rsc - ROUTER CSR GENERATION
# ТРЕБУЕТ: 00-config.rsc должен быть импортирован!
#
# НАЗНАЧЕНИЕ:
# - Генерация ECDSA P-256 private key
# - Создание Certificate Signing Request (CSR)
# - SAN (Subject Alternative Name) с DNS и IP адресами
# - Key usage для TLS server/client и IPsec
#
# МОЖНО ЗАПУСКАТЬ НА ЛЮБОМ РОУТЕРЕ (R1-Core, Site B, Site C, etc.)
############################################################

:log info "===== PKI: Router Certificate Request Generation ====="

############################################################
# STEP 1: Check if router certificate already exists
############################################################

:local certExists [:len [/certificate find name=$cfgRouterCertName]]
:if ($certExists > 0) do={
    :log warning "WARNING: Router certificate already exists: $cfgRouterCertName"
    :log warning "To regenerate, delete existing certificate first:"
    :log warning "  /certificate remove [find name=\"$cfgRouterCertName\"]"

    :local proceed
    :put "Certificate exists. Continue anyway? (yes/no)"
    # In script mode, auto-continue
    :set proceed "yes"

    :if ($proceed != "yes") do={
        :error "Certificate generation cancelled"
    }

    :log warning "Removing existing certificate..."
    /certificate remove [find name=$cfgRouterCertName]
}

############################################################
# STEP 2: Build Subject Alternative Name (SAN)
############################################################

:log info "Building Subject Alternative Name (SAN)..."

# Start with hostname
:local sanList "DNS:$cfgHostname,DNS:$cfgHostname.local"

# Add LAN Gateway IP
:local lanIP [:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]]
:set sanList ($sanList . ",IP:$lanIP")

# Add VTI IPs if they exist (for VPN роутеры)
:if ([:typeof $cfgIPsecLocalAddress] != "nothing") do={
    :local vtiIP [:pick $cfgIPsecLocalAddress 0 [:find $cfgIPsecLocalAddress "/"]]
    :set sanList ($sanList . ",IP:$vtiIP")
}

:if ([:typeof $cfgWGLocalAddress] != "nothing") do={
    :local wgIP [:pick $cfgWGLocalAddress 0 [:find $cfgWGLocalAddress "/"]]
    :set sanList ($sanList . ",IP:$wgIP")
}

# Add additional SANs if configured
:if ([:typeof $cfgCertAdditionalSAN] != "nothing") do={
    :foreach san in=$cfgCertAdditionalSAN do={
        :set sanList ($sanList . "," . $san)
    }
}

:log info "SAN List: $sanList"

############################################################
# STEP 3: Build Key Usage
############################################################

:log info "Configuring key usage..."

# Convert array to comma-separated list
:local keyUsageList ""
:foreach usage in=$cfgCertKeyUsage do={
    :if ([:len $keyUsageList] > 0) do={
        :set keyUsageList ($keyUsageList . ",")
    }
    :set keyUsageList ($keyUsageList . $usage)
}

:log info "Key Usage: $keyUsageList"

############################################################
# STEP 4: Generate CSR
############################################################

:log info "Generating router certificate request..."
:log info "  Common Name: $cfgHostname"
:log info "  Key Type: $cfgRouterKeyType"
:log info "  Key Size: $cfgRouterKeySize"
:log info "  Validity Request: $cfgRouterCertValidityDays days"

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

:log info "CSR generated: $cfgRouterCertName"

############################################################
# STEP 5: Export CSR for Signing
############################################################

:log info "Exporting CSR file..."

# Export CSR to file
:local csrFileName ("$cfgHostname" . ".csr")
/certificate export-certificate $cfgRouterCertName \
    type=pkcs10 \
    file-name=$csrFileName

:log info "CSR exported: $csrFileName"

############################################################
# STEP 6: Display Certificate Request Info
############################################################

:log info "============================================"
:log info "ROUTER CSR GENERATION COMPLETE"
:log info "============================================"
:log info ""
:log info "Certificate Name: $cfgRouterCertName"
:log info "Common Name (CN): $cfgHostname"
:log info "Key Type: $cfgRouterKeyType P-$cfgRouterKeySize"
:log info "Validity: $cfgRouterCertValidityDays days (2 years)"
:log info ""
:log info "Subject Alternative Names:"
:log info "  $sanList"
:log info ""
:log info "Key Usage:"
:log info "  $keyUsageList"
:log info ""
:log info "CSR File: $csrFileName"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Upload CSR to CA for signing:"
:log info "     /import pki/router/11-router-ftp-upload.rsc"
:log info "  2. Wait for CA to sign (auto-signing every 5min)"
:log info "  3. Download and import signed certificate:"
:log info "     /import pki/router/12-router-cert-import.rsc"
:log info ""
:log info "MANUAL ALTERNATIVE (if FTP unavailable):"
:log info "  1. Copy CSR to CA:"
:log info "     scp $csrFileName admin@192.168.1.1:/pki/csr-inbox/"
:log info "  2. Wait for CA auto-signing"
:log info "  3. Download signed cert from CA:"
:log info "     scp admin@192.168.1.1:/pki/certs-outbox/$cfgHostname.crt ./"
:log info "============================================"

:log info "PKI: Router CSR generation completed successfully"
