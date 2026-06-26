# 🚀 Nextcloud – Setup-Wizard
**Ein interaktives Bash‑Skript für die automatisierte Installation und Optimierung von Nextcloud auf Debian/Ubuntu.**

![GitHub stars](https://img.shields.io/github/stars/NeuSmartRa-Systems/nextcloud-setup-wizard)
![GitHub forks](https://img.shields.io/github/forks/NeuSmartRa-Systems/nextcloud-setup-wizard)
![GitHub issues](https://img.shields.io/github/issues/NeuSmartRa-Systems/nextcloud-setup-wizard)
![License](https://img.shields.io/github/license/NeuSmartRa-Systems/nextcloud-setup-wizard)
---

## ✨ Features

- **All-in-One:** Apache2, MariaDB, Redis, Fail2ban, PHP‑Erweiterungen
- **Optimierung:** PHP (upload, memory, opcache), MariaDB (InnoDB), Apache (mpm_prefork)
- **Sicherheit:** MariaDB‑Härtung, Fail2ban‑Filter für Nextcloud‑Logs, Redis‑Passwort
- **Betrieb:** Cron‑Job, Log‑Rotation, vollständiges Installations‑Log
- **Erweitert:** Let’s Encrypt, Web‑Updater, Redis‑Session, empfohlene Apps (Calendar, Contacts, Talk, OnlyOffice, Deck, Tasks, Notes)

---

## 🖥️ Installation

```bash
git clone https://github.com/NeuSmartRa-Systems/nextcloud-setup-wizard.git
cd nextcloud-setup-wizard
chmod +x nc-setup-wizard.sh.sh
sudo ./nc-setup-wizard.sh.sh
```

Das Skript installiert fehlende Abhängigkeiten (curl, gpg, sudo, gum) selbstständig.

---

## ⚙️ Interaktive Konfiguration

Während der Ausführung werden Sie Schritt für Schritt gefragt:

- **Pakete** (Apache, MariaDB, Redis, Fail2ban)
- **Netzwerk** (Domain, lokale IP, Proxy‑IP, trusted_domains)
- **Admin‑Benutzer** (Name, Passwort – bei Leer‑Eingabe wird eines generiert)
- **Datenbank** (Name, Benutzer, Passwort, Root‑Passwort)
- **Pfade** (Installations‑ und Datenverzeichnis)
- **Optimierungen** (PHP, MariaDB, Fail2ban – mit sinnvollen Standardwerten)
- **Zusatzoptionen** (Let’s Encrypt, Web‑Updater, Redis‑Session, erweiterte config.php, empfohlene Apps)

Nach Bestätigung der Zusammenfassung läuft die Installation vollautomatisch.

---

## 📂 Nach der Installation

- **Zugang:** `http://<domain-oder-ip>` (bei Let’s Encrypt HTTPS)
- **Admin‑Credentials:** werden in der Abschlussausgabe angezeigt
- **Installationsverzeichnis:** `/var/www/html/nextcloud` (Standard)
- **Log‑Datei:** `/var/log/nextcloud-install.log`

---

## 📜 Lizenz

**GNU General Public License v3.0** – Nutzung, Modifikation und Weitergabe erlaubt unter gleichen Bedingungen.

---

## 🤝 Beiträge

Issues und Pull Requests sind willkommen.

---

<p align="center">
  NeuSmartRa | Systems – 2026
</p>
