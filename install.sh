#!/bin/bash

# ShareMe - Automatisches Installationsskript
# Dieses Skript automatisiert die Installation von ShareMe auf Debian-basierten Systemen

set -e  # Beendet das Skript bei Fehlern
trap 'echo "Ein Fehler ist aufgetreten. Installation abgebrochen." >&2; exit 1' ERR

# Farbdefinitionen
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funktion zum Anzeigen von Meldungen
print_message() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNUNG]${NC} $1"
}

print_error() {
    echo -e "${RED}[FEHLER]${NC} $1"
}

# Funktion zur Überprüfung der Existenz von Befehlen
check_command() {
    command -v "$1" >/dev/null 2>&1 || { print_error "$1 ist nicht installiert. Bitte installieren Sie es zuerst."; return 1; }
}

# Überprüfen, ob das Skript als Root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    print_error "Dieses Skript muss mit Root-Rechten ausgeführt werden (sudo)."
    exit 1
fi

# Installationsverzeichnis festlegen
INSTALL_DIR="/opt/shareme"
CONFIG_DIR="/etc/shareme"
SERVICE_NAME="shareme"
APP_USER="shareme"
APP_GROUP="shareme"

# Standardeinstellungen
USE_NGINX=false
APP_PORT=5000

# Begrüßung
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║                ShareMe - Installationsskript               ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
print_message "Dieses Skript installiert ShareMe auf Ihrem Debian-System."
echo ""

# Überprüfen, ob es sich um ein Debian-basiertes System handelt
if [ ! -f /etc/debian_version ]; then
    print_error "Dieses Skript ist nur für Debian-basierte Systeme (Debian, Ubuntu) gedacht."
    exit 1
fi

# Fragen, ob die Installation fortgesetzt werden soll
read -p "Möchten Sie mit der Installation fortfahren? (j/n): " confirm
if [[ "$confirm" != "j" && "$confirm" != "J" ]]; then
    print_message "Installation abgebrochen."
    exit 0
fi

# Prüfen, ob wir auf einem Debian-basierten System sind
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "debian" && "$ID" != "ubuntu" && "$ID_LIKE" != *"debian"* ]]; then
        print_warning "Dieses Skript wurde für Debian-basierte Systeme entwickelt. Die Installation könnte fehlschlagen."
        read -p "Möchten Sie trotzdem fortfahren? (j/n): " continue_anyway
        if [[ "$continue_anyway" != "j" && "$continue_anyway" != "J" ]]; then
            print_message "Installation abgebrochen."
            exit 0
        fi
    fi
fi

# 1. Aktualisieren der Paketlisten
print_message "Aktualisiere Paketlisten..."
apt update || { print_error "Fehler beim Aktualisieren der Paketlisten."; exit 1; }

# Fragen, ob Nginx verwendet werden soll
read -p "Möchten Sie Nginx als Reverse-Proxy verwenden? (j/n, Standard: n): " use_nginx_input
if [[ "$use_nginx_input" == "j" || "$use_nginx_input" == "J" ]]; then
    USE_NGINX=true
    print_message "Nginx wird als Reverse-Proxy eingerichtet."
else
    print_message "Die Anwendung wird direkt ohne Reverse-Proxy bereitgestellt."
    read -p "Auf welchem Port soll die Anwendung laufen? (Standard: 5000): " port_input
    if [[ -n "$port_input" && "$port_input" =~ ^[0-9]+$ ]]; then
        APP_PORT=$port_input
    fi
    print_message "Die Anwendung wird auf Port $APP_PORT bereitgestellt."
fi

# 2. Installieren der benötigten Pakete
print_message "Installiere benötigte Pakete..."
# Prüfen, ob die Pakete bereits installiert sind
PACKAGES="python3 python3-pip python3-venv git samba samba-common-bin libldap2-dev libsasl2-dev python3-dev"
if [ "$USE_NGINX" = true ]; then
    PACKAGES="$PACKAGES nginx"
