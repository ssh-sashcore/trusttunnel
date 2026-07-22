#!/bin/bash
set -euo pipefail
#set -x
cd /root/

curl -fsSL https://raw.githubusercontent.com/TrustTunnel/TrustTunnel/refs/heads/master/scripts/install.sh | sh -s -
cd /opt/trusttunnel

read -rp "Domain: " hostname
echo "$hostname"

#####

cd /opt/trusttunnel/

#####
rm -rf /opt/trusttunnel/credentials.toml && \
for i in $(seq 1 3); do \
  pass=$(openssl rand -hex 10 | cut -c1-10); \
  printf '[[client]]\nusername = "admin%s"\npassword = "%s"\n\n' "$i" "$pass" >> /opt/trusttunnel/credentials.toml; \
done
#####

cat > /opt/trusttunnel/vpn.toml << EOF
listen_address = "0.0.0.0:443"

credentials_file = "credentials.toml"

rules_file = "rules.toml"

ipv6_available = true

allow_private_network_connections = false

tls_handshake_timeout_secs = 10

client_listener_timeout_secs = 600

connection_establishment_timeout_secs = 30

tcp_connections_timeout_secs = 604800

udp_connections_timeout_secs = 300

speedtest_enable = false

[forward_protocol]

[forward_protocol.direct]
[listen_protocols]

[listen_protocols.http1]
upload_buffer_size = 32768

[listen_protocols.http2]
initial_connection_window_size = 8388608
initial_stream_window_size = 131072
max_concurrent_streams = 1000
max_frame_size = 16384
header_table_size = 65536

[listen_protocols.quic]
recv_udp_payload_size = 1350
send_udp_payload_size = 1350
initial_max_data = 104857600
initial_max_stream_data_bidi_local = 1048576
initial_max_stream_data_bidi_remote = 1048576
initial_max_stream_data_uni = 1048576
initial_max_streams_bidi = 4096
initial_max_streams_uni = 4096
max_connection_window = 25165824
max_stream_window = 16777216
disable_active_migration = true
enable_early_data = true
message_queue_capacity = 4096
EOF
######

rm -rf /opt/trusttunnel/hosts.toml && \

cat > /opt/trusttunnel/hosts.toml << EOF
ping_hosts = []
speedtest_hosts = []
reverse_proxy_hosts = []

[[main_hosts]]
hostname = "$hostname"
cert_chain_path = "certs/cert.pem"
private_key_path = "certs/key.pem"
allowed_sni = ["time.android.com"]
EOF


####

apt install certbot -y

certbot certonly \
  --standalone \
  --preferred-challenges http \
  -d "$hostname" \
  --agree-tos \
  -m "admin@$hostname" \
  --non-interactive

install -d -m 0755 /opt/trusttunnel/certs
install -m 0644 "/etc/letsencrypt/live/$hostname/fullchain.pem" /opt/trusttunnel/certs/cert.pem
install -m 0600 "/etc/letsencrypt/live/$hostname/privkey.pem" /opt/trusttunnel/certs/key.pem

####

cp trusttunnel.service.template /etc/systemd/system/trusttunnel.service
systemctl daemon-reload
systemctl enable --now trusttunnel.service

####
install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/trusttunnel.sh << EOF
#!/bin/sh
set -eu

[ "\${RENEWED_LINEAGE:-}" = "/etc/letsencrypt/live/$hostname" ] || exit 0

install -d -m 0755 /opt/trusttunnel/certs
install -m 0644 "\$RENEWED_LINEAGE/fullchain.pem" /opt/trusttunnel/certs/cert.pem
install -m 0600 "\$RENEWED_LINEAGE/privkey.pem" /opt/trusttunnel/certs/key.pem

systemctl restart trusttunnel.service
EOF
chmod 0750 /etc/letsencrypt/renewal-hooks/deploy/trusttunnel.sh

####
systemctl enable --now certbot.timer



HOST=$(grep -oP 'hostname\s*=\s*"\K[^"]+' /opt/trusttunnel/hosts.toml) && \
IP=$(ip route get 1 | awk '{print $7; exit}') && \
awk -v host="$HOST" -v ip="$IP" '
/username/ {u=$3; gsub(/"/,"",u)}
/password/ {
  p=$3; gsub(/"/,"",p);
  printf "HOST: %s\nIP: %s\nLOGIN: %s\nPASS: %s\n----------------------\n", host, ip, u, p
}
' /opt/trusttunnel/credentials.toml > /root/clients.txt


cat /root/clients.txt
