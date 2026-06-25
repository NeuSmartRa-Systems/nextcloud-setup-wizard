# Nextcloud Setup

**Interaktives Bash‑Skript zur automatisierten Installation und Optimierung von Nextcloud auf Debian/Ubuntu.**

![GPLv3](https://img.shields.io/badge/License-GPLv3-blue.svg)
![Bash](https://img.shields.io/badge/Bash-5.0+-green)

---

## Features

| Komponente | Funktion |
|------------|----------|
| **Installation** | Apache, MariaDB, Redis, Fail2ban, PHP‑Erweiterungen |
| **Optimierung** | PHP (upload, memory, opcache), MariaDB (InnoDB, connections), Apache (mpm_prefork) |
| **Sicherheit** | MariaDB‑Härtung, Fail2ban‑Filter für Nextcloud‑Logs |
| **Betrieb** | Cron‑Job (alle 5 min), vollständiges Logging (`/var/log/nextcloud-install.log`) |
| **Netzwerk** | Domain, lokale IP, Reverse‑Proxy (z.B. Caddy) |

---

## Installation

```bash
git clone https://github.com/NeuSmartRa/nextcloud-deploy.git
cd nextcloud-deploy
chmod +x nextcloud-deploy.sh
sudo ./nextcloud-deploy.sh
```

Das Skript prüft und installiert fehlende Abhängigkeiten (`curl`, `gpg`, `sudo`, `gum`) automatisch.

---

## Konfigurationsoptionen

| Bereich | Abfrage |
|---------|---------|
| **Pakete** | Apache, MariaDB, Redis, Fail2ban (ja/nein) |
| **Netzwerk** | Domain, lokale IP, Proxy‑IP (optional) |
| **Admin** | Benutzername / Passwort (generiert bei Leer‑Eingabe) |
| **Datenbank** | Name, Benutzer, Passwort (generiert bei Leer‑Eingabe) |
| **Optimierung** | PHP, MariaDB, Fail2ban (mit Standardvorschlägen) |
| **Pfad** | Installationsverzeichnis (Standard: `/var/www/html/nextcloud`) |

Nach der Bestätigung der Zusammenfassung läuft die Installation vollautomatisch.

---

## Nach der Installation

- **Zugang:** `http://<domain-oder-ip>`
- **Admin‑Credentials:** werden in der Abschlussausgabe angezeigt
- **Installationsverzeichnis:** `/var/www/html/nextcloud`
- **Log‑Datei:** `/var/log/nextcloud-install.log`

Für HTTPS wird der Einsatz von **Caddy** oder **Certbot** empfohlen.

---

## Lizenz

**GNU General Public License v3.0**  
Nutzung, Modifikation und Weitergabe erlaubt – jedoch nur unter gleichen Lizenzbedingungen. Kommerzielle Nutzung ist gestattet, jedoch nicht als proprietäres Produkt.

---

## Beiträge

Issues und Pull Requests werden bearbeitet.

---

<p align="center">
  NeuSmartRa | Systems – 2026
</p>
