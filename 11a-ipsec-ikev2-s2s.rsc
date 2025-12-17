############################################################
# 11a-ipsec-ikev2-s2s.rsc - IPsec IKEv2 Site-to-Site VPN (VTI)
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
#
# ОСОБЕННОСТИ:
# - IKEv2 (современный протокол, быстрое переподключение)
# - AES-128-GCM (AEAD шифрование, высокая производительность)
# - SHA-256 PRF (безопасная хеш-функция)
# - ECDH P-256 (эллиптическая кривая для обмена ключами)
# - VTI (Virtual Tunnel Interface) - route-based IPsec
# - Perfect Forward Secrecy (PFS) с ECP256
#
# ПРЕИМУЩЕСТВА VTI:
# - Простая маршрутизация (как обычный интерфейс)
# - Динамические routing протоколы (OSPF, BGP)
# - Множественные подсети без policy-based правил
# - QoS и Traffic Engineering
############################################################

############################################################
# IPsec Phase 1 (IKE) Proposal
############################################################

# IKEv2 Proposal: AES-128-GCM + SHA-256 + ECDH P-256
/ip ipsec proposal
:if ([:len [find name=$cfgIPsecProposalName]] = 0) do={
    add name=$cfgIPsecProposalName \
        auth-algorithms=sha256 \
        enc-algorithms=aes-128-gcm \
        lifetime=8h \
        pfs-group=ecp256 \
        comment="IKEv2 AES-128-GCM SHA-256 ECDH-P256"
}

:log info "IPsec proposal created: $cfgIPsecProposalName (AES-128-GCM, SHA-256, ECP256)"

############################################################
# IPsec Peer Configuration
############################################################

# IPsec Peer (remote site)
/ip ipsec peer
:if ([:len [find name=$cfgIPsecPeerName]] = 0) do={
    add name=$cfgIPsecPeerName \
        address=($cfgIPsecRemoteEndpoint . "/32") \
        exchange-mode=ike2 \
        send-initial-contact=yes \
        passive=no \
        comment="Site-to-Site IPsec peer (IKEv2)"
}

:log info "IPsec peer created: $cfgIPsecPeerName ($cfgIPsecRemoteEndpoint)"

############################################################
# IPsec Identity (Authentication)
############################################################

# Pre-Shared Key authentication
/ip ipsec identity
:if ([:len [find peer=$cfgIPsecPeerName]] = 0) do={
    add peer=$cfgIPsecPeerName \
        auth-method=pre-shared-key \
        secret=$secIPsecPSK \
        generate-policy=port-strict \
        comment="PSK authentication for $cfgIPsecPeerName"
}

:log info "IPsec identity configured with PSK authentication"

############################################################
# IPsec Policy (VTI Template)
############################################################

# Policy template for VTI
/ip ipsec policy
:if ([:len [find group=$cfgIPsecPolicyGroup]] = 0) do={
    add src-address=$cfgIPsecLocalNetwork \
        dst-address=$cfgIPsecRemoteNetwork \
        group=$cfgIPsecPolicyGroup \
        proposal=$cfgIPsecProposalName \
        template=yes \
        comment="VTI policy template for site-to-site"
}

:log info "IPsec policy template created: group=$cfgIPsecPolicyGroup"

############################################################
# VTI Interface (Virtual Tunnel Interface)
############################################################

# Create VTI interface for route-based IPsec
/interface ipsec
:if ([:len [find name=$cfgIPsecInterface]] = 0) do={
    add name=$cfgIPsecInterface \
        mode=ip \
        src-address=[:pick $cfgIPsecLocalAddress 0 [:find $cfgIPsecLocalAddress "/"]] \
        dst-address=[:pick $cfgIPsecRemoteAddress 0 [:find $cfgIPsecRemoteAddress "/"]] \
        disabled=no \
        comment="Site-to-Site VTI tunnel"
}

:log info "VTI interface created: $cfgIPsecInterface"

############################################################
# IP Address on VTI Interface
############################################################

# Assign IP address to VTI interface
/ip address
:if ([:len [find interface=$cfgIPsecInterface]] = 0) do={
    add address=$cfgIPsecLocalAddress \
        interface=$cfgIPsecInterface \
        comment="IPsec VTI local IP"
}

