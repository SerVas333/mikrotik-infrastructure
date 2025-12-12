# 01-base.rsc - Base system configuration
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# Load configuration variables
############################################################

# If this is the first file after 00-config, variables are already loaded
# Otherwise ensure 00-config.rsc was imported:
# /import 00-config.rsc

############################################################
# System Identity
############################################################

/system identity set name=$cfgHostname

############################################################
# Create Bridges
############################################################

/interface bridge
add name=$cfgBridgeLAN comment="Main LAN bridge" vlan-filtering=yes
add name=$cfgBridgeContainers comment="Container bridge" vlan-filtering=no

############################################################
# Bridge Ports (attach physical LAN ports)
############################################################

/interface bridge port
# Add configured LAN ports to bridge
:foreach port in=$cfgLANPorts do={
    add bridge=$cfgBridgeLAN interface=$port
}
# Note: Container veth will be added by 08-containers.rsc

############################################################
# System Services Hardening
############################################################

# Restrict management access to allowed networks only
:local allowedNets [:tostr ($cfgMgmtAllowedNets->0)]
:for i from=1 to=([:len $cfgMgmtAllowedNets]-1) do={
    :set allowedNets ($allowedNets . "," . ($cfgMgmtAllowedNets->$i))
}

/ip service
set ssh address=$allowedNets port=22
set winbox address=$allowedNets port=8291
set www disabled=yes
set www-ssl disabled=yes
set telnet disabled=yes
set api disabled=yes
set api-ssl disabled=yes

############################################################
# System Settings
############################################################

/ip settings set tcp-syncookies=yes

/ip ssh set strong-crypto=yes

############################################################
# Logging Configuration
############################################################

/system logging
add topics=error,critical action=memory
add topics=warning action=memory
add topics=info prefix="INFO: " action=memory

############################################################
# NTP Client
############################################################

# Will be configured in 13-ntp.rsc

############################################################
# END OF BASE CONFIGURATION
############################################################

:log info "Base configuration applied from 01-base.rsc"
:log info "Hostname: $cfgHostname"
:log info "LAN Bridge: $cfgBridgeLAN | Container Bridge: $cfgBridgeContainers"
