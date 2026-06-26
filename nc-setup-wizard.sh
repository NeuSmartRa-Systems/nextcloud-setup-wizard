#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════╗
# ║                                                                   ║
# ║       █     █                                        ███████      ║
# ║       ██    █                                        █     █      ║
# ║       █ █   █               s m a r t                █     █      ║
# ║       █  █  █            ───  systems  ───           ███████      ║
# ║       █   █ █                                        █   █        ║
# ║       █    ██                                        █    █       ║
# ║       █     █                                        █     █      ║
# ║                                                                   ║
# ║ ────────────────────────────────────────────────────────────────  ║
# ║       Nextcloud – Zero-Touch Deployment Engine                    ║
# ║       Caddy-Proxy-Integration (optional, separates Skript)        ║
# ║ ────────────────────────────────────────────────────────────────  ║
# ║         © 2026 NeuSmartRa  │  Systems  │  Release v0.0.1          ║
# ║                                                                   ║
# ╚═══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Globale Variablen ──────────────────────────────────────────────────────

readonly NRS_BLUE="39"
readonly NRS_CYAN="87"
readonly NRS_GRAY="247"
readonly NRS_GOLD="220"
readonly NRS_WHITE="255"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/nextcloud-install.log"
readonly CONFIG_BACKUP_DIR="/root/nextcloud-setup-backups"

# Standardwerte für die erweiterten Konfigurationsparameter
declare -A CONFIG_DEFAULTS=(
  [default_language]="de_DE"
  [default_locale]="de_DE"
  [default_phone_region]="DE"
  [loglevel]="2"
  [logtimezone]="Europe/Berlin"
  [log_rotate_size]="104857600"
  [maintenance_window_start]="1"
  [overwriteprotocol]="https"
  [overwritewebroot]=""
  [htaccess.RewriteBase]="/"
  [filesystem_check_changes]="0"
  [server_id]="cloudspace_srv_01"
  [updater.enabled]="true"
)

# Diese Variablen werden während der Abfragen gefüllt
INSTALL_DIR=""
DOMAIN=""
SERVER_IP=""
PROXY_IP=""
ADMIN_USER=""
ADMIN_PASSWORD=""
DB_NAME=""
DB_USER=""
DB_PASSWORD=""
MARIADB_ROOT_PASSWORD=""
DATA_DIR=""
TRUSTED_DOMAINS_EXTRA=()

# Installationsflags
apache_install="false"
mariadb_install="false"
redis_install="false"
fail2ban_install="false"
proxy_use="false"
php_optimize="false"
mariadb_optimize="false"
fail2ban_optimize="false"
web_updater="true"
redis_session="true"
letsencrypt="false"
advanced_config="false"
install_recommended_apps="false"

# Redis Passwort (wird später generiert)
REDIS_PASSWORD=""

# Optimierungswerte (mit Defaults)
PHP_UPLOAD_MAX="100G"
PHP_POST_MAX="0"
PHP_MEMORY_LIMIT="4096M"
PHP_MAX_EXEC="7200"
PHP_MAX_INPUT="7200"
DEFAULT_OPCACHE_STR="16"
DEFAULT_OPCACHE_MEM="256"
DEFAULT_OPCACHE_FILES="10000"
DEFAULT_OPCACHE_REVALIDATE="60"
DEFAULT_MPM_START="5"
DEFAULT_MPM_MIN="5"
DEFAULT_MPM_MAX="20"
DEFAULT_MPM_WORKERS="1000"
DEFAULT_MPM_CONN="10000"
INNODB_POOL="8G"
INNODB_LOG="2G"
MYSQL_MAX_CONN="1000"
FAIL2BAN_MAXRETRY="5"
FAIL2BAN_BANTIME="3600"
FAIL2BAN_FINDTIME="600"
REDIS_HOST="localhost"
REDIS_PORT="6379"

# ─── Hilfsfunktionen ──────────────────────────────────────────────────────

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

error_exit() {
  echo "⛔ FEHLER: $*" >&2
  log "FEHLER: $*"
  exit 1
}

run_with_spinner() {
  local title="$1"
  shift
  local cmd=("$@")

  echo -n "$title ... "
  {
    "${cmd[@]}" >> "$LOG_FILE" 2>&1
  } &
  local pid=$!

  local spin='-\|/'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i+1) % 4 ))
    printf "\r$title ... ${spin:$i:1} "
    sleep 0.2
  done

  wait "$pid"
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
    printf "\r✅ $title abgeschlossen.     \n"
  else
    printf "\r❌ $title fehlgeschlagen (Fehlercode %s). Siehe Log: %s\n" "$exit_code" "$LOG_FILE"
    exit "$exit_code"
  fi
}

# ─── Prüfungen & Gum-Installation ──────────────────────────────────────

check_prerequisites() {
  if ! command -v sudo &>/dev/null; then
    echo "❌ sudo ist nicht installiert. Installiere jetzt …"
    apt update && apt install -y sudo
  fi
  export SUDO="sudo"

  $SUDO apt update
  $SUDO apt install -y curl gpg

  if ! command -v gum &>/dev/null; then
    echo "❌ gum ist nicht installiert. Möchtest du es automatisch installieren? (j/N)"
    read -r answer
    if [[ "$answer" =~ ^[JjYy]$ ]]; then
      install_gum
    else
      echo "⛔ Ohne gum kann das Skript nicht ausgeführt werden. Beende …"
      exit 1
    fi
  fi

  if [[ $EUID -ne 0 ]]; then
    echo "⚠️  Dieses Skript benötigt Root‑Rechte. Bitte mit sudo ausführen." >&2
    exit 1
  fi
}

install_gum() {
  log "Installiere gum …"
  if command -v apt &>/dev/null; then
    $SUDO mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | $SUDO gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | $SUDO tee /etc/apt/sources.list.d/charm.list >/dev/null
    $SUDO apt update
    $SUDO apt install -y gum
  else
    error_exit "Kein apt gefunden – nur Debian/Ubuntu werden unterstützt."
  fi
}

# ─── Banner ──────────────────────────────────────────────────────────────

