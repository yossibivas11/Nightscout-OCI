# Nightscout on Oracle Cloud

Install [Nightscout](https://nightscout.github.io/) on a free Ubuntu virtual machine in Oracle Cloud Infrastructure. One script installs Docker, starts Nightscout with a local database, and puts Caddy in front of it.

Nightscout shows continuous glucose monitor (CGM) data. It is **not an approved medical device**. Treatment decisions stay with the person and their clinician. This repository only installs the software.

The same instructions are in Hebrew below. אותן הוראות בעברית בהמשך העמוד.

---

## English

### What you need

- An [Oracle Cloud](https://www.oracle.com/cloud/free/) account. The Always Free tier is enough. Oracle asks for a card during signup; a machine on the shapes below stays inside the free allowance.
- A computer that can open a terminal (Windows, Mac, or Linux).
- About 30 minutes the first time.

### 1. Create the virtual machine

In the Oracle Cloud console, create a **Compute instance**:

| Setting | Value |
|---|---|
| Image | Ubuntu 24.04 or 22.04 |
| Shape | `VM.Standard.A1.Flex` with **1 OCPU** and **6 GB RAM** |
| Networking | Assign a public IPv4 address |
| SSH key | Upload a key, or let Oracle generate one and download it |

If Oracle says the Ampere shape is out of capacity, choose `VM.Standard.E2.1.Micro` instead (1 GB RAM, also Always Free). The script adds swap on that size. It is slower, and it is still enough for one Nightscout site.

Copy the **public IP** address from the instance page.

### 2. Open ports 80 and 443

Oracle blocks incoming web traffic until you allow it. SSH (port 22) is already open.

1. Open the instance, then its subnet, then the **security list** (often "Default Security List").
2. Add two **ingress** rules:

| Source | Protocol | Destination port |
|---|---|---|
| `0.0.0.0/0` | TCP | 80 |
| `0.0.0.0/0` | TCP | 443 |

The script also opens those ports in the VM's own firewall. Both places are required.

### 3. Optional: a domain name

Without a domain, the site is `http://YOUR_IP`. That is unencrypted. Anyone on the path between a phone and the VM could read the traffic.

For HTTPS, create a DNS **A record** that points your hostname (for example `ns.example.com`) at the public IP **before** you run the installer. Have an email address ready; Let's Encrypt uses it for the certificate.

### 4. Install

From your computer, connect (use the key file Oracle gave you):

```bash
ssh -i /path/to/your-key ubuntu@YOUR_PUBLIC_IP
```

On the VM:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./install.sh
```

The script asks for:

- **Prompt language** — `en` or `he`.
- **API secret** — at least 12 characters. This is the password AndroidAPS, xDrip, or another uploader will use. It is saved only in `/opt/nightscout/.env` on the VM. It is not stored in git.
- **Glucose units** — `mmol` (default, used in Israel) or `mg/dl`.
- **Timezone** — default `Asia/Jerusalem`. Any [IANA name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) works, for example `Europe/London`.
- **Site language** — `en` or `he`.
- **Domain** — your hostname, or leave empty for HTTP on the IP address.
- **Email** — only if you set a domain.
- **Public viewing** — `no` (default) means each visitor needs the API secret. `yes` means anyone with the link can see the chart.

When it finishes, open the URL it prints. The first start can take a few minutes while Docker downloads the images.

To run it again without questions, set the variables and call the script:

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mmol' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='ns.example.com' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./install.sh
```

`AUTH_DEFAULT_ROLES` is `denied` or `readable`.

### 5. Connect an uploader

In AndroidAPS, xDrip+, or another uploader, set the Nightscout URL to the address you opened and set the API secret to the value you chose. Uploading data is documented by each app; this installer does not change the phone.

### Update

On the VM:

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```

### Backup

The glucose history is in `/opt/nightscout/mongo-data`. Copy that directory off the VM from time to time. Stop the stack first so the copy is consistent:

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

Keep a copy of `/opt/nightscout/.env` with the backup. Without the API secret you can still read a restored database, but every uploader must be told the new secret if you change it.

### What the script changes

- Installs Docker, the Compose plugin, and `iptables-persistent`.
- Adds a 2 GB swap file when the VM has under 1.5 GB of RAM.
- Allows TCP 80 and 443 through the VM firewall.
- Writes `/opt/nightscout` (compose file, Caddyfile, `.env`) and starts three containers: MongoDB, Nightscout, and Caddy.

It does not create the Oracle account, the VM, or the security-list rules.

### If the site does not open

1. Confirm the security list allows TCP 80 and 443 from `0.0.0.0/0`, then run `sudo ./install.sh` again.
2. Read the log: `cd /opt/nightscout && sudo docker compose logs -f`
3. If you set a domain and the certificate failed, check that the DNS A record points at this VM and that ports 80 and 443 are reachable from the internet. Caddy retries after you fix DNS: `cd /opt/nightscout && sudo docker compose restart caddy`
4. On a 1 GB Micro shape, give it a few minutes after the first start.

Running `sudo ./install.sh` again replaces `/opt/nightscout/.env`. Have the API secret ready.

---

## עברית

### מה צריך

- חשבון [Oracle Cloud](https://www.oracle.com/cloud/free/). המסלול Always Free מספיק. בהרשמה אורקל מבקשת כרטיס אשראי; מכונה בגדלים שלמטה נשארת בתוך המכסה החינמית.
- מחשב עם מסוף (חלונות, מק או לינוקס).
- בערך חצי שעה בפעם הראשונה.

### 1. יצירת המכונה

בקונסול של Oracle Cloud יוצרים **Compute instance**:

| הגדרה | ערך |
|---|---|
| Image | Ubuntu 24.04 או 22.04 |
| Shape | `VM.Standard.A1.Flex` עם **1 OCPU** ו-**6 GB RAM** |
| רשת | כתובת IPv4 ציבורית |
| מפתח SSH | מעלים מפתח, או נותנים לאורקל ליצור אחד ומורידים אותו |

אם אורקל מדווחת שאין קיבולת ל-Ampere, בוחרים במקום זאת `VM.Standard.E2.1.Micro` (1 GB זיכרון, גם הוא Always Free). הסקריפט מוסיף swap בגודל הזה. זה איטי יותר, ועדיין מספיק לאתר Nightscout אחד.

מעתיקים את **כתובת ה-IP הציבורית** מעמוד המכונה.

### 2. פתיחת פורטים 80 ו-443

אורקל חוסמת תעבורת רשת נכנסת עד שמתירים אותה. SSH (פורט 22) כבר פתוח.

1. נכנסים למכונה, משם לתת-הרשת (subnet), ומשם ל-**security list** (לרוב "Default Security List").
2. מוסיפים שני כללי **ingress**:

| מקור | פרוטוקול | פורט יעד |
|---|---|---|
| `0.0.0.0/0` | TCP | 80 |
| `0.0.0.0/0` | TCP | 443 |

הסקריפט פותח את הפורטים האלה גם בחומת האש של המכונה עצמה. צריך את שני המקומות.

### 3. שם מתחם (לא חובה)

בלי שם מתחם האתר הוא `http://YOUR_IP`. זו כתובת בלי הצפנה. מי שנמצא על הדרך בין הטלפון למכונה יכול לקרוא את התעבורה.

כדי לקבל HTTPS יוצרים רשומת DNS מסוג **A** שמפנה את השם (למשל `ns.example.com`) אל כתובת ה-IP הציבורית **לפני** שמריצים את ההתקנה. צריך גם כתובת אימייל; Let's Encrypt משתמשת בה לתעודה.

### 4. התקנה

מהמחשב שלכם מתחברים (עם קובץ המפתח שאורקל נתנה):

```bash
ssh -i /path/to/your-key ubuntu@YOUR_PUBLIC_IP
```

על המכונה:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./install.sh
```

הסקריפט שואל:

- **שפת השאלות** — `en` או `he`.
- **סוד API** — לפחות 12 תווים. זו הסיסמה ש-AndroidAPS, ‏xDrip או מעלה אחר ישתמש בה. היא נשמרת רק בקובץ `/opt/nightscout/.env` על המכונה. היא לא נשמרת ב-git.
- **יחידות סוכר** — `mmol` (ברירת המחדל, בשימוש בישראל) או `mg/dl`.
- **אזור זמן** — ברירת המחדל `Asia/Jerusalem`. כל שם [IANA](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) עובד, למשל `Europe/London`.
- **שפת האתר** — `en` או `he`.
- **שם מתחם** — השם שלכם, או ריק כדי לעבוד ב-HTTP על כתובת ה-IP.
- **אימייל** — רק אם הגדרתם שם מתחם.
- **צפייה ציבורית** — `no` (ברירת המחדל) אומר שכל מבקר צריך את סוד ה-API. `yes` אומר שכל מי שיש לו את הקישור רואה את הגרף.

בסיום פותחים את הכתובת שהסקריפט מדפיס. העלייה הראשונה יכולה לקחת כמה דקות בזמן ש-Docker מוריד את התוכנה.

כדי להריץ שוב בלי שאלות מגדירים משתנים וקוראים לסקריפט:

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mmol' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='ns.example.com' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./install.sh
```

`AUTH_DEFAULT_ROLES` הוא `denied` או `readable`.

### 5. חיבור מעלה נתונים

ב-AndroidAPS, ב-xDrip+ או במעלה אחר מגדירים את כתובת Nightscout לכתובת שפתחתם, ואת סוד ה-API לערך שבחרתם. כל אפליקציה מתעדת בעצמה איך מעלים נתונים; ההתקנה הזו לא משנה את הטלפון.

### עדכון

על המכונה:

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```

### גיבוי

היסטוריית הסוכר נמצאת ב-`/opt/nightscout/mongo-data`. כדאי להעתיק את התיקייה הזו אל מחוץ למכונה מדי פעם. עוצרים את השירות קודם כדי שהעותק יהיה עקבי:

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

שומרים עותק של `/opt/nightscout/.env` יחד עם הגיבוי. בלי סוד ה-API עדיין אפשר לקרוא מסד נתונים ששוחזר, אבל אם משנים את הסוד צריך לעדכן כל מעלה נתונים.

### מה הסקריפט משנה

- מתקין את Docker, את תוסף Compose, ואת `iptables-persistent`.
- מוסיף קובץ swap של 2 GB כשלמכונה יש פחות מ-1.5 GB זיכרון.
- מתיר TCP 80 ו-443 בחומת האש של המכונה.
- כותב את `/opt/nightscout` (קובץ compose, ‏Caddyfile, ‏`.env`) ומפעיל שלושה קונטיינרים: MongoDB, ‏Nightscout ו-Caddy.

הוא לא יוצר את חשבון אורקל, לא את המכונה, ולא את כללי ה-security list.

### אם האתר לא נפתח

1. בודקים שה-security list מתיר TCP 80 ו-443 מ-`0.0.0.0/0`, ואז מריצים שוב `sudo ./install.sh`.
2. קוראים את היומן: `cd /opt/nightscout && sudo docker compose logs -f`
3. אם הגדרתם שם מתחם והתעודה נכשלה, בודקים שרשומת ה-A מצביעה למכונה הזו ושאפשר להגיע לפורטים 80 ו-443 מהאינטרנט. אחרי תיקון ה-DNS: `cd /opt/nightscout && sudo docker compose restart caddy`
4. על מכונת Micro של 1 GB נותנים לזה כמה דקות אחרי ההפעלה הראשונה.

הרצה חוזרת של `sudo ./install.sh` מחליפה את `/opt/nightscout/.env`. צריך שסוד ה-API יהיה בהישג יד.
