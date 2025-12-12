# 06-wifi-capsman-core.rsc - Main WiFi CAPsMAN Configuration
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!

############################################################
# WiFi CAPsMAN - Dual Stack (wifiwave2 + legacy)
############################################################

# wifiwave2 (for newer devices like AX3)
:if ([:len [/wifi]] > 0) do={
    /wifi security
    add name=sec-w2 \
        authentication-types=wpa2-psk,wpa3-psk \
        passphrase=$secWiFiMainPass

    /wifi configuration
    add name=cfg-w2 \
        ssid=$cfgWiFiMainSSID \
        country=$cfgWiFiCountry \
        security=sec-w2 \
        mode=ap \
        datapath.interface=$cfgBridgeLAN \
        vlan-mode=use-tag \
        vlan-id=$cfgWiFiMainVLAN

    /wifi caps-man manager set enabled=yes
    /wifi caps-man provisioning add action=create-enabled master-configuration=cfg-w2
}

# legacy CAPsMAN (for older devices like AC2)
/caps-man security
add name=sec-l \
    authentication-types=wpa2-psk,wpa3-psk \
    passphrase=$secWiFiMainPass

/caps-man configuration
add name=cfg-l \
    ssid=$cfgWiFiMainSSID \
    country=$cfgWiFiCountry \
    security=sec-l \
    datapath.bridge=$cfgBridgeLAN \
    vlan-mode=use-tag \
    vlan-id=$cfgWiFiMainVLAN

/caps-man manager set enabled=yes
/caps-man provisioning add action=create-enabled master-configuration=cfg-l

############################################################
# Bridge VLAN Configuration
############################################################

/interface bridge vlan
add bridge=$cfgBridgeLAN \
    tagged=$cfgBridgeLAN \
    vlan-ids=$cfgWiFiMainVLAN \
    comment="Main WiFi VLAN $cfgWiFiMainVLAN"

############################################################
# END OF WIFI CAPSMAN CONFIGURATION
############################################################

:log info "WiFi CAPsMAN configured from 06-wifi-capsman-core.rsc"
:log info "SSID: $cfgWiFiMainSSID | VLAN: $cfgWiFiMainVLAN | Country: $cfgWiFiCountry"
