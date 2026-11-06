#!/usr/bin/env bash
# Install Nightscout (Docker + Caddy) on an Ubuntu VM in Oracle Cloud.
set -euo pipefail

DEST=/opt/nightscout
PROMPT_LANG=en

usage() {
  cat <<'EOF'
Usage: sudo ./install.sh

Run this on a fresh Ubuntu VM in Oracle Cloud, after ports 80 and 443
are allowed in the VCN security list. See README.md.

Non-interactive (all optional except API_SECRET):
  API_SECRET          at least 12 characters
  DISPLAY_UNITS       mmol or mg/dl          (default mmol)
  TZ                  IANA timezone          (default Asia/Jerusalem)
  NS_LANGUAGE         en or he, prompt language (default en)
  SITE_LANGUAGE       en or he, Nightscout UI   (default: NS_LANGUAGE)
  NS_DOMAIN           hostname for HTTPS     (optional)
  ACME_EMAIL          Let's Encrypt email    (required with NS_DOMAIN)
  AUTH_DEFAULT_ROLES  denied or readable     (default denied)
EOF
}

msg() {
  if [[ "$PROMPT_LANG" == "he" ]]; then
    printf '%s\n' "$2" >&2
  else
    printf '%s\n' "$1" >&2
  fi
}

ask() {
  local en="$1" he="$2" default="${3:-}" reply
  if [[ "$PROMPT_LANG" == "he" ]]; then
    read -r -p "$he${default:+ [$default]}: " reply
  else
    read -r -p "$en${default:+ [$default]}: " reply
  fi
  printf '%s' "${reply:-$default}"
}

