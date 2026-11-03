#!/bin/bash
# Hutred: установка сервера-посредника на Oracle Cloud (Ubuntu 24.04).
# Вставляется целиком в «Initialization script» при создании сервера —
# дальше всё ставится само за 3–5 минут.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

SUPABASE_URL="https://izkllkqilyspwxthssdc.supabase.co"

apt-get update
apt-get install -y python3-aiohttp curl gpg debian-keyring debian-archive-keyring apt-transport-https netfilter-persistent

# Caddy — сам получает бесплатный HTTPS-сертификат.
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy

# Образ Oracle по умолчанию закрывает всё, кроме SSH: открываем 80 и 443.
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 80 -j ACCEPT
iptables -I INPUT 6 -m state --state NEW -p tcp --dport 443 -j ACCEPT
netfilter-persistent save

# Адрес сервера вида 1-2-3-4.sslip.io — бесплатное имя, сертификату нужно имя.
IP=$(curl -s https://api.ipify.org)
DOMAIN="${IP//./-}.sslip.io"
mkdir -p /opt/hutred
echo "$DOMAIN" > /opt/hutred/domain

curl -fsSL https://raw.githubusercontent.com/whenuknowmeuseemeshine/hutred/dev/server/relay.py -o /opt/hutred/relay.py

cat > /etc/systemd/system/hutred-relay.service <<UNIT
[Unit]
Description=Hutred relay
After=network-online.target

[Service]
Environment=SUPABASE_URL=$SUPABASE_URL
ExecStart=/usr/bin/python3 /opt/hutred/relay.py
Restart=always
RestartSec=3
DynamicUser=yes

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/caddy/Caddyfile <<CADDY
$DOMAIN {
	reverse_proxy 127.0.0.1:8080 {
		flush_interval -1
	}
}
CADDY

# Обновлять посредника раз в сутки, если в репозитории вышла новая версия.
cat > /etc/cron.daily/hutred-relay-update <<'CRON'
#!/bin/sh
curl -fsSL https://raw.githubusercontent.com/whenuknowmeuseemeshine/hutred/dev/server/relay.py -o /tmp/relay.py && \
  python3 -c "import ast;ast.parse(open('/tmp/relay.py').read())" && \
  ! cmp -s /tmp/relay.py /opt/hutred/relay.py && cp /tmp/relay.py /opt/hutred/relay.py && systemctl restart hutred-relay
exit 0
CRON
chmod +x /etc/cron.daily/hutred-relay-update

systemctl daemon-reload
systemctl enable --now hutred-relay
systemctl restart caddy
