############################################################
# 05-rb2011-wds-station-bridge.rsc - WDS Station for RB2011
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
#
# Назначение:
# - Подключается к WDS AP на R2
# - Расширяет Guest VLAN на локальные LAN порты
# - Обеспечивает безопасность management
#
# Применять на: RB2011 (RouterOS 6.40+)
# Требования: R2 должен быть настроен (04-r2-wds-ap-bridge.rsc)
############################################################

############################################################
# WDS CONFIGURATION
############################################################

# WDS Settings
:local WDS_SSID $cfgWDSSSID
:local WDS_PASS $secWDSPass
:local COUNTRY $cfgWiFiCountry
:local CHANNEL [:tonum $cfgWDSChannel]
:local BAND "2ghz-b/g/n"

# Management Network
:local MGMT_VLAN $cfgMgmtVLAN

# WDS AP on R2 (need to define R2 MAC in 00-config.rsc)
# For now using placeholder
:local R2_MAC "BB:CC:DD:EE:FF:AA"  # REPLACE with actual R2 wds-ap MAC

# LAN Ports для Guest clients
:local GUEST_PORTS [:toarray "ether2,ether3,ether4,ether5,ether6,ether7,ether8,ether9,ether10"]

# Monitoring
:local MIN_SIGNAL_THRESHOLD -75

############################################################
# WARNING
############################################################

:put "WARNING: This script will make destructive changes!"
:put "Press Ctrl+C within 10 seconds to cancel..."
:delay 10s

############################################################
# CLEANUP
############################################################

:log warning "WDS: Starting cleanup (removing DHCP servers, IPs)"

# Remove DHCP servers
/ip dhcp-server
:foreach srv in=[find] do={
    :local srvName [get $srv name]
    :log info "WDS: Removing DHCP server: $srvName"
    remove $srv
}

# Remove IP addresses on LAN ports only
/ip address
:foreach addr in=[find] do={
    :local iface [get $addr interface]
    :foreach port in=$GUEST_PORTS do={
        :if ($iface = $port) do={
            :log info "WDS: Removing IP address on $iface"
            remove $addr
        }
    }
}

:log info "WDS: Cleanup completed"

############################################################
# BRIDGE FOR GUEST NETWORK
############################################################

/interface bridge
:if ([:len [find name=bridge-guest]] = 0) do={
    add name=bridge-guest \
        protocol-mode=rstp \
        comment="Guest network bridge (WDS + LAN)"
} else={
    :log info "WDS: Bridge 'bridge-guest' already exists"
}

:log info "WDS: Bridge created/verified"

############################################################
# WIRELESS SECURITY PROFILE
############################################################

/interface wireless security-profiles
:if ([:len [find name=wds-sec]] = 0) do={
    add name=wds-sec \
        authentication-types=wpa2-psk,wpa3-psk \
        wpa2-pre-shared-key=$WDS_PASS \
        wpa3-sae-password=$WDS_PASS \
        mode=dynamic-keys \
        comment="WDS security (WPA2+WPA3)"
} else={
    set wds-sec \
        authentication-types=wpa2-psk,wpa3-psk \
        wpa2-pre-shared-key=$WDS_PASS \
        wpa3-sae-password=$WDS_PASS
    :log info "WDS: Security profile updated"
}

:log info "WDS: Security profile configured"

############################################################
# WIRELESS INTERFACE: STATION-BRIDGE MODE
############################################################

/interface wireless
set [ find default-name=wlan1 ] \
    mode=station-bridge \
    ssid=$WDS_SSID \
    frequency=$CHANNEL \
    band=$BAND \
    country=$COUNTRY \
    wds-mode=dynamic \
    wds-default-bridge=bridge-guest \
    wds-cost-range=0 \
    wds-ignore-ssid=no \
    security-profile=wds-sec \
    disabled=no \
    comment="WDS Station to R2"

:log info "WDS: wlan1 configured as station-bridge"

