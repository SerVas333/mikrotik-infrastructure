# 11-vpn-site2site.rsc - WireGuard Site-to-Site VPN
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# WireGuard Site-to-Site VPN Configuration
############################################################

# Create WireGuard interface
/interface wireguard
:if ([:len [find name=$cfgWGInterface]] = 0) do={
    add name=$cfgWGInterface \
        listen-port=$cfgWGListenPort \
        private-key=$secWGPrivateKey \
        comment="Site-to-Site VPN tunnel"
}

# Assign IP address to WireGuard interface
/ip address
:if ([:len [find interface=$cfgWGInterface]] = 0) do={
    add address=$cfgWGLocalAddress \
        interface=$cfgWGInterface \
        comment="WireGuard local IP"
}

# Add WireGuard peer (remote site)
/interface wireguard peers
:if ([:len [find interface=$cfgWGInterface]] = 0) do={
    add interface=$cfgWGInterface \
        public-key=$secWGRemotePublicKey \
        allowed-address=$cfgWGRemoteAddress,$cfgWGRemoteAllowedIP \
        endpoint=$cfgWGRemoteEndpoint \
        persistent-keepalive=25s \
        comment="Remote site peer"
}

# Add static route to remote network
/ip route
add dst-address=$cfgWGRemoteAllowedIP \
    gateway=$cfgWGInterface \
    comment="Route to remote site via WireGuard"

############################################################
# END OF WIREGUARD S2S VPN CONFIGURATION
############################################################

:log info "WireGuard Site-to-Site VPN configured from 11-vpn-site2site.rsc"
:log info "Interface: $cfgWGInterface | Listen port: $cfgWGListenPort"
:log info "Local: $cfgWGLocalAddress | Remote: $cfgWGRemoteAddress"
:log info "Remote network: $cfgWGRemoteAllowedIP"
