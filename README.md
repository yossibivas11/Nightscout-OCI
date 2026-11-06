# Nightscout on Oracle Cloud

Deploy [Nightscout](https://nightscout.github.io/) (cgm-remote-monitor) on an [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) Always Free virtual machine, using Nightscout’s official Docker Compose file.

Nightscout is a do-it-yourself project for showing continuous glucose monitor data in a browser. It is not an approved medical device, and it does not replace a meter, a pump, or clinical care. You run it on your own Oracle Cloud account. Read the project documentation before you rely on a site: <https://nightscout.github.io/>.

[עברית](#עברית)

---

## What you need

- An Oracle Cloud account. Sign-up asks for a payment card so Oracle can verify identity. Resources that stay inside the [Always Free limits](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) are not billed. Anything past those limits can be billed, including after an upgrade to a paid account.
- A computer with a terminal: Windows PowerShell, macOS Terminal, or Linux.
- A DNS name you control, for example `nightscout.example.com`. The Compose file gets an HTTPS certificate from Let’s Encrypt, and that only works with a real hostname pointed at the server.
- About an hour the first time. The virtual machine itself is usually ready in a few minutes. Certificate and container download time depends on your network.

Choose the account’s **home region** during sign-up. Always Free compute has to live in that region, and the home region cannot be changed later. A region near you, such as Israel Central (Jerusalem) or Germany Central (Frankfurt), is a reasonable start.

## 1. Create the virtual machine

1. Sign in to the [Oracle Cloud Console](https://cloud.oracle.com/).
2. Open the navigation menu, go to **Compute**, then **Instances**, then **Create instance**.
3. Name the instance, for example `nightscout`.
4. Under **Image**, choose **Ubuntu** and keep an image marked **Always Free Eligible**. Ubuntu 24.04 LTS or 22.04 LTS is fine. Docker’s Ubuntu packages support both.
5. Under **Shape**, choose **Change shape** → **Ampere** → **VM.Standard.A1.Flex**. Set **2 OCPUs** and **12 GB** of memory. That is the whole Always Free Ampere allowance (1,500 OCPU hours and 9,000 GB hours per month, which for an Always Free tenancy is 2 OCPUs and 12 GB). One instance of this size runs Nightscout and MongoDB comfortably.
6. The AMD shape `VM.Standard.E2.1.Micro` is also Always Free, but it has 1 GB of memory. That is too small for Nightscout plus MongoDB. If Ampere creation fails with **out of host capacity**, try another availability domain, wait, and try again. Oracle documents this as a temporary shortage of free hosts in the home region.
7. Under networking, assign a **public IPv4 address**.
8. Add an SSH key. Either let Oracle generate a key pair and download the private key, or upload the public half of a key you already have. Keep the private key. Anyone with it can log in to the server.
9. Leave the boot volume at the default size (about 50 GB). It counts toward the 200 GB of Always Free block storage.
10. Create the instance and wait until the state is **Running**. Copy the **Public IP address**.

Oracle may reclaim an Always Free compute instance it decides is idle. The published rule is a 7-day period where the 95th percentile of CPU use is under 20 percent, network use is under 20 percent, and (for Ampere) memory use is under 20 percent. Details: [Always Free Resources](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## 2. Open ports 80 and 443 in two places

A browser request has to pass Oracle’s network firewall and the firewall inside Ubuntu. SSH (port 22) is already allowed. HTTP (80) and HTTPS (443) are not. Let’s Encrypt also needs port 80.

### Oracle security list

1. On the instance page, open the **subnet**, then the **security list**.
2. **Add Ingress Rules** twice:

| Source CIDR | Protocol | Destination port |
|---|---|---|
| `0.0.0.0/0` | TCP | 80 |
| `0.0.0.0/0` | TCP | 443 |

Leave the rules stateful. You can later restrict SSH (port 22) to your own IP address. Leave 80 and 443 open to the internet, or visitors and Let’s Encrypt cannot reach the site.

### Ubuntu iptables

Connect from your computer. Replace the key path and the IP.

```bash
ssh -i /path/to/your-private-key ubuntu@YOUR_PUBLIC_IP
```

On Windows, OpenSSH refuses a private key that other users can read. In PowerShell, from the folder that contains the key:

```powershell
icacls .\your-private-key.key /inheritance:r /grant:r "${env:USERNAME}:(R)"
ssh -i .\your-private-key.key ubuntu@YOUR_PUBLIC_IP
```

The Ubuntu image allows SSH and then rejects other new connections. Add HTTP and HTTPS **above** that reject rule, then save the rules so a reboot keeps them:

```bash
sudo iptables -L INPUT -n --line-numbers
sudo iptables -I INPUT 1 -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save
sudo iptables -L INPUT -n --line-numbers
```

In the last listing, the `ACCEPT` lines for ports 80 and 443 must appear above the `REJECT` line.

## 3. Install Docker

These are the current Docker Engine steps for Ubuntu, from [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/). Run them on the server.

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run --rm hello-world
```

`hello-world` should print a short success message and exit. The `docker` service starts on boot.

## 4. Download Nightscout’s Compose file

```bash
mkdir -p ~/nightscout
cd ~/nightscout
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/nightscout/cgm-remote-monitor/master/docker-compose.yml
```

That file is maintained by the Nightscout project. It starts three containers:

- **MongoDB** (`mongo:5.0.32`) for the glucose data, stored in `~/nightscout/mongo-data`
- **Nightscout** (`nightscout/cgm-remote-monitor:latest`)
- **Traefik**, which serves HTTPS and requests the Let’s Encrypt certificate

Both the MongoDB and Nightscout images publish an `arm64` build, so this file runs on the Ampere VM as well as on AMD.

## 5. Edit the settings

```bash
nano ~/nightscout/docker-compose.yml
```

Change these values. Leave the rest of the file as it is.

**Password.** Replace `change_me`:

```yaml
API_SECRET: your_own_secret_here
```

Use at least 12 letters and digits, with no spaces or special characters. It is case-sensitive. This password is full access to the site: viewing, uploading, and administration. Do not send it in email or chat, and do not commit the edited Compose file to Git.

**Clock and units.** Replace `TZ: Etc/UTC` with your time zone, and add the three lines under it. `mmol` is the usual choice in Israel. Use `mg/dl` only when the uploader and the pump profile are also in mg/dL. Nightscout warns that mixing those units throws off bolus estimates by a factor of about 18.

```yaml
TZ: Asia/Jerusalem
DISPLAY_UNITS: mmol
LANGUAGE: he
TIME_FORMAT: 24
TRUST_PROXY: "1"
```

`TRUST_PROXY: "1"` tells Nightscout that one reverse proxy (Traefik) sits in front of it. That is the value Nightscout documents for this Compose file. It makes the failed-login delay use the visitor’s address.

**Who can open the page.** The file sets `AUTH_DEFAULT_ROLES: denied`, so a visitor needs a token. Leave it that way unless you have decided that anyone who knows the address may see glucose data. `readable` makes the page public. Tokens and roles are documented at <https://nightscout.github.io/nightscout/setup_variables/>.

**Hostname and certificate email.** In the Traefik labels, replace `localhost` with your DNS name, and keep the backticks:

```yaml
- 'traefik.http.routers.nightscout.rule=Host(`nightscout.example.com`)'
```

In the Traefik command, set a real mailbox for Let’s Encrypt expiry notices:

```yaml
- '--certificatesresolvers.le.acme.email=you@example.com'
```

Save the file in nano with `Ctrl+O`, then `Enter`, then leave with `Ctrl+X`.

## 6. Point the DNS name at the server

At your DNS host, create an **A record**:

```text
nightscout.example.com    A    YOUR_PUBLIC_IP
```

Wait until a lookup from your computer shows that IP. On Linux or macOS: `dig +short nightscout.example.com`. On Windows: `nslookup nightscout.example.com`. Start the containers only after this answers with the instance IP. Let’s Encrypt will fail if it cannot reach the name on port 80.

## 7. Start Nightscout

```bash
cd ~/nightscout
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail 80
```

When the three services are running, open `https://nightscout.example.com`. The first certificate request can take a couple of minutes. With `AUTH_DEFAULT_ROLES: denied`, Nightscout asks for authentication before it shows data. Your uploader (xDrip+, AndroidAPS, Loop, or another) needs the same site URL and the same API secret.

### If the certificate failed

Fix the DNS record and confirm ports 80 and 443 are open, then throw away only the certificate folder and try again. This does not delete glucose data.

```bash
cd ~/nightscout
sudo docker compose down
sudo rm -rf letsencrypt
sudo docker compose up -d
```

Do not delete `mongo-data`.

## 8. Back up the database

The database lives in `~/nightscout/mongo-data` on the VM. Copy a dump off the server as well. A disk that exists only inside Oracle is not a backup.

```bash
cd ~/nightscout
sudo docker compose exec -T mongo mongodump --archive --db=nightscout > ~/nightscout-backup.archive
```

Download `nightscout-backup.archive` to your computer, for example with `scp`, and keep a copy somewhere else. Repeat this on a schedule you will actually follow.

To restore onto a new server that already has the containers running:

```bash
cd ~/nightscout
sudo docker compose exec -T mongo mongorestore --archive --drop < ~/nightscout-backup.archive
```

`--drop` replaces the `nightscout` database with the contents of the archive.

## 9. Update

```bash
cd ~/nightscout
sudo docker compose pull
sudo docker compose up -d
```

This replaces the containers and keeps `mongo-data`. Take a backup first. From time to time, also refresh the operating system:

```bash
sudo apt update && sudo apt upgrade -y
```

Reboot if Ubuntu says a restart is required (`sudo reboot`), then SSH in again and check `sudo docker compose ps`.

## When something does not work

| What you see | What to check |
|---|---|
| SSH does not connect | Instance is Running, you are using `ubuntu` and the private key that matches the instance, and your IP is allowed to port 22 |
| Browser times out | Security list has TCP 80 and 443, and `iptables` shows those ACCEPT lines above REJECT |
| Browser warns about the certificate | DNS A record matches the public IP, the `Host(...)` line matches that name, port 80 was open on the first start. Then follow the certificate reset in step 7 |
| Page loads, uploader is rejected | The uploader URL is `https://` plus the same hostname, and the API secret matches exactly, including capital letters |
| Containers exit | `sudo docker compose logs --tail 200` in `~/nightscout` |

Nightscout configuration variables: <https://nightscout.github.io/nightscout/setup_variables/>.

---

# עברית

הקמה של [Nightscout](https://nightscout.github.io/) על מכונה וירטואלית ב־[Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) במסגרת Always Free, בעזרת קובץ ה־Docker Compose הרשמי של Nightscout.

Nightscout הוא פרויקט עצמאי להצגת נתוני חיישן סוכר בדפדפן. הוא אינו מכשיר רפואי מאושר, והוא אינו מחליף מד סוכר, משאבה או טיפול רפואי. האתר רץ בחשבון Oracle Cloud שלכם. לפני שמסתמכים על האתר כדאי לקרוא את התיעוד של הפרויקט: <https://nightscout.github.io/>.

[English](#nightscout-on-oracle-cloud)

## מה צריך

- חשבון Oracle Cloud. בהרשמה מבקשים כרטיס אשראי כדי לאמת זהות. משאבים שנשארים בתוך [מגבלות Always Free](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) אינם מחויבים. כל מה שחורג מהמגבלות עלול להיות מחויב, גם אחרי שדרוג לחשבון בתשלום.
- מחשב עם מסוף: PowerShell ב־Windows, Terminal ב־macOS, או Linux.
- שם מתחם (DNS) שבשליטתכם, למשל `nightscout.example.com`. קובץ ה־Compose מנפיק אישור HTTPS מ־Let’s Encrypt, וזה עובד רק כששם אמיתי מפנה אל השרת.
- כשעה בפעם הראשונה. המכונה עצמה מוכנה בדרך כלל תוך כמה דקות. זמן האישור והורדת הקונטיינרים תלוי ברשת.

בזמן ההרשמה בוחרים את **אזור הבית** (home region). מחשוב Always Free חייב לרוץ באזור הזה, ואי אפשר להחליף אותו אחר כך. אזור קרוב, למשל ישראל (ירושלים) או גרמניה (פרנקפורט), הוא נקודת התחלה סבירה.

## 1. יצירת המכונה הווירטואלית

1. נכנסים ל־[Oracle Cloud Console](https://cloud.oracle.com/).
2. בתפריט הניווט: **Compute** ← **Instances** ← **Create instance**.
3. נותנים שם, למשל `nightscout`.
4. תחת **Image** בוחרים **Ubuntu** ומשאירים דמות שמסומנת **Always Free Eligible**. Ubuntu 24.04 LTS או 22.04 LTS מתאימים. חבילות Docker ל־Ubuntu תומכות בשתיהן.
5. תחת **Shape** בוחרים **Change shape** ← **Ampere** ← **VM.Standard.A1.Flex**. מגדירים **2 OCPUs** ו־**12 GB** זיכרון. זו כל מכסת Ampere החינמית (1,500 שעות OCPU ו־9,000 שעות GB בחודש, שבחשבון Always Free שוות ל־2 OCPUs ו־12 GB). מכונה אחת בגודל הזה מריצה את Nightscout ואת MongoDB בנוחות.
6. גם הצורה `VM.Standard.E2.1.Micro` של AMD היא Always Free, אבל יש לה 1 GB זיכרון. זה מעט מדי ל־Nightscout יחד עם MongoDB. אם יצירת Ampere נכשלת עם **out of host capacity**, מנסים availability domain אחר, מחכים, ומנסים שוב. Oracle מתעדת את זה כמחסור זמני במארחים חינמיים באזור הבית.
7. ברשת, מסמנים כתובת **public IPv4**.
8. מוסיפים מפתח SSH. אפשר לתת ל־Oracle ליצור זוג מפתחות ולהוריד את המפתח הפרטי, או להעלות מפתח ציבורי שכבר יש לכם. שומרים את המפתח הפרטי. מי שמחזיק בו יכול להיכנס לשרת.
9. משאירים את דיסק האתחול בגודל ברירת המחדל (כ־50 GB). הוא נספר בתוך 200 GB אחסון הבלוק החינמי.
10. יוצרים את המכונה ומחכים למצב **Running**. מעתיקים את **Public IP address**.

Oracle עשויה לקחת בחזרה מכונת Always Free שהיא מגדירה כלא פעילה. הכלל המפורסם: במשך 7 ימים, האחוזון ה־95 של השימוש במעבד מתחת ל־20 אחוז, השימוש ברשת מתחת ל־20 אחוז, ובמכונות Ampere גם השימוש בזיכרון מתחת ל־20 אחוז. הפירוט: [Always Free Resources](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm).

## 2. פתיחת פורטים 80 ו־443 בשני מקומות

בקשה מהדפדפן צריכה לעבור גם את חומת האש של רשת Oracle וגם את חומת האש שבתוך Ubuntu. SSH (פורט 22) כבר פתוח. HTTP (80) ו־HTTPS (443) לא. גם Let’s Encrypt צריך את פורט 80.

### רשימת האבטחה של Oracle

1. בעמוד המכונה פותחים את ה־**subnet** ואז את ה־**security list**.
2. **Add Ingress Rules** פעמיים:

| Source CIDR | פרוטוקול | פורט יעד |
|---|---|---|
| `0.0.0.0/0` | TCP | 80 |
| `0.0.0.0/0` | TCP | 443 |

משאירים את הכללים stateful. אפשר אחר כך להגביל את SSH (פורט 22) לכתובת ה־IP שלכם. את 80 ו־443 משאירים פתוחים לאינטרנט, אחרת מבקרים ו־Let’s Encrypt לא מגיעים לאתר.

### iptables בתוך Ubuntu

מתחברים מהמחשב שלכם. מחליפים את נתיב המפתח ואת כתובת ה־IP.

```bash
ssh -i /path/to/your-private-key ubuntu@YOUR_PUBLIC_IP
```

ב־Windows, OpenSSH מסרב למפתח פרטי שמשתמשים אחרים יכולים לקרוא. ב־PowerShell, מהתיקייה שבה נמצא המפתח:

```powershell
icacls .\your-private-key.key /inheritance:r /grant:r "${env:USERNAME}:(R)"
ssh -i .\your-private-key.key ubuntu@YOUR_PUBLIC_IP
```

דמות Ubuntu מאפשרת SSH ודוחה שאר חיבורים חדשים. מוסיפים HTTP ו־HTTPS **מעל** כלל הדחייה, ושומרים את הכללים כדי שיישארו אחרי אתחול:

```bash
sudo iptables -L INPUT -n --line-numbers
sudo iptables -I INPUT 1 -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT 1 -p tcp -m state --state NEW -m tcp --dport 80 -j ACCEPT
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
sudo netfilter-persistent save
sudo iptables -L INPUT -n --line-numbers
```

ברשימה האחרונה, שורות ה־`ACCEPT` של פורטים 80 ו־443 חייבות להופיע מעל שורת ה־`REJECT`.

## 3. התקנת Docker

אלה שלבי ההתקנה העדכניים של Docker Engine על Ubuntu, מתוך [Install Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/). מריצים אותם על השרת.

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo docker run --rm hello-world
```

`hello-world` אמור להדפיס הודעת הצלחה קצרה ולצאת. שירות `docker` עולה אוטומטית עם המכונה.

## 4. הורדת קובץ ה־Compose של Nightscout

```bash
mkdir -p ~/nightscout
cd ~/nightscout
curl -fsSL -o docker-compose.yml https://raw.githubusercontent.com/nightscout/cgm-remote-monitor/master/docker-compose.yml
```

הקובץ מתוחזק על ידי פרויקט Nightscout. הוא מפעיל שלושה קונטיינרים:

- **MongoDB** (`mongo:5.0.32`) לנתוני הסוכר, בתיקייה `~/nightscout/mongo-data`
- **Nightscout** (`nightscout/cgm-remote-monitor:latest`)
- **Traefik**, שמגיש HTTPS ומבקש את אישור Let’s Encrypt

גם ל־MongoDB וגם ל־Nightscout יש בניית `arm64`, ולכן הקובץ רץ על מכונת Ampere וגם על AMD.

## 5. עריכת ההגדרות

```bash
nano ~/nightscout/docker-compose.yml
```

משנים את הערכים האלה. את שאר הקובץ משאירים כמו שהוא.

**סיסמה.** מחליפים את `change_me`:

```yaml
API_SECRET: your_own_secret_here
```

לפחות 12 אותיות וספרות, בלי רווחים ובלי תווים מיוחדים. יש הבדל בין אותיות גדולות לקטנות. הסיסמה הזו היא גישה מלאה לאתר: צפייה, העלאה וניהול. לא שולחים אותה בדוא״ל או בצ׳אט, ולא שומרים את קובץ ה־Compose הערוך ב־Git.

**שעון ויחידות.** מחליפים את `TZ: Etc/UTC` באזור הזמן שלכם, ומוסיפים מתחתיו את שלוש השורות. `mmol` הוא הבחירה הרגילה בישראל. משתמשים ב־`mg/dl` רק כשגם התוכנה שמעלה את הנתונים וגם פרופיל המשאבה הם ב־mg/dL. Nightscout מזהיר שערבוב יחידות מסיט הערכות בולוס בערך פי 18.

```yaml
TZ: Asia/Jerusalem
DISPLAY_UNITS: mmol
LANGUAGE: he
TIME_FORMAT: 24
TRUST_PROXY: "1"
```

`TRUST_PROXY: "1"` אומר ל־Nightscout שפרוקסי אחד (Traefik) יושב לפניו. זה הערך ש־Nightscout מתעד לקובץ ה־Compose הזה. כך השהיית ההתחברות הכושלת משתמשת בכתובת של המבקר.

**מי יכול לפתוח את הדף.** הקובץ מגדיר `AUTH_DEFAULT_ROLES: denied`, כך שמבקר צריך אסימון (token). משאירים את זה כך, אלא אם החלטתם שכל מי שמכיר את הכתובת יכול לראות נתוני סוכר. `readable` הופך את הדף לציבורי. אסימונים ותפקידים מתועדים ב־<https://nightscout.github.io/nightscout/setup_variables/>.

**שם המתחם ודוא״ל לאישור.** בתוויות של Traefik מחליפים את `localhost` בשם ה־DNS שלכם, ומשאירים את הסימנים `` ` ``:

```yaml
- 'traefik.http.routers.nightscout.rule=Host(`nightscout.example.com`)'
```

בפקודות של Traefik מגדירים תיבת דוא״ל אמיתית להודעות תפוגה של Let’s Encrypt:

```yaml
- '--certificatesresolvers.le.acme.email=you@example.com'
```

שומרים ב־nano עם `Ctrl+O`, אחר כך `Enter`, ויוצאים עם `Ctrl+X`.

## 6. הפניית שם המתחם אל השרת

אצל ספק ה־DNS יוצרים רשומת **A**:

```text
nightscout.example.com    A    YOUR_PUBLIC_IP
```

ממתינים עד שבדיקה מהמחשב שלכם מציגה את הכתובת הזו. ב־Linux או macOS: `dig +short nightscout.example.com`. ב־Windows: `nslookup nightscout.example.com`. מפעילים את הקונטיינרים רק אחרי שהתשובה היא כתובת ה־IP של המכונה. Let’s Encrypt ייכשל אם הוא לא מגיע אל השם בפורט 80.

## 7. הפעלת Nightscout

```bash
cd ~/nightscout
sudo docker compose up -d
sudo docker compose ps
sudo docker compose logs --tail 80
```

כששלושת השירותים רצים, פותחים את `https://nightscout.example.com`. בקשת האישור הראשונה יכולה לקחת כמה דקות. עם `AUTH_DEFAULT_ROLES: denied`, Nightscout מבקש אימות לפני שהוא מציג נתונים. התוכנה שמעלה נתונים (xDrip+, AndroidAPS, Loop או אחרת) צריכה את אותה כתובת אתר ואת אותה סיסמת API.

### אם האישור נכשל

מתקנים את רשומת ה־DNS ומוודאים שפורטים 80 ו־443 פתוחים, ואז מוחקים רק את תיקיית האישורים ומנסים שוב. זה לא מוחק נתוני סוכר.

```bash
cd ~/nightscout
sudo docker compose down
sudo rm -rf letsencrypt
sudo docker compose up -d
```

לא מוחקים את `mongo-data`.

## 8. גיבוי מסד הנתונים

מסד הנתונים נמצא ב־`~/nightscout/mongo-data` על המכונה. מעתיקים גם גיבוי אל מחוץ לשרת. דיסק שקיים רק בתוך Oracle אינו גיבוי.

```bash
cd ~/nightscout
sudo docker compose exec -T mongo mongodump --archive --db=nightscout > ~/nightscout-backup.archive
```

מורידים את `nightscout-backup.archive` למחשב, למשל עם `scp`, ושומרים עותק במקום נוסף. חוזרים על זה בקצב שתעמדו בו.

כדי לשחזר על שרת חדש שהקונטיינרים בו כבר רצים:

```bash
cd ~/nightscout
sudo docker compose exec -T mongo mongorestore --archive --drop < ~/nightscout-backup.archive
```

`--drop` מחליף את מסד הנתונים `nightscout` בתוכן של קובץ הגיבוי.

## 9. עדכון

```bash
cd ~/nightscout
sudo docker compose pull
sudo docker compose up -d
```

זה מחליף את הקונטיינרים ושומר את `mongo-data`. קודם לוקחים גיבוי. מדי פעם מרעננים גם את מערכת ההפעלה:

```bash
sudo apt update && sudo apt upgrade -y
```

אם Ubuntu מודיע שצריך אתחול, מריצים `sudo reboot`, מתחברים שוב ב־SSH, ובודקים `sudo docker compose ps`.

## כשמשהו לא עובד

| מה רואים | מה בודקים |
|---|---|
| SSH לא מתחבר | המכונה במצב Running, המשתמש הוא `ubuntu`, המפתח הפרטי תואם למכונה, וה־IP שלכם מורשה לפורט 22 |
| הדפדפן נתקע בלי תשובה | ב־security list יש TCP 80 ו־443, וב־`iptables` שורות ה־ACCEPT שלהם נמצאות מעל REJECT |
| הדפדפן מזהיר לגבי האישור | רשומת A מתאימה לכתובת הציבורית, שורת `Host(...)` מתאימה לאותו שם, ופורט 80 היה פתוח בהפעלה הראשונה. אחר כך מבצעים את איפוס האישור בשלב 7 |
| הדף נטען אבל ההעלאה נדחית | כתובת ההעלאה היא `https://` ועוד אותו שם מתחם, וסיסמת ה־API זהה לגמרי, כולל אותיות גדולות |
| קונטיינר נעצר | `sudo docker compose logs --tail 200` מתוך `~/nightscout` |

משתני ההגדרה של Nightscout: <https://nightscout.github.io/nightscout/setup_variables/>.
