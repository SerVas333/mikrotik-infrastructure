# 04-lan-dhcp.rsc - LAN Network & DHCP
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# LAN Gateway Address
############################################################

/ip address
add address=$cfgLANGateway \
    interface=$cfgBridgeLAN \
    comment="LAN gateway"

############################################################
# DHCP Pool & Server
############################################################

/ip pool
add name=pool-lan \
    ranges=($cfgLANPoolStart . "-" . $cfgLANPoolEnd)

/ip dhcp-server
add name=dhcp-lan \
    interface=$cfgBridgeLAN \
    address-pool=pool-lan \
    lease-time=1d

/ip dhcp-server network
add address=$cfgLANNetwork \
    gateway=[:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]] \
    dns-server=[:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]]

############################################################
# IPv6 Router Advertisement
############################################################

/ipv6 nd
add interface=$cfgBridgeLAN \
    managed-address-configuration=yes \
    other-configuration-flag=yes \
    comment="IPv6 RA for LAN"

############################################################
# END OF LAN DHCP CONFIGURATION
############################################################

:log info "LAN DHCP configuration applied from 04-lan-dhcp.rsc"
:log info "LAN Network: $cfgLANNetwork | Gateway: $cfgLANGateway"
:log info "DHCP Pool: $cfgLANPoolStart - $cfgLANPoolEnd"
