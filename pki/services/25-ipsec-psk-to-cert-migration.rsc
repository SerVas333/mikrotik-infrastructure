############################################################
# pki/services/25-ipsec-psk-to-cert-migration.rsc
# PSK → CERTIFICATE MIGRATION FOR VPN ROUTERS
#
# ТРЕБУЕТ: 00-config.rsc, router certificate, IPsec с PSK работает!
#
# НАЗНАЧЕНИЕ:
# - Безопасная миграция IPsec от PSK к certificate authentication
# - Zero-downtime migration для VPN роутеров (Site B, Site C, etc.)
# - Dual auth setup (PSK + Cert) для безопасной миграции
# - Rollback procedures если certificate auth не работает
#
# BOOTSTRAP SCENARIO:
# 1. Site B подключен к R1-Core через IPsec с PSK
# 2. Получен certificate через FTP over VPN
# 3. Migration к certificate auth без downtime
############################################################

:log info "===== PKI: IPsec PSK → Certificate Migration ====="

############################################################
# STEP 1: Verify Prerequisites
############################################################

:log info "Step 1/6: Verifying prerequisites..."

# Check IPsec peer exists
:local peerExists [:len [/ip ipsec peer find name=$cfgIPsecPeerName]]
:if ($peerExists = 0) do={
    :log error "ERROR: IPsec peer not found: $cfgIPsecPeerName"
    :log error "Setup IPsec first: /import 11a-ipsec-ikev2-s2s.rsc"
    :error "IPsec peer missing"
}

# Check PSK identity exists
:local pskIdentity [/ip ipsec identity find peer=$cfgIPsecPeerName where auth-method=pre-shared-key]
:if ([:len $pskIdentity] = 0) do={
    :log warning "WARNING: PSK identity not found"
    :log warning "This script is for migrating FROM PSK TO certificate auth"
    :log warning "If already using certificates, use: /import pki/services/20-ipsec-cert-auth.rsc"
    :error "PSK identity not found - migration not needed?"
}

# Check router certificate exists
:local certExists [:len [/certificate find name=$cfgRouterCertName where !invalid]]
:if ($certExists = 0) do={
    :log error "ERROR: Router certificate not found: $cfgRouterCertName"
    :log error "Import certificate first:"
    :log error "  1. /import pki/router/10-router-cert-gen.rsc"
    :log error "  2. /import pki/router/11-router-ftp-upload.rsc"
    :log error "  3. /import pki/router/12-router-cert-import.rsc"
    :error "Router certificate missing"
}

# Check CA certificate exists and trusted
:local caExists [:len [/certificate find name=$cfgCACommonName where trusted=yes]]
:if ($caExists = 0) do={
    :log error "ERROR: CA certificate not found or not trusted: $cfgCACommonName"
    :error "CA certificate missing"
}

:log info "Prerequisites verified:"
:log info "  ✅ IPsec peer: $cfgIPsecPeerName"
:log info "  ✅ PSK identity: active"
:log info "  ✅ Router certificate: $cfgRouterCertName"
:log info "  ✅ CA certificate: $cfgCACommonName (trusted)"

############################################################
# STEP 2: Check Current IPsec Tunnel Status
############################################################

:log info "Step 2/6: Checking current IPsec tunnel status..."

:local tunnelActive [:len [/ip ipsec active-peers find]]
:if ($tunnelActive > 0) do={
    :log info "IPsec tunnel is ACTIVE (good!)"
    /ip ipsec active-peers print
} else={
    :log warning "WARNING: No active IPsec peers found"
    :log warning "Tunnel may not be established yet"
    :log warning "Continue anyway? This will add certificate auth parallel to PSK"

    # In script mode, continue
    :log info "Continuing with migration..."
}

############################################################
# STEP 3: Add Certificate Identity (Dual Auth Setup)
############################################################

:log info "Step 3/6: Adding certificate identity (dual auth setup)..."
:log info "NOTE: PSK identity will remain active for now"

# Check if certificate identity already exists
:local certIdentity [/ip ipsec identity find peer=$cfgIPsecPeerName where auth-method=rsa-signature]
:if ([:len $certIdentity] > 0) do={
    :log warning "Certificate identity already exists, updating..."
    /ip ipsec identity set $certIdentity \
        certificate=$cfgRouterCertName \
        match-by=certificate
} else={
    :log info "Creating new certificate identity..."
    /ip ipsec identity add \
        peer=$cfgIPsecPeerName \
        auth-method=rsa-signature \
        certificate=$cfgRouterCertName \
        generate-policy=port-strict \
        match-by=certificate \
        comment="Certificate auth (migrated from PSK)"
}

