#!/bin/bash
# add_samba_user.sh
# Usage: sudo ./add_samba_user.sh <username>
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Dieses Skript muss als root ausgeführt werden!" >&2
  exit 1
fi

if [ -z "$1" ]; then
  echo "Usage: $0 <username>" >&2
  exit 2
fi

username="$1"

# User ggf. anlegen (nur falls noch nicht vorhanden)
if ! id "$username" &>/dev/null; then
  useradd -M -s /usr/sbin/nologin "$username"
fi

# Samba-User anlegen (Passwort kommt per STDIN)
smbpasswd -a "$username"