fi

MISSING_PACKAGES=""
for pkg in $PACKAGES; do
    if ! dpkg -l | grep -q "^ii  $pkg "; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done

if [ -n "$MISSING_PACKAGES" ]; then
    print_message "Installiere fehlende Pakete:$MISSING_PACKAGES"
    apt install -y $MISSING_PACKAGES || {
        print_error "Fehler bei der Installation der Pakete.";
        exit 1;
    }
else
    print_message "Alle benötigten Pakete sind bereits installiert."
fi

# 3. Erstellen eines Benutzers für die Anwendung
print_message "Erstelle Benutzer für die Anwendung..."
if id "$APP_USER" &>/dev/null; then
    print_warning "Benutzer $APP_USER existiert bereits."
else
    useradd -m -r -s /bin/bash "$APP_USER" || {
        print_error "Fehler beim Erstellen des Benutzers.";
        exit 1;
    }
fi

# 4. Erstellen der Verzeichnisstruktur
print_message "Erstelle Verzeichnisstruktur..."

# Prüfen, ob die Verzeichnisse bereits existieren
if [ -d "$INSTALL_DIR" ]; then
    print_warning "Installationsverzeichnis $INSTALL_DIR existiert bereits."
    read -p "Möchten Sie es überschreiben? (j/n): " overwrite_dir
    if [[ "$overwrite_dir" == "j" || "$overwrite_dir" == "J" ]]; then
        print_message "Bestehende Installation wird überschrieben."
        # Sichern der alten Installation
        BACKUP_DIR="${INSTALL_DIR}_backup_$(date +%Y%m%d%H%M%S)"
        mv "$INSTALL_DIR" "$BACKUP_DIR"
        print_message "Alte Installation wurde nach $BACKUP_DIR gesichert."
    else
        print_message "Installation abgebrochen."
        exit 0
    fi
fi

# Verzeichnisse erstellen
mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" || {
    print_error "Fehler beim Erstellen der Verzeichnisse.";
    exit 1;
}

# 5. Klonen des Repositories oder Kopieren der Dateien
if [ -d "$(pwd)/app.py" ] || [ -f "$(pwd)/app.py" ]; then
    # Dateien sind bereits im aktuellen Verzeichnis
    print_message "Kopiere Dateien aus dem aktuellen Verzeichnis..."
    cp -r . "$INSTALL_DIR" || {
        print_error "Fehler beim Kopieren der Dateien.";
        exit 1;
    }
else
    # Repository klonen
    print_message "Klone Repository..."
    git clone https://github.com/yourusername/ShareMe.git "$INSTALL_DIR" || {
        print_error "Fehler beim Klonen des Repositories.";
        exit 1;
    }
fi

# 6. Erstellen und Aktivieren der virtuellen Umgebung
print_message "Erstelle virtuelle Python-Umgebung..."
cd "$INSTALL_DIR" || { print_error "Fehler beim Wechseln ins Installationsverzeichnis."; exit 1; }
python3 -m venv venv || { print_error "Fehler beim Erstellen der virtuellen Umgebung."; exit 1; }

# 7. Installieren der Python-Abhängigkeiten
print_message "Installiere Python-Abhängigkeiten..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip || {
    print_warning "Fehler beim Aktualisieren von pip. Fahre trotzdem fort...";
}

# Stelle sicher, dass die richtigen Versionen installiert werden
print_message "Installiere kompatible Paketversionen..."

# Installiere zuerst Werkzeug, um sicherzustellen, dass die richtige Version verwendet wird
"$INSTALL_DIR/venv/bin/pip" install Werkzeug==2.0.1 || {
    print_error "Fehler beim Installieren von Werkzeug.";
    exit 1;
}

