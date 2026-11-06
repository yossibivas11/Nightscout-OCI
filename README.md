# Nightscout on Oracle Cloud

This is the whole path: open a free Oracle Cloud account, create one Ubuntu server, give it a free DuckDNS name, and run `deploy.sh` on that server. The script installs Nightscout and opens it at `https://yourname.duckdns.org`.

Nightscout shows continuous glucose monitor data in a browser. It is not an approved medical device. It does not replace a meter, a pump, or clinical care.

[עברית](#עברית)

---

## English

You do the Oracle and DuckDNS steps in a browser. You run `deploy.sh` only after you have connected to the server. The script does not create the Oracle account, the server, or the DuckDNS name.

### 1. Open an Oracle Cloud account

1. Go to [oracle.com/cloud/free](https://www.oracle.com/cloud/free/) and start the free account.
2. Use a personal email you can open. Oracle sends a verification link. Open it before the rest of the form will continue.
3. Choose a **cloud account name**. You type this name every time you log in. Write it down.
4. Choose the **home region** once. It cannot be changed later, and the free server has to live in that region. In Israel, choose **Israel Central (Jerusalem)** if it is in the list. If you would rather have a region where free Arm servers are easier to get, choose **Germany Central (Frankfurt)**.
5. Enter your address and mobile number. Oracle sends a code to the phone.
6. Enter a credit or debit card. Oracle uses it to check that the account belongs to a real person. A small temporary charge may appear and is then reversed. Prepaid and virtual cards are often rejected. Always Free resources are not a monthly bill. Do not upgrade the account to Pay As You Go, and do not create databases or extra disks.
7. Wait until Oracle says the account is ready. That can take minutes, and sometimes longer. They email you.

Log in later at [cloud.oracle.com](https://cloud.oracle.com/) with the cloud account name and the email.

New accounts also get a short trial with credits. The server you create below is an Always Free shape, so it does not spend those credits. When the trial ends, this server can stay.

### 2. Open the terminal that is already on the Oracle site

You do not install a terminal on your computer, and you do not connect from Windows. Oracle has a terminal in the browser.

1. In the top bar of the Oracle Cloud page, next to the region name, click the **Cloud Shell** icon (it looks like a prompt, `>_`). Choose **Cloud Shell**, not Code Editor.
2. A black terminal opens at the bottom of the page. The first time, it can take a minute. If a tutorial pops up, close it.
3. Paste these three lines, one at a time:

```bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/nightscout -N ""
cat ~/.ssh/nightscout.pub
```

4. The last line prints one long line that starts with `ssh-ed25519`. Select that whole line and copy it. Leave Cloud Shell open. The key stays there if you close it later; open Cloud Shell the same way to get it back.

### 3. Create the server

In the console, open the navigation menu, then **Compute**, then **Instances**, then **Create instance**.

| Setting | What to choose |
|---|---|
| Name | `nightscout` |
| Placement | Leave an availability domain marked **Always Free Eligible** |
| Image | **Canonical Ubuntu 24.04**. Ubuntu 22.04 is also fine. Do not choose Oracle Linux. The script stops on anything except Ubuntu. |
| Shape | **Ampere**, `VM.Standard.A1.Flex`, **1 OCPU**, **6 GB** memory. The free Ampere allowance is 2 OCPUs and 12 GB, so this uses half of it. |
| Networking | Create a new virtual cloud network. Public subnet. **Assign a public IPv4 address**. |
| SSH keys | **Paste a public key**, and paste the `ssh-ed25519` line from Cloud Shell. Do not download a key. |

Click **Create**. Wait until the instance says **Running**. Copy the **Public IP address** from the instance page.

If creation fails with **out of host capacity**, change the availability domain to another one marked Always Free Eligible and try again. If Ampere is still unavailable, use the AMD shape `VM.Standard.E2.1.Micro` (1 GB). The script adds swap on that size. It is slower, and it still runs one Nightscout site.

Oracle can take back a free server that stays almost idle for a week. A site that receives glucose uploads is normally busy enough. Details are on Oracle's [Always Free](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) page.

### 4. Let the internet reach the site

Oracle allows SSH (port 22) and blocks the web until you add two rules. The script cannot do this part.

1. On the instance page, click the **subnet** name.
2. Click the **security list** (usually **Default Security List**).
3. Click **Add Ingress Rules**. Leave **Stateless** unchecked.

Add one rule, then add a second:

| Source CIDR | Protocol | Destination port |
|---|---|---|
| `0.0.0.0/0` | TCP | `80` |
| `0.0.0.0/0` | TCP | `443` |

### 5. Create the DuckDNS name

DuckDNS is free. There is no payment page.

1. Open [duckdns.org](https://www.duckdns.org/) and sign in with Google, GitHub, Reddit, or X.
2. Under domains, type a short name and add it. Letters and numbers only, for example `mysugar`. The site name becomes `mysugar.duckdns.org`. If the name is taken, pick another.
3. DuckDNS fills in the IP address of the computer you are using right now. That is your home address, and it is the wrong one. Delete it, paste the **public IP from the Oracle instance page**, and click **update ip**.
4. Copy the **token** at the top of the DuckDNS page and keep it somewhere you will find again. You need the token only if the server's IP changes later.

Check from your own computer before you continue. The answer must be the Oracle IP, not your home IP.

```text
nslookup mysugar.duckdns.org
```

### 6. Go into the server from that same terminal

Click the Cloud Shell terminal at the bottom of the Oracle page. If you closed it, click the `>_` icon again and choose **Cloud Shell**. Paste this, with the public IP from the instance page:

```bash
ssh -i ~/.ssh/nightscout ubuntu@YOUR_PUBLIC_IP
```

The first time, type `yes` and press Enter. You are then on the server. The prompt changes. Every command after this runs on the server.

### 7. Run the script

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./deploy.sh
```

The script asks eight things, in this order. Nothing is shown while you type the API secret. That is normal.

| Prompt | What to type |
|---|---|
| Prompt language (en/he) | `en`, or `he` if you want the rest of the questions in Hebrew. Press Enter to keep `en`. |
| API secret, twice | At least 12 letters and digits. No spaces, quotes, `#`, or `$`. Write it down. AndroidAPS or xDrip needs the same value. It is saved only in `/opt/nightscout/.env` on the server. |
| Glucose units | Press Enter for `mg/dl`. That is the default. Type `mmol` only if the uploader and the pump profile use mmol/L. |
| Timezone | Press Enter for `Asia/Jerusalem`. |
| Nightscout language (en/he) | `he` for a Hebrew site, or `en`. |
| Domain name for HTTPS | The full DuckDNS name, such as `mysugar.duckdns.org`. No `https://`. |
| Email for the certificate | A real email address. Let's Encrypt uses it for expiry notices. |
| Let anyone with the link view the site? | `no` unless you want the chart visible to anyone who knows the address. `yes` or `כן` makes it public. |

The first run downloads the Nightscout, database, and certificate software. That often takes several minutes. At the end it prints `https://mysugar.duckdns.org`. Open that address. With the default answer `no`, the site asks for the API secret before it shows data.

In AndroidAPS or xDrip, set the Nightscout URL to that same `https://...duckdns.org` address and set the API secret to the value you typed.

### If you already know every answer

You can skip the questions. `API_SECRET` is required. The domain must be the full DuckDNS name, and the email is required because a domain is set.

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mg/dl' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='mysugar.duckdns.org' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./deploy.sh
```

`AUTH_DEFAULT_ROLES=denied` hides the chart until a visitor has the secret. `readable` shows it to anyone with the link.

Running `sudo ./deploy.sh` again replaces `/opt/nightscout/.env`. Have the API secret ready.

### When something fails

| What you see | What to do |
|---|---|
| Cloud Shell cannot reach the server | The instance is Running, the command is `ssh -i ~/.ssh/nightscout ubuntu@` plus the public IP, and the pasted key is the one Cloud Shell printed. |
| The browser spins and never loads | The security list is missing TCP 80 or 443. Add them, then run `sudo ./deploy.sh` again. |
| The browser warns about the certificate | `nslookup yourname.duckdns.org` must print the Oracle public IP. Then on the server run `cd /opt/nightscout && sudo docker compose restart caddy` and wait a couple of minutes. |
| The page opens and the phone is rejected | The URL in the uploader is `https://` plus the DuckDNS name, and the API secret matches exactly, including capital letters. |
| You stopped the server and the site disappeared | A stopped instance can come back with a new public IP. Copy the new IP into DuckDNS, click **update ip**, and restart Caddy with the command above. The token from the DuckDNS page is the other way to set it: `https://www.duckdns.org/update?domains=mysugar&token=YOUR_TOKEN&ip=NEW_IP` |

Logs on the server:

```bash
cd /opt/nightscout && sudo docker compose logs -f
```

### Updates and a copy of the data

Glucose history is in `/opt/nightscout/mongo-data`. The API secret is in `/opt/nightscout/.env`. Copy both off the server. A disk that exists only at Oracle is not a backup.

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

To update Nightscout later, without running the questions again:

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```

---

# עברית

זה המסלול המלא: פותחים חשבון Oracle Cloud בחינם, יוצרים שרת אובונטו אחד, נותנים לו שם בחינם ב-DuckDNS, ומריצים את `deploy.sh` על השרת. הסקריפט מתקין את Nightscout ופותח אותו בכתובת `https://yourname.duckdns.org`.

Nightscout מציג נתוני חיישן סוכר בדפדפן. הוא אינו מכשיר רפואי מאושר. הוא אינו מחליף מד סוכר, משאבה או טיפול רפואי.

[English](#nightscout-on-oracle-cloud)

את שלבי Oracle ו-DuckDNS עושים בדפדפן. את `deploy.sh` מריצים רק אחרי שהתחברתם לשרת. הסקריפט לא יוצר את חשבון Oracle, לא את השרת, ולא את השם ב-DuckDNS.

### 1. פתיחת חשבון Oracle Cloud

1. נכנסים ל-[oracle.com/cloud/free](https://www.oracle.com/cloud/free/) ומתחילים חשבון בחינם.
2. משתמשים באימייל אישי שאפשר לפתוח. Oracle שולחת קישור אימות. פותחים אותו לפני שהטופס ממשיך.
3. בוחרים **cloud account name**. את השם הזה מקלידים בכל כניסה. רושמים אותו.
4. בוחרים **home region** פעם אחת. אי אפשר להחליף אותו אחר כך, והשרת החינמי חייב לשבת באזור הזה. בישראל בוחרים **Israel Central (Jerusalem)** אם הוא ברשימה. אם מעדיפים אזור שבו קל יותר לקבל שרת Arm חינמי, בוחרים **Germany Central (Frankfurt)**.
5. ממלאים כתובת ומספר נייד. Oracle שולחת קוד לטלפון.
6. ממלאים כרטיס אשראי או חיוב. Oracle משתמשת בו כדי לבדוק שהחשבון שייך לאדם אמיתי. יכולה להופיע חיוב זמני קטן, והוא מוחזר. כרטיסים נטענים ווירטואליים נדחים לעיתים קרובות. משאבי Always Free אינם חשבון חודשי. לא משדרגים את החשבון ל-Pay As You Go, ולא יוצרים מסדי נתונים או דיסקים נוספים.
7. מחכים עד ש-Oracle מודיעה שהחשבון מוכן. זה יכול לקחת דקות, ולפעמים יותר. הם שולחים אימייל.

אחר כך נכנסים ב-[cloud.oracle.com](https://cloud.oracle.com/) עם שם חשבון הענן והאימייל.

לחשבון חדש יש גם תקופת ניסיון עם קרדיטים. השרת שיוצרים בהמשך הוא מסוג Always Free, ולכן הוא לא מוציא את הקרדיטים האלה. כשתקופת הניסיון נגמרת, השרת הזה יכול להישאר.

### 2. פתיחת המסוף שכבר נמצא באתר של Oracle

לא מתקינים מסוף על המחשב, ולא מתחברים מ-Windows. ל-Oracle יש מסוף בתוך הדפדפן.

1. בסרגל העליון של עמוד Oracle Cloud, ליד שם האזור, לוחצים על סמל **Cloud Shell** (הוא נראה כמו שורת פקודה, `>_`). בוחרים **Cloud Shell**, לא Code Editor.
2. מסוף שחור נפתח בתחתית העמוד. בפעם הראשונה זה יכול לקחת דקה. אם קופץ מדריך, סוגרים אותו.
3. מדביקים את שלוש השורות האלה, אחת בכל פעם:

```bash
mkdir -p ~/.ssh
ssh-keygen -t ed25519 -f ~/.ssh/nightscout -N ""
cat ~/.ssh/nightscout.pub
```

4. השורה האחרונה מדפיסה שורה ארוכה אחת שמתחילה ב-`ssh-ed25519`. מסמנים את כל השורה ומעתיקים אותה. משאירים את Cloud Shell פתוח. המפתח נשאר שם גם אם סוגרים אחר כך; פותחים את Cloud Shell באותה דרך כדי לחזור אליו.

### 3. יצירת השרת

בקונסול פותחים את תפריט הניווט, אחר כך **Compute**, אחר כך **Instances**, ואז **Create instance**.

| הגדרה | מה בוחרים |
|---|---|
| שם | `nightscout` |
| מיקום | משאירים availability domain שמסומן **Always Free Eligible** |
| Image | **Canonical Ubuntu 24.04**. גם Ubuntu 22.04 מתאים. לא בוחרים Oracle Linux. הסקריפט נעצר על כל מערכת שאינה אובונטו. |
| Shape | **Ampere**, `VM.Standard.A1.Flex`, **1 OCPU**, **6 GB** זיכרון. המכסה החינמית של Ampere היא 2 OCPUs ו-12 GB, אז זה חצי ממנה. |
| רשת | יוצרים רשת וירטואלית חדשה. תת-רשת ציבורית. **Assign a public IPv4 address**. |
| מפתחות SSH | **Paste a public key**, ומדביקים את שורת `ssh-ed25519` מ-Cloud Shell. לא מורידים מפתח. |

לוחצים **Create**. מחכים עד שהמכונה במצב **Running**. מעתיקים את **Public IP address** מעמוד המכונה.

אם היצירה נכשלת עם **out of host capacity**, מחליפים availability domain לאחר שמסומן Always Free Eligible ומנסים שוב. אם Ampere עדיין לא זמין, משתמשים בצורה של AMD בשם `VM.Standard.E2.1.Micro` (1 GB). הסקריפט מוסיף swap בגודל הזה. זה איטי יותר, וזה עדיין מריץ אתר Nightscout אחד.

Oracle יכולה לקחת בחזרה שרת חינמי שנשאר כמעט בלי פעילות במשך שבוע. אתר שמקבל העלאות סוכר בדרך כלל פעיל מספיק. הפירוט בעמוד [Always Free](https://docs.oracle.com/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm) של Oracle.

### 4. לאפשר לאינטרנט להגיע לאתר

Oracle מאפשרת SSH (פורט 22) וחוסמת את האתר עד שמוסיפים שני כללים. הסקריפט לא יכול לעשות את החלק הזה.

1. בעמוד המכונה לוחצים על שם ה-**subnet**.
2. לוחצים על ה-**security list** (בדרך כלל **Default Security List**).
3. לוחצים **Add Ingress Rules**. משאירים את **Stateless** לא מסומן.

מוסיפים כלל אחד, ואז כלל שני:

| Source CIDR | פרוטוקול | פורט יעד |
|---|---|---|
| `0.0.0.0/0` | TCP | `80` |
| `0.0.0.0/0` | TCP | `443` |

### 5. יצירת השם ב-DuckDNS

DuckDNS בחינם. אין עמוד תשלום.

1. פותחים את [duckdns.org](https://www.duckdns.org/) ונכנסים עם Google, GitHub, Reddit או X.
2. תחת domains מקלידים שם קצר ומוסיפים אותו. אותיות וספרות בלבד, למשל `mysugar`. שם האתר יהיה `mysugar.duckdns.org`. אם השם תפוס, בוחרים אחר.
3. DuckDNS ממלא את כתובת ה-IP של המחשב שבו אתם גולשים עכשיו. זו כתובת הבית, והיא כתובת שגויה. מוחקים אותה, מדביקים את **כתובת ה-IP הציבורית מעמוד המכונה ב-Oracle**, ולוחצים **update ip**.
4. מעתיקים את ה-**token** מראש עמוד DuckDNS ושומרים אותו במקום שאפשר למצוא אחר כך. צריך את הטוקן רק אם כתובת ה-IP של השרת תשתנה.

בודקים מהמחשב שלכם לפני שממשיכים. התשובה חייבת להיות כתובת ה-IP של Oracle, לא כתובת הבית.

```text
nslookup mysugar.duckdns.org
```

### 6. כניסה לשרת מאותו מסוף

לוחצים על מסוף Cloud Shell בתחתית העמוד של Oracle. אם סגרתם אותו, לוחצים שוב על הסמל `>_` ובוחרים **Cloud Shell**. מדביקים את זה, עם כתובת ה-IP הציבורית מעמוד המכונה:

```bash
ssh -i ~/.ssh/nightscout ubuntu@YOUR_PUBLIC_IP
```

בפעם הראשונה מקלידים `yes` ולוחצים Enter. עכשיו אתם על השרת. שורת הפקודה משתנה. כל פקודה מכאן רצה על השרת.

### 7. הרצת הסקריפט

```bash
sudo apt-get update
sudo apt-get install -y git
git clone https://github.com/yossibivas11/Nightscout-OCI.git
cd Nightscout-OCI
sudo ./deploy.sh
```

הסקריפט שואל שמונה דברים, בסדר הזה. בזמן שמקלידים את סוד ה-API לא רואים כלום על המסך. זה תקין.

| שאלה | מה מקלידים |
|---|---|
| Prompt language (en/he) | `en`, או `he` אם רוצים את שאר השאלות בעברית. Enter משאיר `en`. |
| סוד API, פעמיים | לפחות 12 אותיות וספרות. בלי רווחים, בלי גרשיים, בלי `#` ובלי `$`. רושמים אותו. AndroidAPS או xDrip צריכים את אותו ערך. הוא נשמר רק בקובץ `/opt/nightscout/.env` על השרת. |
| יחידות סוכר | Enter עבור `mg/dl`. זו ברירת המחדל. מקלידים `mmol` רק אם תוכנת ההעלאה ופרופיל המשאבה משתמשים ב-mmol/L. |
| אזור זמן | Enter עבור `Asia/Jerusalem`. |
| שפת האתר (en/he) | `he` לאתר בעברית, או `en`. |
| שם מתחם ל-HTTPS | השם המלא מ-DuckDNS, למשל `mysugar.duckdns.org`. בלי `https://`. |
| אימייל לתעודה | כתובת אימייל אמיתית. Let's Encrypt משתמשת בה להודעות על תפוגת התעודה. |
| כל מי שיש לו את הקישור יכול לצפות? | `no`, אלא אם רוצים שהגרף יהיה גלוי לכל מי שמכיר את הכתובת. `yes` או `כן` הופכים אותו לציבורי. |

ההרצה הראשונה מורידה את תוכנת Nightscout, את מסד הנתונים ואת תוכנת התעודה. זה לוקח לעיתים כמה דקות. בסוף מודפס `https://mysugar.duckdns.org`. פותחים את הכתובת. עם התשובה `no`, האתר מבקש את סוד ה-API לפני שהוא מציג נתונים.

ב-AndroidAPS או ב-xDrip מגדירים את כתובת Nightscout לאותה כתובת `https://...duckdns.org`, ואת סוד ה-API לערך שהקלדתם.

### אם כבר יודעים את כל התשובות

אפשר לדלג על השאלות. `API_SECRET` חובה. השם חייב להיות השם המלא מ-DuckDNS, והאימייל חובה כי הוגדר שם מתחם.

```bash
sudo API_SECRET='choose-a-long-secret' DISPLAY_UNITS='mg/dl' TZ='Asia/Jerusalem' \
  NS_LANGUAGE=he SITE_LANGUAGE=he NS_DOMAIN='mysugar.duckdns.org' ACME_EMAIL='you@example.com' \
  AUTH_DEFAULT_ROLES=denied ./deploy.sh
```

`AUTH_DEFAULT_ROLES=denied` מסתיר את הגרף עד שלמבקר יש את הסוד. `readable` מציג אותו לכל מי שיש לו את הקישור.

הרצה נוספת של `sudo ./deploy.sh` מחליפה את `/opt/nightscout/.env`. צריך להכין את סוד ה-API.

### כשמשהו נכשל

| מה רואים | מה עושים |
|---|---|
| Cloud Shell לא מגיע לשרת | המכונה במצב Running, הפקודה היא `ssh -i ~/.ssh/nightscout ubuntu@` ועוד כתובת ה-IP הציבורית, והמפתח שהודבק הוא זה ש-Cloud Shell הדפיס. |
| הדפדפן מסתובב ולא נטען | ב-security list חסר TCP 80 או 443. מוסיפים אותם, ואז מריצים שוב `sudo ./deploy.sh`. |
| הדפדפן מזהיר לגבי התעודה | `nslookup yourname.duckdns.org` חייב להדפיס את כתובת ה-IP הציבורית של Oracle. אחר כך על השרת מריצים `cd /opt/nightscout && sudo docker compose restart caddy` ומחכים כמה דקות. |
| הדף נפתח והטלפון נדחה | הכתובת בתוכנת ההעלאה היא `https://` ועוד שם ה-DuckDNS, וסוד ה-API זהה לגמרי, כולל אותיות גדולות. |
| עצרתם את השרת והאתר נעלם | מכונה שנעצרה יכולה לחזור עם כתובת IP ציבורית חדשה. מעתיקים את הכתובת החדשה ל-DuckDNS, לוחצים **update ip**, ומפעילים מחדש את Caddy עם הפקודה למעלה. הטוקן מעמוד DuckDNS הוא הדרך השנייה לעדכן: `https://www.duckdns.org/update?domains=mysugar&token=YOUR_TOKEN&ip=NEW_IP` |

יומן על השרת:

```bash
cd /opt/nightscout && sudo docker compose logs -f
```

### עדכונים ועותק של הנתונים

היסטוריית הסוכר נמצאת ב-`/opt/nightscout/mongo-data`. סוד ה-API נמצא ב-`/opt/nightscout/.env`. מעתיקים את שניהם אל מחוץ לשרת. דיסק שקיים רק ב-Oracle אינו גיבוי.

```bash
cd /opt/nightscout
sudo docker compose stop
sudo tar czf "$HOME/nightscout-mongo-backup.tgz" mongo-data
sudo docker compose start
```

כדי לעדכן את Nightscout אחר כך, בלי לענות שוב על השאלות:

```bash
cd /opt/nightscout
sudo docker compose pull
sudo docker compose up -d
```
