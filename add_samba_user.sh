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

# Lese zwei Passwörter von STDIN
read -r password1
read -r password2

if [ "$password1" != "$password2" ]; then
  echo "Passwörter stimmen nicht überein!" >&2
  exit 3
fi

echo -e "$password1\n$password2" | smbpasswd -s -a "$username"
