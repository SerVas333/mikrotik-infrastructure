############################################################
# EXAMPLE: Site B (Branch Office) Configuration
# IPsec IKEv2 Site-to-Site VPN
#
# СЦЕНАРИЙ:
# - Site A (Main): 192.168.1.0/24, WAN: 203.0.113.10
# - Site B (Branch): 10.21.0.0/24, WAN: 198.51.100.20
# - VTI Tunnel: 10.12.0.0/30 (Site A: .1, Site B: .2)
#
# ЭТОТ ФАЙЛ ДЛЯ SITE B (Branch Office)
############################################################

############################################################
# STEP 1: Configure variables in 00-config.rsc on Site B
############################################################

# ⚠️ ВАЖНО: Swap local/remote параметры по сравнению с Site A!

:global cfgIPsecInterface "ipsec-s2s"

# VTI IPs (SWAPPED!)
:global cfgIPsecLocalAddress "10.12.0.2/30"           # Site B VTI IP
:global cfgIPsecRemoteAddress "10.12.0.1/30"          # Site A VTI IP

# Endpoints (SWAPPED!)
:global cfgIPsecRemoteEndpoint "203.0.113.10"         # Site A WAN IP

# Networks (SWAPPED!)
:global cfgIPsecRemoteNetwork "192.168.1.0/24"        # Site A LAN
:global cfgIPsecLocalNetwork "10.21.0.0/24"           # Site B LAN

# Same as Site A
:global cfgIPsecProposalName "ike2-aes128gcm"
:global cfgIPsecPolicyGroup "ipsec-s2s-group"
:global cfgIPsecPeerName "remote-site"

############################################################
# STEP 2: Configure PSK in 00-secrets.rsc on Site B
############################################################

# ⚠️ КРИТИЧЕСКИ ВАЖНО: Используйте ТОТ ЖЕ PSK, что и на Site A!
:global secIPsecPSK "MyVeryStrongSharedSecret123!@#"

############################################################
# STEP 3: Import configuration
############################################################

# На Site B выполните:
# /import 00-config.rsc
# /import 00-secrets.rsc
# /import 11a-ipsec-ikev2-s2s.rsc

############################################################
# VERIFICATION COMMANDS (run on Site B)
############################################################

# После импорта проверьте:

# 1. Проверить что туннель установлен
/ip ipsec active-peers print
# Ожидается: uptime=... ph2-state=established

# 2. Ping VTI IP удаленной стороны (Site A)
/ping 10.12.0.1 count=5
# Ожидается: replies with 0% loss

# 3. Ping LAN Site A
/ping 192.168.1.1 count=5 src-address=10.21.0.1
# Ожидается: replies with 0% loss

# 4. Проверить маршрут
/ip route print where dst-address=192.168.1.0/24
# Ожидается: gateway=ipsec-s2s

# 5. Проверить VTI интерфейс
/interface ipsec print detail
# Ожидается: running=yes

# 6. Проверить логи
/log print where topics~"ipsec"
# Ожидается: no errors

############################################################
# CONFIGURATION SUMMARY - SITE B
############################################################

:log info "============================================"
:log info "Site B (Branch Office) Configuration Summary"
:log info "============================================"
:log info "Local LAN: 10.21.0.0/24"
:log info "Local WAN: 198.51.100.20 (configure manually)"
:log info "Local VTI: 10.12.0.2/30"
:log info ""
:log info "Remote (Site A) LAN: 192.168.1.0/24"
:log info "Remote (Site A) WAN: 203.0.113.10"
:log info "Remote (Site A) VTI: 10.12.0.1/30"
:log info ""
:log info "Cryptography: IKEv2 AES-128-GCM SHA-256 ECDH-P256"
:log info "============================================"

############################################################
# TROUBLESHOOTING TIPS
############################################################

# Если туннель не устанавливается:

# 1. Проверьте что PSK одинаковый на обеих сторонах
#    /ip ipsec identity print detail

# 2. Проверьте что remote endpoint правильный
#    /ip ipsec peer print detail

# 3. Проверьте firewall
#    /ip firewall filter print where protocol~"udp|esp"

# 4. Проверьте логи на ошибки
#    /log print where topics~"ipsec,error"

# 5. Проверьте что WAN IP доступен
#    /ping 203.0.113.10 count=5

# 6. Если есть NAT, убедитесь что NAT-T работает
#    UDP 4500 должен быть открыт

############################################################
# EXAMPLE: Full Site B Basic Configuration
############################################################

# Если у вас совершенно новый роутер на Site B, вот минимальная конфигурация:

## SYSTEM
# /system identity set name="Site-B-Branch"

## LAN INTERFACE
# /ip address add address=10.21.0.1/24 interface=ether2 comment="LAN"

## WAN INTERFACE (PPPoE example)
# /interface pppoe-client
# add name=pppoe-wan interface=ether1 user="your-user" password="your-pass"

## MASQUERADE NAT
# /ip firewall nat
# add chain=srcnat out-interface=pppoe-wan action=masquerade

## DHCP SERVER
# /ip pool add name=lan-pool ranges=10.21.0.100-10.21.0.200
# /ip dhcp-server add name=lan-dhcp interface=ether2 address-pool=lan-pool
# /ip dhcp-server network add address=10.21.0.0/24 gateway=10.21.0.1 dns-server=10.21.0.1

## DNS
# /ip dns set servers=1.1.1.1,1.0.0.1 allow-remote-requests=yes

## Теперь импортируйте IPsec конфигурацию
# /import 00-config.rsc
# /import 00-secrets.rsc
# /import 11a-ipsec-ikev2-s2s.rsc

############################################################
# END OF SITE B EXAMPLE CONFIGURATION
############################################################
