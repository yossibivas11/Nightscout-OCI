#!/usr/bin/env bash
# Nightscout on Oracle Cloud Always Free - one-shot deployer.
# Run in OCI Cloud Shell (browser, works from Windows/macOS/Linux):
#   bash deploy.sh            deploy (safe to re-run; reuses what exists)
#   bash deploy.sh render     only write the VM bootstrap script locally (no cloud changes)
#   bash deploy.sh destroy    delete the VM, network and budget created by this script
# Self-heal Windows (CRLF) line endings, then re-run:
grep -q $'\r' "$0" && { tr -d '\r' < "$0" > "$0.lf"; exec bash "$0.lf" "$@"; } #
set -euo pipefail

# ---------------- settings (override with environment variables) ----------------
P="${NAME_PREFIX:-ns}"                 # prefix for all resource names
OCPUS="${OCPUS:-1}"
MEMORY_GB="${MEMORY_GB:-2}"
BOOT_GB="${BOOT_GB:-50}"        # API minimum is 50 GB (console says 47)
IMAGE_FLAVOR="${IMAGE_FLAVOR:-minimal}" # minimal | standard
MAX_ATTEMPTS="${MAX_ATTEMPTS:-120}"     # launch attempts when A1 is out of capacity
RETRY_SECONDS="${RETRY_SECONDS:-60}"
WORK="${WORK_DIR:-$HOME/nightscout-oci}"
CREDS="$HOME/nightscout-credentials.txt"
MODE="${1:-deploy}"

log()  { printf '\n==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '    !! %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
gen()  { local s; s=$(openssl rand -base64 64 | tr -dc 'A-Za-z0-9'); printf '%s' "${s:0:$1}"; }

ask() { # ask VAR "prompt" [default]
  local var=$1 msg=$2 def=${3:-} cur=${!1:-}
  if [ -z "$cur" ]; then
    if [ -n "$def" ]; then read -rp "    $msg [$def]: " cur; cur=${cur:-$def}
    else while [ -z "$cur" ]; do read -rp "    $msg: " cur; done; fi
  fi
  printf -v "$var" '%s' "$cur"
}

mkdir -p "$WORK"

# ---------------- files that go onto the VM ----------------
compose_file() { cat <<'EOF'
# Single Nightscout instance by design - do NOT add replicas.
x-logging: &logging
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"

services:
  mongo:
    image: mongo:6
    container_name: ns-mongo
    restart: unless-stopped
    command: ["--wiredTigerCacheSizeGB", "0.5"]
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_USER}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_PASSWORD}
    volumes:
      - ./data/mongo:/data/db
    healthcheck:
      test: ["CMD", "mongosh", "--quiet", "--eval", "db.adminCommand('ping').ok"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 30s
    logging: *logging

  nightscout:
    image: nightscout/cgm-remote-monitor:${NS_VERSION:-latest}
    build:
      context: https://github.com/nightscout/cgm-remote-monitor.git#${NS_GIT_REF:-master}
    container_name: ns-web
    restart: unless-stopped
    depends_on:
      mongo:
        condition: service_healthy
    environment:
      MONGODB_URI: mongodb://${MONGO_USER}:${MONGO_PASSWORD}@mongo:27017/${MONGO_DB:-nightscout}?authSource=admin
      API_SECRET: ${API_SECRET}
      PORT: 1337
      NODE_ENV: production
      TZ: ${TZ:-Asia/Jerusalem}
      INSECURE_USE_HTTP: "true"
      HOSTNAME: "0.0.0.0"
      BASE_URL: https://${DUCKDNS_SUBDOMAIN}.duckdns.org
      DISPLAY_UNITS: ${DISPLAY_UNITS:-mg/dl}
      TIME_FORMAT: "24"
      AUTH_DEFAULT_ROLES: ${AUTH_DEFAULT_ROLES:-denied}
      ENABLE: ${NS_ENABLE}
      SHOW_PLUGINS: ${NS_SHOW_PLUGINS}
      DBSIZE_MAX: ${DBSIZE_MAX:-30000}
      CUSTOM_TITLE: ${CUSTOM_TITLE:-Nightscout}
    expose:
      - "1337"
    logging: *logging

  caddy:
    image: caddy:2
    container_name: ns-caddy
    restart: unless-stopped
    depends_on:
      - nightscout
    ports:
      - "80:80"
      - "443:443"
    environment:
      NS_DOMAIN: ${DUCKDNS_SUBDOMAIN}.duckdns.org
      ACME_EMAIL: ${ACME_EMAIL}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data/caddy:/data
      - ./data/caddy-config:/config
    logging: *logging

  duckdns:
    image: lscr.io/linuxserver/duckdns:latest
    container_name: ns-duckdns
    restart: unless-stopped
    environment:
      SUBDOMAINS: ${DUCKDNS_SUBDOMAIN}
      TOKEN: ${DUCKDNS_TOKEN}
      TZ: ${TZ:-Asia/Jerusalem}
    logging: *logging
EOF
}