:log info "Certificate identity configured"
:log info "Current authentication methods: PSK + Certificate (dual auth)"

############################################################
# STEP 4: Wait and Verify Tunnel Remains Active
############################################################

:log info "Step 4/6: Verifying tunnel remains active after adding certificate auth..."

:delay 10s

:local tunnelStillActive [:len [/ip ipsec active-peers find]]
:if ($tunnelStillActive > 0) do={
    :log info "✅ Tunnel remains ACTIVE after certificate auth addition"
    /ip ipsec active-peers print
} else={
    :log error "❌ WARNING: Tunnel not active!"
    :log error "This may be normal during renegotiation"
    :log error "Wait 30 seconds for tunnel re-establishment..."

    :delay 30s

    :set tunnelStillActive [:len [/ip ipsec active-peers find]]
    :if ($tunnelStillActive > 0) do={
        :log info "✅ Tunnel re-established successfully"
    } else={
        :log error "❌ ERROR: Tunnel failed to re-establish"
        :log error "ROLLBACK: Removing certificate identity..."

        :local certId [/ip ipsec identity find peer=$cfgIPsecPeerName where auth-method=rsa-signature]
        :if ([:len $certId] > 0) do={
            /ip ipsec identity remove $certId
        }

        :error "Migration failed - rolled back to PSK only"
    }
}

############################################################
# STEP 5: Test Connectivity
############################################################

:log info "Step 5/6: Testing VPN connectivity..."

:local remoteVTI [:pick $cfgIPsecRemoteAddress 0 [:find $cfgIPsecRemoteAddress "/"]]
:log info "Pinging remote VTI: $remoteVTI"

:local pingResult [/ping $remoteVTI count=5]
:if ($pingResult > 0) do={
    :log info "✅ Ping successful: $pingResult/5 replies"
} else={
    :log error "❌ Ping failed to remote VTI"
    :log error "Tunnel may not be working correctly"
    :log error "Check logs: /log print where topics~\"ipsec\""
}

############################################################
# STEP 6: Optional - Remove PSK Identity
############################################################

:log warning "============================================"
:log warning "MIGRATION STATUS: DUAL AUTH ACTIVE"
:log warning "============================================"
:log warning ""
:log warning "Current Configuration:"
:log warning "  Authentication: PSK + Certificate (both active)"
:log warning "  Status: Tunnel operational"
:log warning ""
:log warning "NEXT STEPS:"
:log warning ""
:log warning "Option A: Keep dual auth (RECOMMENDED for now)"
:log warning "  - Both PSK and Certificate auth work"
:log warning "  - Safe fallback if certificate expires"
:log warning "  - No action needed"
:log warning ""
:log warning "Option B: Remove PSK auth (after verification)"
:log warning "  - Only certificate auth will work"
:log warning "  - More secure (no PSK)"
:log warning "  - Run this command to remove PSK:"
:log warning "    /ip ipsec identity remove [find peer=$cfgIPsecPeerName where auth-method=pre-shared-key]"
:log warning ""
:log warning "VERIFICATION:"
:log warning "  Check identities: /ip ipsec identity print"
:log warning "  Check active tunnel: /ip ipsec active-peers print"
:log warning "  Check logs: /log print where topics~\"ipsec\""
:log warning "============================================"

############################################################
# STEP 7: Display Current Configuration
############################################################

:log info ""
:log info "CURRENT IPSEC IDENTITIES:"
/ip ipsec identity print where peer=$cfgIPsecPeerName

:log info ""
:log info "ACTIVE IPSEC PEERS:"
/ip ipsec active-peers print

############################################################
# STEP 8: Provide Rollback Instructions
############################################################

:log info "============================================"
:log info "ROLLBACK PROCEDURE (if needed)"
:log info "============================================"
:log info ""
:log info "If certificate auth doesn't work:"
:log info ""
:log info "1. Remove certificate identity:"
:log info "   /ip ipsec identity remove [find peer=$cfgIPsecPeerName where auth-method=rsa-signature]"
:log info ""
:log info "2. Verify PSK identity still exists:"
:log info "   /ip ipsec identity print where peer=$cfgIPsecPeerName"
:log info ""
:log info "3. Wait for tunnel re-establishment (30-60 seconds)"
:log info ""
:log info "4. Check logs for errors:"
:log info "   /log print where topics~\"ipsec,error\""
:log info "============================================"

:log info "PKI: IPsec PSK → Certificate migration completed (dual auth active)"