show_banner() {
  gum style \
    --border double \
    --border-foreground "$NRS_BLUE" \
    --padding "1 4" \
    --margin "0 2" \
    --foreground "$NRS_WHITE" \
    "
  $(gum style --foreground "$NRS_BLUE" --bold "█     █")                                        $(gum style --foreground "$NRS_BLUE" --bold "███████")
  $(gum style --foreground "$NRS_BLUE" --bold "██    █")                                        $(gum style --foreground "$NRS_BLUE" --bold "█     █")
  $(gum style --foreground "$NRS_BLUE" --bold "█ █   █")               $(gum style --foreground "$NRS_CYAN" "s m a r t")                $(gum style --foreground "$NRS_BLUE" --bold "█     █")
  $(gum style --foreground "$NRS_BLUE" --bold "█  █  █")            $(gum style --foreground "$NRS_GRAY" "───  systems  ───")           $(gum style --foreground "$NRS_BLUE" --bold "███████")
  $(gum style --foreground "$NRS_BLUE" --bold "█   █ █")                                        $(gum style --foreground "$NRS_BLUE" --bold "█   █")
  $(gum style --foreground "$NRS_BLUE" --bold "█    ██")                                        $(gum style --foreground "$NRS_BLUE" --bold "█    █")
  $(gum style --foreground "$NRS_BLUE" --bold "█     █")                                        $(gum style --foreground "$NRS_BLUE" --bold "█     █")
  ────────────────────────────────────────────────────────────────
  $(gum style --foreground "$NRS_GOLD" "")  $(gum style --foreground "$NRS_CYAN" "Nextcloud – Setup v2.1")
  ────────────────────────────────────────────────────────────────
  $(gum style --foreground "$NRS_GOLD" "© 2026 NeuSmartRa  │  Systems  │  Release v0.0.1")
  "
}

# ─── Passwortabfrage mit Wiederholung ──────────────────────────────────

ask_password_with_confirm() {
  local prompt="$1"
  local placeholder="$2"
  local password=""
  local password_confirm=""

  while true; do
    password=$(gum input --password --placeholder "$placeholder" --prompt "$prompt")
    if [[ -z "$password" ]]; then
      password=$(openssl rand -base64 12)
      gum style --foreground "$NRS_GOLD" "⚠️  Generiertes Passwort: $password"
      echo "$password"
      return 0
    fi

    password_confirm=$(gum input --password --placeholder "Passwort wiederholen" --prompt "🔁 $prompt (wiederholen): ")
    if [[ "$password" == "$password_confirm" ]]; then
      echo "$password"
      return 0
    else
      gum style --foreground 196 "⛔ Passwörter stimmen nicht überein. Bitte erneut versuchen."
    fi
  done
}

# ─── Interaktive Konfiguration (erweitert) ────────────────────────────

ask_values() {
  gum style --foreground "$NRS_CYAN" "⚙️  Bitte konfigurieren Sie Ihr Setup (Enter = Standardwert):"

  # ---- Paketauswahl ----
  echo -n "Apache2 (Webserver) installieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && apache_install="true" || apache_install="false"

  echo -n "MariaDB (Datenbank) installieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && mariadb_install="true" || mariadb_install="false"

  echo -n "Redis (Cache) installieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && redis_install="true" || redis_install="false"

  echo -n "Fail2ban (Schutz) installieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && fail2ban_install="true" || fail2ban_install="false"

  # ---- Netzwerk ----
  echo -n "Soll die Nextcloud von außen (Domain) erreichbar sein? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    DOMAIN=$(gum input --placeholder "nextcloud.example.de" --value "$(hostname -f)" --prompt "🌐  Domain (für Nextcloud): ")
    [[ -z "$DOMAIN" ]] && DOMAIN="$(hostname -f)"
  else
    DOMAIN=""
  fi

  echo -n "Soll die Nextcloud über die lokale IP zugänglich sein? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    SERVER_IP=$(gum input --placeholder "192.168.100.10" --value "192.168.100.10" --prompt "🌍  IP des Servers (lokal): ")
    [[ -z "$SERVER_IP" ]] && SERVER_IP="192.168.100.10"
  else
    SERVER_IP=""
  fi

  # ---- Reverse Proxy ----
  echo -n "Soll ein Reverse-Proxy verwendet werden? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    proxy_use="true"
    PROXY_IP=$(gum input --placeholder "192.168.100.23" --prompt "🔒  IP des Reverse-Proxys: ")
    [[ -z "$PROXY_IP" ]] && PROXY_IP="192.168.100.23"
    echo "ℹ️  Für die Einrichtung eines Reverse-Proxys wird das Script 'Caddy – Zero-Touch Deployment Engine' empfohlen."
  else
    proxy_use="false"
    PROXY_IP=""
  fi

  # ---- Weitere trusted_domains (kommagetrennt) ----
  echo -n "Möchtest du weitere trusted_domains hinzufügen? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    extra_domains=$(gum input --placeholder "domain2.de, 10.0.0.5, proxy.example.com" --prompt "📌  Weitere Domains/IPs (kommagetrennt): ")
    if [[ -n "$extra_domains" ]]; then
      IFS=',' read -ra TRUSTED_DOMAINS_EXTRA <<< "$extra_domains"
    fi
  fi

  # ---- Admin ----
  ADMIN_USER=$(gum input --placeholder "admin" --value "admin" --prompt "👤  Admin-Benutzername: ")
  [[ -z "$ADMIN_USER" ]] && ADMIN_USER="admin"
  ADMIN_PASSWORD=$(ask_password_with_confirm "🔑  Admin-Passwort: " "mindestens 8 Zeichen")

  # ---- MariaDB Root-Passwort (getrennt) ----
  if [[ "$mariadb_install" == "true" ]]; then
    MARIADB_ROOT_PASSWORD=$(ask_password_with_confirm "🔑  MariaDB Root-Passwort: " "sicheres Passwort für root")
    DB_NAME=$(gum input --placeholder "nextcloud" --value "nextcloud" --prompt "🗄️  Datenbankname: ")
    [[ -z "$DB_NAME" ]] && DB_NAME="nextcloud"
    DB_USER=$(gum input --placeholder "nextclouduser" --value "nextclouduser" --prompt "👤  Datenbank-Benutzer: ")
    [[ -z "$DB_USER" ]] && DB_USER="nextclouduser"
    DB_PASSWORD=$(ask_password_with_confirm "🔑  Datenbank-Passwort für $DB_USER: " "sicheres Passwort")
  fi

  # ---- Datenverzeichnis ----
  DATA_DIR=$(gum input --placeholder "/var/www/html/nextcloud/data" --value "/var/www/html/nextcloud/data" --prompt "📁  Datenverzeichnis (separater Pfad möglich): ")
  [[ -z "$DATA_DIR" ]] && DATA_DIR="/var/www/html/nextcloud/data"

  # ---- Installationsverzeichnis ----
  INSTALL_DIR=$(gum input --placeholder "/var/www/html/nextcloud" --value "/var/www/html/nextcloud" --prompt "📁  Installationsverzeichnis: ")
  [[ -z "$INSTALL_DIR" ]] && INSTALL_DIR="/var/www/html/nextcloud"

  # ---- Optimierungen (PHP, MariaDB, Fail2ban) ----
  echo -n "Soll PHP optimiert werden? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    php_optimize="true"
    PHP_UPLOAD_MAX=$(gum input --placeholder "100G" --value "100G" --prompt "📤  upload_max_filesize: ")
    PHP_POST_MAX=$(gum input --placeholder "0" --value "0" --prompt "📥  post_max_size (0 = unbeschränkt): ")
    PHP_MEMORY_LIMIT=$(gum input --placeholder "4096M" --value "4096M" --prompt "🧠  memory_limit: ")
    PHP_MAX_EXEC=$(gum input --placeholder "7200" --value "7200" --prompt "⏱️  max_execution_time (Sekunden): ")
    PHP_MAX_INPUT=$(gum input --placeholder "7200" --value "7200" --prompt "⏱️  max_input_time (Sekunden): ")
  fi

  if [[ "$mariadb_install" == "true" ]]; then
    echo -n "Soll MariaDB optimiert werden? (j/N) "
    read -r answer
    if [[ "$answer" =~ ^[JjYy]$ ]]; then
      mariadb_optimize="true"
      INNODB_POOL=$(gum input --placeholder "8G" --value "8G" --prompt "🗄️  innodb_buffer_pool_size: ")
      INNODB_LOG=$(gum input --placeholder "2G" --value "2G" --prompt "📄 innodb_log_file_size: ")
      MYSQL_MAX_CONN=$(gum input --placeholder "1000" --value "1000" --prompt "🔗 max_connections: ")
    fi
  fi

  if [[ "$fail2ban_install" == "true" ]]; then
    echo -n "Soll Fail2ban optimiert werden? (j/N) "
    read -r answer
    if [[ "$answer" =~ ^[JjYy]$ ]]; then
      fail2ban_optimize="true"
      FAIL2BAN_MAXRETRY=$(gum input --placeholder "5" --value "5" --prompt "🔐  maxretry: ")
      FAIL2BAN_BANTIME=$(gum input --placeholder "3600" --value "3600" --prompt "⏳  bantime (Sekunden): ")
      FAIL2BAN_FINDTIME=$(gum input --placeholder "600" --value "600" --prompt "⏳  findtime (Sekunden): ")
    fi
  fi

  # ---- NEU: Web-Updater ----
  echo -n "Web-Updater (Nextcloud-eigener Update-Assistant) aktivieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && web_updater="true" || web_updater="false"

  # ---- NEU: Redis-Session ----
  if [[ "$redis_install" == "true" ]]; then
    echo -n "Redis auch für PHP-Sessions verwenden? (j/N) "
    read -r answer
    [[ "$answer" =~ ^[JjYy]$ ]] && redis_session="true" || redis_session="false"
  else
    redis_session="false"
  fi

  # ---- NEU: Let's Encrypt ----
  if [[ -n "$DOMAIN" ]]; then
    echo -n "SSL-Zertifikat mit Let's Encrypt einrichten? (j/N) "
    read -r answer
    [[ "$answer" =~ ^[JjYy]$ ]] && letsencrypt="true" || letsencrypt="false"
  fi

  # ---- NEU: Erweiterte config.php-Parameter ----
  echo -n "Möchtest du erweiterte Nextcloud-Konfigurationsparameter festlegen? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
    advanced_config="true"
    ask_advanced_config
  else
    advanced_config="false"
  fi

  # ---- NEU: Empfohlene Apps vorinstallieren ----
  echo -n "Möchtest du empfohlene Nextcloud-Apps (Calendar, Contacts, Talk, OnlyOffice, Deck, Tasks, Notes) vorinstallieren? (j/N) "
  read -r answer
  [[ "$answer" =~ ^[JjYy]$ ]] && install_recommended_apps="true" || install_recommended_apps="false"

  # ---- Zusammenfassung anzeigen ----
  show_summary
}

