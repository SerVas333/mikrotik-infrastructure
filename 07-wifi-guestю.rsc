# 07-wifi-guest.rsc
:local GUEST_SSID "Guest_SV";
:local GUEST_PASS "GuestPass1234";
:local GUEST_VLAN 30;
:local GUEST_GW "10.30.0.1/24";
:local GUEST_POOL_START "10.30.0.10";
:local GUEST_POOL_END "10.30.0.250";
:local DNS "$LAN_GW";   # uses LAN gateway variable from 04-lan-dhcp if same session

:local BRIDGE "bridge-lan";

# create VLAN interface
/interface vlan
add name=vlan-guest vlan-id=$GUEST_VLAN interface=$BRIDGE

# address & dhcp
/ip address add address=$GUEST_GW interface=vlan-guest comment="Guest gateway"
/ip pool add name=guest-pool ranges=$GUEST_POOL_START-$GUEST_POOL_END
/ip dhcp-server add name=dhcp-guest interface=vlan-guest address-pool=guest-pool lease-time=6h
/ip dhcp-server network add address=10.30.0.0/24 gateway=10.30.0.1 dns-server=192.168.1.1

# wifiwave2 guest profile
:if ([:len [/wifi]] > 0) do={
    /wifi security add name=sec-w2-guest authentication-types=wpa2-psk passphrase=$GUEST_PASS
    /wifi configuration add name=cfg-w2-guest ssid=$GUEST_SSID security=sec-w2-guest \
        datapath.interface=$BRIDGE vlan-mode=use-tag vlan-id=$GUEST_VLAN
    /wifi caps-man provisioning add action=create-enabled master-configuration=cfg-w2-guest
}

# legacy guest profile
/caps-man security add name=sec-l-guest authentication-types=wpa2-psk passphrase=$GUEST_PASS
/caps-man configuration add name=cfg-l-guest ssid=$GUEST_SSID security=sec-l-guest \
    datapath.bridge=$BRIDGE vlan-mode=use-tag vlan-id=$GUEST_VLAN
/caps-man provisioning add action=create-enabled master-configuration=cfg-l-guest

# Firewall isolation - insert high priority rules
/ip firewall filter
add chain=forward src-address=10.30.0.0/24 dst-address=192.168.1.0/24 action=drop comment="Guest -> LAN block"
add chain=forward src-address=10.30.0.0/24 dst-address=10.11.0.0/16 action=drop comment="Guest -> containers block"
add chain=forward src-address=10.30.0.0/24 dst-address=172.16.99.0/24 action=drop comment="Guest -> mgmt block"
add chain=input src-address=10.30.0.0/24 action=drop comment="Guest -> router block"

# NAT for guest to Internet
/ip firewall nat
add chain=srcnat src-address=10.30.0.0/24 out-interface=pppoe-out1 action=masquerade comment="Guest NAT"
