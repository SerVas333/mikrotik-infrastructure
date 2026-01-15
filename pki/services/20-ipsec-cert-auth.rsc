############################################################
# pki/services/20-ipsec-cert-auth.rsc - IPsec IKEv2 WITH CERTIFICATES
# ТРЕБУЕТ: 00-config.rsc, router certificate должен быть импортирован!
#
# НАЗНАЧЕНИЕ:
# - IPsec IKEv2 Site-to-Site VPN с certificate authentication
# - ЗАМЕНЯЕТ PSK authentication из 11a-ipsec-ikev2-s2s.rsc
# - Использует существующую VTI infrastructure
# - Zero-downtime migration от PSK к certificates
#
# ОСОБЕННОСТИ:
# - Authentication: rsa-signature (works with ECDSA certificates!)
# - Encryption: AES-128-GCM (AEAD)
# - Key Exchange: ECDH P-256
# - PFS: ECP256
# - VTI (Virtual Tunnel Interface) для route-based IPsec
############################################################

:log info "===== PKI: IPsec IKEv2 Certificate Authentication Setup ====="

############################################################
# STEP 1: Verify Prerequisites
############################################################

:log info "Verifying prerequisites..."

# Check router certificate exists
:local certExists [:len [/certificate find name=$cfgRouterCertName where !invalid]]
:if ($certExists = 0) do={
    :log error "ERROR: Router certificate not found: $cfgRouterCertName"
    :log error "Import certificate first: /import pki/router/12-router-cert-import.rsc"
    :error "Router certificate missing"
}

# Check CA certificate exists and is trusted
:local caExists [:len [/certificate find name=$cfgCACommonName where trusted=yes]]
:if ($caExists = 0) do={
    :log error "ERROR: CA certificate not found or not trusted: $cfgCACommonName"
    :log error "Import CA certificate first"
    :error "CA certificate missing"
}

:log info "Prerequisites verified:"
:log info "  ✅ Router certificate: $cfgRouterCertName"
:log info "  ✅ CA certificate: $cfgCACommonName (trusted)"

############################################################
# STEP 2: IPsec Proposal (same as PSK version)
############################################################

:log info "Configuring IPsec proposal..."

/ip ipsec proposal
:if ([:len [find name=$cfgIPsecProposalName]] = 0) do={
    add name=$cfgIPsecProposalName \
        auth-algorithms=sha256 \
        enc-algorithms=aes-128-gcm \
        lifetime=8h \
        pfs-group=ecp256 \
        comment="IKEv2 AES-128-GCM SHA-256 ECDH-P256"
}

:log info "IPsec proposal configured: $cfgIPsecProposalName"

############################################################
# STEP 3: IPsec Peer Configuration
############################################################

:log info "Configuring IPsec peer..."

/ip ipsec peer
:if ([:len [find name=$cfgIPsecPeerName]] > 0) do={
    :log warning "Updating existing peer: $cfgIPsecPeerName"
    set $cfgIPsecPeerName \
        address=($cfgIPsecRemoteEndpoint . "/32") \
        exchange-mode=ike2 \
        send-initial-contact=yes \
        passive=no
} else={
    add name=$cfgIPsecPeerName \
        address=($cfgIPsecRemoteEndpoint . "/32") \
        exchange-mode=ike2 \
        send-initial-contact=yes \
        passive=no \
        comment="Site-to-Site IPsec peer (IKEv2 with certificates)"
}

:log info "IPsec peer configured: $cfgIPsecPeerName"

############################################################
# STEP 4: IPsec Identity - CERTIFICATE AUTHENTICATION
############################################################

:log info "Configuring IPsec identity with certificate authentication..."

# Remove old PSK identity if exists
/ip ipsec identity
:local pskIdentity [find peer=$cfgIPsecPeerName where auth-method=pre-shared-key]
:if ([:len $pskIdentity] > 0) do={
    :log warning "Removing PSK identity (migrating to certificate auth)..."
    remove $pskIdentity
}

# Add or update certificate identity
:local certIdentity [find peer=$cfgIPsecPeerName where auth-method=rsa-signature]
:if ([:len $certIdentity] = 0) do={
    :log info "Creating new certificate identity..."
    add peer=$cfgIPsecPeerName \
        auth-method=rsa-signature \
        certificate=$cfgRouterCertName \
        generate-policy=port-strict \
        match-by=certificate \
        comment="Certificate authentication for $cfgIPsecPeerName"
} else={
    :log info "Updating existing certificate identity..."
    set $certIdentity \
        certificate=$cfgRouterCertName \
        match-by=certificate
}

:log info "IPsec identity configured: rsa-signature (certificate auth)"

############################################################
# STEP 5: IPsec Policy Template (VTI)
############################################################

:log info "Configuring IPsec policy template..."

/ip ipsec policy
:if ([:len [find group=$cfgIPsecPolicyGroup]] = 0) do={
    add src-address=$cfgIPsecLocalNetwork \
        dst-address=$cfgIPsecRemoteNetwork \
        group=$cfgIPsecPolicyGroup \
        proposal=$cfgIPsecProposalName \
        template=yes \
        comment="VTI policy template for site-to-site"
}

:log info "IPsec policy configured: group=$cfgIPsecPolicyGroup"

############################################################
# STEP 6: VTI Interface
############################################################

:log info "Configuring VTI interface..."