# ─── Abfrage der erweiterten config.php-Parameter ──────────────────

ask_advanced_config() {
  gum style --foreground "$NRS_CYAN" "🔧  Erweiterte Nextcloud-Konfiguration"

  # Kategorie: Sicherheit
  gum style --foreground "$NRS_GOLD" "── Sicherheit ──"
  CONFIG_overwriteprotocol=$(gum choose --header "overwriteprotocol (http/https)" "http" "https")
  CONFIG_loglevel=$(gum choose --header "Loglevel (0=Debug, 1=Info, 2=Warning, 3=Error, 4=Fatal)" "0" "1" "2" "3" "4")
  if [[ "$proxy_use" == "true" ]]; then
    extra_proxy=$(gum input --placeholder "$PROXY_IP" --prompt "🔒  Weitere trusted_proxies (kommagetrennt, optional): ")
    if [[ -n "$extra_proxy" ]]; then
      IFS=',' read -ra CONFIG_trusted_proxies_extra <<< "$extra_proxy"
    fi
  fi

  # Kategorie: Lokalisierung
  gum style --foreground "$NRS_GOLD" "── Lokalisierung ──"
  CONFIG_default_language=$(gum input --placeholder "${CONFIG_DEFAULTS[default_language]}" --value "${CONFIG_DEFAULTS[default_language]}" --prompt "🌐  default_language: ")
  [[ -z "$CONFIG_default_language" ]] && CONFIG_default_language="${CONFIG_DEFAULTS[default_language]}"
  CONFIG_default_locale=$(gum input --placeholder "${CONFIG_DEFAULTS[default_locale]}" --value "${CONFIG_DEFAULTS[default_locale]}" --prompt "🌍  default_locale: ")
  [[ -z "$CONFIG_default_locale" ]] && CONFIG_default_locale="${CONFIG_DEFAULTS[default_locale]}"
  CONFIG_default_phone_region=$(gum input --placeholder "${CONFIG_DEFAULTS[default_phone_region]}" --value "${CONFIG_DEFAULTS[default_phone_region]}" --prompt "📞  default_phone_region: ")
  [[ -z "$CONFIG_default_phone_region" ]] && CONFIG_default_phone_region="${CONFIG_DEFAULTS[default_phone_region]}"

  # Kategorie: Performance
  gum style --foreground "$NRS_GOLD" "── Performance ──"
  CONFIG_maintenance_window_start=$(gum input --placeholder "${CONFIG_DEFAULTS[maintenance_window_start]}" --value "${CONFIG_DEFAULTS[maintenance_window_start]}" --prompt "⏰  maintenance_window_start (Stunde, 0-23): ")
  [[ -z "$CONFIG_maintenance_window_start" ]] && CONFIG_maintenance_window_start="${CONFIG_DEFAULTS[maintenance_window_start]}"
  CONFIG_filesystem_check_changes=$(gum choose --header "filesystem_check_changes (0=deaktiviert, 1=aktiviert)" "0" "1")

  # Kategorie: Logging
  gum style --foreground "$NRS_GOLD" "── Logging ──"
  CONFIG_logtimezone=$(gum input --placeholder "${CONFIG_DEFAULTS[logtimezone]}" --value "${CONFIG_DEFAULTS[logtimezone]}" --prompt "🕒  logtimezone: ")
  [[ -z "$CONFIG_logtimezone" ]] && CONFIG_logtimezone="${CONFIG_DEFAULTS[logtimezone]}"
  CONFIG_log_rotate_size=$(gum input --placeholder "${CONFIG_DEFAULTS[log_rotate_size]}" --value "${CONFIG_DEFAULTS[log_rotate_size]}" --prompt "📄  log_rotate_size (Bytes): ")
  [[ -z "$CONFIG_log_rotate_size" ]] && CONFIG_log_rotate_size="${CONFIG_DEFAULTS[log_rotate_size]}"

  # Kategorie: Erweitert
  gum style --foreground "$NRS_GOLD" "── Erweitert ──"
  CONFIG_server_id=$(gum input --placeholder "${CONFIG_DEFAULTS[server_id]}" --value "${CONFIG_DEFAULTS[server_id]}" --prompt "🆔  server_id: ")
  [[ -z "$CONFIG_server_id" ]] && CONFIG_server_id="${CONFIG_DEFAULTS[server_id]}"
  CONFIG_overwritewebroot=$(gum input --placeholder "${CONFIG_DEFAULTS[overwritewebroot]}" --value "${CONFIG_DEFAULTS[overwritewebroot]}" --prompt "📂  overwritewebroot (leer lassen für Standard): ")
  CONFIG_htaccess_RewriteBase=$(gum input --placeholder "${CONFIG_DEFAULTS[htaccess.RewriteBase]}" --value "${CONFIG_DEFAULTS[htaccess.RewriteBase]}" --prompt "🔧  htaccess.RewriteBase: ")
  [[ -z "$CONFIG_htaccess_RewriteBase" ]] && CONFIG_htaccess_RewriteBase="${CONFIG_DEFAULTS[htaccess.RewriteBase]}"

  # Updater überschreiben, falls web_updater deaktiviert
  if [[ "$web_updater" == "false" ]]; then
    CONFIG_updater_enabled="false"
  else
    CONFIG_updater_enabled="true"
  fi
}

