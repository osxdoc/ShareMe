#!/bin/bash

# ShareMe - Reparaturskript
# Dieses Skript behebt Kompatibilitätsprobleme mit den Python-Abhängigkeiten

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

print_message "Beginne mit der Reparatur der ShareMe-Installation..."

# 1. Dienst stoppen
print_message "Stoppe den ShareMe-Dienst..."
systemctl stop $SERVICE_NAME

# 2. Python-Abhängigkeiten neu installieren
print_message "Installiere Python-Abhängigkeiten neu..."
cd $INSTALL_DIR
source venv/bin/activate
pip install --upgrade pip
pip uninstall -y Flask Werkzeug Flask-WTF Flask-Login python-ldap gunicorn
pip install -r requirements.txt

# 3. Berechtigungen setzen
print_message "Setze Berechtigungen..."
chown -R $APP_USER:$APP_GROUP $INSTALL_DIR

# 4. Dienst neu starten
print_message "Starte den ShareMe-Dienst neu..."
systemctl daemon-reload
systemctl restart $SERVICE_NAME

# 5. Status überprüfen
print_message "Überprüfe den Status des Dienstes..."
sleep 3
if systemctl is-active $SERVICE_NAME &>/dev/null; then
    print_message "Der ShareMe-Dienst läuft jetzt."
    
    # Port aus der Konfiguration ermitteln
    PORT=$(grep -oP 'ExecStart=.*-b\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/$SERVICE_NAME.service || echo "7890")
    
    # Firewall-Regel hinzufügen, falls nötig
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        print_message "Füge Firewall-Regel für Port $PORT hinzu..."
        ufw allow $PORT/tcp
    fi
    
    # IP-Adresse ermitteln
    IP_ADDRESS=$(hostname -I | awk '{print $1}')
    
    print_message "ShareMe ist jetzt verfügbar unter: http://$IP_ADDRESS:$PORT"
    print_message "Standard-Anmeldedaten: admin / admin"
else
    print_error "Der ShareMe-Dienst konnte nicht gestartet werden."
    print_message "Überprüfen Sie die Logs mit: journalctl -u $SERVICE_NAME"
fi

exit 0
