# 12-dns-doh.rsc - DNS over HTTPS Configuration
# REQUIRES: 00-config.rsc must be imported first!

############################################################
# DNS Configuration with DoH
############################################################

/ip dns
set allow-remote-requests=$cfgDNSAllowRemote \
    use-doh-server=$cfgDNSDoHURL \
    verify-doh-cert=yes \
    servers=$cfgDNSServers \
    max-udp-packet-size=4096 \
    cache-size=8192KiB

############################################################
# Static DNS Records (optional)
############################################################

# Add custom DNS records here if needed
# Example:
# /ip dns static
# add name=router.local address=192.168.1.1

############################################################
# END OF DNS CONFIGURATION
############################################################

:log info "DNS over HTTPS configured from 12-dns-doh.rsc"
:log info "DoH URL: $cfgDNSDoHURL"
:log info "Allow remote requests: $cfgDNSAllowRemote"
