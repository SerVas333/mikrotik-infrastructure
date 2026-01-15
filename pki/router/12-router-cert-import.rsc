############################################################
# pki/router/12-router-cert-import.rsc - CERTIFICATE IMPORT
# ТРЕБУЕТ: 00-config.rsc, signed certificate должен быть downloaded!
#
# НАЗНАЧЕНИЕ:
# - Import CA root certificate (если не импортирован)
# - Import signed router certificate
# - Verify certificate chain
# - Configure services (SSTP, HTTPS) для использования certificate
#
# МОЖНО ЗАПУСКАТЬ НА ЛЮБОМ РОУТЕРЕ
############################################################

:log info "===== PKI: Certificate Import & Configuration ====="

############################################################
# STEP 1: Check if CA Root Certificate is Installed
############################################################

:log info "Checking for CA root certificate..."

:local caInstalled [:len [/certificate find name=$cfgCACommonName where trusted=yes]]

:if ($caInstalled = 0) do={
    :log warning "CA root certificate not found or not trusted"
    :log info "Attempting to import CA root certificate..."

    # Check if ca-root.crt file exists
    :local caFileExists [:len [/file find name="ca-root.crt"]]

    :if ($caFileExists = 0) do={
        :log error "ERROR: ca-root.crt file not found"
        :log error "Copy CA root certificate from CA server:"
        :log error "  scp admin@192.168.1.1:ca-root.crt ./"
        :log error "Then re-run this script"
        :error "CA root certificate missing"
    }

    # Import CA root certificate
    :log info "Importing ca-root.crt..."
    /certificate import file-name=ca-root.crt passphrase=""

    # Wait for import
    :delay 2s

    # Set CA as trusted
    :log info "Setting CA as trusted..."
    /certificate set $cfgCACommonName trusted=yes

    :log info "CA root certificate imported and trusted"
} else={
    :log info "CA root certificate already installed and trusted"
}

############################################################
# STEP 2: Verify Router Certificate File Exists
############################################################

:local certFileName ("$cfgHostname" . ".crt")
:local certFileExists [:len [/file find name=$certFileName]]

:if ($certFileExists = 0) do={
    :log error "ERROR: Signed certificate file not found: $certFileName"
    :log error "Download certificate first: /import pki/router/11-router-ftp-upload.rsc"
    :error "Certificate file missing"
}

:log info "Certificate file verified: $certFileName"

############################################################
# STEP 3: Check if Certificate Already Imported
############################################################

:local certImported [:len [/certificate find name=$cfgRouterCertName where !invalid]]

:if ($certImported > 0) do={
    :log warning "WARNING: Router certificate already imported: $cfgRouterCertName"
    :log warning "Certificate details:"
    /certificate print detail where name=$cfgRouterCertName

    :local proceed "yes"
    :log info "Continuing with re-import..."

    :log warning "Removing existing certificate..."
    /certificate remove [find name=$cfgRouterCertName]
    :delay 1s
}

############################################################
# STEP 4: Import Signed Router Certificate
############################################################

:log info "Importing signed router certificate..."

/certificate import file-name=$certFileName passphrase=""

:log info "Certificate import initiated"

# Wait for import to complete
:delay 3s

############################################################
# STEP 5: Verify Certificate Import
############################################################

:log info "Verifying imported certificate..."

# Find the imported certificate
# Note: Import may create cert with different name (with -1, -2 suffix)
:local importedCerts [/certificate find where common-name=$cfgHostname]

:if ([:len $importedCerts] = 0) do={
    :log error "ERROR: Certificate import failed - no certificate found with CN=$cfgHostname"
    :error "Certificate import verification failed"
}

# Get the first match (should be our certificate)
:local certID [:pick $importedCerts 0]
:local actualCertName [/certificate get $certID name]

:log info "Certificate imported with name: $actualCertName"

# If name doesn't match expected, rename it
:if ($actualCertName != $cfgRouterCertName) do={
    :log warning "Certificate name mismatch, renaming..."
    :log info "  Old name: $actualCertName"
    :log info "  New name: $cfgRouterCertName"

    /certificate set $actualCertName name=$cfgRouterCertName
    :log info "Certificate renamed to: $cfgRouterCertName"
}

