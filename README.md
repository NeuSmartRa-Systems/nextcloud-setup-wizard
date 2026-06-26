# 🚀 Nextcloud – Setup-Wizard

**Ein interaktives Bash‑Skript für die automatisierte Installation und Optimierung von Nextcloud auf Debian/Ubuntu.**

![GitHub stars](https://img.shields.io/github/stars/NeuSmartRa-Systems/nextcloud-setup-wizard)
![GitHub forks](https://img.shields.io/github/forks/NeuSmartRa-Systems/nextcloud-setup-wizard)
![GitHub issues](https://img.shields.io/github/issues/NeuSmartRa-Systems/nextcloud-setup-wizard)
![License](https://img.shields.io/github/license/NeuSmartRa-Systems/nextcloud-setup-wizard)

---

## 📸 Screenshots

<table>
  <tr>
    <td><img src="screenshots/start.png" alt="Startbildschirm" width="400"/></td>
    <td><img src="screenshots/config.png" alt="Konfigurationsmenü" width="400"/></td>
  </tr>
  <tr>
    <td><img src="screenshots/summary.png" alt="Zusammenfassung" width="400"/></td>
    <td><img src="screenshots/done.png" alt="Erfolgreiche Installation" width="400"/></td>
  </tr>
</table>

---

## ✨ Features auf einen Blick

| Bereich | Funktion |
|---------|----------|
| **Installation** | Apache2, MariaDB, Redis, Fail2ban, PHP‑Erweiterungen |
| **Optimierung** | PHP (upload, memory, opcache), MariaDB (InnoDB), Apache (mpm_prefork) |
| **Sicherheit** | MariaDB‑Härtung, Fail2ban‑Filter, Redis‑Passwort |
| **Betrieb** | Cron‑Job, Log‑Rotation, vollständiges Installations‑Log |
| **Erweitert** | Let's Encrypt, Web‑Updater, Redis‑Session, empfohlene Apps (Calendar, Contacts, Talk, OnlyOffice, Deck, Tasks, Notes) |

---

## 🖥️ Installation

```bash
# Repository klonen
git clone https://github.com/NeuSmartRa-Systems/nextcloud-setup-wizard.git
cd nextcloud-setup-wizard

# Skript ausführbar machen
chmod +x nc-setup-wizard.sh

# Installation starten (Root-Rechte werden automatisch verlangt)
sudo ./nc-setup-wizard.sh
```

Das Skript installiert fehlende Abhängigkeiten (`curl`, `gpg`, `sudo`, `gum`) selbstständig.

---

## ⚙️ Interaktive Konfiguration

Während der Ausführung wirst du Schritt für Schritt durch die Konfiguration geführt:

- **Pakete** (Apache, MariaDB, Redis, Fail2ban – jeweils optional)
- **Netzwerk** (Domain, lokale IP, Proxy‑IP, zusätzliche trusted_domains)
- **Admin‑Benutzer** (Name, Passwort – bei Leer‑Eingabe wird ein sicheres generiert)
- **Datenbank** (Name, Benutzer, Passwort, Root‑Passwort)
- **Pfade** (Installations‑ und Datenverzeichnis)
- **Optimierungen** (PHP, MariaDB, Fail2ban – mit sinnvollen Standardwerten)
- **Zusatzoptionen** (Let's Encrypt, Web‑Updater, Redis‑Session, erweiterte config.php, empfohlene Apps)

Nach Bestätigung der Zusammenfassung läuft die Installation **vollautomatisch** ab.

---

## 📂 Nach der Installation

| Was | Wo |
|-----|-----|
| **Zugang** | `http://<domain-oder-ip>` (bei Let's Encrypt HTTPS) |
| **Admin‑Credentials** | werden in der Abschlussausgabe angezeigt |
| **Installationsverzeichnis** | `/var/www/html/nextcloud` (Standard) |
| **Datenverzeichnis** | `/var/www/html/nextcloud/data` (Standard) |
| **Log‑Datei** | `/var/log/nextcloud-install.log` |

---

## 🎯 Warum dieses Skript?

- ❌ **Manuelle Installation** – viele Schritte, Fehleranfällig
- ✅ **Setup-Wizard** – 5 Minuten, interaktiv, optimiert, sicher

---

## 📜 Lizenz

**GNU General Public License v3.0** – Nutzung, Modifikation und Weitergabe erlaubt unter gleichen Bedingungen.

---

## 🤝 Beiträge

Issues und Pull Requests sind willkommen!  
Bei Fragen oder Verbesserungsvorschlägen einfach ein Issue öffnen.

---

## 🐛 Bekannte Fahler

- Das Script läuft durch und setzt Nexctloud auf. Beim Speichern der erweiterten config.php Einstelungen tritt ein Fehler auf, beeinträchtigt das Setup sonst aber nicht.
**Lösung:** Die erweiterten config.php Einstellungen vorerst nicht benutzen. 

---

<p align="center">
  <b>NeuSmartRa</b> | Systems – 2026
</p>