# Dann installiere Flask und die anderen Abhängigkeiten
"$INSTALL_DIR/venv/bin/pip" install Flask==2.0.1 Flask-WTF==0.15.1 Flask-Login==0.5.0 python-ldap==3.3.1 gunicorn==20.1.0 || {
    print_error "Fehler beim Installieren der Python-Abhängigkeiten.";
    exit 1;
}

# Überprüfe die installierten Versionen
print_message "Überprüfe installierte Versionen..."
"$INSTALL_DIR/venv/bin/pip" list | grep -E 'Flask|Werkzeug' || {
    print_warning "Konnte installierte Versionen nicht anzeigen.";
}

# 8. Installieren von Samba-Tools
print_message "Installiere Samba-Tools..."
sudo apt-get update
sudo apt-get install -y samba samba-common-bin

# 9. Installieren von Gunicorn
print_message "Installiere Gunicorn..."
"$INSTALL_DIR/venv/bin/pip" install gunicorn || {
    print_error "Fehler beim Installieren von Gunicorn.";
    exit 1;
}

# 9. Samba-Konfiguration sichern
print_message "Sichere Samba-Konfiguration..."
cp /etc/samba/smb.conf /etc/samba/smb.conf.backup.$(date +%Y%m%d%H%M%S) || {
    print_warning "Fehler beim Sichern der Samba-Konfiguration.";
}

# 10. Berechtigungen für Samba-Konfiguration anpassen
print_message "Passe Berechtigungen für Samba-Konfiguration an..."
chmod 664 /etc/samba/smb.conf || { print_warning "Fehler beim Ändern der Berechtigungen für smb.conf."; }
chown root:"$APP_GROUP" /etc/samba/smb.conf || { print_warning "Fehler beim Ändern des Besitzers für smb.conf."; }

# 11. Sudo-Berechtigungen für die Anwendung einrichten
print_message "Richte Sudo-Berechtigungen ein..."
cat > /etc/sudoers.d/shareme << EOF
$APP_USER ALL=(root) NOPASSWD: /usr/sbin/service smbd restart
$APP_USER ALL=(root) NOPASSWD: /usr/sbin/service nmbd restart
$APP_USER ALL=(root) NOPASSWD: /usr/bin/pdbedit
$APP_USER ALL=(root) NOPASSWD: /usr/bin/smbpasswd
$APP_USER ALL=(root) NOPASSWD: $INSTALL_DIR/add_samba_user.sh
EOF
chmod 440 /etc/sudoers.d/shareme || { print_error "Fehler beim Setzen der Berechtigungen für die Sudoers-Datei."; exit 1; }

# 11.5 Hilfsskript für Samba-User anlegen (immer relativ zum Skriptverzeichnis)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_SCRIPT="$SCRIPT_DIR/add_samba_user.sh"
TARGET_SCRIPT="$INSTALL_DIR/add_samba_user.sh"
if [ -f "$SOURCE_SCRIPT" ]; then
    print_message "Kopiere add_samba_user.sh aus $SOURCE_SCRIPT nach $TARGET_SCRIPT ..."
    cp "$SOURCE_SCRIPT" "$TARGET_SCRIPT"
    chown $APP_USER:$APP_GROUP "$TARGET_SCRIPT"
    chmod 750 "$TARGET_SCRIPT"
else
    print_warning "add_samba_user.sh nicht gefunden im Skriptverzeichnis ($SOURCE_SCRIPT), bitte manuell kopieren!"
fi

# Sudoers-Eintrag für add_samba_user.sh automatisch ergänzen
SUDOERS_FILE="/etc/sudoers.d/shareme"
if ! grep -q "$TARGET_SCRIPT" "$SUDOERS_FILE" 2>/dev/null; then
    echo "$APP_USER ALL=(root) NOPASSWD: $TARGET_SCRIPT" >> "$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
    print_message "Sudoers-Eintrag für $TARGET_SCRIPT ergänzt."
fi

