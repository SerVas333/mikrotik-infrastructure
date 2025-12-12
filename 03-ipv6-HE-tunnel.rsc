# 03-ipv6-HE-tunnel.rsc - Hurricane Electric IPv6 Tunnel
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# Create 6in4 (SIT) Tunnel
############################################################

/interface 6to4
add name=$cfgIPv6TunnelInterface \
    local-address=$cfgWANPublicIP \
    remote-address=$cfgHERemoteIP \
    mtu=1280 \
    comment="Hurricane Electric IPv6 tunnel"

############################################################
# IPv6 Address on Tunnel
############################################################

/ipv6 address
add interface=$cfgIPv6TunnelInterface \
    address=$cfgHELocalIPv6 \
    advertise=no \
    comment="HE tunnel IPv6 address"

############################################################
# IPv6 Default Route
############################################################

/ipv6 route
add dst-address=2000::/3 \
    gateway=$cfgHERemoteGW \
    comment="IPv6 default route via HE"

############################################################
# END OF IPv6 TUNNEL CONFIGURATION
############################################################

:log info "IPv6 HE tunnel configured from 03-ipv6-HE-tunnel.rsc"
:log info "Tunnel: $cfgIPv6TunnelInterface | Local IPv6: $cfgHELocalIPv6"