caddy_file() { cat <<'EOF'
{
	email {$ACME_EMAIL}
}

{$NS_DOMAIN} {
	encode gzip
	reverse_proxy nightscout:1337
}
EOF
}

env_file() { cat <<EOF
DUCKDNS_SUBDOMAIN=${DUCKDNS_SUBDOMAIN}
DUCKDNS_TOKEN=${DUCKDNS_TOKEN}
ACME_EMAIL=${ACME_EMAIL}
API_SECRET=${API_SECRET}
MONGO_USER=nightscout
MONGO_PASSWORD=${MONGO_PASSWORD}
MONGO_DB=nightscout
NS_VERSION=latest
NS_GIT_REF=master
DISPLAY_UNITS=${DISPLAY_UNITS}
TZ=${NS_TZ}
AUTH_DEFAULT_ROLES=denied
CUSTOM_TITLE=Nightscout
DBSIZE_MAX=30000
NS_ENABLE=careportal boluscalc food bwp cage sage iage bage iob cob basal ar2 rawbg pump openaps loop dbsize
NS_SHOW_PLUGINS=careportal iob cob basal pump openaps dbsize
EOF
}

vm_setup() { cat <<'EOF'
#!/usr/bin/env bash
# Runs on the VM as root (via cloud-init). Re-runnable: sudo bash /opt/nightscout/setup.sh
set -euo pipefail
cd "$(dirname "$0")"
export DEBIAN_FRONTEND=noninteractive
APT="apt-get -o DPkg::Lock::Timeout=600 -y"

echo "==> Base packages"
$APT update
$APT install curl ca-certificates openssl git iptables iptables-persistent

echo "==> Docker"
command -v docker >/dev/null 2>&1 || curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu 2>/dev/null || true

echo "==> Host firewall: allow 80/443"
for p in 80 443; do
  iptables -C INPUT -p tcp --dport "$p" -m state --state NEW -j ACCEPT 2>/dev/null \
    || iptables -I INPUT 1 -p tcp --dport "$p" -m state --state NEW -j ACCEPT
done
netfilter-persistent save || true

mkdir -p data/mongo data/caddy data/caddy-config
chmod 600 .env

echo "==> Nightscout image"
if docker compose pull nightscout; then echo "   prebuilt image pulled"
else echo "   no prebuilt arm64 image - building from source"; docker compose build nightscout; fi

echo "==> Start"
docker compose up -d mongo duckdns caddy
docker compose up -d --no-build nightscout
docker compose ps
echo "NIGHTSCOUT_SETUP_DONE"
EOF
}

