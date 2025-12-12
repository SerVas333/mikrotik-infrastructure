# 13-ntp.rsc - NTP Configuration
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# NTP Client Configuration
############################################################

# Extract primary and secondary NTP servers from array
:local ntpPrimary [:pick $cfgNTPServers 0]
:local ntpSecondary [:pick $cfgNTPServers 1]

/system ntp client
set enabled=yes \
    primary-ntp=$ntpPrimary \
    secondary-ntp=$ntpSecondary

:log info "NTP client configured: $ntpPrimary, $ntpSecondary"

############################################################
# NTP Server (for LAN clients)
############################################################

/system ntp server
set enabled=yes \
    broadcast=no

:log info "NTP server enabled for LAN clients"

############################################################
# END OF NTP CONFIGURATION
############################################################

:log info "NTP configuration applied from 13-ntp.rsc"
