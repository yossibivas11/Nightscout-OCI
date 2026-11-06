# Nightscout on Oracle Cloud

`deploy.sh` installs Nightscout on an Ubuntu virtual machine in Oracle Cloud. You answer a few questions. The script installs Docker, opens the VM firewall, and starts Nightscout, MongoDB, and Caddy.

Nightscout shows continuous glucose monitor data. It is not an approved medical device, and it does not replace a meter, a pump, or clinical care. This repository only runs the installer.

[עברית](#עברית)

---

## Before you run the script

The script does not create the Oracle account or the virtual machine. Do this once:

1. Sign in at [cloud.oracle.com](https://cloud.oracle.com/) and create a **Compute instance**.
2. Image: **Ubuntu 24.04 or 22.04**. Shape: `VM.Standard.A1.Flex` with **1 OCPU** and **6 GB** of memory. If Oracle reports that Ampere is out of capacity, use `VM.Standard.E2.1.Micro` instead. The script adds swap on that smaller machine.
3. Assign a **public IPv4 address** and add an SSH key. Copy the public IP from the instance page.
4. Open the instance subnet’s **security list** and add two ingress rules, source `0.0.0.0/0`, TCP, ports **80** and **443**. Port 22 is already open.
5. For HTTPS, create a DNS **A record** from your hostname to that public IP before you run the script. Have an email address ready for the certificate. You can skip this and use `http://` plus the public IP.

## Run it

From your computer:

```bash
ssh -i /path/to/your-key ubuntu@YOUR_PUBLIC_IP
```

On the VM:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./deploy.sh
```

`sudo ./deploy.sh --help` prints the variables below and does not install anything.

## What it asks

| Question | What to enter |
|---|---|
| Prompt language | `en` or `he` |
| API secret | At least 12 characters, typed twice. No quotes, `#`, or `$`. This is the password for AndroidAPS, xDrip, or another uploader. It is saved only in `/opt/nightscout/.env`. |
| Glucose units | `mmol` (default) or `mg/dl` |
| Timezone | Default `Asia/Jerusalem`. Any [IANA name](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) works. |
| Nightscout language | `en` or `he` |
| Domain | Your hostname, or leave empty for HTTP on the public IP |
| Email | Only when you set a domain. Let’s Encrypt uses it for the certificate. |
| Anyone with the link can view | `no` (default) asks each visitor for the API secret. `yes` or `כן` lets anyone with the URL see the chart. |

When it finishes, it prints the URL. The first start waits while Docker downloads the images. In the uploader, set that URL and the same API secret.

## Run it without questions

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mmol' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='ns.example.com' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./deploy.sh
```

`API_SECRET` is required in this form. The others are optional.

| Variable | Default | Values |
|---|---|---|
| `API_SECRET` | none | at least 12 characters |
| `DISPLAY_UNITS` | `mmol` | `mmol` or `mg/dl` |
| `TZ` | `Asia/Jerusalem` | IANA timezone |
| `NS_LANGUAGE` | `en` | `en` or `he`, the language of the script’s messages |
| `SITE_LANGUAGE` | same as `NS_LANGUAGE` | `en` or `he`, the Nightscout site |
| `NS_DOMAIN` | empty | hostname for HTTPS |
| `ACME_EMAIL` | empty | required when `NS_DOMAIN` is set |
| `AUTH_DEFAULT_ROLES` | `denied` | `denied` or `readable` |

Running `sudo ./deploy.sh` again replaces `/opt/nightscout/.env`. Keep the API secret.

## Afterward

Logs:

```bash
cd /opt/nightscout && sudo docker compose logs -f
```

Update the containers (the glucose data stays in `mongo-data`):

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```

Backup. Stop the stack so the copy is consistent, then copy both files off the VM:

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

Keep a copy of `/opt/nightscout/.env` with that archive.

## If the site does not open

1. The security list must allow TCP 80 and 443 from `0.0.0.0/0`. Then run `sudo ./deploy.sh` again.
2. Read the log: `cd /opt/nightscout && sudo docker compose logs -f`
3. If the certificate failed, the DNS A record must point at this VM and ports 80 and 443 must be reachable. Then: `cd /opt/nightscout && sudo docker compose restart caddy`
4. On the 1 GB Micro shape, wait a few minutes after the first start.

---

# עברית

`deploy.sh` מתקין את Nightscout על מכונת אובונטו ב-Oracle Cloud. עונים על כמה שאלות. הסקריפט מתקין את Docker, פותח את חומת האש של המכונה, ומפעיל את Nightscout, את MongoDB ואת Caddy.

Nightscout מציג נתוני חיישן סוכר. הוא אינו מכשיר רפואי מאושר, והוא אינו מחליף מד סוכר, משאבה או טיפול רפואי. המאגר הזה רק מריץ את ההתקנה.

[English](#nightscout-on-oracle-cloud)

## לפני שמריצים את הסקריפט

הסקריפט לא יוצר את חשבון Oracle ולא את המכונה. עושים את זה פעם אחת:

1. נכנסים ל-[cloud.oracle.com](https://cloud.oracle.com/) ויוצרים **Compute instance**.
2. Image: **Ubuntu 24.04 או 22.04**. Shape: `VM.Standard.A1.Flex` עם **1 OCPU** ו-**6 GB** זיכרון. אם Oracle מדווחת שאין קיבולת ל-Ampere, משתמשים ב-`VM.Standard.E2.1.Micro`. הסקריפט מוסיף swap על המכונה הקטנה הזו.
3. מגדירים **כתובת IPv4 ציבורית** ומוסיפים מפתח SSH. מעתיקים את כתובת ה-IP הציבורית מעמוד המכונה.
4. פותחים את ה-**security list** של תת-הרשת ומוסיפים שני כללי ingress, מקור `0.0.0.0/0`, TCP, פורטים **80** ו-**443**. פורט 22 כבר פתוח.
5. כדי לקבל HTTPS יוצרים רשומת DNS מסוג **A** מהשם שלכם אל כתובת ה-IP הציבורית לפני שמריצים את הסקריפט. צריך כתובת אימייל לתעודה. אפשר לדלג ולהשתמש ב-`http://` יחד עם כתובת ה-IP הציבורית.

## הרצה

מהמחשב שלכם:

```bash
ssh -i /path/to/your-key ubuntu@YOUR_PUBLIC_IP
```

על המכונה:

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./deploy.sh
```

`sudo ./deploy.sh --help` מדפיס את המשתנים שלמטה ולא מתקין כלום.

## על מה הוא שואל

| שאלה | מה מזינים |
|---|---|
| שפת השאלות | `en` או `he` |
| סוד API | לפחות 12 תווים, פעמיים. בלי גרשיים, בלי `#` ובלי `$`. זו הסיסמה של AndroidAPS, xDrip או תוכנת העלאה אחרת. היא נשמרת רק ב-`/opt/nightscout/.env`. |
| יחידות סוכר | `mmol` (ברירת מחדל) או `mg/dl` |
| אזור זמן | ברירת המחדל `Asia/Jerusalem`. כל [שם IANA](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones) מתאים. |
| שפת האתר | `en` או `he` |
| שם מתחם | השם שלכם, או ריק כדי להשתמש ב-HTTP על כתובת ה-IP הציבורית |
| אימייל | רק כשמגדירים שם מתחם. Let’s Encrypt משתמשת בו לתעודה. |
| כל מי שיש לו את הקישור יכול לצפות | `no` (ברירת מחדל) מבקש מכל מבקר את סוד ה-API. `yes` או `כן` מאפשר לכל מי שיש לו את הכתובת לראות את הגרף. |

בסיום הוא מדפיס את הכתובת. ההפעלה הראשונה ממתינה בזמן ש-Docker מוריד את הדמויות. בתוכנת ההעלאה מגדירים את הכתובת הזו ואת אותו סוד API.

## הרצה בלי שאלות

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mmol' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='ns.example.com' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./deploy.sh
```

בצורה הזו `API_SECRET` חובה. השאר רשות.

| משתנה | ברירת מחדל | ערכים |
|---|---|---|
| `API_SECRET` | אין | לפחות 12 תווים |
| `DISPLAY_UNITS` | `mmol` | `mmol` או `mg/dl` |
| `TZ` | `Asia/Jerusalem` | אזור זמן IANA |
| `NS_LANGUAGE` | `en` | `en` או `he`, שפת ההודעות של הסקריפט |
| `SITE_LANGUAGE` | כמו `NS_LANGUAGE` | `en` או `he`, שפת אתר Nightscout |
| `NS_DOMAIN` | ריק | שם מתחם ל-HTTPS |
| `ACME_EMAIL` | ריק | חובה כש-`NS_DOMAIN` מוגדר |
| `AUTH_DEFAULT_ROLES` | `denied` | `denied` או `readable` |

הרצה נוספת של `sudo ./deploy.sh` מחליפה את `/opt/nightscout/.env`. שומרים את סוד ה-API.

## אחר כך

יומן:

```bash
cd /opt/nightscout && sudo docker compose logs -f
```

עדכון הקונטיינרים (נתוני הסוכר נשארים ב-`mongo-data`):

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```

גיבוי. עוצרים את השירותים כדי שהעותק יהיה עקבי, ואז מעתיקים את שני הקבצים אל מחוץ למכונה:

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

שומרים עותק של `/opt/nightscout/.env` יחד עם הארכיון.

## אם האתר לא נפתח

1. ה-security list חייב לאפשר TCP 80 ו-443 מ-`0.0.0.0/0`. אחר כך מריצים שוב `sudo ./deploy.sh`.
2. קוראים את היומן: `cd /opt/nightscout && sudo docker compose logs -f`
3. אם התעודה נכשלה, רשומת ה-A ב-DNS צריכה להצביע למכונה הזו, ופורטים 80 ו-443 צריכים להיות נגישים. אחר כך: `cd /opt/nightscout && sudo docker compose restart caddy`
4. על מכונת Micro של 1 GB ממתינים כמה דקות אחרי ההפעלה הראשונה.
