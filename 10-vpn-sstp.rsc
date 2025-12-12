# 10-vpn-sstp.rsc - SSTP VPN Server
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# SSTP VPN Server Configuration
############################################################

# IP Pool for SSTP clients
/ip pool
:if ([:len [find name=$cfgSSTPPoolName]] = 0) do={
    add name=$cfgSSTPPoolName ranges=$cfgSSTPPoolRange
}

# PPP Profile
/ppp profile
:if ([:len [find name=sstp-profile]] = 0) do={
    add name=sstp-profile \
        local-address=[:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]] \
        remote-address=$cfgSSTPPoolName \
        dns-server=$cfgSSTPDNS \
        use-encryption=required \
        comment="SSTP VPN profile"
}

# PPP Secrets (users)
/ppp secret
:if ([:len [find name=$secSSTPUser]] = 0) do={
    add name=$secSSTPUser \
        password=$secSSTPPass \
        profile=sstp-profile \
        service=sstp \
        comment="SSTP VPN user"
}

# Enable SSTP Server
# IMPORTANT: Requires valid certificate (see 14-cert-renew.rsc for Let's Encrypt)
/interface sstp-server server
set enabled=yes \
    default-profile=sstp-profile \
    certificate=$cfgSSTPCertName \
    authentication=mschap2 \
    force-aes=yes

############################################################
# END OF SSTP VPN CONFIGURATION
############################################################

:log info "SSTP VPN server configured from 10-vpn-sstp.rsc"
:log info "Pool: $cfgSSTPPoolName ($cfgSSTPPoolRange)"
:log info "Certificate: $cfgSSTPCertName"
:log info "User: $secSSTPUser"
