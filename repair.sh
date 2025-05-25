#!/bin/bash

# ShareMe - Reparaturskript
# Dieses Skript behebt bekannte Probleme mit der ShareMe-Installation

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

print_message "ShareMe Reparatur-Tool - Behebt alle bekannten Probleme mit der Installation"

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

print_header "7. Template-Dateien korrigieren"
TEMPLATES_DIR="$INSTALL_DIR/templates"

# Überprüfen, ob das Templates-Verzeichnis existiert
if [ ! -d "$TEMPLATES_DIR" ]; then
    print_warning "Templates-Verzeichnis nicht gefunden: $TEMPLATES_DIR"
else
    # Sichern der aktuellen Template-Dateien
    print_message "Sichere aktuelle Template-Dateien..."
    mkdir -p "$INSTALL_DIR/templates_backup"
    cp -r "$TEMPLATES_DIR"/* "$INSTALL_DIR/templates_backup/"
    print_message "Template-Dateien wurden gesichert in $INSTALL_DIR/templates_backup/"

    # Überprüfen und Korrigieren der base.html
    BASE_TEMPLATE="$TEMPLATES_DIR/base.html"
    if [ -f "$BASE_TEMPLATE" ]; then
        print_message "Überprüfe base.html..."
        
        # Zählen, wie oft der content-Block definiert ist
        CONTENT_COUNT=$(grep -c "{% block content %}" "$BASE_TEMPLATE")
        
        if [ "$CONTENT_COUNT" -gt 1 ]; then
            print_message "Der content-Block ist $CONTENT_COUNT mal in base.html definiert. Korrigiere..."
            
            # Erstelle eine temporäre Datei
            TMP_FILE=$(mktemp)
            
            # Finde die erste Instanz des content-Blocks und behalte sie bei
            # Entferne alle weiteren Instanzen
            awk '
            BEGIN { found = 0 }
            /{% block content %}/ {
                if (found == 0) {
                    found = 1;
                    print;
                } else {
                    next;
                }
                next;
            }
            /{% endblock %}/ {
                if (found == 1) {
                    print;
                    found = 0;
                } else {
                    print;
                }
                next;
            }
            { print }
            ' "$BASE_TEMPLATE" > "$TMP_FILE"
            
            # Ersetze die Originaldatei
            mv "$TMP_FILE" "$BASE_TEMPLATE"
            chown $APP_USER:$APP_GROUP "$BASE_TEMPLATE"
            chmod 644 "$BASE_TEMPLATE"
            
            print_message "base.html wurde korrigiert."
        else
            print_message "base.html scheint in Ordnung zu sein."
        fi
    else
        print_warning "base.html nicht gefunden."
    fi

    # Überprüfen und Korrigieren der login.html
    LOGIN_TEMPLATE="$TEMPLATES_DIR/login.html"
    if [ -f "$LOGIN_TEMPLATE" ]; then
        print_message "Überprüfe login.html..."
        
        # Prüfe, ob login.html einen content-Block oder einen unauthenticated_content-Block definiert
        if grep -q "{% block content %}" "$LOGIN_TEMPLATE" || grep -q "{% block unauthenticated_content %}" "$LOGIN_TEMPLATE"; then
            print_message "login.html enthält einen gültigen Block (content oder unauthenticated_content). Keine Reparatur nötig."
            # Prüfe, ob extends-Anweisung vorhanden ist
            if grep -q "{% extends 'base.html' %}" "$LOGIN_TEMPLATE"; then
                print_message "login.html erweitert base.html korrekt."
            else
                print_warning "login.html erweitert base.html nicht. Füge extends-Anweisung hinzu..."
                TMP_FILE=$(mktemp)
                echo "{% extends 'base.html' %}" > "$TMP_FILE"
                cat "$LOGIN_TEMPLATE" >> "$TMP_FILE"
                mv "$TMP_FILE" "$LOGIN_TEMPLATE"
                chown $APP_USER:$APP_GROUP "$LOGIN_TEMPLATE"
                chmod 644 "$LOGIN_TEMPLATE"
                print_message "extends-Anweisung zu login.html hinzugefügt."
            fi
        else
            print_warning "login.html enthält weder content- noch unauthenticated_content-Block. Füge content-Block hinzu..."
            TMP_FILE=$(mktemp)
            if grep -q "{% extends 'base.html' %}" "$LOGIN_TEMPLATE"; then
                awk '
                /{% extends .base.html. %}/ {
                    print;
                    print "";
                    print "{% block content %}";
                    next;
                }
                { print }
                END {
                    print "{% endblock %}";
                }
                ' "$LOGIN_TEMPLATE" > "$TMP_FILE"
            else
                echo "{% extends 'base.html' %}" > "$TMP_FILE"
                echo "" >> "$TMP_FILE"
                echo "{% block content %}" >> "$TMP_FILE"
                cat "$LOGIN_TEMPLATE" >> "$TMP_FILE"
                echo "{% endblock %}" >> "$TMP_FILE"
            fi
            mv "$TMP_FILE" "$LOGIN_TEMPLATE"
            chown $APP_USER:$APP_GROUP "$LOGIN_TEMPLATE"
            chmod 644 "$LOGIN_TEMPLATE"
            print_message "content-Block zu login.html hinzugefügt."
        fi
    else
        print_warning "login.html nicht gefunden."
    fi
fi

print_header "8. Firewall-Regel prüfen"
# Port aus der Konfiguration ermitteln
PORT=$(grep -oP 'ExecStart=.*-b\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/$SERVICE_NAME.service || echo "5000")

# Überprüfen, ob der Port in der Firewall geöffnet ist
if command -v ufw &>/dev/null; then
    if ! ufw status | grep -q "$PORT/tcp"; then
        print_message "Öffne Port $PORT in der Firewall..."
        ufw allow $PORT/tcp
        print_message "Port $PORT wurde in der Firewall geöffnet."
    else
        print_message "Port $PORT ist bereits in der Firewall geöffnet."
    fi
else
    print_warning "ufw ist nicht installiert. Bitte stellen Sie sicher, dass der Port $PORT in Ihrer Firewall geöffnet ist."
fi

# Anzeigen der IP-Adresse und des Ports
IP_ADDRESS=$(hostname -I | awk '{print $1}')
print_message "ShareMe ist jetzt verfügbar unter: http://$IP_ADDRESS:$PORT"
print_message "Standard-Anmeldedaten: admin / admin"

print_header "9. Status überprüfen"
sleep 5

if systemctl is-active $SERVICE_NAME &>/dev/null; then
    print_message "Der ShareMe-Dienst läuft jetzt."
else
    print_error "Der ShareMe-Dienst konnte nicht gestartet werden."
    print_message "Hier sind die letzten Zeilen der Logs:"
    journalctl -u $SERVICE_NAME -n 20 --no-pager
fi

print_header "10. Geprüfte Templates aus dem Repository kopieren"
SOURCE_TEMPLATES="./templates"
TARGET_TEMPLATES="$INSTALL_DIR/templates"

if [ -d "$SOURCE_TEMPLATES" ]; then
    print_message "Kopiere base.html und login.html aus dem Repository..."
    cp -v "$SOURCE_TEMPLATES/base.html" "$TARGET_TEMPLATES/"
    cp -v "$SOURCE_TEMPLATES/login.html" "$TARGET_TEMPLATES/"
    chown $APP_USER:$APP_GROUP "$TARGET_TEMPLATES/base.html" "$TARGET_TEMPLATES/login.html"
    chmod 644 "$TARGET_TEMPLATES/base.html" "$TARGET_TEMPLATES/login.html"
    print_message "Templates base.html und login.html wurden erfolgreich überschrieben und Berechtigungen gesetzt."
else
    print_warning "Quell-Templates nicht gefunden: $SOURCE_TEMPLATES"
fi

print_header "Reparatur abgeschlossen"
print_message "Wenn die Anwendung immer noch nicht funktioniert, überprüfen Sie die vollständigen Logs mit:"
print_message "sudo journalctl -u $SERVICE_NAME"

exit 0
