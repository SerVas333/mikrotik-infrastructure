# 05-vlan-mgmt.rsc - Management VLAN Configuration
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# Create Management VLAN Interface
############################################################

/interface vlan
add name=vlan-mgmt \
    vlan-id=$cfgMgmtVLAN \
    interface=$cfgBridgeLAN \
    comment="Management VLAN $cfgMgmtVLAN"

############################################################
# Management Gateway Address
############################################################

/ip address
add address=$cfgMgmtGateway \
    interface=vlan-mgmt \
    comment="Management gateway"

############################################################
# DHCP for Management VLAN
############################################################

/ip pool
add name=pool-mgmt \
    ranges=($cfgMgmtPoolStart . "-" . $cfgMgmtPoolEnd)

/ip dhcp-server
add name=dhcp-mgmt \
    interface=vlan-mgmt \
    address-pool=pool-mgmt \
    lease-time=1d

/ip dhcp-server network
add address=$cfgMgmtNetwork \
    gateway=[:pick $cfgMgmtGateway 0 [:find $cfgMgmtGateway "/"]] \
    dns-server=[:pick $cfgMgmtGateway 0 [:find $cfgMgmtGateway "/"]]

############################################################
# Bridge VLAN Filtering
############################################################

/interface bridge vlan
add bridge=$cfgBridgeLAN \
    tagged=$cfgBridgeLAN \
    vlan-ids=$cfgMgmtVLAN \
    comment="Management VLAN"

############################################################
# END OF MANAGEMENT VLAN CONFIGURATION
############################################################

:log info "Management VLAN configuration applied from 05-vlan-mgmt.rsc"
:log info "VLAN ID: $cfgMgmtVLAN | Network: $cfgMgmtNetwork"
:log info "Gateway: $cfgMgmtGateway | Pool: $cfgMgmtPoolStart - $cfgMgmtPoolEnd"
