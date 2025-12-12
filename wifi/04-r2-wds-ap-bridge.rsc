############################################################
# 04-r2-wds-ap-bridge.rsc - WDS AP Bridge for R2
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
#
# Назначение:
# - Создает WDS AP для беспроводного моста R2 ↔ RB2011
# - Расширяет Guest VLAN на удаленную локацию
# - Работает параллельно с CAPsMAN Guest SSID
#
# Применять на: R2 (hAP ac2)
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
:local RB2011_MAC $cfgWDSRB2011MAC

# Network
:local VLAN_GUEST $cfgGuestVLAN
:local VLAN_MGMT $cfgMgmtVLAN
:local BRIDGE $cfgBridgeLAN

# Performance
:local MAX_BANDWIDTH "50M/50M"

############################################################
# SECURITY PROFILE
############################################################

# WPA2+WPA3 для максимальной безопасности
/interface wireless security-profiles
add name=wds-sec \
    authentication-types=wpa2-psk,wpa3-psk \
    wpa2-pre-shared-key=$WDS_PASS \
    wpa3-sae-password=$WDS_PASS \
    mode=dynamic-keys \
    comment="WDS security profile (WPA2+WPA3)"

:log info "WDS: Security profile created (WPA2+WPA3)"

############################################################
# VIRTUAL AP FOR WDS
############################################################

# Создать Virtual AP для WDS bridging
/interface wireless
add name=wds-ap \
    master-interface=wlan1 \
    ssid=$WDS_SSID \
    mode=ap-bridge \
    wds-mode=dynamic \
    wds-default-bridge=$BRIDGE \
    wds-cost-range=0 \
    wds-ignore-ssid=no \
    frequency=$CHANNEL \
    band=$BAND \
    country=$COUNTRY \
    security-profile=wds-sec \
    disabled=no \
    default-authentication=no \
    comment="WDS AP for RB2011 bridge"

:log info "WDS: Virtual AP created on wlan1"

############################################################
# MAC ADDRESS FILTERING (CRITICAL SECURITY)
############################################################

# Разрешить ТОЛЬКО RB2011 подключаться к WDS AP
/interface wireless access-list
add interface=wds-ap \
    mac-address=$RB2011_MAC \
    authentication=yes \
    forwarding=yes \
    comment="RB2011 WDS Station - ALLOWED"

# Запретить все остальные устройства
add interface=wds-ap \
    authentication=no \
    forwarding=no \
    comment="Deny all others"

:log info "WDS: MAC filtering configured (whitelist: $RB2011_MAC)"

############################################################
# BRIDGE VLAN CONFIGURATION
############################################################

# Добавить WDS AP в Guest VLAN
/interface bridge vlan
:if ([:len [/interface bridge vlan find vlan-ids=$VLAN_GUEST]] = 0) do={
    add bridge=$BRIDGE tagged=$BRIDGE,wds-ap vlan-ids=$VLAN_GUEST comment="Guest VLAN with WDS"
} else={
    # Добавить wds-ap к существующему VLAN entry
    :local currentTagged [/interface bridge vlan get [find vlan-ids=$VLAN_GUEST] tagged]
    :if ([:typeof [:find $currentTagged "wds-ap"]] = "nil") do={
        /interface bridge vlan set [find vlan-ids=$VLAN_GUEST] tagged="$currentTagged,wds-ap"
    }
}

# Добавить WDS AP в Management VLAN
:if ([:len [/interface bridge vlan find vlan-ids=$VLAN_MGMT]] = 0) do={
    add bridge=$BRIDGE tagged=$BRIDGE,wds-ap vlan-ids=$VLAN_MGMT comment="Management VLAN with WDS"
} else={
    :local currentTagged [/interface bridge vlan get [find vlan-ids=$VLAN_MGMT] tagged]
    :if ([:typeof [:find $currentTagged "wds-ap"]] = "nil") do={
        /interface bridge vlan set [find vlan-ids=$VLAN_MGMT] tagged="$currentTagged,wds-ap"
    }
}

# Добавить WDS AP в bridge БЕЗ PVID (все VLANs tagged)
/interface bridge port
add bridge=$BRIDGE \
    interface=wds-ap \
    frame-types=admit-only-vlan-tagged \
    comment="WDS AP → Guest VLAN $VLAN_GUEST + Management VLAN $VLAN_MGMT"

:log info "WDS: Bridge VLAN configured (VLAN $VLAN_GUEST + $VLAN_MGMT)"

############################################################
# FIREWALL: ISOLATION AND PROTECTION
############################################################

# Запретить доступ к management R2 с WDS AP interface
/ip firewall filter
add chain=input \
    in-interface=wds-ap \
    action=drop \
    comment="WDS: Block management access from WDS AP"

# Изолировать WDS только на Guest VLAN forwarding
add chain=forward \
    in-interface=wds-ap \
    out-interface=!$BRIDGE \
    action=drop \
    comment="WDS: Isolate WDS to bridge only"

:log info "WDS: Firewall rules configured (isolation)"

############################################################
# BANDWIDTH LIMITATION
############################################################

# Rate limit для WDS канала
/queue simple
add name=wds-rate-limit \
    target=wds-ap \
    max-limit=$MAX_BANDWIDTH \
    burst-limit=60M/60M \
    burst-threshold=40M/40M \
    burst-time=10s/10s \
    priority=7/7 \
    comment="WDS bandwidth limit"

:log info "WDS: Bandwidth limit configured ($MAX_BANDWIDTH)"

############################################################
# END OF WDS AP CONFIGURATION
############################################################

:log info "WDS AP configuration completed from wifi/04-r2-wds-ap-bridge.rsc"
:log info "WDS SSID: $WDS_SSID | Channel: $CHANNEL MHz"
:log info "VLANs: $VLAN_GUEST (Guest), $VLAN_MGMT (Management)"
:log info "Whitelist MAC: $RB2011_MAC"