render_user_data() { # writes $WORK/user-data.sh
  {
    echo '#!/bin/bash'
    echo 'set -euxo pipefail'
    echo 'mkdir -p /opt/nightscout && cd /opt/nightscout'
    echo "cat > docker-compose.yml <<'NS_EOF_COMPOSE'"; compose_file; echo 'NS_EOF_COMPOSE'
    echo "cat > Caddyfile <<'NS_EOF_CADDY'";          caddy_file;   echo 'NS_EOF_CADDY'
    echo "cat > .env <<'NS_EOF_ENV'";                 env_file;     echo 'NS_EOF_ENV'
    echo "cat > setup.sh <<'NS_EOF_SETUP'";           vm_setup;     echo 'NS_EOF_SETUP'
    echo 'chmod 700 setup.sh && chmod 600 .env'
    echo 'bash setup.sh'
  } > "$WORK/user-data.sh"
}

# ---------------- inputs ----------------
collect_inputs() {
  log "Settings"
  ask DUCKDNS_SUBDOMAIN "DuckDNS subdomain (the part before .duckdns.org)"
  DUCKDNS_SUBDOMAIN=$(printf '%s' "$DUCKDNS_SUBDOMAIN" | tr 'A-Z' 'a-z' | sed 's/\.duckdns\.org$//; s#^https\?://##')
  [[ "$DUCKDNS_SUBDOMAIN" =~ ^[a-z0-9-]+$ ]] || die "Subdomain may contain only a-z, 0-9 and '-'"
  ask DUCKDNS_TOKEN "DuckDNS token (duckdns.org account page)"
  ask ACME_EMAIL "Email for TLS certificate and budget alerts"
  ask DISPLAY_UNITS "Glucose units (mg/dl or mmol)" "mg/dl"
  ask NS_TZ "Time zone" "Asia/Jerusalem"
  ask ENABLE_BACKUP "Weekly boot-volume backup, 3-week retention, free tier (y/n)" "y"
  API_SECRET="${API_SECRET:-$(gen 32)}"
  MONGO_PASSWORD="${MONGO_PASSWORD:-$(gen 32)}"
  # Re-run: keep secrets from the first deployment so .env matches the running DB
  if [ -f "$CREDS" ]; then
    API_SECRET=$(awk -F': ' '/^API_SECRET/{print $2}' "$CREDS"); MONGO_PASSWORD=$(awk -F': ' '/^MONGO_PASSWORD/{print $2}' "$CREDS")
    info "Reusing secrets from $CREDS"
  fi
}

# ---------------- OCI helpers ----------------
oci_ctx() {
  command -v oci >/dev/null || die "OCI CLI not found. Run this in OCI Cloud Shell."
  command -v jq  >/dev/null || die "jq not found."
  TENANCY="${OCI_TENANCY:-$(awk -F= '/^tenancy/{gsub(/ /,"");print $2;exit}' "$HOME/.oci/config" 2>/dev/null || true)}"
  [ -n "$TENANCY" ] || ask TENANCY "Tenancy OCID (Profile > Tenancy)"
  C="$TENANCY"
  HOME_REGION=$(oci iam region-subscription list --tenancy-id "$TENANCY" \
    | jq -r '.data[] | select(."is-home-region"==true) | ."region-name"')
  [ -n "$HOME_REGION" ] || die "Could not determine home region."
  R=(--region "$HOME_REGION")
  info "Tenancy root compartment, home region: $HOME_REGION (Always Free lives here)"
}

by_name() { # by_name <oci list args...>  -> first matching id not terminated
  { oci "$@" "${R[@]}" --all 2>/dev/null || true; } | jq -r --arg n "$NAME" \
    '[.data[]? | select(."display-name"==$n and (."lifecycle-state"|test("TERMINAT|DELET")|not))][0].id // empty' 2>/dev/null || true
}

find_instance() { NAME="$P-vm" by_name compute instance list -c "$C"; }

