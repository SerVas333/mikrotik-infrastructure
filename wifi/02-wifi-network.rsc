############################################################
# 02-wifi-network.rsc - Network Configuration for WiFi VLANs
# REQUIRES: 00-config.rsc must be imported first!
#
# Создаёт:
# - VLAN интерфейсы для Main и Guest WiFi
# - IP адреса на VLAN интерфейсах
# - DHCP серверы для клиентов WiFi
# - DNS настройки
#
# ВАЖНО:
# - Применяйте ПОСЛЕ 01-wifi-capsman.rsc
# - Firewall и NAT правила в firewall_complete.rsc
############################################################

############################################################
# VLAN ИНТЕРФЕЙСЫ
############################################################

# Main WiFi VLAN interface
:if ([:len [/interface vlan find name=vlan-main-wifi]] = 0) do={
    /interface vlan
    add name=vlan-main-wifi \
        vlan-id=$cfgWiFiMainVLAN \
        interface=$cfgBridgeLAN \
        comment="Main WiFi VLAN $cfgWiFiMainVLAN"

    :log info "Created VLAN interface: vlan-main-wifi (VLAN $cfgWiFiMainVLAN)"
}

# Guest WiFi VLAN interface
:if ([:len [/interface vlan find name=vlan-guest-wifi]] = 0) do={
    /interface vlan
    add name=vlan-guest-wifi \
        vlan-id=$cfgWiFiGuestVLAN \
        interface=$cfgBridgeLAN \
        comment="Guest WiFi VLAN $cfgWiFiGuestVLAN"

    :log info "Created VLAN interface: vlan-guest-wifi (VLAN $cfgWiFiGuestVLAN)"
}

############################################################
# IP АДРЕСА
############################################################

# Main WiFi gateway (using cfgLANGateway, adjust if different)
# For now, using hardcoded example from original file
# In production, add cfgWiFiMainGateway to 00-config.rsc
:local mainGateway "192.168.20.1/24"

:if ([:len [/ip address find interface=vlan-main-wifi]] = 0) do={
    /ip address
    add address=$mainGateway \
        interface=vlan-main-wifi \
        comment="Main WiFi gateway"

    :log info "Added IP address $mainGateway to vlan-main-wifi"
}

# Guest WiFi gateway
:if ([:len [/ip address find interface=vlan-guest-wifi]] = 0) do={
    /ip address
    add address=$cfgGuestGateway \
        interface=vlan-guest-wifi \
        comment="Guest WiFi gateway"

    :log info "Added IP address $cfgGuestGateway to vlan-guest-wifi"
}

############################################################
# DHCP POOLS
############################################################

# Main WiFi pool
:if ([:len [/ip pool find name=pool-main-wifi]] = 0) do={
    /ip pool
    add name=pool-main-wifi \
        ranges="192.168.20.10-192.168.20.250" \
        comment="DHCP pool for main WiFi"

    :log info "Created DHCP pool: pool-main-wifi"
}

# Guest WiFi pool
:if ([:len [/ip pool find name=pool-guest-wifi]] = 0) do={
    /ip pool
    add name=pool-guest-wifi \
        ranges=($cfgGuestPoolStart . "-" . $cfgGuestPoolEnd) \
        comment="DHCP pool for guest WiFi"

    :log info "Created DHCP pool: pool-guest-wifi"
}

############################################################
# DHCP SERVERS
############################################################

# Main WiFi DHCP server
:if ([:len [/ip dhcp-server find name=dhcp-main-wifi]] = 0) do={
    /ip dhcp-server
    add name=dhcp-main-wifi \
        interface=vlan-main-wifi \
        address-pool=pool-main-wifi \
        lease-time=1d \
        disabled=no \
        comment="DHCP server for main WiFi"

    :log info "Created DHCP server: dhcp-main-wifi"
}

# Guest WiFi DHCP server
:if ([:len [/ip dhcp-server find name=dhcp-guest-wifi]] = 0) do={
    /ip dhcp-server
    add name=dhcp-guest-wifi \
        interface=vlan-guest-wifi \
        address-pool=pool-guest-wifi \
        lease-time=6h \
        disabled=no \
        comment="DHCP server for guest WiFi"

    :log info "Created DHCP server: dhcp-guest-wifi"
}

############################################################
# DHCP NETWORKS
############################################################

# Main WiFi DHCP network
:if ([:len [/ip dhcp-server network find comment="Main WiFi DHCP network"]] = 0) do={
    /ip dhcp-server network
    add address=192.168.20.0/24 \
        gateway=192.168.20.1 \
        dns-server=[:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]] \
        comment="Main WiFi DHCP network"

    :log info "Configured DHCP network for main WiFi"
}

# Guest WiFi DHCP network
:if ([:len [/ip dhcp-server network find comment="Guest WiFi DHCP network"]] = 0) do={
    /ip dhcp-server network
    add address=$cfgGuestNetwork \
        gateway=[:pick $cfgGuestGateway 0 [:find $cfgGuestGateway "/"]] \
        dns-server=[:pick $cfgLANGateway 0 [:find $cfgLANGateway "/"]] \
        comment="Guest WiFi DHCP network"

    :log info "Configured DHCP network for guest WiFi"
}

############################################################
# FINALIZATION
############################################################

:log info "WiFi network configuration completed from wifi/02-wifi-network.rsc"
:log info "Main WiFi: VLAN $cfgWiFiMainVLAN | Gateway: $mainGateway"
:log info "Guest WiFi: VLAN $cfgWiFiGuestVLAN | Gateway: $cfgGuestGateway"
:log info "Guest DHCP: $cfgGuestPoolStart - $cfgGuestPoolEnd"
