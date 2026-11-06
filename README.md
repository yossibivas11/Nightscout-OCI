# Nightscout on Oracle Cloud Always Free

`deploy.sh` builds the whole site from [OCI Cloud Shell](https://docs.oracle.com/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm): the network, a free Ampere A1 virtual machine (1 OCPU, 2 GB), MongoDB, Nightscout, HTTPS (Caddy and Let's Encrypt), and DuckDNS.

Nothing is installed on your own computer. Cloud Shell is a Linux terminal inside the Oracle website, already logged in to your account. The script runs there.

Nightscout shows continuous glucose monitor data. It is not an approved medical device.

[עברית](#עברית)

---

## English

### Before you start

Do this once, in a browser.

1. **Oracle account.** Sign up at [oracle.com/cloud/free](https://www.oracle.com/cloud/free/). A card is required for identity verification. The **home region** is permanent, and Always Free resources only exist there. Pick a region near you that has Ampere A1 capacity. Frankfurt is often a good choice.
2. **Upgrade to Pay As You Go** under **Billing**. A paid account is not subject to Oracle's idle-instance reclamation, and you still pay $0 while you stay inside Always Free limits. The script creates a $1 budget alert so any real charge emails you.
3. **DuckDNS.** Go to [duckdns.org](https://www.duckdns.org/), sign in, and add a subdomain such as `my-ns`. Copy the **token** at the top of the page. Do not use your full name. The URL is public.

### Deploy

This usually takes 5–25 minutes, most of it waiting.

1. Sign in to the [OCI Console](https://cloud.oracle.com/). The region selector at the top right must show your **home region**.
2. Click the **Developer tools / Cloud Shell** icon (`>_`) in the top bar. Wait until the terminal opens.
3. In the Cloud Shell window, open the **gear menu → Upload** and choose `deploy.sh`.
4. Run:

```bash
bash deploy.sh
```

5. Answer the prompts:

| Prompt | What to enter |
|---|---|
| DuckDNS subdomain | Only the part before `.duckdns.org`, for example `my-ns` |
| DuckDNS token | The token from the DuckDNS account page |
| Email | Used for certificate notices and budget alerts |
| Glucose units | `mg/dl` or `mmol`. Press Enter for `mg/dl` |
| Time zone | Press Enter for `Asia/Jerusalem`, or type another IANA name |
| Weekly boot-volume backup | Press Enter for `y` (3-week retention, inside the free tier) |

The script generates **API_SECRET**. You do not invent one.

6. Wait until it says Nightscout is up. It prints the URL and **API_SECRET**, and saves them to `~/nightscout-credentials.txt` in Cloud Shell.

```bash
cat ~/nightscout-credentials.txt
```

Running `bash deploy.sh` again is safe. It reuses the network, the VM, and the secrets from that file.

Windows line endings are fixed automatically if the script was edited in Notepad.

### If it says "out of host capacity"

That is normal for free A1 virtual machines. The script tries every availability domain, waits 60 seconds, and repeats, up to 120 attempts. You can close the browser tab and run `bash deploy.sh` again later. What was already created is reused.

### After deploy

Open `https://<subdomain>.duckdns.org`. Click the lock icon and enter **API_SECRET**.

In **Admin Tools → Subjects**, create tokens:

- `aaps` with role **admin**. Check your AAPS version's NSClient v3 documentation.
- `follower` with role **readable**. Share `https://<subdomain>.duckdns.org/?token=<follower-token>`.

**xDrip+:** Settings → Cloud Upload → Nightscout Sync. Set the base URL to `XDRIP_BASE_URL` from the credentials file.

**AAPS** (NSClient v3): URL `https://<subdomain>.duckdns.org`, token = the `aaps` token.

Let only one app upload blood glucose. Two uploaders create duplicate readings.

### SSH, if you need it

You do not need this for a normal deploy. The `SSH:` line in `~/nightscout-credentials.txt` works as-is inside Cloud Shell.

From Windows:

1. In Cloud Shell, **gear menu → Download**, enter `.ssh/ns-key`, and save it to `C:\Users\<you>\.ssh\ns-key`.
2. In PowerShell:

```powershell
$key = "$env:USERPROFILE\.ssh\ns-key"
icacls $key /inheritance:r /grant:r "$($env:USERNAME):(R)"
ssh -i $key ubuntu@<PUBLIC_IP>
```

`icacls` clears the "unprotected private key" error. OpenSSH is already part of Windows 10 and 11.

On the VM:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
cd /opt/nightscout && sudo docker compose ps
sudo docker compose logs -f nightscout
sudo docker compose pull && sudo docker compose up -d
```

### Commands

| Command | What it does |
|---|---|
| `bash deploy.sh` | Deploy, or resume a partial deploy |
| `bash deploy.sh render` | Write the VM bootstrap to `~/nightscout-oci/user-data.sh` for review. No cloud changes |
| `bash deploy.sh destroy` | Delete the VM (**all data**), the network, and the budget. You must type `destroy` |

Settings can be overridden with environment variables, for example `IMAGE_FLAVOR=standard MAX_ATTEMPTS=300 bash deploy.sh`.

| Variable | Default | Meaning |
|---|---|---|
| `IMAGE_FLAVOR` | `minimal` | `minimal` is Ubuntu 24.04 Minimal. `standard` is the full Ubuntu image |
| `OCPUS` / `MEMORY_GB` | `1` / `2` | VM size. The free Ampere limit is 2 OCPU and 12 GB total |
| `MAX_ATTEMPTS` / `RETRY_SECONDS` | `120` / `60` | How the capacity retry loop waits |
| `NAME_PREFIX` | `ns` | Prefix for the resource names |

### What the script creates

All of this stays inside Always Free limits:

- VCN `ns-vcn`, an internet gateway, a public subnet, and ports **22, 80, and 443**
- VM `ns-vm`: A1.Flex, 1 OCPU, 2 GB memory, 50 GB boot volume
- On the VM, in `/opt/nightscout`: MongoDB 6 (not exposed to the internet), one Nightscout container, Caddy, and a DuckDNS updater
- Budget `ns-guard`: $1 per month, email on any spend
- Optional backup policy `ns-weekly`: weekly incremental backups, kept for 3 weeks

### Limits

- **One Nightscout container.** Do not scale it out. Nightscout keeps state in memory, and extra copies duplicate alarms.
- Always Free has **no SLA**. Leave the backup policy on.
- If no arm64 Nightscout image is published, the VM builds it from source. The first boot is then a few minutes longer.
- `DBSIZE_MAX=30000` (MiB) only drives the on-screen database-size warning. It does not limit storage.

---

# עברית

`deploy.sh` בונה את כל האתר מתוך [OCI Cloud Shell](https://docs.oracle.com/iaas/Content/API/Concepts/devcloudshellgettingstarted.htm): הרשת, מכונה וירטואלית חינמית מסוג Ampere A1‏ (1 OCPU, ‏2 GB), MongoDB,‏ Nightscout,‏ HTTPS‏ (Caddy ו-Let's Encrypt) ו-DuckDNS.

שום דבר לא מותקן על המחשב שלכם. Cloud Shell הוא מסוף לינוקס בתוך אתר Oracle, שכבר מחובר לחשבון. הסקריפט רץ שם.

Nightscout מציג נתוני חיישן סוכר. הוא אינו מכשיר רפואי מאושר.

[English](#nightscout-on-oracle-cloud-always-free)

### לפני שמתחילים

עושים את זה פעם אחת, בדפדפן.

1. **חשבון Oracle.** נרשמים ב-[oracle.com/cloud/free](https://www.oracle.com/cloud/free/). נדרש כרטיס לאימות זהות. **אזור הבית** קבוע, ומשאבי Always Free קיימים רק בו. בוחרים אזור קרוב שיש בו קיבולת Ampere A1. פרנקפורט היא בחירה שמצליחה לעיתים קרובות.
2. **שדרוג ל-Pay As You Go** תחת **Billing**. חשבון בתשלום אינו כפוף למחיקת מכונות לא פעילות של Oracle, ועדיין משלמים $0 כל עוד נשארים בתוך מגבלות Always Free. הסקריפט יוצר התראת תקציב של $1 כדי שכל חיוב אמיתי יישלח אליכם באימייל.
3. **DuckDNS.** נכנסים ל-[duckdns.org](https://www.duckdns.org/), מתחברים, ומוסיפים תת-שם כמו `my-ns`. מעתיקים את ה-**token** מראש העמוד. לא משתמשים בשם המלא. הכתובת ציבורית.

### פריסה

זה לוקח בדרך כלל 5–25 דקות, ורובן המתנה.

1. נכנסים ל-[OCI Console](https://cloud.oracle.com/). בורר האזור בפינה הימנית העליונה חייב להראות את **אזור הבית**.
2. לוחצים על סמל **Developer tools / Cloud Shell**‏ (`>_`) בסרגל העליון. מחכים שהמסוף ייפתח.
3. בחלון Cloud Shell פותחים **תפריט גלגל השיניים ← Upload** ובוחרים את `deploy.sh`.
4. מריצים:

```bash
bash deploy.sh
```

5. עונים על השאלות:

| שאלה | מה מזינים |
|---|---|
| תת-שם DuckDNS | רק החלק שלפני `.duckdns.org`, למשל `my-ns` |
| טוקן DuckDNS | הטוקן מעמוד החשבון ב-DuckDNS |
| אימייל | להודעות על התעודה ולהתראות תקציב |
| יחידות סוכר | `mg/dl` או `mmol`. Enter משאיר `mg/dl` |
| אזור זמן | Enter משאיר `Asia/Jerusalem`, או מקלידים שם IANA אחר |
| גיבוי שבועי של דיסק האתחול | Enter משאיר `y` (שמירה לשלושה שבועות, בתוך המסלול החינמי) |

הסקריפט מייצר את **API_SECRET**. לא ממציאים סיסמה.

6. מחכים עד שמופיע ש-Nightscout עלה. הוא מדפיס את הכתובת ואת **API_SECRET**, ושומר אותם בקובץ `~/nightscout-credentials.txt` ב-Cloud Shell.

```bash
cat ~/nightscout-credentials.txt
```

אפשר להריץ `bash deploy.sh` שוב. הוא משתמש מחדש ברשת, במכונה ובסודות מהקובץ הזה.

אם ערכתם את הסקריפט ב-Notepad, מעברי השורה של Windows מתוקנים אוטומטית בהפעלה.

### אם מופיע "out of host capacity"

זה מצב רגיל במכונות A1 חינמיות. הסקריפט מנסה כל availability domain, ממתין 60 שניות, וחוזר על זה עד 120 ניסיונות. אפשר לסגור את הלשונית ולהריץ `bash deploy.sh` שוב מאוחר יותר. מה שכבר נוצר נשמר.

### אחרי הפריסה

פותחים את `https://<subdomain>.duckdns.org`. לוחצים על סמל המנעול ומזינים את **API_SECRET**.

ב-**Admin Tools ← Subjects** יוצרים אסימונים:

- `aaps` עם תפקיד **admin**. בודקים את תיעוד NSClient v3 של גרסת AAPS שלכם.
- `follower` עם תפקיד **readable**. משתפים `https://<subdomain>.duckdns.org/?token=<follower-token>`.

**xDrip+:**‏ Settings ← Cloud Upload ← Nightscout Sync. כתובת הבסיס היא `XDRIP_BASE_URL` מקובץ הפרטים.

**AAPS**‏ (NSClient v3): הכתובת `https://<subdomain>.duckdns.org`, והאסימון הוא אסימון `aaps`.

רק אפליקציה אחת מעלה ערכי סוכר. שתי תוכנות העלאה יוצרות כפילויות.

### SSH, אם צריך

לא צריך את זה בפריסה רגילה. שורת `SSH:` בקובץ `~/nightscout-credentials.txt` עובדת כמו שהיא בתוך Cloud Shell.

מ-Windows:

1. ב-Cloud Shell, **תפריט גלגל השיניים ← Download**, מזינים `.ssh/ns-key`, ושומרים אל `C:\Users\<you>\.ssh\ns-key`.
2. ב-PowerShell:

```powershell
$key = "$env:USERPROFILE\.ssh\ns-key"
icacls $key /inheritance:r /grant:r "$($env:USERNAME):(R)"
ssh -i $key ubuntu@<PUBLIC_IP>
```

`icacls` פותר את השגיאה "unprotected private key". OpenSSH כבר כלול ב-Windows 10 וב-Windows 11.

על המכונה:

```bash
sudo tail -n 100 /var/log/cloud-init-output.log
cd /opt/nightscout && sudo docker compose ps
sudo docker compose logs -f nightscout
sudo docker compose pull && sudo docker compose up -d
```

### פקודות

| פקודה | מה היא עושה |
|---|---|
| `bash deploy.sh` | פריסה, או המשך של פריסה חלקית |
| `bash deploy.sh render` | כותב את סקריפט האתחול של המכונה אל `~/nightscout-oci/user-data.sh` לבדיקה. בלי שינוי בענן |
| `bash deploy.sh destroy` | מוחק את המכונה (**כל הנתונים**), את הרשת ואת התקציב. צריך להקליד `destroy` |

אפשר לדרוס הגדרות במשתני סביבה, למשל `IMAGE_FLAVOR=standard MAX_ATTEMPTS=300 bash deploy.sh`.

| משתנה | ברירת מחדל | משמעות |
|---|---|---|
| `IMAGE_FLAVOR` | `minimal` | `minimal` הוא Ubuntu 24.04 Minimal.‏ `standard` הוא דמות Ubuntu המלאה |
| `OCPUS` / `MEMORY_GB` | `1` / `2` | גודל המכונה. מגבלת Ampere החינמית היא 2 OCPU ו-12 GB בסך הכל |
| `MAX_ATTEMPTS` / `RETRY_SECONDS` | `120` / `60` | לולאת הניסיונות כשאין קיבולת |
| `NAME_PREFIX` | `ns` | קידומת לשמות המשאבים |

### מה הסקריפט יוצר

הכול נשאר בתוך מגבלות Always Free:

- VCN בשם `ns-vcn`, שער אינטרנט, תת-רשת ציבורית, ופורטים **22, 80 ו-443**
- מכונה `ns-vm`:‏ A1.Flex,‏ 1 OCPU,‏ 2 GB זיכרון, דיסק אתחול של 50 GB
- על המכונה, ב-`/opt/nightscout`:‏ MongoDB 6 (לא חשוף לאינטרנט), קונטיינר Nightscout אחד, Caddy, ומעדכן DuckDNS
- תקציב `ns-guard`:‏ $1 לחודש, אימייל על כל הוצאה
- מדיניות גיבוי אופציונלית `ns-weekly`: גיבוי מצטבר שבועי, נשמר לשלושה שבועות

### מגבלות

- **קונטיינר Nightscout אחד.** לא מגדילים את מספר העותקים. Nightscout שומר מצב בזיכרון, ועותקים נוספים מכפילים אזעקות.
- ל-Always Free **אין SLA**. משאירים את מדיניות הגיבוי פעילה.
- אם לא מתפרסמת דמות arm64 של Nightscout, המכונה בונה אותה מקוד המקור. האתחול הראשון אז ארוך בכמה דקות.
- `DBSIZE_MAX=30000`‏ (MiB) רק מפעיל את אזהרת גודל מסד הנתונים על המסך. הוא לא מגביל אחסון.