# 11.6 WSGI-Datei erstellen
print_message "Erstelle WSGI-Datei..."
cat > $INSTALL_DIR/wsgi.py << EOF
from app import app

if __name__ == "__main__":
    app.run()
EOF
chown $APP_USER:$APP_GROUP $INSTALL_DIR/wsgi.py
chmod 755 $INSTALL_DIR/wsgi.py

# 12. Systemd-Service erstellen
print_message "Erstelle Systemd-Service..."
cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=ShareMe Samba Web Manager
After=network.target

[Service]
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --chdir $INSTALL_DIR -w 4 -b 0.0.0.0:$APP_PORT wsgi:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 13. Nginx-Konfiguration erstellen, falls gewünscht
if [ "$USE_NGINX" = true ]; then
    print_message "Erstelle Nginx-Konfiguration..."
    cat > /etc/nginx/sites-available/$SERVICE_NAME << EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # 14. Nginx-Konfiguration aktivieren
    print_message "Aktiviere Nginx-Konfiguration..."
    ln -sf /etc/nginx/sites-available/$SERVICE_NAME /etc/nginx/sites-enabled/ || {
        print_error "Fehler beim Aktivieren der Nginx-Konfiguration.";
        exit 1;
    }
fi

# 15. Berechtigungen für Installationsverzeichnis setzen
print_message "Setze Berechtigungen für Installationsverzeichnis..."
chown -R "$APP_USER":"$APP_GROUP" "$INSTALL_DIR" || {
    print_error "Fehler beim Setzen der Berechtigungen für das Installationsverzeichnis.";
    exit 1;
}

# 16. Systemd neu laden und Dienste starten
print_message "Lade Systemd neu und starte Dienste..."
systemctl daemon-reload || { print_error "Fehler beim Neuladen von Systemd."; exit 1; }
systemctl enable $SERVICE_NAME || { print_error "Fehler beim Aktivieren des ShareMe-Dienstes."; exit 1; }
systemctl restart $SERVICE_NAME || { print_error "Fehler beim Starten des ShareMe-Dienstes."; exit 1; }

# Nginx nur neustarten, wenn es verwendet wird
if [ "$USE_NGINX" = true ]; then
    systemctl restart nginx || { print_error "Fehler beim Neustarten von Nginx."; exit 1; }
fi

# 17. Firewall-Regeln hinzufügen (falls ufw installiert ist)
if command -v ufw &> /dev/null; then
    print_message "Füge Firewall-Regeln hinzu..."
    if [ "$USE_NGINX" = true ]; then
        ufw allow 80/tcp || { print_warning "Fehler beim Hinzufügen der Firewall-Regel für HTTP."; }
    else
        ufw allow $APP_PORT/tcp || { print_warning "Fehler beim Hinzufügen der Firewall-Regel für Port $APP_PORT."; }
    fi
fi

# 18. Überprüfen, ob der Dienst erfolgreich gestartet wurde
print_message "Warte auf Dienststart..."
sleep 5

if systemctl is-active $SERVICE_NAME &>/dev/null; then
    print_message "Installation erfolgreich abgeschlossen!"
    if [ "$USE_NGINX" = true ]; then
        print_message "ShareMe wurde erfolgreich installiert und läuft unter http://$(hostname -I | awk '{print $1}')"
    else
        print_message "ShareMe wurde erfolgreich installiert und läuft unter http://$(hostname -I | awk '{print $1}'):$APP_PORT"
    fi
    print_message "Standard-Anmeldedaten: admin / admin"
    print_message "Bitte ändern Sie das Passwort nach der ersten Anmeldung!"
else
    print_warning "Der Dienst konnte nicht gestartet werden. Überprüfen Sie die Logs mit:"
    print_message "sudo journalctl -u $SERVICE_NAME"
    print_message "Oder führen Sie das Reparaturskript aus:"
    print_message "sudo ./fix_installation.sh"
fi

exit 0