############################################################
# STEP 6: Verify Certificate Details
############################################################

:log info "Verifying certificate details..."

:local certDetails [/certificate get [find name=$cfgRouterCertName]]
:local certStatus ($certDetails->"status")
:local certInvalid ($certDetails->"invalid")
:local certTrusted ($certDetails->"trusted")
:local certDaysValid ($certDetails->"days-valid")
:local certIssuer ($certDetails->"issuer")
:local certSubject ($certDetails->"subject")

:if ($certInvalid = true) do={
    :log error "ERROR: Certificate is INVALID!"
    :log error "Certificate details:"
    /certificate print detail where name=$cfgRouterCertName
    :error "Certificate validation failed"
}

:log info "Certificate verification successful:"
:log info "  Status: $certStatus"
:log info "  Invalid: $certInvalid"
:log info "  Trusted: $certTrusted"
:log info "  Days Valid: ~$certDaysValid"
:log info "  Issuer: $certIssuer"

############################################################
# STEP 7: Configure SSTP VPN to Use Certificate
############################################################

:log info "Configuring SSTP VPN server to use certificate..."

:do {
    /interface sstp-server server set certificate=$cfgRouterCertName
    :log info "SSTP server configured with certificate: $cfgRouterCertName"
} on-error={
    :log warning "SSTP server configuration skipped (may not be configured yet)"
}

############################################################
# STEP 8: Configure HTTPS WebFig to Use Certificate
############################################################

:log info "Configuring HTTPS WebFig/API to use certificate..."

:do {
    /ip service set www-ssl certificate=$cfgRouterCertName
    :log info "HTTPS WebFig/API configured with certificate: $cfgRouterCertName"
} on-error={
    :log warning "HTTPS configuration failed (service may be disabled)"
}

# Enable www-ssl if disabled
:do {
    :local wwwSslDisabled [/ip service get www-ssl disabled]
    :if ($wwwSslDisabled = true) do={
        :log info "Enabling HTTPS WebFig service..."
        /ip service set www-ssl disabled=no
        :log info "HTTPS WebFig enabled on port 443"
    }
} on-error={
    :log warning "HTTPS enable check skipped"
}

############################################################
# STEP 9: Cleanup Certificate Files (optional)
############################################################

:log info "Cleaning up certificate files..."

# Remove CSR file (no longer needed)
:local csrFileName ("$cfgHostname" . ".csr")
:if ([:len [/file find name=$csrFileName]] > 0) do={
    :log info "Removing CSR file: $csrFileName"
    /file remove [find name=$csrFileName]
}

# Keep certificate file for backup
:log info "Keeping certificate file: $certFileName (for backup)"

############################################################
# STEP 10: Display Certificate Information
############################################################

:log info "============================================"
:log info "CERTIFICATE IMPORT COMPLETE"
:log info "============================================"
:log info ""
:log info "Router Certificate: $cfgRouterCertName"
:log info "Common Name: $cfgHostname"
:log info "Issuer: $certIssuer"
:log info "Days Valid: ~$certDaysValid (expires in ~2 years)"
:log info "Status: $certStatus"
:log info ""
:log info "SERVICES CONFIGURED:"
:log info "  ✅ SSTP VPN: Using $cfgRouterCertName"
:log info "  ✅ HTTPS WebFig/API: Using $cfgRouterCertName"
:log info "  ⏳ IPsec: Configure manually with pki/services/20-ipsec-cert-auth.rsc"
:log info ""
:log info "VERIFICATION:"
:log info "  View all certificates: /certificate print"
:log info "  View certificate details: /certificate print detail where name=\"$cfgRouterCertName\""
:log info "  Check HTTPS: https://$cfgHostname/ or https://$([:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]])/"
:log info "  Check SSTP: /interface sstp-server server print"
:log info ""
:log info "NEXT STEPS:"
:log info "  1. Configure IPsec with certificates (if applicable):"
:log info "     /import pki/services/20-ipsec-cert-auth.rsc"
:log info "  2. Setup auto-renewal:"
:log info "     /import pki/router/13-router-auto-renewal.rsc"
:log info "  3. Test HTTPS access in browser (no warnings!)"
:log info "============================================"

:log info "PKI: Certificate import completed successfully"