############################################################
# WIRELESS CONNECT LIST
############################################################

/interface wireless connect-list
remove [find]
add interface=wlan1 \
    mac-address=$R2_MAC \
    security-profile=wds-sec \
    ssid=$WDS_SSID \
    comment="Connect to R2 WDS AP only"

:log info "WDS: Connect-list configured (whitelist: $R2_MAC)"

############################################################
# BRIDGE PORTS
############################################################

# Add wlan1 to bridge-guest
/interface bridge port
:if ([:len [find interface=wlan1]] = 0) do={
    add bridge=bridge-guest interface=wlan1 comment="WDS wireless link"
} else={
    set [find interface=wlan1] bridge=bridge-guest
}

# Add all LAN ports to bridge-guest
:foreach port in=$GUEST_PORTS do={
    :if ([:len [/interface bridge port find interface=$port]] = 0) do={
        /interface bridge port add bridge=bridge-guest interface=$port comment="Guest LAN port"
        :log info "WDS: Added $port to bridge-guest"
    } else={
        /interface bridge port set [find interface=$port] bridge=bridge-guest
        :log info "WDS: Updated $port to bridge-guest"
    }
}

:log info "WDS: Bridge ports configured"

############################################################
# MANAGEMENT VLAN
############################################################

# Create VLAN interface for management
/interface vlan
:if ([:len [find name=vlan-mgmt]] = 0) do={
    add name=vlan-mgmt \
        interface=bridge-guest \
        vlan-id=$MGMT_VLAN \
        comment="Management VLAN $MGMT_VLAN"
}

# Get IP via DHCP from R1
/ip dhcp-client
:if ([:len [find interface=vlan-mgmt]] = 0) do={
    add interface=vlan-mgmt \
        use-peer-dns=no \
        use-peer-ntp=no \
        add-default-route=yes \
        comment="Management IP from R1 DHCP"
}

:log info "WDS: Management VLAN configured (VLAN $MGMT_VLAN)"

############################################################
# FIREWALL: SECURE CONFIGURATION
############################################################

:log warning "WDS: Replacing firewall rules with secure configuration"

/ip firewall filter
remove [find]

# INPUT CHAIN
add chain=input \
    connection-state=established,related \
    action=accept \
    comment="WDS: Allow established connections"

add chain=input \
    connection-state=invalid \
    action=drop \
    comment="WDS: Drop invalid"

# Allow management ONLY from VLAN 99
add chain=input \
    in-interface=vlan-mgmt \
    action=accept \
    comment="WDS: Allow management from VLAN $MGMT_VLAN"

# ICMP rate limiting
add chain=input \
    in-interface=bridge-guest \
    protocol=icmp \
    icmp-options=8:0 \
    limit=5/s,2:packet \
    action=accept \
    comment="WDS: Allow ping (rate limited)"

add chain=input \
    in-interface=bridge-guest \
    protocol=icmp \
    action=drop \
    comment="WDS: Drop excessive ICMP"

# Block management from guest bridge
add chain=input \
    in-interface=bridge-guest \
    action=drop \
    comment="WDS: Block management from guest"

# Allow other input
add chain=input \
    action=accept \
    comment="WDS: Allow other input"

# FORWARD CHAIN
add chain=forward \
    in-interface=bridge-guest \
    out-interface=bridge-guest \
    action=accept \
    comment="WDS: Allow bridge forwarding"

add chain=forward \
    action=drop \
    comment="WDS: Drop all routing"

:log info "WDS: Firewall configured"

############################################################
# END OF WDS STATION CONFIGURATION
############################################################

:log info "WDS Station configuration completed from wifi/05-rb2011-wds-station-bridge.rsc"
:log info "WDS SSID: $WDS_SSID | Channel: $CHANNEL MHz"
:log info "Management: VLAN $MGMT_VLAN via DHCP"
:log info "Connect to R2 MAC: $R2_MAC"
