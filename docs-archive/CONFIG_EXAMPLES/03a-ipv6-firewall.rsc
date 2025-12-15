# ===================================================================
# 03a-ipv6-firewall.rsc
# IPv6 Firewall Configuration - УЛУЧШЕННАЯ ВЕРСИЯ
# Based on MikroTik best practices 2025 + Perplexity recommendations
# ===================================================================

############################################################
# КОНФИГУРАЦИЯ ПЕРЕМЕННЫХ
############################################################

:local LAN_BRIDGE "bridge-lan"
:local WAN_IFACE1 "pppoe-out1"
:local WAN_IFACE2 "sit1"

# Rate limiting для ICMPv6
:local ICMP_INPUT_LIMIT "50/5s,10:packet"
:local ICMP_FORWARD_LIMIT "100/5s,20:packet"

############################################################

# INPUT Chain
/ipv6 firewall filter
add chain=input connection-state=established,related action=accept \
    comment="Accept established/related"
add chain=input connection-state=invalid action=drop \
    comment="Drop invalid"
add chain=input protocol=icmpv6 limit=$ICMP_INPUT_LIMIT action=accept \
    comment="Accept ICMPv6 (rate limited)"
add chain=input protocol=icmpv6 action=drop \
    comment="Drop ICMPv6 flood"
add chain=input protocol=udp dst-port=546 src-address=fe80::/10 action=accept \
    comment="Accept DHCPv6-Client"
add chain=input in-interface-list=LAN action=accept \
    comment="Accept from LAN"
add chain=input action=log log-prefix="IPv6-INPUT-DROP: " \
    comment="Log other input"
add chain=input action=drop \
    comment="Drop all other input"

# FORWARD Chain
add chain=forward connection-state=established,related action=accept \
    comment="Accept established/related"
add chain=forward connection-state=invalid action=drop \
    comment="Drop invalid"
add chain=forward protocol=icmpv6 limit=$ICMP_FORWARD_LIMIT action=accept \
    comment="Accept ICMPv6 forward"
add chain=forward protocol=icmpv6 action=drop \
    comment="Drop ICMPv6 forward flood"
add chain=forward in-interface-list=WAN src-address=fc00::/7 action=drop \
    comment="Drop ULA from WAN"
add chain=forward in-interface-list=WAN src-address=fe80::/10 action=drop \
    comment="Drop link-local from WAN"
add chain=forward in-interface-list=LAN out-interface-list=WAN action=accept \
    comment="Allow LAN to WAN"
add chain=forward in-interface-list=WAN out-interface-list=LAN action=drop \
    comment="Drop WAN to LAN by default"
add chain=forward action=log log-prefix="IPv6-FORWARD-DROP: " \
    comment="Log other forward"
add chain=forward action=drop \
    comment="Drop all other forward"

# Interface Lists
:if ([:len [/interface list find name=LAN]] = 0) do={
    /interface list add name=LAN comment="LAN interfaces"
    /interface list member add list=LAN interface=$LAN_BRIDGE
}

:if ([:len [/interface list find name=WAN]] = 0) do={
    /interface list add name=WAN comment="WAN interfaces"
    /interface list member add list=WAN interface=$WAN_IFACE1
    /interface list member add list=WAN interface=$WAN_IFACE2
}

# IPv6 ND Security (отключить Router Advertisement на WAN)
/ipv6 nd
set [ find interface=$WAN_IFACE1 ] ra-interval=0s ra-lifetime=0s \
    advertise=no comment="Disable RA on PPPoE"
set [ find interface=$WAN_IFACE2 ] ra-interval=0s ra-lifetime=0s \
    advertise=no comment="Disable RA on HE tunnel"

:log info "IPv6 Firewall configured successfully"
