############################################################
# 00-config.rsc - ЦЕНТРАЛИЗОВАННАЯ КОНФИГУРАЦИЯ
# Все переменные инфраструктуры MikroTik в одном месте
#
# ВАЖНО: Импортировать ПЕРВЫМ перед всеми другими модулями!
# Использование: /import 00-config.rsc
############################################################

############################################################
# SYSTEM
############################################################

:global cfgHostname "R1-Core"
:global cfgTimezone "Europe/Kiev"

############################################################
# NETWORK INTERFACES
############################################################

:global cfgWanInterface "ether1"
:global cfgWanPPPoE "pppoe-out1"
:global cfgBridgeLAN "bridge-lan"
:global cfgBridgeContainers "bridge-containers"
:global cfgVethContainers "veth-containers"

# Physical ports attached to LAN bridge
:global cfgLANPorts [:toarray "ether2,ether3,ether4"]

############################################################
# IPv4 ADDRESSING
############################################################

# LAN Main Network
:global cfgLANNetwork "192.168.1.0/24"
:global cfgLANGateway "192.168.1.1/24"
:global cfgLANPoolStart "192.168.1.50"
:global cfgLANPoolEnd "192.168.1.250"

# Management VLAN
:global cfgMgmtVLAN 99
:global cfgMgmtNetwork "172.16.99.0/24"
:global cfgMgmtGateway "172.16.99.1/24"
:global cfgMgmtPoolStart "172.16.99.20"
:global cfgMgmtPoolEnd "172.16.99.200"

# Guest Network (VLAN 30)
:global cfgGuestVLAN 30
:global cfgGuestNetwork "10.30.0.0/24"
:global cfgGuestGateway "10.30.0.1/24"
:global cfgGuestPoolStart "10.30.0.100"
:global cfgGuestPoolEnd "10.30.0.200"

# Container Network
:global cfgContainerNetwork "10.11.0.0/24"
:global cfgContainerGateway "10.11.0.1/24"
:global cfgContainerXRayIP "10.11.0.10"
:global cfgContainerNginxIP "10.11.0.11"
:global cfgContainerCertbotIP "10.11.0.12"

############################################################
# IPv6 (Hurricane Electric Tunnel)
############################################################

# REPLACE WITH YOUR ACTUAL VALUES!
:global cfgWANPublicIP "<YOUR_WAN_PUBLIC_IP>"       # e.g. 101.102.103.104
:global cfgHERemoteIP "216.66.84.46"                 # HE tunnel server
:global cfgHELocalIPv6 "2001:470:6e:2b7::2/64"      # Your allocated IPv6
:global cfgHERemoteGW "2001:470:6e:2b7::1"          # HE gateway
:global cfgIPv6TunnelInterface "sit1"

# IPv6 Prefix Delegation (replace with your /48 or /64)
:global cfgIPv6LANPrefix "2001:470:xxxx:1::/64"
:global cfgIPv6GuestPrefix "2001:470:xxxx:30::/64"
:global cfgIPv6MgmtPrefix "2001:470:xxxx:99::/64"

############################################################
# WIFI CONFIGURATION
############################################################

# WiFi Country and Band Settings
:global cfgWiFiCountry "ukraine"
:global cfgWiFiMainSSID "MyNetwork"
:global cfgWiFiGuestSSID "Guest"

# VLAN IDs
:global cfgWiFiMainVLAN 20
:global cfgWiFiGuestVLAN 30

# Channel Settings (2.4 GHz)
:global cfgWiFi24GHzChannel "2462"    # Channel 11
:global cfgWiFi24GHzWidth "20mhz"

# Channel Settings (5 GHz)
:global cfgWiFi5GHzChannel "5180"     # Channel 36
:global cfgWiFi5GHzWidth "20/40/80mhz-XXXX"

# WDS Bridge Settings (for RB2011 ↔ R2)
:global cfgWDSSSID "Guest-WDS"
:global cfgWDSChannel "2462"          # CH11 (same as guest to avoid conflict)
:global cfgWDSRB2011MAC "AA:BB:CC:DD:EE:FF"  # REPLACE WITH ACTUAL RB2011 MAC!

############################################################
# DNS CONFIGURATION
############################################################

:global cfgDNSDoHURL "https://cloudflare-dns.com/dns-query"
:global cfgDNSServers "1.1.1.1,1.0.0.1"
:global cfgDNSAllowRemote "no"

############################################################
# NTP CONFIGURATION
############################################################

:global cfgNTPServers [:toarray "time.cloudflare.com,pool.ntp.org"]

############################################################
# BGP CONFIGURATION
############################################################

:global cfgBGPLocalAS 65899
:global cfgBGPRemoteAS 65999
:global cfgBGPPeerIP "<BGP_PEER_IP>"           # REPLACE!
:global cfgBGPRouterID "<ROUTER_ID>"           # REPLACE! (usually your WAN IP)
:global cfgBGPXRayTable "xray"
:global cfgBGPXRayNextHop "10.11.0.10"
:global cfgBGPConnectionName "upstream-bgp"

############################################################
# VPN CONFIGURATION
############################################################

# SSTP VPN
:global cfgSS TPCertName "router-cert"
:global cfgSSTPPoolName "pool-sstp"
:global cfgSSTPPoolRange "192.168.88.2-192.168.88.10"
:global cfgSSTPDNS "192.168.1.1"

# WireGuard Site-to-Site
:global cfgWGInterface "wg-s2s"
:global cfgWGListenPort 13231
:global cfgWGLocalAddress "10.10.0.1/24"
:global cfgWGRemoteAddress "10.10.0.2/24"
:global cfgWGRemoteEndpoint "<REMOTE_SITE_IP>:13231"  # REPLACE!
:global cfgWGRemoteAllowedIP "10.20.0.0/24"           # REPLACE with remote LAN

############################################################
# CONTAINER STORAGE PATHS
############################################################

:global cfgContainerTmpDir "/disk1/tmp"
:global cfgContainerImagesRoot "/disk1/images"
:global cfgContainerLetsRoot "/disk1/lets"

############################################################
# DOCKER IMAGES
############################################################

:global cfgDockerXRayImage "teddysun/xray:1.8.4"
:global cfgDockerNginxImage "nginx:1.25.3-alpine"
:global cfgDockerCertbotImage "certbot/certbot:v2.7.4"

############################################################
# MANAGEMENT ACCESS (IP ranges allowed to access SSH/Winbox)
#
# РЕШЕНИЕ CRIT-05: ACL управления
# - Разрешает доступ к SSH/Winbox из указанных сетей
# - Рекомендуется: ТОЛЬКО Management VLAN (172.16.99.0/24)
# - Текущая конфигурация: LAN + Management (для совместимости)
#
# Best Practice (рекомендуется для production):
# :global cfgMgmtAllowedNets [:toarray "172.16.99.0/24"]
#
# Current (для совместимости):
############################################################

:global cfgMgmtAllowedNets [:toarray "192.168.1.0/24,172.16.99.0/24"]

# Опционально: Разрешить доступ ТОЛЬКО из Management VLAN
# (закомментируйте строку выше и раскомментируйте строку ниже)
# :global cfgMgmtAllowedNets [:toarray "172.16.99.0/24"]

############################################################
# END OF CONFIGURATION
############################################################

:log info "Configuration variables loaded from 00-config.rsc"
:log warning "NEXT STEP: Import 00-secrets.rsc, then import other modules in order"
