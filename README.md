# Nightscout on Oracle Cloud Always Free — automated, Windows-friendly

One script, `deploy.sh`, builds everything: network, a free **Ampere A1** VM (1 OCPU / 2 GB), MongoDB, Nightscout, HTTPS (Caddy + Let's Encrypt) and DuckDNS.

**Nothing to install on Windows.** The script runs in **OCI Cloud Shell**, a Linux terminal inside your browser that is already logged in to your Oracle account.

---

## Before you start (one-time, manual)

1. **Oracle account**
   - Sign up at oracle.com/cloud/free. A card is required for identity verification.
   - **Home region** is permanent and Always Free only works there. Pick one near you with A1 capacity (Frankfurt is often suggested).
   - Recommended: **Billing → Upgrade to Pay As You Go**. Paid accounts are not subject to idle-instance reclamation; you still pay $0 inside Always Free limits. The script adds a $1 budget alert as a guard.
2. **DuckDNS**
   - Go to duckdns.org, sign in, **add a subdomain** (e.g. `my-ns`), copy the **token** shown at the top.
   - Don't use your full name: the URL is public.

---

## Deploy (about 5–25 minutes, mostly waiting)

1. Sign in to the **OCI Console**. Make sure the region selector (top right) shows your **home region**.
2. Click the **Developer tools / Cloud Shell** icon (`>_`) in the top bar. Wait for the terminal to open.
3. Upload the script: Cloud Shell window **⚙ menu → Upload** → choose `deploy.sh`.
4. Run:
   ```bash
   bash deploy.sh
   ```
5. Answer the prompts:
   - DuckDNS subdomain (only the part before `.duckdns.org`)
   - DuckDNS token
   - Email (TLS certificate notices and budget alerts)
   - Units `mg/dl` or `mmol`, time zone, and whether to enable the weekly free backup
6. Wait for **"Nightscout is up"**. The script prints your URL and **API_SECRET** and saves them to `~/nightscout-credentials.txt` in Cloud Shell.
   - To see them later: `cat ~/nightscout-credentials.txt`

### If it says "out of host capacity"
Normal for free A1 VMs. The script retries across availability domains every 60 s for up to 120 attempts. You can close the browser tab and re-run `bash deploy.sh` later; it reuses what was already created.

### Edited the script in Notepad?
Windows line endings are fixed automatically when the script starts.

---

## After deploy

- **Open** `https://<subdomain>.duckdns.org`, click the lock icon, enter **API_SECRET**.
- **Admin Tools → Subjects** — create tokens:
  - `aaps` with role **admin** (check your AAPS version's NSClient v3 docs)
  - `follower` with role **readable** — share `https://<subdomain>.duckdns.org/?token=<follower-token>`
- **xDrip+**: Settings → Cloud Upload → Nightscout Sync → Base URL = `XDRIP_BASE_URL` from the credentials file.
- **AAPS** (NSClient v3): URL `https://<subdomain>.duckdns.org`, token = the `aaps` token.
- Let only one app upload BG to avoid duplicates.




## Optional: SSH into the VM from Windows

Normally not needed. If you want it:

1. In Cloud Shell: **⚙ menu → Download** → enter `.ssh/ns-key` → save it to `C:\Users\<you>\.ssh\ns-key`.
2. In **PowerShell** (OpenSSH is built into Windows 10/11):
   ```powershell
   $key = "$env:USERPROFILE\.ssh\ns-key"
   icacls $key /inheritance:r /grant:r "$($env:USERNAME):(R)"
   ssh -i $key ubuntu@<PUBLIC_IP>
   ```
   `icacls` fixes the "unprotected private key" error.
3. Useful on the VM:
   - Bootstrap log: `sudo tail -n 100 /var/log/cloud-init-output.log`
   - Status: `cd /opt/nightscout && sudo docker compose ps`
   - Logs: `sudo docker compose logs -f nightscout`
   - Update: `sudo docker compose pull && sudo docker compose up -d`

Or skip Windows entirely and SSH from Cloud Shell: the `SSH:` line in the credentials file works there as-is.

---

## Commands

| Command | What it does |
|---|---|
| `bash deploy.sh` | Deploy, or resume a partial deploy |
| `bash deploy.sh render` | Write the VM bootstrap to `~/nightscout-oci/user-data.sh` for review; no cloud changes |
| `bash deploy.sh destroy` | Delete VM (**all data**), network and budget. Asks you to type `destroy` |

Settings can be overridden with environment variables, e.g. `IMAGE_FLAVOR=standard MAX_ATTEMPTS=300 bash deploy.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `IMAGE_FLAVOR` | `minimal` | `minimal` = Ubuntu 24.04 Minimal, `standard` = full Ubuntu |
| `OCPUS` / `MEMORY_GB` | `1` / `2` | VM size (free limit: 2 OCPU / 12 GB total) |
| `MAX_ATTEMPTS` / `RETRY_SECONDS` | `120` / `60` | Capacity retry loop |
| `NAME_PREFIX` | `ns` | Prefix for resource names |

---

## What the script creates (all Always Free)

- VCN `ns-vcn`, internet gateway, public subnet; ports **22, 80, 443** open
- VM `ns-vm`: A1.Flex 1 OCPU / 2 GB, 50 GB boot volume (≈35+ GB usable for data; 2 years ≈ 1 GB)
- On the VM (`/opt/nightscout`): MongoDB 6 (not exposed), Nightscout (single instance), Caddy, DuckDNS updater
- Budget `ns-guard`: $1/month, email on any spend
- Optional backup policy `ns-weekly`: weekly incremental, 3-week retention (stays within the free backup count)

## Notes and limits

- **One Nightscout instance only.** Never scale it out (in-memory cache, socket.io, duplicate alarms).
- **No SLA** on Always Free. Keep the backup policy on.
- If no arm64 Nightscout image is published, the VM builds it from source (adds a few minutes on first boot).
- `DBSIZE_MAX=30000` (MiB) only drives the on-screen DB-size warning. It does not limit storage.
