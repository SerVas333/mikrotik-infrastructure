############################################################
# 01-wifi-capsman.rsc - Dual-Stack CAPsMAN Configuration
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
#
# Dual-stack CAPsMAN конфигурация:
# - wifiwave2 (для hAP ax3, RB5009 и др.)
# - legacy CAPsMAN (для hAP ac2, ac3 и др.)
#
# Main SSID + Guest SSID с полной поддержкой роуминга
#
# ВАЖНО:
# - Network конфигурация (VLAN, DHCP) в 02-wifi-network.rsc
# - Firewall правила должны быть в firewall_complete.rsc
############################################################

############################################################
# ПОДГОТОВКА: Bridge VLAN Filtering
############################################################

# Включить VLAN filtering на bridge
/interface bridge
set $cfgBridgeLAN vlan-filtering=yes

:log info "Bridge VLAN filtering enabled"

# Добавить uplink порты в bridge (если ещё не добавлены)
# Assuming uplink ports are part of cfgLANPorts or need separate definition
# For now, using example ports from original file
:local UPLINK_PORTS [:toarray "ether5,ether6"]

:foreach port in=$UPLINK_PORTS do={
    :if ([:len [/interface bridge port find interface=$port]] = 0) do={
        /interface bridge port add bridge=$cfgBridgeLAN interface=$port
        :log info "Added $port to bridge $cfgBridgeLAN"
    }
}

############################################################
# WIFIWAVE2 (для ax3, RB5009, и других новых устройств)
############################################################

:if ([:len [/wifi]] > 0) do={

    # Security profiles
    /wifi security
    add name=sec-w2-main \
        authentication-types=wpa2-psk,wpa3-psk \
        passphrase=$secWiFiMainPass \
        comment="Main WiFi security (WPA2+WPA3)"

    add name=sec-w2-guest \
        authentication-types=wpa2-psk \
        passphrase=$secWiFiGuestPass \
        comment="Guest WiFi security (WPA2 only)"

    # Main WiFi configuration
    /wifi configuration
    add name=cfg-w2-main \
        country=$cfgWiFiCountry \
        ssid=$cfgWiFiMainSSID \
        mode=ap \
        security=sec-w2-main \
        datapath.interface=$cfgBridgeLAN \
        vlan-mode=use-tag \
        vlan-id=$cfgWiFiMainVLAN \
        datapath.client-isolation=no \
        roaming.enabled=yes \
        roaming.decision=best-signal \
        roaming.k-enabled=yes \
        roaming.r-enabled=yes \
        roaming.v-enabled=yes \
        comment="Main SSID with roaming support"

    # Guest WiFi configuration
    /wifi configuration
    add name=cfg-w2-guest \
        country=$cfgWiFiCountry \
        ssid=$cfgWiFiGuestSSID \
        mode=ap \
        security=sec-w2-guest \
        datapath.interface=$cfgBridgeLAN \
        vlan-mode=use-tag \
        vlan-id=$cfgWiFiGuestVLAN \
        datapath.client-isolation=yes \
        roaming.enabled=no \
        comment="Guest SSID with client isolation"

    # Enable CAPsMAN manager for wifiwave2
    /wifi caps-man manager
    set enabled=yes \
        interfaces=$cfgBridgeLAN \
        primary-configuration=cfg-w2-main

    # Provisioning - автоматическое создание AP интерфейсов
    /wifi caps-man provisioning
    add action=create-enabled \
        master-configuration=cfg-w2-main \
        name=prov-w2-main \
        comment="Provision main SSID"

    add action=create-enabled \
        master-configuration=cfg-w2-guest \
        name=prov-w2-guest \
        comment="Provision guest SSID"

    :log info "wifiwave2 CAPsMAN: Main and Guest configurations created"
}

############################################################
# LEGACY CAPSMAN (для ac2, ac3, и других старых устройств)
############################################################

# Security profiles
/caps-man security
add name=sec-l-main \
    authentication-types=wpa2-psk \
    passphrase=$secWiFiMainPass \
    encryption=aes-ccm \
    comment="Legacy: Main WiFi security"

add name=sec-l-guest \
    authentication-types=wpa2-psk \
    passphrase=$secWiFiGuestPass \
    encryption=aes-ccm \
    comment="Legacy: Guest WiFi security"

# Main WiFi configuration
/caps-man configuration
add name=cfg-l-main \
    ssid=$cfgWiFiMainSSID \
    country=$cfgWiFiCountry \
    security=sec-l-main \
    datapath.bridge=$cfgBridgeLAN \
    vlan-mode=use-tag \
    vlan-id=$cfgWiFiMainVLAN \
    datapath.client-isolation=no \
    channel.band=5ghz-a/n/ac \
    channel.control-channel-width=20mhz \
    comment="Legacy: Main SSID (5GHz)"

# Guest WiFi configuration
/caps-man configuration
add name=cfg-l-guest \
    ssid=$cfgWiFiGuestSSID \
    country=$cfgWiFiCountry \
    security=sec-l-guest \
    datapath.bridge=$cfgBridgeLAN \
    vlan-mode=use-tag \
    vlan-id=$cfgWiFiGuestVLAN \
    datapath.client-isolation=yes \
    channel.band=2ghz-b/g/n \
    channel.control-channel-width=20mhz \
    comment="Legacy: Guest SSID (2.4GHz)"

# Enable legacy CAPsMAN manager
/caps-man manager
set enabled=yes

# Provisioning
/caps-man provisioning
add action=create-enabled \
    master-configuration=cfg-l-main \
    name=prov-l-main \
    comment="Legacy: Provision main SSID"

add action=create-enabled \
    master-configuration=cfg-l-guest \
    name=prov-l-guest \
    comment="Legacy: Provision guest SSID"

:log info "Legacy CAPsMAN: Main and Guest configurations created"

############################################################
# BRIDGE VLAN TABLE
# Обеспечивает правильную маршрутизацию VLAN трафика
############################################################

# Добавить VLAN entries в bridge VLAN table
:local vlanList [:toarray "$cfgWiFiMainVLAN,$cfgWiFiGuestVLAN,$cfgMgmtVLAN"]
:local uplinkPorts [:toarray "ether5,ether6"]

:foreach vlanId in=$vlanList do={
    :if ([:len [/interface bridge vlan find vlan-ids=$vlanId]] = 0) do={
        /interface bridge vlan
        add bridge=$cfgBridgeLAN \
            tagged=($cfgBridgeLAN . "," . [:tostr $uplinkPorts]) \
            vlan-ids=$vlanId \
            comment="VLAN $vlanId"

        :log info "Added VLAN $vlanId to bridge VLAN table"
    }
}

:log info "Bridge VLAN entries configured for SSIDs and Management"

############################################################
# FINALIZATION
############################################################

:log info "WiFi CAPsMAN configuration completed from wifi/01-wifi-capsman.rsc"
:log info "Main SSID: $cfgWiFiMainSSID (VLAN $cfgWiFiMainVLAN)"
:log info "Guest SSID: $cfgWiFiGuestSSID (VLAN $cfgWiFiGuestVLAN)"
:log info "Next steps:"
:log info "1. Apply 02-wifi-network.rsc for VLAN interfaces and DHCP"
:log info "2. Add firewall rules to firewall_complete.rsc"
:log info "3. Configure CAPs (R2/R3) - see README.md"
