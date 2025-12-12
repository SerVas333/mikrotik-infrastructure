# 02-wan-pppoe-ipv4.rsc - WAN PPPoE + Basic IPv4 Firewall
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# PPPoE Client (WAN Connection)
############################################################

/interface pppoe-client
add name=$cfgWanPPPoE \
    interface=$cfgWanInterface \
    user=$secPPPoEUser \
    password=$secPPPoEPass \
    add-default-route=yes \
    use-peer-dns=no \
    disabled=no \
    comment="WAN PPPoE connection"

############################################################
# Basic IPv4 Firewall (INPUT Chain)
############################################################

/ip firewall filter

# Accept established/related connections
add chain=input connection-state=established,related \
    action=accept comment="Allow established/related"

# Drop invalid packets
add chain=input connection-state=invalid \
    action=drop comment="Drop invalid packets"

# Allow LAN to router
add chain=input in-interface=$cfgBridgeLAN \
    action=accept comment="Allow LAN -> router"

# Drop WAN -> router (except allowed services)
add chain=input in-interface=$cfgWanPPPoE \
    action=drop comment="Drop WAN -> router"

############################################################
# Basic IPv4 Firewall (FORWARD Chain)
############################################################

# Accept established/related
add chain=forward connection-state=established,related \
    action=accept comment="Allow established/related forward"

# Drop invalid
add chain=forward connection-state=invalid \
    action=drop comment="Drop invalid forward"

############################################################
# NAT Masquerade
############################################################

/ip firewall nat
add chain=srcnat out-interface=$cfgWanPPPoE \
    action=masquerade comment="Masquerade to WAN"

############################################################
# END OF WAN CONFIGURATION
############################################################

:log info "WAN PPPoE configuration applied from 02-wan-pppoe-ipv4.rsc"
:log info "WAN Interface: $cfgWanInterface | PPPoE: $cfgWanPPPoE"
:log info "PPPoE User: $secPPPoEUser"