:log info "VTI IP assigned: $cfgIPsecLocalAddress on $cfgIPsecInterface"

############################################################
# Static Route to Remote Network
############################################################

# Route to remote LAN via VTI
/ip route
:if ([:len [find dst-address=$cfgIPsecRemoteNetwork gateway=$cfgIPsecInterface]] = 0) do={
    add dst-address=$cfgIPsecRemoteNetwork \
        gateway=$cfgIPsecInterface \
        distance=1 \
        comment="Route to remote site via IPsec VTI"
}

:log info "Static route added: $cfgIPsecRemoteNetwork via $cfgIPsecInterface"

############################################################
# Firewall Rules for IPsec
############################################################

# Allow IPsec traffic (IKE UDP/500, NAT-T UDP/4500, ESP)
/ip firewall filter

# Allow IKE (UDP 500)
:if ([:len [find chain=input protocol=udp dst-port=500 comment~"IPsec IKE"]] = 0) do={
    add chain=input \
        protocol=udp \
        dst-port=500 \
        action=accept \
        place-before=0 \
        comment="IPsec IKE (UDP 500)"
}

# Allow NAT-T (UDP 4500)
:if ([:len [find chain=input protocol=udp dst-port=4500 comment~"IPsec NAT-T"]] = 0) do={
    add chain=input \
        protocol=udp \
        dst-port=4500 \
        action=accept \
        place-before=0 \
        comment="IPsec NAT-T (UDP 4500)"
}

# Allow ESP protocol
:if ([:len [find chain=input protocol=ipsec-esp comment~"IPsec ESP"]] = 0) do={
    add chain=input \
        protocol=ipsec-esp \
        action=accept \
        place-before=0 \
        comment="IPsec ESP"
}

:log info "Firewall rules added for IPsec (UDP 500, UDP 4500, ESP)"

############################################################
# Optional: NAT Exemption for Site-to-Site Traffic
############################################################

# Exclude site-to-site traffic from masquerade NAT
/ip firewall nat
:if ([:len [find chain=srcnat src-address=$cfgIPsecLocalNetwork dst-address=$cfgIPsecRemoteNetwork comment~"IPsec NAT exemption"]] = 0) do={
    add chain=srcnat \
        src-address=$cfgIPsecLocalNetwork \
        dst-address=$cfgIPsecRemoteNetwork \
        action=accept \
        place-before=0 \
        comment="IPsec NAT exemption (site-to-site traffic)"
}

:log info "NAT exemption added for site-to-site traffic"

############################################################
# Status and Verification
############################################################

:log info "============================================"
:log info "IPsec IKEv2 Site-to-Site VPN Configuration Complete"
:log info "============================================"
:log info "Cryptography:"
:log info "  - IKE: AES-128-GCM, SHA-256, ECDH P-256"
:log info "  - ESP: AES-128-GCM, PFS ECP256"
:log info "  - Mode: IKEv2 with VTI (route-based)"
:log info ""
:log info "Configuration:"
:log info "  - VTI Interface: $cfgIPsecInterface"
:log info "  - Local VTI IP: $cfgIPsecLocalAddress"
:log info "  - Remote VTI IP: $cfgIPsecRemoteAddress"
:log info "  - Remote Endpoint: $cfgIPsecRemoteEndpoint"
:log info "  - Local Network: $cfgIPsecLocalNetwork"
:log info "  - Remote Network: $cfgIPsecRemoteNetwork"
:log info ""
:log info "NEXT STEPS:"
:log info "1. Configure IDENTICAL settings on remote site"
:log info "2. Use SAME Pre-Shared Key on both sides"
:log info "3. Swap local/remote IPs and networks on remote site"
:log info "4. Verify connectivity: /ping $cfgIPsecRemoteAddress"
:log info "5. Check tunnel status: /ip ipsec active-peers print"
:log info "6. Check policies: /ip ipsec policy print"
:log info "============================================"

############################################################
# END OF IPsec IKEv2 SITE-TO-SITE VPN CONFIGURATION
############################################################