# ---------------- deploy steps ----------------
network() {
  log "Network"
  VCN_ID=$(NAME="$P-vcn" by_name network vcn list -c "$C")
  if [ -z "$VCN_ID" ]; then
    VCN_ID=$(oci network vcn create "${R[@]}" -c "$C" --display-name "$P-vcn" --cidr-blocks '["10.0.0.0/16"]' \
      --dns-label nsvcn --wait-for-state AVAILABLE 2>/dev/null | jq -r .data.id)
    info "created VCN"
  else info "reusing VCN"; fi
  VCN=$(oci network vcn get "${R[@]}" --vcn-id "$VCN_ID")
  RT_ID=$(jq -r '.data."default-route-table-id"' <<<"$VCN")
  SL_ID=$(jq -r '.data."default-security-list-id"' <<<"$VCN")

  IGW_ID=$(NAME="$P-igw" by_name network internet-gateway list -c "$C" --vcn-id "$VCN_ID")
  if [ -z "$IGW_ID" ]; then
    IGW_ID=$(oci network internet-gateway create "${R[@]}" -c "$C" --vcn-id "$VCN_ID" --display-name "$P-igw" \
      --is-enabled true --wait-for-state AVAILABLE 2>/dev/null | jq -r .data.id)
    info "created internet gateway"
  fi

  oci network route-table update "${R[@]}" --rt-id "$RT_ID" --force \
    --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$IGW_ID\"}]" >/dev/null

  local tcp='"protocol":"6","source":"0.0.0.0/0","isStateless":false'
  oci network security-list update "${R[@]}" --security-list-id "$SL_ID" --force \
    --ingress-security-rules "[
      {$tcp,\"tcpOptions\":{\"destinationPortRange\":{\"min\":22,\"max\":22}}},
      {$tcp,\"tcpOptions\":{\"destinationPortRange\":{\"min\":80,\"max\":80}}},
      {$tcp,\"tcpOptions\":{\"destinationPortRange\":{\"min\":443,\"max\":443}}},
      {\"protocol\":\"1\",\"source\":\"0.0.0.0/0\",\"isStateless\":false,\"icmpOptions\":{\"type\":3,\"code\":4}}]" \
    --egress-security-rules '[{"protocol":"all","destination":"0.0.0.0/0","isStateless":false}]' >/dev/null
  info "ports 22/80/443 open"

  SUBNET_ID=$(NAME="$P-subnet" by_name network subnet list -c "$C" --vcn-id "$VCN_ID")
  if [ -z "$SUBNET_ID" ]; then
    SUBNET_ID=$(oci network subnet create "${R[@]}" -c "$C" --vcn-id "$VCN_ID" --display-name "$P-subnet" \
      --cidr-block 10.0.0.0/24 --dns-label nssub --wait-for-state AVAILABLE 2>/dev/null | jq -r .data.id)
    info "created public subnet"
  fi
}

image() {
  log "Image"
  local list re
  list=$(oci compute image list "${R[@]}" -c "$C" --operating-system "Canonical Ubuntu" \
    --shape VM.Standard.A1.Flex --sort-by TIMECREATED --sort-order DESC --all)
  re='24\.04-aarch64'; [ "$IMAGE_FLAVOR" = minimal ] && re='24\.04-Minimal-aarch64'
  IMAGE_ID=$(jq -r --arg re "$re" '[.data[] | select(."display-name"|test($re))][0].id // empty' <<<"$list")
  if [ -z "$IMAGE_ID" ] && [ "$IMAGE_FLAVOR" = minimal ]; then
    warn "Ubuntu 24.04 Minimal (arm) not offered here - using standard Ubuntu 24.04"
    IMAGE_ID=$(jq -r '[.data[] | select(."display-name"|test("24\\.04-aarch64"))][0].id // empty' <<<"$list")
  fi
  [ -n "$IMAGE_ID" ] || die "No Ubuntu 24.04 arm64 image found."
  info "$(jq -r --arg id "$IMAGE_ID" '.data[]|select(.id==$id)|."display-name"' <<<"$list")"
}

ssh_key() {
  SSH_PUB="${SSH_PUBLIC_KEY_FILE:-$HOME/.ssh/$P-key.pub}"
  if [ ! -f "$SSH_PUB" ]; then
    command -v ssh-keygen >/dev/null || die "ssh-keygen not found; set SSH_PUBLIC_KEY_FILE to an existing .pub key"
    # RSA, not ED25519: OCI Cloud Shell runs in FIPS mode, which rejects ED25519
    mkdir -p "$HOME/.ssh"; ssh-keygen -t rsa -b 4096 -N "" -C nightscout-oci -f "${SSH_PUB%.pub}" -q
    info "generated SSH key ${SSH_PUB%.pub}"
  fi
}

launch() {
  log "VM (A1.Flex ${OCPUS} OCPU / ${MEMORY_GB} GB, ${BOOT_GB} GB disk)"
  INSTANCE_ID=$(find_instance)
  if [ -n "$INSTANCE_ID" ]; then info "reusing existing VM (bootstrap already applied at first boot)"; return; fi
  local ads attempt=0 ad
  mapfile -t ads < <(oci iam availability-domain list "${R[@]}" -c "$C" | jq -r '.data[].name')
  while :; do
    for ad in "${ads[@]}"; do
      attempt=$((attempt+1))
      info "attempt $attempt/$MAX_ATTEMPTS in ${ad##*:}"
      if oci compute instance launch "${R[@]}" -c "$C" --availability-domain "$ad" \
          --display-name "$P-vm" --shape VM.Standard.A1.Flex \
          --shape-config "{\"ocpus\":$OCPUS,\"memoryInGBs\":$MEMORY_GB}" \
          --image-id "$IMAGE_ID" --boot-volume-size-in-gbs "$BOOT_GB" \
          --subnet-id "$SUBNET_ID" --assign-public-ip true \
          --ssh-authorized-keys-file "$SSH_PUB" --user-data-file "$WORK/user-data.sh" \
          --wait-for-state RUNNING --max-wait-seconds 900 >"$WORK/launch.json" 2>"$WORK/launch.err"; then
        INSTANCE_ID=$(jq -r .data.id "$WORK/launch.json"); info "VM running"; return
      fi
      INSTANCE_ID=$(find_instance)   # launch accepted but wait timed out
      if [ -n "$INSTANCE_ID" ]; then
        oci compute instance get "${R[@]}" --instance-id "$INSTANCE_ID" --wait-for-state RUNNING >/dev/null 2>&1 || true
        return
      fi
      if grep -qi 'capacity' "$WORK/launch.err"; then info "out of host capacity"
      elif grep -qiE 'LimitExceeded|limit' "$WORK/launch.err"; then
        cat "$WORK/launch.err" >&2; die "A1 limit exceeded - free allowance already used by other instances?"
      else cat "$WORK/launch.err" >&2; die "Launch failed"; fi
      [ "$attempt" -ge "$MAX_ATTEMPTS" ] && die "No A1 capacity after $attempt attempts. Re-run later."
    done
    info "waiting ${RETRY_SECONDS}s before retrying"; sleep "$RETRY_SECONDS"
  done
}

instance_facts() {
  PUBLIC_IP=$(oci compute instance list-vnics "${R[@]}" --instance-id "$INSTANCE_ID" | jq -r '.data[0]."public-ip"')
  INSTANCE_AD=$(oci compute instance get "${R[@]}" --instance-id "$INSTANCE_ID" | jq -r '.data."availability-domain"')
  BOOT_VOL_ID=$(oci compute boot-volume-attachment list "${R[@]}" -c "$C" --availability-domain "$INSTANCE_AD" \
    --instance-id "$INSTANCE_ID" | jq -r '.data[0]."boot-volume-id"')
  info "public IP: $PUBLIC_IP"
}

duckdns() {
  log "DuckDNS -> $PUBLIC_IP"
  local r; r=$(curl -fsS "https://www.duckdns.org/update?domains=${DUCKDNS_SUBDOMAIN}&token=${DUCKDNS_TOKEN}&ip=${PUBLIC_IP}" || true)
  [ "$r" = "OK" ] && info "updated" || warn "DuckDNS update failed (check subdomain/token). The VM retries every 5 min."
}

budget() {
  log "Budget guard (\$1/month, alert on any spend)"
  local id; id=$({ oci budgets budget list "${R[@]}" -c "$C" --all 2>/dev/null || true; } \
    | jq -r --arg n "$P-guard" '[.data[]? | select(."display-name"==$n)][0].id // empty')
  if [ -n "$id" ]; then info "exists"; return; fi
  if id=$(oci budgets budget create "${R[@]}" -c "$C" --display-name "$P-guard" --amount 1 \
        --reset-period MONTHLY --target-type COMPARTMENT --targets "[\"$C\"]" 2>/dev/null | jq -r .data.id) && [ -n "$id" ]; then
    oci budgets alert-rule create "${R[@]}" --budget-id "$id" --display-name any-spend --type ACTUAL \
      --threshold 1 --threshold-type PERCENTAGE --recipients "$ACME_EMAIL" >/dev/null 2>&1 \
      && info "created, alerts to $ACME_EMAIL" || warn "budget created, alert rule failed - add it in Billing > Budgets"
  else warn "could not create budget - create one manually in Billing > Budgets"; fi
}

backup() {
  [[ "$ENABLE_BACKUP" =~ ^[Yy] ]] || return 0
  log "Boot-volume backup policy (weekly, keep 3)"
  local pid
  pid=$(NAME="$P-weekly" by_name bv volume-backup-policy list -c "$C")
  if [ -z "$pid" ]; then
    pid=$(oci bv volume-backup-policy create "${R[@]}" -c "$C" --display-name "$P-weekly" \
      --schedules '[{"backupType":"INCREMENTAL","period":"ONE_WEEK","dayOfWeek":"SUNDAY","hourOfDay":3,"timeZone":"UTC","retentionSeconds":1814400}]' \
      2>/dev/null | jq -r .data.id) || pid=""
  fi
  [ -n "$pid" ] || { warn "could not create policy - set one in Block Storage > Boot Volumes"; return 0; }
  oci bv volume-backup-policy-assignment create "${R[@]}" --asset-id "$BOOT_VOL_ID" --policy-id "$pid" >/dev/null 2>&1 \
    && info "assigned" || info "already assigned (or assignment failed - check the console)"
}

wait_site() {
  FQDN="${DUCKDNS_SUBDOMAIN}.duckdns.org"
  log "Waiting for https://$FQDN (Docker install + image pull/build: usually 5-25 min)"
  local i code
  for i in $(seq 1 100); do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$FQDN/api/v1/status.json" || true)
    case "$code" in 200|401) info "Nightscout is up (HTTP $code)"; return 0;; esac
    sleep 30
  done
  warn "Not up after 50 min. SSH in and check: sudo tail -n 100 /var/log/cloud-init-output.log"
}

save_creds() {
  umask 077
  cat > "$CREDS" <<EOF
URL: https://${DUCKDNS_SUBDOMAIN}.duckdns.org
API_SECRET: ${API_SECRET}
MONGO_PASSWORD: ${MONGO_PASSWORD}
XDRIP_BASE_URL: https://${API_SECRET}@${DUCKDNS_SUBDOMAIN}.duckdns.org/api/v1/
PUBLIC_IP: ${PUBLIC_IP:-}
SSH: ssh -i ${SSH_PUB%.pub} ubuntu@${PUBLIC_IP:-<ip>}
INSTANCE_OCID: ${INSTANCE_ID:-}
REGION: ${HOME_REGION:-}
EOF
}

destroy() {
  oci_ctx
  log "This deletes the VM (and ALL Nightscout data on it), network and budget."
  read -rp "    Type 'destroy' to confirm: " c; [ "$c" = destroy ] || die "Cancelled."
  local id
  id=$(find_instance) && [ -n "$id" ] && { info "terminating VM"; oci compute instance terminate "${R[@]}" --instance-id "$id" \
    --preserve-boot-volume false --force --wait-for-state TERMINATED >/dev/null 2>&1 || true; }
  VCN_ID=$(NAME="$P-vcn" by_name network vcn list -c "$C")
  if [ -n "$VCN_ID" ]; then
    id=$(NAME="$P-subnet" by_name network subnet list -c "$C" --vcn-id "$VCN_ID")
    [ -n "$id" ] && oci network subnet delete "${R[@]}" --subnet-id "$id" --force --wait-for-state TERMINATED >/dev/null 2>&1 || true
    RT_ID=$(oci network vcn get "${R[@]}" --vcn-id "$VCN_ID" | jq -r '.data."default-route-table-id"')
    oci network route-table update "${R[@]}" --rt-id "$RT_ID" --route-rules '[]' --force >/dev/null 2>&1 || true
    id=$(NAME="$P-igw" by_name network internet-gateway list -c "$C" --vcn-id "$VCN_ID")
    [ -n "$id" ] && oci network internet-gateway delete "${R[@]}" --ig-id "$id" --force --wait-for-state TERMINATED >/dev/null 2>&1 || true
    oci network vcn delete "${R[@]}" --vcn-id "$VCN_ID" --force --wait-for-state TERMINATED >/dev/null 2>&1 || true
    info "network deleted"
  fi
  id=$({ oci budgets budget list "${R[@]}" -c "$C" --all 2>/dev/null || true; } | jq -r --arg n "$P-guard" '[.data[]?|select(."display-name"==$n)][0].id // empty')
  [ -n "$id" ] && oci budgets budget delete "${R[@]}" --budget-id "$id" --force >/dev/null 2>&1 || true
  id=$(NAME="$P-weekly" by_name bv volume-backup-policy list -c "$C" || true)
  [ -n "$id" ] && warn "backup policy '$P-weekly' and existing backups kept - delete them in the console if unwanted"
  mv -f "$CREDS" "$CREDS.old" 2>/dev/null || true
  log "Done."
}

# ---------------- main ----------------
case "$MODE" in
  render)
    DUCKDNS_SUBDOMAIN="${DUCKDNS_SUBDOMAIN:-example}" DUCKDNS_TOKEN="${DUCKDNS_TOKEN:-token}" \
    ACME_EMAIL="${ACME_EMAIL:-you@example.com}" DISPLAY_UNITS="${DISPLAY_UNITS:-mg/dl}" NS_TZ="${NS_TZ:-Asia/Jerusalem}" \
    API_SECRET="${API_SECRET:-$(gen 32)}" MONGO_PASSWORD="${MONGO_PASSWORD:-$(gen 32)}"
    render_user_data; echo "Wrote $WORK/user-data.sh"; exit 0 ;;
  destroy) destroy; exit 0 ;;
  deploy) ;;
  *) die "Usage: bash deploy.sh [deploy|render|destroy]" ;;
esac

oci_ctx
collect_inputs
render_user_data
network
image
ssh_key
launch
instance_facts
save_creds
duckdns
if [ "${SKIP_BUDGET:-n}" = y ]; then info "budget skipped (SKIP_BUDGET=y)"
else budget || warn "budget step failed - create it in Billing > Budgets"; fi
backup || warn "backup step failed - set a policy in Block Storage > Boot Volumes"
wait_site

log "Finished"
cat "$CREDS"
echo
echo "Saved to $CREDS (Cloud Shell home, private). Copy API_SECRET somewhere safe."