# ─── Zusammenfassung ──────────────────────────────────────────────────

show_summary() {
  echo ""
  gum style --foreground "$NRS_WHITE" "📋  Zusammenfassung Ihrer Eingaben:"
  [[ -n "$DOMAIN" ]] && gum style --foreground "$NRS_WHITE" "   Domain:                   $DOMAIN"
  [[ -n "$SERVER_IP" ]] && gum style --foreground "$NRS_WHITE" "   Server-IP:                $SERVER_IP"
  [[ "$proxy_use" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Proxy-IP:                 $PROXY_IP"
  gum style --foreground "$NRS_WHITE" "   Admin-Benutzer:           $ADMIN_USER"
  gum style --foreground "$NRS_WHITE" "   Admin-Passwort:           ••••••••"
  [[ "$mariadb_install" == "true" ]] && {
    gum style --foreground "$NRS_WHITE" "   MariaDB Root-Passwort:    ••••••••"
    gum style --foreground "$NRS_WHITE" "   DB-Name:                  $DB_NAME"
    gum style --foreground "$NRS_WHITE" "   DB-User:                  $DB_USER"
    gum style --foreground "$NRS_WHITE" "   DB-Passwort:              ••••••••"
  }
  gum style --foreground "$NRS_WHITE" "   Installationsverzeichnis: $INSTALL_DIR"
  gum style --foreground "$NRS_WHITE" "   Datenverzeichnis:          $DATA_DIR"
  [[ "$apache_install" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Apache:                   aktiviert"
  [[ "$mariadb_install" == "true" ]] && gum style --foreground "$NRS_WHITE" "   MariaDB:                  aktiviert"
  [[ "$redis_install" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Redis:                    aktiviert"
  [[ "$fail2ban_install" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Fail2ban:                 aktiviert"
  [[ "$php_optimize" == "true" ]] && gum style --foreground "$NRS_WHITE" "   PHP-Optimierung:          aktiviert"
  [[ "$mariadb_optimize" == "true" ]] && gum style --foreground "$NRS_WHITE" "   MariaDB-Optimierung:      aktiviert"
  [[ "$fail2ban_optimize" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Fail2ban-Optimierung:     aktiviert"
  [[ "$web_updater" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Web-Updater:              aktiviert"
  [[ "$redis_session" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Redis-Session:            aktiviert"
  [[ "$letsencrypt" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Let's Encrypt:            aktiviert"
  [[ "$advanced_config" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Erweiterte Config:        benutzerdefiniert"
  [[ "$install_recommended_apps" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Empfohlene Apps:          werden installiert"
  echo ""

  if ! gum confirm "Mit diesen Daten fortfahren?" --affirmative "Ja, los!" --negative "Abbrechen"; then
    gum style --foreground "$NRS_GRAY" "⏹️  Abgebrochen."
    exit 0
  fi
}

# ─── Installationsfunktionen ──────────────────────────────────────────

install_dependencies() {
  log "Aktualisiere Paketlisten …"
  $SUDO apt update

  local packages=()
  packages+=(wget unzip curl ca-certificates rsync cron bzip2)

  if [[ "$apache_install" == "true" ]]; then
    packages+=(apache2 libapache2-mod-php)
  fi

  if [[ "$mariadb_install" == "true" ]]; then
    packages+=(mariadb-server)
  fi

  packages+=(php-{curl,gd,intl,mbstring,mysql,xml,zip,bcmath,json,common,opcache,imagick,apcu,gmp})
  if [[ "$redis_install" == "true" ]]; then
    packages+=(php-redis)
  fi
  packages+=(php-smbclient smbclient libsmbclient-dev)

  if [[ "$redis_install" == "true" ]]; then
    packages+=(redis-server)
  fi

  if [[ "$fail2ban_install" == "true" ]]; then
    packages+=(fail2ban)
  fi

  if [[ "$letsencrypt" == "true" ]]; then
    packages+=(certbot python3-certbot-apache)
  fi

  # logrotate ist meist schon installiert, aber sicherheitshalber
  packages+=(logrotate)

  log "Installiere benötigte Pakete: ${packages[*]}"
  $SUDO apt install -y "${packages[@]}"

  $SUDO phpenmod intl mbstring bcmath gd curl xml zip imagick apcu || true
  [[ "$redis_install" == "true" ]] && $SUDO phpenmod redis || true

  [[ "$apache_install" == "true" ]] && $SUDO systemctl restart apache2 && $SUDO systemctl enable apache2
  [[ "$mariadb_install" == "true" ]] && $SUDO systemctl enable --now mariadb
  [[ "$redis_install" == "true" ]] && $SUDO systemctl enable --now redis-server
  [[ "$fail2ban_install" == "true" ]] && $SUDO systemctl enable --now fail2ban
}

secure_mariadb() {
  log "Sichere MariaDB-Installation …"
  $SUDO mysql <<EOF
  ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
EOF
}

create_nextcloud_db() {
  log "Lege Datenbank '${DB_NAME}' und Benutzer '${DB_USER}' an …"
  $SUDO mysql -u root -p"$MARIADB_ROOT_PASSWORD" <<EOF
  CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
  CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
  GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
  FLUSH PRIVILEGES;
EOF
}

download_nextcloud() {
  local tmp_dir="/tmp/nextcloud-install"
  log "Lade Nextcloud herunter …"
  mkdir -p "$tmp_dir"
  cd "$tmp_dir"
  wget -q https://download.nextcloud.com/server/releases/latest.tar.bz2 || error_exit "Download fehlgeschlagen."
  tar -xjf latest.tar.bz2
  $SUDO rsync -a nextcloud/ "$INSTALL_DIR"
  $SUDO chown -R www-data:www-data "$INSTALL_DIR"
  $SUDO chmod -R 755 "$INSTALL_DIR"
  cd /tmp
  rm -rf "$tmp_dir"
}

configure_apache() {
  local conf_file="/etc/apache2/sites-available/${DOMAIN:-default}.conf"
  local server_name="${DOMAIN:-localhost}"
  log "Konfiguriere Apache für ${server_name} …"
  $SUDO tee "$conf_file" >/dev/null <<EOF
  <VirtualHost *:80>
  ServerName ${server_name}
  DocumentRoot ${INSTALL_DIR}

  <Directory ${INSTALL_DIR}>
  Options +FollowSymlinks
  AllowOverride All
  Require all granted
  <IfModule mod_dav.c>
  Dav off
  </IfModule>
  SetEnv HOME ${INSTALL_DIR}
  SetEnv HTTP_HOME ${INSTALL_DIR}
  </Directory>

  # Apache-Upload-Limit auf 0 (unbegrenzt) setzen
  LimitRequestBody 0

  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
  </VirtualHost>
EOF
  if [[ -n "$DOMAIN" ]]; then
    $SUDO a2ensite "${DOMAIN}.conf"
  else
    $SUDO a2ensite "default.conf"
  fi
  $SUDO a2dissite 000-default.conf
  $SUDO a2enmod rewrite headers env dir mime
  $SUDO systemctl reload apache2
}

run_nextcloud_install() {
  log "Führe Nextcloud-Installation aus …"
  # Datenverzeichnis erstellen, falls nicht vorhanden
  $SUDO mkdir -p "$DATA_DIR"
  $SUDO chown www-data:www-data "$DATA_DIR"

  $SUDO -u www-data php "$INSTALL_DIR/occ" maintenance:install \
    --database="mysql" \
    --database-name="$DB_NAME" \
    --database-user="$DB_USER" \
    --database-pass="$DB_PASSWORD" \
    --admin-user="$ADMIN_USER" \
    --admin-pass="$ADMIN_PASSWORD" \
    --data-dir="$DATA_DIR" \
    --no-interaction

  # trusted_domains setzen
  local idx=0
  [[ -n "$SERVER_IP" ]] && { $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_domains $((idx++)) --value="$SERVER_IP"; }
  [[ -n "$DOMAIN" ]] && { $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_domains $((idx++)) --value="$DOMAIN"; }
  [[ -n "$PROXY_IP" ]] && { $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_domains $((idx++)) --value="$PROXY_IP"; }
  for extra in "${TRUSTED_DOMAINS_EXTRA[@]}"; do
    extra=$(echo "$extra" | xargs) # trim
    [[ -n "$extra" ]] && { $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_domains $((idx++)) --value="$extra"; }
  done

  [[ -n "$DOMAIN" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set overwrite.cli.url --value="https://${DOMAIN}"
}

configure_php() {
  local php_ini="/etc/php/8.4/apache2/php.ini"
  if [[ ! -f "$php_ini" ]]; then
    php_ini=$(find /etc/php -name php.ini -path "*/apache2/*" | head -n1)
  fi
  log "Passe PHP-Konfiguration an ($php_ini) …"
  $SUDO sed -i "s/^upload_max_filesize =.*/upload_max_filesize = $PHP_UPLOAD_MAX/" "$php_ini"
  $SUDO sed -i "s/^post_max_size =.*/post_max_size = $PHP_POST_MAX/" "$php_ini"
  $SUDO sed -i "s/^memory_limit =.*/memory_limit = $PHP_MEMORY_LIMIT/" "$php_ini"
  $SUDO sed -i "s/^max_execution_time =.*/max_execution_time = $PHP_MAX_EXEC/" "$php_ini"
  $SUDO sed -i "s/^max_input_time =.*/max_input_time = $PHP_MAX_INPUT/" "$php_ini"
  # Opcache
  if grep -q "opcache.interned_strings_buffer" "$php_ini"; then
    $SUDO sed -i "s/^opcache.interned_strings_buffer =.*/opcache.interned_strings_buffer = $DEFAULT_OPCACHE_STR/" "$php_ini"
  else
    echo "opcache.interned_strings_buffer = $DEFAULT_OPCACHE_STR" | $SUDO tee -a "$php_ini"
  fi
  if grep -q "opcache.memory_consumption" "$php_ini"; then
    $SUDO sed -i "s/^opcache.memory_consumption =.*/opcache.memory_consumption = $DEFAULT_OPCACHE_MEM/" "$php_ini"
  else
    echo "opcache.memory_consumption = $DEFAULT_OPCACHE_MEM" | $SUDO tee -a "$php_ini"
  fi
  if grep -q "opcache.max_accelerated_files" "$php_ini"; then
    $SUDO sed -i "s/^opcache.max_accelerated_files =.*/opcache.max_accelerated_files = $DEFAULT_OPCACHE_FILES/" "$php_ini"
  else
    echo "opcache.max_accelerated_files = $DEFAULT_OPCACHE_FILES" | $SUDO tee -a "$php_ini"
  fi
  if grep -q "opcache.revalidate_freq" "$php_ini"; then
    $SUDO sed -i "s/^opcache.revalidate_freq =.*/opcache.revalidate_freq = $DEFAULT_OPCACHE_REVALIDATE/" "$php_ini"
  else
    echo "opcache.revalidate_freq = $DEFAULT_OPCACHE_REVALIDATE" | $SUDO tee -a "$php_ini"
  fi

  # Redis-Session, falls aktiviert
  if [[ "$redis_session" == "true" ]]; then
    log "Aktiviere Redis für PHP-Sessions …"
    if grep -q "^session.save_handler" "$php_ini"; then
      $SUDO sed -i "s/^session.save_handler =.*/session.save_handler = redis/" "$php_ini"
    else
      echo "session.save_handler = redis" | $SUDO tee -a "$php_ini"
    fi
    if grep -q "^session.save_path" "$php_ini"; then
      $SUDO sed -i "s/^session.save_path =.*/session.save_path = \"tcp:\/\/${REDIS_HOST}:${REDIS_PORT}\"/" "$php_ini"
    else
      echo "session.save_path = \"tcp://${REDIS_HOST}:${REDIS_PORT}\"" | $SUDO tee -a "$php_ini"
    fi
  fi

  $SUDO systemctl restart apache2
}

configure_mpm() {
  local mpm_conf="/etc/apache2/mods-available/mpm_prefork.conf"
  log "Passe Apache mpm_prefork an …"
  $SUDO tee "$mpm_conf" >/dev/null <<EOF
  <IfModule mpm_prefork_module>
  StartServers        $DEFAULT_MPM_START
  MinSpareServers     $DEFAULT_MPM_MIN
  MaxSpareServers     $DEFAULT_MPM_MAX
  MaxRequestWorkers   $DEFAULT_MPM_WORKERS
  MaxConnectionsPerChild $DEFAULT_MPM_CONN
  </IfModule>
EOF
  $SUDO systemctl restart apache2
}

configure_mariadb() {
  local mariadb_conf="/etc/mysql/mariadb.conf.d/50-server.cnf"
  if [[ ! -f "$mariadb_conf" ]]; then
    mariadb_conf="/etc/mysql/mariadb.conf.d/50-mariadb.cnf"
  fi
  log "Passe MariaDB-Konfiguration an ($mariadb_conf) …"
  if ! grep -q "^\[mysqld\]" "$mariadb_conf"; then
    echo "[mysqld]" | $SUDO tee -a "$mariadb_conf"
  fi
  $SUDO sed -i "/^\[mysqld\]/,/^\[/ s/^innodb_buffer_pool_size =.*/innodb_buffer_pool_size = $INNODB_POOL/" "$mariadb_conf"
  $SUDO sed -i "/^\[mysqld\]/,/^\[/ s/^innodb_log_file_size =.*/innodb_log_file_size = $INNODB_LOG/" "$mariadb_conf"
  $SUDO sed -i "/^\[mysqld\]/,/^\[/ s/^max_connections =.*/max_connections = $MYSQL_MAX_CONN/" "$mariadb_conf"
  if grep -q "query_cache_size" "$mariadb_conf"; then
    $SUDO sed -i "s/^query_cache_size =.*/query_cache_size = 0/" "$mariadb_conf"
  else
    echo "query_cache_size = 0" | $SUDO tee -a "$mariadb_conf"
  fi
  if grep -q "query_cache_type" "$mariadb_conf"; then
    $SUDO sed -i "s/^query_cache_type =.*/query_cache_type = 0/" "$mariadb_conf"
  else
    echo "query_cache_type = 0" | $SUDO tee -a "$mariadb_conf"
  fi
  $SUDO systemctl restart mariadb
}

# ─── Redis mit Passwortschutz und Persistenz ────────────────────────────

configure_redis() {
  log "Konfiguriere Redis mit Passwortschutz …"
  # Generiere ein zufälliges Passwort für Redis
  REDIS_PASSWORD=$(openssl rand -base64 24 | tr -d "=+/" | head -c 32)
  log "Redis-Passwort generiert: $REDIS_PASSWORD"

  # In redis.conf setzen
  local redis_conf="/etc/redis/redis.conf"
  if [[ -f "$redis_conf" ]]; then
    # requirepass setzen
    if grep -q "^requirepass" "$redis_conf"; then
      $SUDO sed -i "s/^requirepass.*/requirepass ${REDIS_PASSWORD}/" "$redis_conf"
    else
      echo "requirepass ${REDIS_PASSWORD}" | $SUDO tee -a "$redis_conf"
    fi
    # Persistenz: RDB-Snapshots beibehalten (Standard sind save 900 1, 300 10, 60 10000)
    # Optional AOF aktivieren? Wir belassen es bei RDB.
    # dir für RDB-Datei ist standardmäßig /var/lib/redis – bleibt so.
    log "Redis-Persistenz (RDB) bleibt aktiv (Standard-Snapshots)."
  else
    log "WARNUNG: redis.conf nicht gefunden – überspringe Passwortsetzung."
  fi

  $SUDO systemctl restart redis-server
}

# ─── logrotate für Nextcloud-Logs ──────────────────────────────────────

setup_logrotate() {
  log "Richte logrotate für Nextcloud-Logs ein …"
  local logrotate_file="/etc/logrotate.d/nextcloud"
  $SUDO tee "$logrotate_file" >/dev/null <<EOF
${DATA_DIR}/nextcloud.log {
  daily
  rotate 7
  compress
  missingok
  notifempty
  create 0640 www-data www-data
  sharedscripts
  postrotate
    if [ -f ${INSTALL_DIR}/occ ]; then
      sudo -u www-data php ${INSTALL_DIR}/occ log:manage --backend file --file ${DATA_DIR}/nextcloud.log --rotate-size 104857600
    fi
  endscript
}
EOF
  log "logrotate eingerichtet: $logrotate_file"
}

# ─── Web-Updater ──────────────────────────────────────────────────────────

configure_web_updater() {
  if [[ "$web_updater" == "true" ]]; then
    log "Aktiviere Web-Updater …"
    if [[ -d "$INSTALL_DIR/updater" ]]; then
      $SUDO chown -R www-data:www-data "$INSTALL_DIR/updater"
      $SUDO chmod -R 755 "$INSTALL_DIR/updater"
    fi
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set updater.enabled --value=true
    if $SUDO -u www-data php "$INSTALL_DIR/occ" list | grep -q updater:enable; then
      $SUDO -u www-data php "$INSTALL_DIR/occ" updater:enable
    fi
  else
    log "Deaktiviere Web-Updater …"
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set updater.enabled --value=false
  fi
}

# ─── Let's Encrypt ──────────────────────────────────────────────────────

configure_letsencrypt() {
  if [[ "$letsencrypt" == "true" && -n "$DOMAIN" ]]; then
    log "Richte Let's Encrypt ein …"
    $SUDO certbot --apache -d "$DOMAIN" --non-interactive --agree-tos --email "admin@${DOMAIN}" || {
      log "Let's Encrypt fehlgeschlagen – überspringe."
      return 1
    }
    log "Let's Encrypt erfolgreich eingerichtet."
  fi
}

# ─── Erweiterte Nextcloud-Konfiguration ──────────────────────────────

apply_advanced_config() {
  log "Wende erweiterte Nextcloud-Konfiguration an …"
  # Sicherheit
  [[ -n "${CONFIG_overwriteprotocol:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set overwriteprotocol --value="$CONFIG_overwriteprotocol"
  [[ -n "${CONFIG_loglevel:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set loglevel --value="$CONFIG_loglevel"
  if [[ "$proxy_use" == "true" && -n "$PROXY_IP" ]]; then
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_proxies 0 --value="$PROXY_IP"
    if [[ -n "${CONFIG_trusted_proxies_extra:-}" ]]; then
      local idx=1
      for proxy in "${CONFIG_trusted_proxies_extra[@]}"; do
        proxy=$(echo "$proxy" | xargs)
        [[ -n "$proxy" ]] && { $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set trusted_proxies $((idx++)) --value="$proxy"; }
      done
    fi
  fi

  # Lokalisierung
  [[ -n "${CONFIG_default_language:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set default_language --value="$CONFIG_default_language"
  [[ -n "${CONFIG_default_locale:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set default_locale --value="$CONFIG_default_locale"
  [[ -n "${CONFIG_default_phone_region:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set default_phone_region --value="$CONFIG_default_phone_region"

  # Performance
  [[ -n "${CONFIG_maintenance_window_start:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set maintenance_window_start --value="$CONFIG_maintenance_window_start"
  [[ -n "${CONFIG_filesystem_check_changes:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set filesystem_check_changes --value="$CONFIG_filesystem_check_changes"

  # Logging
  [[ -n "${CONFIG_logtimezone:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set logtimezone --value="$CONFIG_logtimezone"
  [[ -n "${CONFIG_log_rotate_size:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set log_rotate_size --value="$CONFIG_log_rotate_size"

  # Erweitert
  [[ -n "${CONFIG_server_id:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set server_id --value="$CONFIG_server_id"
  [[ -n "${CONFIG_overwritewebroot:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set overwritewebroot --value="$CONFIG_overwritewebroot"
  [[ -n "${CONFIG_htaccess_RewriteBase:-}" ]] && $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set htaccess.RewriteBase --value="$CONFIG_htaccess_RewriteBase"

  # Redis-Cache (falls installiert)
  if [[ "$redis_install" == "true" ]]; then
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set memcache.local --value='\OC\Memcache\Redis'
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set memcache.distributed --value='\OC\Memcache\Redis'
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set memcache.locking --value='\OC\Memcache\Redis'
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set redis host --value="$REDIS_HOST"
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set redis port --value="$REDIS_PORT"
    # Redis-Passwort setzen, falls generiert
    if [[ -n "$REDIS_PASSWORD" ]]; then
      $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set redis password --value="$REDIS_PASSWORD"
    fi
    if [[ "$redis_session" == "true" ]]; then
      $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set memcache.session --value='\OC\Memcache\Redis'
    fi
  fi

  # Updater
  if [[ "$web_updater" == "true" ]]; then
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set updater.enabled --value=true
  else
    $SUDO -u www-data php "$INSTALL_DIR/occ" config:system:set updater.enabled --value=false
  fi

  $SUDO -u www-data php "$INSTALL_DIR/occ" maintenance:update:htaccess
}

# ─── Empfohlene Apps installieren ──────────────────────────────────────

install_recommended_apps() {
  if [[ "$install_recommended_apps" != "true" ]]; then
    return
  fi
  log "Installiere empfohlene Nextcloud-Apps …"
  local apps=("calendar" "contacts" "talk" "deck" "tasks" "notes" "onlyoffice")
  for app in "${apps[@]}"; do
    log "Installiere App: $app"
    if $SUDO -u www-data php "$INSTALL_DIR/occ" app:install "$app" >> "$LOG_FILE" 2>&1; then
      log "App $app erfolgreich installiert."
    else
      log "WARNUNG: Installation von $app fehlgeschlagen (möglicherweise nicht verfügbar)."
    fi
  done
}

# ─── Cronjob ──────────────────────────────────────────────────────────

setup_cron() {
  log "Richte Cronjob für Nextcloud ein …"
  local cron_entry="*/5 * * * * php -f $INSTALL_DIR/cron.php"
  (crontab -u www-data -l 2>/dev/null || true; echo "$cron_entry") | crontab -u www-data -
  log "Cronjob eingerichtet: $cron_entry"
}

# ─── Fail2ban ──────────────────────────────────────────────────────────

configure_fail2ban() {
  local filter_file="/etc/fail2ban/filter.d/nextcloud.conf"
  log "Konfiguriere Fail2ban …"
  $SUDO tee "$filter_file" >/dev/null <<EOF
  [Definition]
  failregex = ^.*Login failed: .* (Remote IP: <HOST>).*$
  ^.*\"remoteAddr\":\"<HOST>\".*Trusted domain error.*$
  ignoreregex =
EOF

  local jail_file="/etc/fail2ban/jail.d/nextcloud.local"
  $SUDO tee "$jail_file" >/dev/null <<EOF
  [nextcloud]
  backend = auto
  enabled = true
  port = 80,443
  protocol = tcp
  filter = nextcloud
  maxretry = ${FAIL2BAN_MAXRETRY}
  bantime = ${FAIL2BAN_BANTIME}
  findtime = ${FAIL2BAN_FINDTIME}
  logpath = ${DATA_DIR}/nextcloud.log
EOF

  $SUDO systemctl restart fail2ban
}

# ─── Health-Check ──────────────────────────────────────────────────────

run_health_check() {
  log "Führe Health-Check durch …"
  local status_output
  status_output=$($SUDO -u www-data php "$INSTALL_DIR/occ" status 2>&1) || true
  local security_output
  security_output=$($SUDO -u www-data php "$INSTALL_DIR/occ" security:check 2>&1) || true

  echo ""
  gum style --foreground "$NRS_CYAN" "🔍 Health-Check Ergebnisse:"
  echo "$status_output" | while IFS= read -r line; do
    gum style --foreground "$NRS_WHITE" "   $line"
  done
  echo ""
  echo "$security_output" | while IFS= read -r line; do
    gum style --foreground "$NRS_GOLD" "   $line"
  done
  echo ""
}

# ─── Platzhalter für Werte‑Anpassung ──────────────────────────────────

just_adjust_values() {
  gum style --foreground "$NRS_CYAN" "🛠️  Dies ist ein Platzhalter für das nachträgliche Anpassen von Werten."
  gum style --foreground "$NRS_GRAY" "Du kannst später hier die Logik einbauen, um z.B. nur PHP- oder MariaDB-Werte zu ändern, ohne die gesamte Installation neu zu starten."
  gum style --foreground "$NRS_GOLD" "Aktuell wird nur eine Zusammenfassung der aktuellen Werte angezeigt (die du ändern könntest)."
  gum confirm "Zurück zum Hauptmenü?" --affirmative "Ja" && return
}

# ─── Hauptmenü ──────────────────────────────────────────────────────────

main_menu() {
  while true; do
    local action
    action=$(gum choose --header "📋 Was möchtest du tun?" \
      "Nextcloud installieren" \
      "Werte nachträglich anpassen (Platzhalter)" \
      "Beenden")
    case "$action" in
      "Nextcloud installieren")
        install_full
        break
        ;;
      "Werte nachträglich anpassen (Platzhalter)")
        just_adjust_values
        ;;
      "Beenden")
        gum style --foreground "$NRS_GRAY" "👋 Auf Wiedersehen!"
        exit 0
        ;;
    esac
  done
}

# ─── Hauptinstallationsroutine ──────────────────────────────────────────

install_full() {
  clear
  show_banner
  ask_values

  # Exportiere alle benötigten Variablen für Subshells
  export DOMAIN SERVER_IP PROXY_IP ADMIN_USER ADMIN_PASSWORD \
    DB_NAME DB_USER DB_PASSWORD MARIADB_ROOT_PASSWORD DATA_DIR \
    PHP_UPLOAD_MAX PHP_POST_MAX PHP_MEMORY_LIMIT PHP_MAX_EXEC PHP_MAX_INPUT \
    INNODB_POOL INNODB_LOG MYSQL_MAX_CONN FAIL2BAN_MAXRETRY FAIL2BAN_BANTIME FAIL2BAN_FINDTIME \
    INSTALL_DIR REDIS_HOST REDIS_PORT \
    apache_install mariadb_install redis_install fail2ban_install \
    proxy_use php_optimize mariadb_optimize fail2ban_optimize \
    web_updater redis_session letsencrypt advanced_config install_recommended_apps

  clear
  show_banner
  log "Starte Nextcloud-Installation mit den gewählten Optionen."

  # Schritt 1: Abhängigkeiten
  run_with_spinner "📦 Schritt 1: Abhängigkeiten werden installiert" install_dependencies

  # Schritt 2: MariaDB sichern
  if [[ "$mariadb_install" == "true" ]]; then
    run_with_spinner "🔐 Schritt 2: MariaDB wird gesichert" secure_mariadb
    run_with_spinner "🗄️  Schritt 3: Datenbank wird angelegt" create_nextcloud_db
  else
    echo "⏩  Schritte 2–3 übersprungen (keine MariaDB)."
  fi

  # Schritt 4: Nextcloud herunterladen
  run_with_spinner "📥 Schritt 4: Nextcloud wird heruntergeladen" download_nextcloud

  # Schritt 5: Apache konfigurieren (mit LimitRequestBody)
  if [[ "$apache_install" == "true" ]]; then
    run_with_spinner "🔧 Schritt 5: Apache wird konfiguriert (Upload-Limit: unbegrenzt)" configure_apache
  else
    echo "⏩  Schritt 5 übersprungen (Apache nicht installiert)."
  fi

  # Schritt 6: Nextcloud installieren
  run_with_spinner "⚡ Schritt 6: Nextcloud wird installiert" run_nextcloud_install

  # Schritt 7: PHP optimieren (inkl. Redis-Session)
  if [[ "$php_optimize" == "true" || "$redis_session" == "true" ]]; then
    run_with_spinner "⚙️  Schritt 7: PHP wird optimiert" configure_php
  else
    echo "⏩  Schritt 7 übersprungen (PHP‑Optimierung nicht gewünscht)."
  fi

  # Schritt 8: Apache mpm_prefork
  if [[ "$apache_install" == "true" ]]; then
    run_with_spinner "⚙️  Schritt 8: Apache mpm_prefork wird optimiert" configure_mpm
  else
    echo "⏩  Schritt 8 übersprungen (kein Apache)."
  fi

  # Schritt 9: MariaDB optimieren
  if [[ "$mariadb_install" == "true" && "$mariadb_optimize" == "true" ]]; then
    run_with_spinner "🗄️  Schritt 9: MariaDB wird optimiert" configure_mariadb
  else
    echo "⏩  Schritt 9 übersprungen (MariaDB nicht installiert oder Optimierung nicht gewünscht)."
  fi

  # Schritt 10: Redis konfigurieren (mit Passwort & Persistenz)
  if [[ "$redis_install" == "true" ]]; then
    run_with_spinner "📦 Schritt 10: Redis wird konfiguriert (Passwortschutz & Persistenz)" configure_redis
  else
    echo "⏩  Schritt 10 übersprungen (Redis nicht installiert)."
  fi

  # Schritt 11: Web-Updater aktivieren
  run_with_spinner "🔄 Schritt 11: Web-Updater wird konfiguriert" configure_web_updater

  # Schritt 12: Erweiterte Nextcloud-Konfiguration
  if [[ "$advanced_config" == "true" ]]; then
    run_with_spinner "🔧 Schritt 12: Erweiterte config.php wird angewendet" apply_advanced_config
  else
    echo "⏩  Schritt 12 übersprungen (keine erweiterte Konfiguration gewünscht)."
  fi

  # Schritt 13: Cronjob
  run_with_spinner "📅 Schritt 13: Cronjob wird eingerichtet" setup_cron

  # Schritt 14: Fail2ban
  if [[ "$fail2ban_install" == "true" ]]; then
    run_with_spinner "🔐 Schritt 14: Fail2ban wird konfiguriert" configure_fail2ban
  else
    echo "⏩  Schritt 14 übersprungen (Fail2ban nicht installiert)."
  fi

  # Schritt 15: Let's Encrypt
  if [[ "$letsencrypt" == "true" ]]; then
    run_with_spinner "🔒 Schritt 15: Let's Encrypt wird eingerichtet" configure_letsencrypt
  else
    echo "⏩  Schritt 15 übersprungen (Let's Encrypt nicht gewünscht)."
  fi

  # Schritt 16: logrotate für Nextcloud-Logs
  run_with_spinner "📄 Schritt 16: logrotate für Nextcloud-Logs wird eingerichtet" setup_logrotate

  # Schritt 17: Empfohlene Apps installieren
  if [[ "$install_recommended_apps" == "true" ]]; then
    run_with_spinner "📦 Schritt 17: Empfohlene Apps werden installiert" install_recommended_apps
  else
    echo "⏩  Schritt 17 übersprungen (Apps nicht gewünscht)."
  fi

  # Berechtigungen final setzen
  echo "▶️  Berechtigungen final setzen …"
  $SUDO chown -R www-data:www-data "$INSTALL_DIR"
  $SUDO chown -R www-data:www-data "$DATA_DIR"
  $SUDO chmod -R 755 "$INSTALL_DIR"
  $SUDO chmod -R 755 "$DATA_DIR"
  echo "✅ Berechtigungen gesetzt."

  # Maintenance Repair
  echo "▶️  Maintenance Repair ausführen …"
  $SUDO -u www-data php "$INSTALL_DIR/occ" maintenance:repair --include-expensive || true
  echo "✅ Maintenance Repair abgeschlossen."

  # Health-Check (Schritt 18)
  run_health_check

  # Abschlussbanner
  echo ""
  gum style --border rounded --border-foreground "$NRS_GOLD" --padding "1 4" --foreground "$NRS_WHITE" "
  ✨  Nextcloud wurde erfolgreich installiert und optimiert!

  🔗  ${DOMAIN:-localhost} (HTTPS: ${letsencrypt:-false})
  👤  Benutzername: $ADMIN_USER
  🔑  Passwort:     $(gum style --foreground "$NRS_GOLD" --bold "$ADMIN_PASSWORD")

  ⚡   ${redis_install:+Redis aktiv (Passwort gesetzt), }${fail2ban_install:+Fail2ban aktiv, }${web_updater:+Web-Updater aktiv, }Optimierungen nach Wahl.
  📅  Cronjob läuft alle 5 Minuten.
  📁  Installationsverzeichnis: $INSTALL_DIR
  📂  Datenverzeichnis:          $DATA_DIR
  📄  Log-Datei: $LOG_FILE
  🔒  Redis-Passwort:            $(gum style --foreground "$NRS_GOLD" "$REDIS_PASSWORD")
  "

  log "Installation erfolgreich abgeschlossen."
  exit 0
}

# ─── Skript‑Start ──────────────────────────────────────────────────────

echo "ℹ️  Prüfe und installiere benötigte Basis‑Tools (curl, gpg, sudo) …"
sleep 1
check_prerequisites

clear
show_banner
main_menu