reject_secret() {
  local s="$1"
  [[ ${#s} -ge 12 ]] || return 0
  [[ "$s" != *$'\n'* ]] || return 0
  [[ "$s" =~ [\$\`\\\"\'#] ]] && return 0
  return 1
}

read_secret() {
  local s1 s2
  while true; do
    if [[ "$PROMPT_LANG" == "he" ]]; then
      read -r -s -p "סוד API (לפחות 12 תווים). אותו ערך יוזן ב-AndroidAPS או ב-xDrip: " s1
      printf '\n'
      read -r -s -p "הקלידו שוב: " s2
      printf '\n'
    else
      read -r -s -p "API secret (at least 12 characters). You will type this into AndroidAPS or xDrip: " s1
      printf '\n'
      read -r -s -p "Repeat it: " s2
      printf '\n'
    fi
    if [[ "$s1" != "$s2" ]]; then
      msg "They do not match." "הערכים לא זהים."
      continue
    fi
    if reject_secret "$s1"; then
      msg "Use at least 12 characters, with no quotes, #, or dollar signs." \
        "לפחות 12 תווים, בלי גרשיים, בלי # ובלי סימן דולר."
      continue
    fi
    printf '%s' "$s1"
    return
  done
}

open_port() {
  local port="$1"
  if iptables -C INPUT -m state --state NEW -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    return 0
  fi
  # Oracle's Ubuntu image rejects traffic that does not match an earlier rule.
  if ! iptables -I INPUT 6 -m state --state NEW -p tcp --dport "$port" -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -m state --state NEW -p tcp --dport "$port" -j ACCEPT
  fi
}

write_caddyfile() {
  local domain="$1" email="$2" path="$3"
  if [[ -n "$domain" ]]; then
    cat >"$path" <<EOF
{
	email ${email}
}

${domain} {
	reverse_proxy nightscout:1337
}
EOF
  else
    cat >"$path" <<'EOF'
:80 {
	reverse_proxy nightscout:1337
}
EOF
  fi
}

ensure_swap() {
  local kb
  kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo)"
  if [[ "$kb" -ge 1500000 ]]; then
    return 0
  fi
  if swapon --show | awk 'NR>1 {found=1} END {exit !found}'; then
    return 0
  fi
  msg "This VM has about 1 GB of RAM. Adding a 2 GB swap file." \
    "למכונה יש בערך 1 GB זיכרון. מוסיפים קובץ swap של 2 GB."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "$(id -u)" -ne 0 ]]; then
  msg "Run it with sudo: sudo ./install.sh" "צריך להריץ עם sudo: sudo ./install.sh"
  exit 1
fi

if [[ ! -r /etc/os-release ]] || ! grep -q '^ID=ubuntu' /etc/os-release; then
  msg "This script supports Ubuntu on the VM." "הסקריפט תומך באובונטו על המכונה."
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -f "$ROOT/docker-compose.yml" ]]; then
  msg "docker-compose.yml was not found next to install.sh." \
    "לא נמצא docker-compose.yml ליד install.sh."
  exit 1
fi

if [[ -n "${API_SECRET:-}" ]]; then
  PROMPT_LANG="${NS_LANGUAGE:-en}"
  secret="$API_SECRET"
  if reject_secret "$secret"; then
    msg "API_SECRET must be at least 12 characters, with no quotes, #, or dollar signs." \
      "API_SECRET חייב להיות לפחות 12 תווים, בלי גרשיים, בלי # ובלי סימן דולר."
    exit 1
  fi
  units="${DISPLAY_UNITS:-mmol}"
  tz="${TZ:-Asia/Jerusalem}"
  site_lang="${SITE_LANGUAGE:-$PROMPT_LANG}"
  domain="${NS_DOMAIN:-}"
  acme_email="${ACME_EMAIL:-}"
  auth="${AUTH_DEFAULT_ROLES:-denied}"
else
  if [[ ! -t 0 ]]; then
    msg "No terminal for questions. Set API_SECRET and run again, or see --help." \
      "אין מסוף לשאלות. הגדירו API_SECRET והריצו שוב, או ראו --help."
    exit 1
  fi
  PROMPT_LANG="$(ask "Prompt language (en/he)" "שפת השאלות (en/he)" "en")"
  PROMPT_LANG="${PROMPT_LANG,,}"
  [[ "$PROMPT_LANG" == "he" || "$PROMPT_LANG" == "en" ]] || PROMPT_LANG=en
  secret="$(read_secret)"
  units="$(ask "Glucose units (mmol or mg/dl)" "יחידות סוכר (mmol או mg/dl)" "mmol")"
  tz="$(ask "Timezone" "אזור זמן" "Asia/Jerusalem")"
  site_lang="$(ask "Nightscout language (en/he)" "שפת האתר (en/he)" "$PROMPT_LANG")"
  domain="$(ask "Domain name for HTTPS, or leave empty" "שם מתחם ל-HTTPS, או ריק" "")"
  acme_email=""
  if [[ -n "$domain" ]]; then
    acme_email="$(ask "Email for the certificate" "אימייל לתעודה" "")"
  fi
  public="$(ask "Let anyone with the link view the site? (yes/no)" "כל מי שיש לו את הקישור יכול לצפות? (yes/no)" "no")"
  public="${public,,}"
  if [[ "$public" == "yes" || "$public" == "y" || "$public" == "כן" ]]; then
    auth="readable"
  else
    auth="denied"
  fi
fi

units="${units,,}"
PROMPT_LANG="${PROMPT_LANG,,}"
case "$units" in
  mmol|mg/dl) ;;
  *)
    msg "DISPLAY_UNITS must be mmol or mg/dl." "DISPLAY_UNITS חייב להיות mmol או mg/dl."
    exit 1
    ;;
esac
site_lang="${site_lang,,}"
[[ "$site_lang" == "en" || "$site_lang" == "he" ]] || site_lang=en
[[ "$auth" == "denied" || "$auth" == "readable" ]] || auth=denied
if [[ -n "$domain" ]]; then
  if [[ ! "$domain" =~ ^[A-Za-z0-9.-]+$ || "$domain" != *.* ]]; then
    msg "The domain looks wrong." "שם המתחם לא נראה תקין."
    exit 1
  fi
  if [[ "$acme_email" != *@* ]]; then
    msg "An email is required when a domain is set." "כשמגדירים שם מתחם חובה אימייל."
    exit 1
  fi
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl docker.io iptables-persistent
if ! docker compose version >/dev/null 2>&1; then
  apt-get install -y docker-compose-v2 || apt-get install -y docker-compose
fi
systemctl enable --now docker

ensure_swap
open_port 80
open_port 443
if command -v netfilter-persistent >/dev/null 2>&1; then
  netfilter-persistent save
fi

install -d -m 755 "$DEST"
install -m 644 "$ROOT/docker-compose.yml" "$DEST/docker-compose.yml"
write_caddyfile "$domain" "$acme_email" "$DEST/Caddyfile"

if [[ -n "$domain" ]]; then
  base_url="https://${domain}"
else
  base_url=""
fi

umask 077
{
  printf 'API_SECRET=%s\n' "$secret"
  printf 'DISPLAY_UNITS=%s\n' "$units"
  printf 'TZ=%s\n' "$tz"
  printf 'LANGUAGE=%s\n' "$site_lang"
  printf 'TIME_FORMAT=%s\n' "24"
  printf 'ENABLE=%s\n' "careportal basal rawbg cob iob cage sage pump dbsize"
  printf 'AUTH_DEFAULT_ROLES=%s\n' "$auth"
  if [[ -n "$base_url" ]]; then
    printf 'BASE_URL=%s\n' "$base_url"
  fi
} >"$DEST/.env"
chmod 600 "$DEST/.env"

compose() {
  if docker compose version >/dev/null 2>&1; then
    docker compose "$@"
  else
    docker-compose "$@"
  fi
}

cd "$DEST"
compose pull
compose up -d

ip="$(curl -fsS --max-time 5 https://ifconfig.me || true)"
echo
if [[ -n "$domain" ]]; then
  msg "Nightscout is starting at https://${domain}" "Nightscout עולה בכתובת https://${domain}"
  msg "The DNS A record must already point at this VM, or the certificate will fail." \
    "רשומת ה-A ב-DNS צריכה כבר להצביע למכונה הזו, אחרת התעודה תיכשל."
elif [[ -n "$ip" ]]; then
  msg "Nightscout is starting at http://${ip}" "Nightscout עולה בכתובת http://${ip}"
  msg "This address is plain HTTP. Add a domain later if you want HTTPS." \
    "זו כתובת HTTP בלי הצפנה. אפשר להוסיף שם מתחם אחר כך כדי לקבל HTTPS."
else
  msg "Nightscout is starting. Open http:// and the VM public IP." \
    "Nightscout עולה. פתחו http:// ואת כתובת ה-IP הציבורית של המכונה."
fi
msg "The API secret is stored only in ${DEST}/.env" "סוד ה-API שמור רק בקובץ ${DEST}/.env"
msg "Logs: cd ${DEST} && sudo docker compose logs -f" "יומן: cd ${DEST} && sudo docker compose logs -f"
