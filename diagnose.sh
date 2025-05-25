#!/bin/bash

# ShareMe - Diagnoseskript
# Dieses Skript hilft bei der Diagnose von Problemen mit der ShareMe-Installation

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

# Header
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║              ShareMe - Diagnose-Werkzeug                   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 1. Überprüfen des Dienststatus
print_header "Dienststatus überprüfen"
systemctl status $SERVICE_NAME

# 2. Überprüfen der Logs
print_header "Dienst-Logs überprüfen"
journalctl -u $SERVICE_NAME -n 50 --no-pager

# 3. Überprüfen der Netzwerkverbindungen
print_header "Netzwerkverbindungen überprüfen"
print_message "Aktive Verbindungen:"
ss -tulpn | grep -E '(python|gunicorn|nginx)'

# 4. Überprüfen der Firewall
print_header "Firewall-Einstellungen überprüfen"
if command -v ufw &> /dev/null; then
    print_message "UFW-Firewall-Status:"
    ufw status
else
    print_message "UFW ist nicht installiert. Überprüfen Sie andere Firewalls wie iptables."
    iptables -L -n
fi

# 5. Überprüfen der Konfigurationsdateien
print_header "Konfigurationsdateien überprüfen"
print_message "Systemd-Dienstkonfiguration:"
cat /etc/systemd/system/$SERVICE_NAME.service

# Überprüfen, ob Nginx verwendet wird
if systemctl is-active nginx &>/dev/null; then
    print_message "Nginx-Konfiguration:"
    cat /etc/nginx/sites-available/$SERVICE_NAME
fi

# 6. Überprüfen der Berechtigungen
print_header "Berechtigungen überprüfen"
print_message "Berechtigungen für Installationsverzeichnis:"
ls -la $INSTALL_DIR

print_message "Berechtigungen für Samba-Konfiguration:"
ls -la /etc/samba/smb.conf

# 7. Testen der Anwendung direkt
print_header "Anwendung direkt testen"
print_message "Versuche, die Anwendung direkt zu erreichen:"

# Finden des Ports aus der Systemd-Konfiguration
PORT=$(grep -oP 'ExecStart=.*-b\s+0.0.0.0:\K[0-9]+' /etc/systemd/system/$SERVICE_NAME.service || echo "5000")
curl -v http://localhost:$PORT/

# 8. Zusammenfassung und Empfehlungen
print_header "Zusammenfassung und Empfehlungen"

if ! systemctl is-active $SERVICE_NAME &>/dev/null; then
    print_error "Der ShareMe-Dienst läuft nicht. Starten Sie ihn mit: sudo systemctl start $SERVICE_NAME"
fi

if ss -tulpn | grep -q ":$PORT"; then
    print_message "Die Anwendung hört auf Port $PORT."
else
    print_error "Die Anwendung hört nicht auf Port $PORT. Überprüfen Sie die Logs für weitere Details."
fi

if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
    if ! ufw status | grep -q "$PORT/tcp.*ALLOW"; then
        print_error "Die Firewall könnte den Zugriff auf Port $PORT blockieren. Erlauben Sie den Zugriff mit: sudo ufw allow $PORT/tcp"
    fi
fi

print_message "Wenn Sie die Anwendung über die IP-Adresse nicht erreichen können, versuchen Sie folgendes:"
print_message "1. Stellen Sie sicher, dass der Dienst läuft: sudo systemctl restart $SERVICE_NAME"
print_message "2. Öffnen Sie den Port in der Firewall: sudo ufw allow $PORT/tcp"
print_message "3. Prüfen Sie, ob die Anwendung auf allen Interfaces hört (0.0.0.0)"
print_message "4. Versuchen Sie, die Anwendung lokal zu erreichen: curl http://localhost:$PORT/"

exit 0
