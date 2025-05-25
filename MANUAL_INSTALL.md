# Manuelle Installation von ShareMe

Diese Anleitung beschreibt die manuelle Installation von ShareMe auf einem Debian-basierten System.

## 1. Sudo-Rechte einrichten (falls noch nicht vorhanden)

Falls Ihr Benutzer noch keine sudo-Rechte hat, melden Sie sich als root an und führen Sie folgende Befehle aus:

```bash
apt update
apt install sudo
usermod -aG sudo BENUTZERNAME
```

Ersetzen Sie BENUTZERNAME mit Ihrem tatsächlichen Benutzernamen. Melden Sie sich danach ab und wieder an, damit die Änderungen wirksam werden.

## 2. Benötigte Pakete installieren

```bash
sudo apt update
sudo apt install -y python3 python3-pip python3-venv git samba samba-common-bin nginx
```

## 3. ShareMe herunterladen

```bash
git clone https://github.com/yourusername/ShareMe.git
cd ShareMe
```

## 4. Python-Umgebung einrichten

```bash
# Virtuelle Umgebung erstellen
python3 -m venv venv

# Virtuelle Umgebung aktivieren
source venv/bin/activate

# Abhängigkeiten installieren
pip install -r requirements.txt

# Gunicorn für Produktionsumgebungen installieren
pip install gunicorn
```

## 5. Samba-Konfiguration für den Webzugriff vorbereiten

Damit die Webanwendung die Samba-Konfiguration bearbeiten kann, müssen die entsprechenden Berechtigungen eingerichtet werden:

```bash
# Sichern der ursprünglichen smb.conf
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup

# Berechtigungen für die Webanwendung einrichten
# Option 1: Berechtigungen für die smb.conf-Datei anpassen (weniger sicher)
sudo chmod 664 /etc/samba/smb.conf
sudo chown root:www-data /etc/samba/smb.conf

# Option 2: Sudo-Berechtigungen für bestimmte Befehle einrichten (empfohlen)
sudo visudo
```

Fügen Sie in der sudoers-Datei folgende Zeilen hinzu (ersetzen Sie www-data durch den Benutzer, unter dem die Anwendung läuft):

```
www-data ALL=(root) NOPASSWD: /usr/sbin/service smbd restart
www-data ALL=(root) NOPASSWD: /usr/sbin/service nmbd restart
www-data ALL=(root) NOPASSWD: /usr/bin/pdbedit
www-data ALL=(root) NOPASSWD: /usr/bin/smbpasswd
```

## 6. Systemdienst einrichten

Erstellen Sie eine Systemd-Service-Datei:

```bash
sudo nano /etc/systemd/system/shareme.service
```

Fügen Sie folgenden Inhalt ein (passen Sie die Pfade an):

```
[Unit]
Description=ShareMe Samba Web Manager
After=network.target

[Service]
User=www-data
Group=www-data
WorkingDirectory=/path/to/ShareMe
Environment="PATH=/path/to/ShareMe/venv/bin"
ExecStart=/path/to/ShareMe/venv/bin/gunicorn -w 4 -b 0.0.0.0:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
```

Setzen Sie die korrekten Berechtigungen für die Anwendungsverzeichnisse:

```bash
sudo chown -R www-data:www-data /path/to/ShareMe
```

Aktivieren und starten Sie den Dienst:

```bash
sudo systemctl daemon-reload
sudo systemctl enable shareme
sudo systemctl start shareme
```

## 7. Nginx als Reverse-Proxy einrichten

Erstellen Sie eine Nginx-Konfigurationsdatei:

```bash
sudo nano /etc/nginx/sites-available/shareme
```

Fügen Sie folgende Konfiguration ein:

```
server {
    listen 80;
    server_name your_domain_or_ip;

    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Aktivieren Sie die Konfiguration und starten Sie Nginx neu:

```bash
sudo ln -s /etc/nginx/sites-available/shareme /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## 8. Firewall konfigurieren (optional)

Wenn Sie ufw verwenden, öffnen Sie Port 80 für HTTP:

```bash
sudo ufw allow 80/tcp
```

## 9. Testen der Installation

Öffnen Sie einen Webbrowser und navigieren Sie zu http://ihre-server-ip. Sie sollten die ShareMe-Anmeldemaske sehen.

Die Standardanmeldedaten sind:
- Benutzername: admin
- Passwort: admin

**Wichtig**: Ändern Sie das Passwort nach der ersten Anmeldung!
