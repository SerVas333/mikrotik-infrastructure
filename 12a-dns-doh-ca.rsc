# 12a-dns-doh-ca.rsc - Cloudflare DNS CA Certificate Auto-Update
# REQUIRES: 00-config.rsc must be imported first!

###############################################
# Cloudflare Root CA Certificate Update
###############################################

:local CF_CA_URL "https://developers.cloudflare.com/ssl/static/origin_ca_ecc_root.pem"
:local CF_CA_FILE "cloudflare-root.pem"

# Remove old certificate file
/file
:if ([:len [find name=$CF_CA_FILE]] > 0) do={
    remove $CF_CA_FILE
}

# Download CA certificate
/tool fetch \
    url=$CF_CA_URL \
    dst-path=$CF_CA_FILE \
    keep-result=yes

:delay 2s

# Import certificate
/certificate
import file-name=$CF_CA_FILE passphrase=""

:log info "Cloudflare DoH Root CA updated from $CF_CA_URL"

###############################################
# Scheduler - Auto-update every 14 days
###############################################

/system scheduler
:if ([:len [find name="update-doh-ca"]] = 0) do={
    add name="update-doh-ca" \
        interval=2w \
        on-event="/import 12a-dns-doh-ca.rsc" \
        start-time=03:00:00 \
        comment="Auto-update Cloudflare Root CA for DoH"
}

:log info "Cloudflare CA auto-update scheduler configured"
