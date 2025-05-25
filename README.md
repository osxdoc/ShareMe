# ShareMe - Samba Web Manager

ShareMe ist eine Webanwendung zur Verwaltung von Samba-Freigaben und Benutzern über eine benutzerfreundliche Weboberfläche. Die Anwendung ermöglicht die Konfiguration von Samba-Shares, Benutzerverwaltung und mehr - alles über einen Webbrowser.

## Funktionen

- Verwaltung von Samba-Freigaben (Erstellen, Bearbeiten, Löschen)
- Benutzerverwaltung (Erstellen, Löschen, Passwort zurücksetzen)
- Übersichtliches Dashboard
- Mehrsprachige Benutzeroberfläche (Deutsch)
- Responsive Design für Desktop und mobile Geräte

## Voraussetzungen

- Debian Linux oder Ubuntu
- Superuser-Rechte für die Installation und Konfiguration

## Installation

### Automatische Installation (empfohlen)

Für eine einfache Installation verwenden Sie das mitgelieferte Installationsskript:

```bash
# Stellen Sie sicher, dass Sie Root-Rechte haben oder sudo verwenden können
sudo ./install.sh
```

Das Skript führt automatisch alle notwendigen Schritte aus:

1. Installation aller benötigten Pakete (Python, Samba, Nginx, etc.)
2. Erstellung eines dedizierten Benutzers für die Anwendung
3. Einrichtung der Verzeichnisstruktur und Berechtigungen
4. Konfiguration von Samba für den Webzugriff
5. Einrichtung eines Systemdienstes
6. Konfiguration von Nginx als Reverse-Proxy
7. Starten aller Dienste

Nach Abschluss der Installation können Sie auf die Anwendung über http://ihre-server-ip zugreifen.

### Manuelle Installation

Wenn Sie die Installation lieber manuell durchführen möchten, finden Sie eine detaillierte Anleitung in der Datei [MANUAL_INSTALL.md](MANUAL_INSTALL.md).

## Nach der Installation

### Zugriff auf die Anwendung

Nach erfolgreicher Installation können Sie auf die Anwendung über einen Webbrowser zugreifen:

```
http://ihre-server-ip
```

Die Standardanmeldedaten sind:
- **Benutzername**: admin
- **Passwort**: admin

### Erste Schritte

1. Melden Sie sich mit den Standardanmeldedaten an
2. Ändern Sie sofort das Admin-Passwort
3. Erstellen Sie Ihre ersten Samba-Freigaben
4. Fügen Sie Benutzer hinzu, die auf die Freigaben zugreifen dürfen

## Fehlerbehebung

### Probleme mit Berechtigungen

Wenn Sie Probleme mit Berechtigungen haben:

```bash
# Überprüfen Sie die Berechtigungen der smb.conf
ls -la /etc/samba/smb.conf

# Stellen Sie sicher, dass der Benutzer, unter dem die Anwendung läuft, 
# die entsprechenden sudo-Rechte hat
sudo grep shareme /etc/sudoers /etc/sudoers.d/*
```

### Dienst startet nicht

Wenn der Dienst nicht startet:

```bash
# Überprüfen Sie die Logs
sudo journalctl -u shareme.service

# Stellen Sie sicher, dass die Pfade in der Service-Datei korrekt sind
sudo systemctl status shareme.service
```

### Samba-Dienste neu starten

Wenn Änderungen nicht übernommen werden:

```bash
sudo systemctl restart smbd
sudo systemctl restart nmbd
```

## Sicherheitshinweise

- Die Standardanmeldedaten sind `admin`/`admin`. Ändern Sie diese nach der ersten Anmeldung!
- Für den Produktionseinsatz sollte HTTPS konfiguriert werden
- Stellen Sie sicher, dass die Webanwendung nur aus vertrauenswürdigen Netzwerken erreichbar ist

## Lizenz

MIT

## Autor

Erstellt mit Cascade AI