/interface ipsec
:if ([:len [find name=$cfgIPsecInterface]] = 0) do={
    add name=$cfgIPsecInterface \
        mode=ip \
        src-address=[:pick $cfgIPsecLocalAddress 0 [:find $cfgIPsecLocalAddress "/"]] \
        dst-address=[:pick $cfgIPsecRemoteAddress 0 [:find $cfgIPsecRemoteAddress "/"]] \
        disabled=no \
        comment="Site-to-Site VTI tunnel (certificate auth)"
}

:log info "VTI interface configured: $cfgIPsecInterface"

############################################################
# STEP 7: VTI IP Address
############################################################

:log info "Configuring VTI IP address..."

/ip address
:if ([:len [find interface=$cfgIPsecInterface]] = 0) do={
    add address=$cfgIPsecLocalAddress \
        interface=$cfgIPsecInterface \
        comment="IPsec VTI local IP"
}

:log info "VTI IP configured: $cfgIPsecLocalAddress"

############################################################
# STEP 8: Static Route to Remote Network
############################################################

:log info "Configuring static route to remote network..."

/ip route
:if ([:len [find dst-address=$cfgIPsecRemoteNetwork gateway=$cfgIPsecInterface]] = 0) do={
    add dst-address=$cfgIPsecRemoteNetwork \
        gateway=$cfgIPsecInterface \
        distance=1 \
        comment="Route to remote site via IPsec VTI (cert auth)"
}

:log info "Route configured: $cfgIPsecRemoteNetwork via $cfgIPsecInterface"

############################################################
# STEP 9: Firewall Rules for IPsec
############################################################

:log info "Configuring firewall rules for IPsec..."

/ip firewall filter

# Allow IKE (UDP 500)
:if ([:len [find chain=input protocol=udp dst-port=500 comment~"IPsec IKE"]] = 0) do={
    add chain=input protocol=udp dst-port=500 action=accept \
        place-before=0 comment="IPsec IKE (UDP 500)"
}

# Allow NAT-T (UDP 4500)
:if ([:len [find chain=input protocol=udp dst-port=4500 comment~"IPsec NAT-T"]] = 0) do={
    add chain=input protocol=udp dst-port=4500 action=accept \
        place-before=0 comment="IPsec NAT-T (UDP 4500)"
}

# Allow ESP protocol
:if ([:len [find chain=input protocol=ipsec-esp comment~"IPsec ESP"]] = 0) do={
    add chain=input protocol=ipsec-esp action=accept \
        place-before=0 comment="IPsec ESP"
}

:log info "Firewall rules configured for IPsec"

############################################################
# STEP 10: NAT Exemption (if needed)
############################################################

:log info "Configuring NAT exemption for site-to-site traffic..."

/ip firewall nat
:if ([:len [find chain=srcnat src-address=$cfgIPsecLocalNetwork dst-address=$cfgIPsecRemoteNetwork comment~"IPsec NAT exemption"]] = 0) do={
    add chain=srcnat \
        src-address=$cfgIPsecLocalNetwork \
        dst-address=$cfgIPsecRemoteNetwork \
        action=accept \
        place-before=0 \
        comment="IPsec NAT exemption (site-to-site traffic)"
}

:log info "NAT exemption configured"

############################################################
# STEP 11: Display Configuration Summary
############################################################

:log info "============================================"
:log info "IPsec IKEv2 CERTIFICATE AUTHENTICATION COMPLETE"
:log info "============================================"
:log info ""
:log info "AUTHENTICATION:"
:log info "  Method: rsa-signature (certificate-based)"
:log info "  Local Certificate: $cfgRouterCertName"
:log info "  CA: $cfgCACommonName"
:log info "  ✅ PSK authentication REMOVED"
:log info ""
:log info "CRYPTOGRAPHY:"
:log info "  IKE: AES-128-GCM, SHA-256, ECDH P-256"
:log info "  ESP: AES-128-GCM, PFS ECP256"
:log info "  Mode: IKEv2 with VTI (route-based)"
:log info ""
:log info "CONFIGURATION:"
:log info "  VTI Interface: $cfgIPsecInterface"
:log info "  Local VTI IP: $cfgIPsecLocalAddress"
:log info "  Remote VTI IP: $cfgIPsecRemoteAddress"
:log info "  Remote Endpoint: $cfgIPsecRemoteEndpoint"
:log info "  Local Network: $cfgIPsecLocalNetwork"
:log info "  Remote Network: $cfgIPsecRemoteNetwork"
:log info ""
:log info "VERIFICATION:"
:log info "  Check identity: /ip ipsec identity print"
:log info "  Check peer: /ip ipsec peer print"
:log info "  Check active peers: /ip ipsec active-peers print"
:log info "  Ping remote VTI: /ping [:pick $cfgIPsecRemoteAddress 0 [:find $cfgIPsecRemoteAddress \"/\"]]"
:log info "  Check tunnel: /ip ipsec installed-sa print"
:log info ""
:log info "TROUBLESHOOTING:"
:log info "  If tunnel doesn't establish:"
:log info "  1. Check remote site has same CA-signed certificate"
:log info "  2. Check logs: /log print where topics~\"ipsec\""
:log info "  3. Verify certificate validity: /certificate print detail"
:log info "  4. Check firewall allows UDP 500, 4500, ESP"
:log info "============================================"

:log info "PKI: IPsec certificate authentication configured successfully"
