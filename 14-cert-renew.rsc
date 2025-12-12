# 14-cert-renew.rsc - Let's Encrypt Certificate Auto-Renewal
# REQUIRES: 00-config.rsc and 00-secrets.rsc must be imported first!
# REQUIRES: Container configuration (08-containers.rsc) must be applied first!

############################################################
# Certificate Renewal Configuration
############################################################

:local DOMAIN $secLetsEncryptDomain
:local EMAIL $secLetsEncryptEmail
:local CF_INI_PATH "/data/cf.ini"
:local CERTBOT_CONTAINER "certbot"
:local NGINX_CONTAINER "nginx"
:local LETS_PATH "/etc/letsencrypt/live/$DOMAIN"

############################################################
# Certbot Obtain Script (initial certificate)
############################################################

/system script
:if ([:len [find name=certbot-obtain]] = 0) do={
    add name=certbot-obtain \
        policy=ftp,read,write,policy,test,password,sensitive \
        source="
:log info \"[ACME] Starting certbot obtain for $DOMAIN\"

/container start $CERTBOT_CONTAINER
:delay 5s

/container exec $CERTBOT_CONTAINER command=\"certbot certonly --dns-cloudflare --dns-cloudflare-credentials $CF_INI_PATH -d $DOMAIN -d '*.$DOMAIN' --non-interactive --agree-tos --email $EMAIL --preferred-challenges dns-01\"

:delay 5s

/container exec $NGINX_CONTAINER command=\"nginx -s reload || true\"

/container stop $CERTBOT_CONTAINER

:log info \"[ACME] Certbot obtain completed\"
" \
        comment="Initial Let's Encrypt certificate obtain"
}

############################################################
# Certbot Renew Script (automatic renewal)
############################################################

/system script
:if ([:len [find name=certbot-renew]] = 0) do={
    add name=certbot-renew \
        policy=ftp,read,write,policy,test,password,sensitive \
        source="
:log info \"[ACME] Starting certbot renew...\"

/container start $CERTBOT_CONTAINER
:delay 5s

/container exec $CERTBOT_CONTAINER command=\"certbot renew --dns-cloudflare --dns-cloudflare-credentials $CF_INI_PATH --non-interactive --deploy-hook 'nginx -s reload'\"

:delay 5s

/container stop $CERTBOT_CONTAINER

:log info \"[ACME] Certbot renew completed\"
" \
        comment="Automatic Let's Encrypt certificate renewal"
}

############################################################
# Scheduler for Auto-Renewal
############################################################

/system scheduler
:if ([:len [find name=cert-renew-sched]] = 0) do={
    add name=cert-renew-sched \
        interval=12h \
        on-event=certbot-renew \
        start-time=startup \
        comment="Auto-renew Let's Encrypt certificates every 12 hours"
}

############################################################
# END OF CERTIFICATE RENEWAL CONFIGURATION
############################################################

:log info "Certificate renewal configured from 14-cert-renew.rsc"
:log info "Domain: $DOMAIN | Email: $EMAIL"
:log info "Auto-renewal: Every 12 hours"
:log info "To obtain initial certificate: /system script run certbot-obtain"
