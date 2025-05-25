#!/bin/bash

# ShareMe - Umfassendes Reparaturskript
# Dieses Skript behebt alle bekannten Probleme mit der ShareMe-Installation

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

print_header() {
    echo -e "\n${YELLOW}=== $1 ===${NC}\n"
}

# Überprüfen, ob das Skript als Root ausgeführt wird
if [ "$EUID" -ne 0 ]; then
    print_error "Dieses Skript muss mit Root-Rechten ausgeführt werden (sudo)."
    exit 1
fi

# Variablen
SERVICE_NAME="shareme"
INSTALL_DIR="/opt/shareme"
APP_USER="shareme"
APP_GROUP="shareme"

# Header
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              ShareMe - Reparaturwerkzeug                   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

print_header "1. Dienst stoppen"
systemctl stop $SERVICE_NAME
print_message "ShareMe-Dienst gestoppt."

print_header "2. Python-Abhängigkeiten neu installieren"
cd $INSTALL_DIR

# Virtuelle Umgebung aktivieren
source venv/bin/activate

# Pip aktualisieren
print_message "Aktualisiere pip..."
pip install --upgrade pip

# Inkompatible Pakete entfernen
print_message "Entferne inkompatible Pakete..."
pip uninstall -y Flask Werkzeug Flask-WTF Flask-Login python-ldap gunicorn

# Installiere die richtigen Versionen in der richtigen Reihenfolge
print_message "Installiere kompatible Versionen..."
pip install Werkzeug==2.0.1
pip install Flask==2.0.1
pip install Flask-WTF==0.15.1
pip install Flask-Login==0.5.0
pip install python-ldap==3.3.1
pip install gunicorn==20.1.0

print_message "Python-Abhängigkeiten wurden erfolgreich neu installiert."

print_header "3. Berechtigungen korrigieren"
chown -R $APP_USER:$APP_GROUP $INSTALL_DIR
chmod -R 755 $INSTALL_DIR
print_message "Berechtigungen wurden korrigiert."

print_header "4. WSGI-Datei erstellen"
cat > $INSTALL_DIR/wsgi.py << EOF
from app import app

if __name__ == "__main__":
    app.run()
EOF
chown $APP_USER:$APP_GROUP $INSTALL_DIR/wsgi.py
chmod 755 $INSTALL_DIR/wsgi.py
print_message "WSGI-Datei wurde erstellt."

print_header "5. Service-Datei korrigieren"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"

# Sichern der aktuellen Service-Datei
if [ -f "$SERVICE_FILE" ]; then
    cp "$SERVICE_FILE" "${SERVICE_FILE}.backup"
    print_message "Aktuelle Service-Datei wurde gesichert als ${SERVICE_FILE}.backup"
fi

# Ermitteln des aktuell konfigurierten Ports
PORT=$(grep -oP 'ExecStart=.*-b\s+0.0.0.0:\K[0-9]+' "$SERVICE_FILE" 2>/dev/null || echo "5000")

# Erstellen einer neuen Service-Datei mit korrektem Pfad
cat > "$SERVICE_FILE" << EOF
[Unit]
Description=ShareMe Samba Web Manager
After=network.target

[Service]
User=$APP_USER
Group=$APP_GROUP
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin"
ExecStart=$INSTALL_DIR/venv/bin/gunicorn --chdir $INSTALL_DIR -w 4 -b 0.0.0.0:$PORT wsgi:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

print_message "Service-Datei wurde korrigiert."

print_header "6. Dienst neu starten"
systemctl daemon-reload
systemctl restart $SERVICE_NAME
print_message "ShareMe-Dienst wurde neu gestartet."

print_header "7. Firewall-Regel prüfen"
# Port aus der Konfiguration ermitteln
PORT=$(grep -oP 'ExecStart=.*-b\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/$SERVICE_NAME.service || echo "5000")

# Firewall-Regel hinzufügen, falls nötig
if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    print_message "Füge Firewall-Regel für Port $PORT hinzu..."
    ufw allow $PORT/tcp
    print_message "Firewall-Regel wurde hinzugefügt."
fi

print_header "6. Status überprüfen"
sleep 5

if systemctl is-active $SERVICE_NAME &>/dev/null; then
    print_message "Der ShareMe-Dienst läuft jetzt."
    
    # IP-Adresse ermitteln
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    print_message "ShareMe ist jetzt verfügbar unter: http://$IP_ADDRESS:$PORT"
    print_message "Standard-Anmeldedaten: admin / admin"
else
    print_error "Der ShareMe-Dienst konnte nicht gestartet werden."
    print_message "Hier sind die letzten Zeilen der Logs:"
    journalctl -u $SERVICE_NAME -n 20 --no-pager
fi

print_header "Reparatur abgeschlossen"
print_message "Wenn die Anwendung immer noch nicht funktioniert, überprüfen Sie die vollständigen Logs mit:"
print_message "sudo journalctl -u $SERVICE_NAME"

exit 0
