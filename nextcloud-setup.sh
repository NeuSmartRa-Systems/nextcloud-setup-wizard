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
# ║                     Nextcloud – Setup                             ║
# ║ ────────────────────────────────────────────────────────────────  ║
# ║         © 2026 NeuSmartRa  │  Systems  │  Release v1.0.0          ║
# ║                                                                   ║
# ╚═══════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Globale Variablen ──────────────────────────────────────────

readonly NRS_BLUE="39"
readonly NRS_CYAN="87"
readonly NRS_GRAY="247"
readonly NRS_GOLD="220"
readonly NRS_WHITE="255"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOG_FILE="/var/log/nextcloud-install.log"

# Standardwerte (werden später durch User‑Eingaben überschrieben)
DEFAULT_PHP_UPLOAD_MAX="100G"
DEFAULT_PHP_POST_MAX="0"
DEFAULT_PHP_MEMORY_LIMIT="4096M"
DEFAULT_PHP_MAX_EXEC="7200"
DEFAULT_PHP_MAX_INPUT="7200"
DEFAULT_OPCACHE_STR="16"
DEFAULT_OPCACHE_MEM="256"
DEFAULT_OPCACHE_FILES="10000"
DEFAULT_OPCACHE_REVALIDATE="60"
DEFAULT_MPM_START="5"
DEFAULT_MPM_MIN="5"
DEFAULT_MPM_MAX="20"
DEFAULT_MPM_WORKERS="1000"
DEFAULT_MPM_CONN="10000"
DEFAULT_INNODB_POOL="8G"
DEFAULT_INNODB_LOG="2G"
DEFAULT_MYSQL_MAX_CONN="1000"
DEFAULT_FAIL2BAN_MAXRETRY="5"
DEFAULT_FAIL2BAN_BANTIME="3600"
DEFAULT_FAIL2BAN_FINDTIME="600"
DEFAULT_REDIS_HOST="localhost"
DEFAULT_REDIS_PORT="6379"

# ─── Hilfsfunktionen ────────────────────────────────────────────

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$LOG_FILE"
}

error_exit() {
  echo "⛔ FEHLER: $*" >&2
  log "FEHLER: $*"
  exit 1
}

# ─── Spinner-Funktion ──────────────────────────────────────────

run_with_spinner() {
  local title="$1"
  shift
  local cmd=("$@")

  echo -n "$title ... "

  # Starte den Befehl im Hintergrund, leite Ausgabe in LOG_FILE um
  {
    "${cmd[@]}" >> "$LOG_FILE" 2>&1
  } &
  local pid=$!

  # Spinner-Animation
  local spin='-\|/'
  local i=0
  while kill -0 "$pid" 2>/dev/null; do
  i=$(( (i+1) % 4 ))
  printf "\r$title ... ${spin:$i:1} "
  sleep 0.2
  done

  # Warten auf Beendigung und Status prüfen
  wait "$pid"
  local exit_code=$?
  if [[ $exit_code -eq 0 ]]; then
  printf "\r✅ $title abgeschlossen.     \n"
  else
  printf "\r❌ $title fehlgeschlagen (Fehlercode %s). Siehe Log: %s\n" "$exit_code" "$LOG_FILE"
  exit "$exit_code"
  fi
}

# ─── Root‑ und Abhängigkeitsprüfung ────────────────────────────

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

# ─── Gum‑Installation ──────────────────────────────────────────

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

# ─── Banner ─────────────────────────────────────────────────────

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
  $(gum style --foreground "$NRS_GOLD" "")  $(gum style --foreground "$NRS_CYAN" "Nextcloud – Setup")
  ────────────────────────────────────────────────────────────────
  $(gum style --foreground "$NRS_GOLD" "© 2026 NeuSmartRa  │  Systems  │  Release v1.0.0")
  "
}

# ─── Passwortabfrage mit Wiederholung ──────────────────────────

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

# ─── Interaktive Konfiguration ──────────────────────────────────

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

  # ---- Netzwerkkonfiguration ----
  echo -n "Soll die Nextcloud von außen (Domain) erreichbar sein? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
  extern_access="true"
  DOMAIN=$(gum input --placeholder "nextcloud.example.de" --value "$(hostname -f)" --prompt "🌐  Domain (für Nextcloud): ")
  [[ -z "$DOMAIN" ]] && DOMAIN="$(hostname -f)"
  else
  extern_access="false"
  DOMAIN=""
  fi

  echo -n "Soll die Nextcloud über die lokale IP zugänglich sein? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
  intern_access="true"
  SERVER_IP=$(gum input --placeholder "192.168.100.10" --value "192.168.100.10" --prompt "🌍  IP des Servers (lokal): ")
  [[ -z "$SERVER_IP" ]] && SERVER_IP="192.168.100.10"
  else
  intern_access="false"
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

  # ---- Admin ----
  ADMIN_USER=$(gum input --placeholder "admin" --value "admin" --prompt "👤  Admin-Benutzername: ")
  [[ -z "$ADMIN_USER" ]] && ADMIN_USER="admin"
  ADMIN_PASSWORD=$(ask_password_with_confirm "🔑  Admin-Passwort: " "mindestens 8 Zeichen")

  # ---- MariaDB Details (nur wenn installiert) ----
  if [[ "$mariadb_install" == "true" ]]; then
  DB_NAME=$(gum input --placeholder "nextcloud" --value "nextcloud" --prompt "🗄️  Datenbankname: ")
  [[ -z "$DB_NAME" ]] && DB_NAME="nextcloud"

  DB_USER=$(gum input --placeholder "nextclouduser" --value "nextclouduser" --prompt "👤  Datenbank-Benutzer: ")
  [[ -z "$DB_USER" ]] && DB_USER="nextclouduser"

  DB_PASSWORD=$(ask_password_with_confirm "🔑  Datenbank-Passwort: " "sicheres Passwort")
  else
  DB_NAME=""
  DB_USER=""
  DB_PASSWORD=""
  fi

  # ---- Optimierungen ----
  echo -n "Soll PHP optimiert werden? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
  php_optimize="true"
  PHP_UPLOAD_MAX=$(gum input --placeholder "$DEFAULT_PHP_UPLOAD_MAX" --value "$DEFAULT_PHP_UPLOAD_MAX" --prompt "📤  upload_max_filesize: ")
  [[ -z "$PHP_UPLOAD_MAX" ]] && PHP_UPLOAD_MAX="$DEFAULT_PHP_UPLOAD_MAX"

  PHP_POST_MAX=$(gum input --placeholder "$DEFAULT_PHP_POST_MAX" --value "$DEFAULT_PHP_POST_MAX" --prompt "📥  post_max_size (0 = unbeschränkt, oder größer als upload_max_filesize): ")
  [[ -z "$PHP_POST_MAX" ]] && PHP_POST_MAX="$DEFAULT_PHP_POST_MAX"

  PHP_MEMORY_LIMIT=$(gum input --placeholder "$DEFAULT_PHP_MEMORY_LIMIT" --value "$DEFAULT_PHP_MEMORY_LIMIT" --prompt "🧠  memory_limit: ")
  [[ -z "$PHP_MEMORY_LIMIT" ]] && PHP_MEMORY_LIMIT="$DEFAULT_PHP_MEMORY_LIMIT"

  PHP_MAX_EXEC=$(gum input --placeholder "$DEFAULT_PHP_MAX_EXEC" --value "$DEFAULT_PHP_MAX_EXEC" --prompt "⏱️  max_execution_time (Sekunden): ")
  [[ -z "$PHP_MAX_EXEC" ]] && PHP_MAX_EXEC="$DEFAULT_PHP_MAX_EXEC"

  PHP_MAX_INPUT=$(gum input --placeholder "$DEFAULT_PHP_MAX_INPUT" --value "$DEFAULT_PHP_MAX_INPUT" --prompt "⏱️  max_input_time (Sekunden, muss >= max_execution_time sein): ")
  [[ -z "$PHP_MAX_INPUT" ]] && PHP_MAX_INPUT="$DEFAULT_PHP_MAX_INPUT"
  else
  php_optimize="false"
  fi

  if [[ "$mariadb_install" == "true" ]]; then
  echo -n "Soll MariaDB optimiert werden? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
  mariadb_optimize="true"
  INNODB_POOL=$(gum input --placeholder "$DEFAULT_INNODB_POOL" --value "$DEFAULT_INNODB_POOL" --prompt "🗄️  innodb_buffer_pool_size: ")
  [[ -z "$INNODB_POOL" ]] && INNODB_POOL="$DEFAULT_INNODB_POOL"

  INNODB_LOG=$(gum input --placeholder "$DEFAULT_INNODB_LOG" --value "$DEFAULT_INNODB_LOG" --prompt "📄 innodb_log_file_size: ")
  [[ -z "$INNODB_LOG" ]] && INNODB_LOG="$DEFAULT_INNODB_LOG"

  MYSQL_MAX_CONN=$(gum input --placeholder "$DEFAULT_MYSQL_MAX_CONN" --value "$DEFAULT_MYSQL_MAX_CONN" --prompt "🔗 max_connections: ")
  [[ -z "$MYSQL_MAX_CONN" ]] && MYSQL_MAX_CONN="$DEFAULT_MYSQL_MAX_CONN"
  else
  mariadb_optimize="false"
  fi
  else
  mariadb_optimize="false"
  fi

  if [[ "$fail2ban_install" == "true" ]]; then
  echo -n "Soll Fail2ban optimiert werden? (j/N) "
  read -r answer
  if [[ "$answer" =~ ^[JjYy]$ ]]; then
  fail2ban_optimize="true"
  FAIL2BAN_MAXRETRY=$(gum input --placeholder "$DEFAULT_FAIL2BAN_MAXRETRY" --value "$DEFAULT_FAIL2BAN_MAXRETRY" --prompt "🔐  Fail2ban maxretry: ")
  [[ -z "$FAIL2BAN_MAXRETRY" ]] && FAIL2BAN_MAXRETRY="$DEFAULT_FAIL2BAN_MAXRETRY"

  FAIL2BAN_BANTIME=$(gum input --placeholder "$DEFAULT_FAIL2BAN_BANTIME" --value "$DEFAULT_FAIL2BAN_BANTIME" --prompt "⏳  Fail2ban bantime (Sekunden): ")
  [[ -z "$FAIL2BAN_BANTIME" ]] && FAIL2BAN_BANTIME="$DEFAULT_FAIL2BAN_BANTIME"

  FAIL2BAN_FINDTIME=$(gum input --placeholder "$DEFAULT_FAIL2BAN_FINDTIME" --value "$DEFAULT_FAIL2BAN_FINDTIME" --prompt "⏳  Fail2ban findtime (Sekunden): ")
  [[ -z "$FAIL2BAN_FINDTIME" ]] && FAIL2BAN_FINDTIME="$DEFAULT_FAIL2BAN_FINDTIME"
  else
  fail2ban_optimize="false"
  fi
  else
  fail2ban_optimize="false"
  fi

  # ---- Installationsverzeichnis ----
  install_dir=$(gum input --placeholder "/var/www/html/nextcloud" --value "/var/www/html/nextcloud" --prompt "📁  Installationsverzeichnis: ")
  [[ -z "$install_dir" ]] && install_dir="/var/www/html/nextcloud"

  # ---- Zusammenfassung anzeigen ----
  echo ""
  gum style --foreground "$NRS_WHITE" "📋  Zusammenfassung:"
  [[ "$extern_access" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Domain:                   $DOMAIN"
  [[ "$intern_access" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Server-IP:                $SERVER_IP"
  [[ "$proxy_use" == "true" ]] && gum style --foreground "$NRS_WHITE" "   Proxy-IP:                 $PROXY_IP"
  gum style --foreground "$NRS_WHITE" "   Admin-Benutzer:           $ADMIN_USER"
  gum style --foreground "$NRS_WHITE" "   Admin-Passwort:           ••••••••"
  [[ "$mariadb_install" == "true" ]] && {
    gum style --foreground "$NRS_WHITE" "   DB-Name:                  $DB_NAME"
    gum style --foreground "$NRS_WHITE" "   DB-User:                  $DB_USER"
    gum style --foreground "$NRS_WHITE" "   DB-Passwort:              ••••••••"
  }
  [[ "$php_optimize" == "true" ]] && {
    gum style --foreground "$NRS_WHITE" "   PHP upload_max:           $PHP_UPLOAD_MAX"
    gum style --foreground "$NRS_WHITE" "   PHP post_max:             $PHP_POST_MAX"
    gum style --foreground "$NRS_WHITE" "   PHP memory_limit:         $PHP_MEMORY_LIMIT"
    gum style --foreground "$NRS_WHITE" "   PHP max_execution:        $PHP_MAX_EXEC"
    gum style --foreground "$NRS_WHITE" "   PHP max_input:            $PHP_MAX_INPUT"
  }
  [[ "$mariadb_optimize" == "true" ]] && {
    gum style --foreground "$NRS_WHITE" "   innodb_buffer_pool_size:  $INNODB_POOL"
    gum style --foreground "$NRS_WHITE" "   innodb_log_file_size:     $INNODB_LOG"
    gum style --foreground "$NRS_WHITE" "   max_connections:          $MYSQL_MAX_CONN"
  }
  [[ "$fail2ban_optimize" == "true" ]] && {
    gum style --foreground "$NRS_WHITE" "   Fail2ban maxretry:        $FAIL2BAN_MAXRETRY"
    gum style --foreground "$NRS_WHITE" "   Fail2ban bantime:         $FAIL2BAN_BANTIME"
    gum style --foreground "$NRS_WHITE" "   Fail2ban findtime:        $FAIL2BAN_FINDTIME"
  }
  gum style --foreground "$NRS_WHITE" "   Installationsverzeichnis: $install_dir"
  echo ""

  if ! gum confirm "Mit diesen Daten fortfahren?" --affirmative "Ja, los!" --negative "Abbrechen"; then
  gum style --foreground "$NRS_GRAY" "⏹️  Abgebrochen."
  exit 0
  fi
}

# ─── Installationsfunktionen ──────────────────────────────────

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
  local root_pw="$1"
  log "Sichere MariaDB-Installation …"
  $SUDO mysql <<EOF
  ALTER USER 'root'@'localhost' IDENTIFIED BY '${root_pw}';
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  FLUSH PRIVILEGES;
  EOF
}

create_nextcloud_db() {
  log "Lege Datenbank '${DB_NAME}' und Benutzer '${DB_USER}' an …"
  $SUDO mysql -u root -p"$DB_PASSWORD" <<EOF
  CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
  CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASSWORD}';
  GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
  FLUSH PRIVILEGES;
  EOF
}

download_nextcloud() {
  local install_dir="$1"
  local tmp_dir="/tmp/nextcloud-install"
  log "Lade Nextcloud herunter …"
  mkdir -p "$tmp_dir"
  cd "$tmp_dir"
  wget -q https://download.nextcloud.com/server/releases/latest.tar.bz2 || \
  error_exit "Download fehlgeschlagen."
  tar -xjf latest.tar.bz2
  $SUDO rsync -a nextcloud/ "$install_dir"
  $SUDO chown -R www-data:www-data "$install_dir"
  $SUDO chmod -R 755 "$install_dir"
  cd /tmp
  rm -rf "$tmp_dir"
}

configure_apache() {
  local domain="$1"
  local install_dir="$2"
  local conf_file="/etc/apache2/sites-available/${domain}.conf"
  log "Konfiguriere Apache für ${domain} …"
  $SUDO tee "$conf_file" >/dev/null <<EOF
  <VirtualHost *:80>
  ServerName ${domain}
  DocumentRoot ${install_dir}

  <Directory ${install_dir}>
  Options +FollowSymlinks
  AllowOverride All
  Require all granted
  <IfModule mod_dav.c>
  Dav off
  </IfModule>
  SetEnv HOME ${install_dir}
  SetEnv HTTP_HOME ${install_dir}
  </Directory>

  ErrorLog \${APACHE_LOG_DIR}/error.log
  CustomLog \${APACHE_LOG_DIR}/access.log combined
  </VirtualHost>
  EOF
  $SUDO a2ensite "${domain}.conf"
  $SUDO a2dissite 000-default.conf
  $SUDO a2enmod rewrite headers env dir mime
  $SUDO systemctl reload apache2
}

run_nextcloud_install() {
  local install_dir="$1"
  local domain="$2"
  log "Führe Nextcloud-Installation aus …"
  $SUDO -u www-data php "$install_dir/occ" maintenance:install \
  --database="mysql" \
  --database-name="$DB_NAME" \
  --database-user="$DB_USER" \
  --database-pass="$DB_PASSWORD" \
  --admin-user="$ADMIN_USER" \
  --admin-pass="$ADMIN_PASSWORD" \
  --data-dir="${install_dir}/data" \
  --no-interaction

  local idx=0
  [[ -n "$SERVER_IP" ]] && { $SUDO -u www-data php "$install_dir/occ" config:system:set trusted_domains $((idx++)) --value="$SERVER_IP"; }
  [[ -n "$DOMAIN" ]] && { $SUDO -u www-data php "$install_dir/occ" config:system:set trusted_domains $((idx++)) --value="$DOMAIN"; }
  [[ -n "$PROXY_IP" ]] && { $SUDO -u www-data php "$install_dir/occ" config:system:set trusted_domains $((idx++)) --value="$PROXY_IP"; }

  [[ -n "$DOMAIN" ]] && $SUDO -u www-data php "$install_dir/occ" config:system:set overwrite.cli.url --value="https://${DOMAIN}"
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

configure_redis() {
  log "Konfiguriere Redis …"
  $SUDO systemctl enable redis-server
  $SUDO systemctl restart redis-server
}

extend_nextcloud_config() {
  local config_file="$install_dir/config/config.php"
  log "Erweitere Nextcloud config.php ($config_file) …"
  if [[ ! -f "$config_file" ]]; then
  error_exit "config.php nicht gefunden unter $config_file"
  fi
  $SUDO cp "$config_file" "$config_file.bak"

  $SUDO -u www-data php "$install_dir/occ" config:system:set overwriteprotocol --value="https"
  $SUDO -u www-data php "$install_dir/occ" config:system:set default_phone_region --value="DE"
  $SUDO -u www-data php "$install_dir/occ" config:system:set loglevel --value="2"
  $SUDO -u www-data php "$install_dir/occ" config:system:set logtimezone --value="Europe/Berlin"
  $SUDO -u www-data php "$install_dir/occ" config:system:set log_rotate_size --value="104857600"
  $SUDO -u www-data php "$install_dir/occ" config:system:set maintenance_window_start --value="1"
  $SUDO -u www-data php "$install_dir/occ" config:system:set default_language --value="de_DE"
  $SUDO -u www-data php "$install_dir/occ" config:system:set default_locale --value="de_DE"
  $SUDO -u www-data php "$install_dir/occ" config:system:set overwritewebroot --value=""
  $SUDO -u www-data php "$install_dir/occ" config:system:set htaccess.RewriteBase --value="/"
  $SUDO -u www-data php "$install_dir/occ" config:system:set filesystem_check_changes --value="0"

  if [[ "$proxy_use" == "true" && -n "$PROXY_IP" ]]; then
  $SUDO -u www-data php "$install_dir/occ" config:system:set trusted_proxies 0 --value="$PROXY_IP"
  fi

  $SUDO -u www-data php "$install_dir/occ" config:system:set server_id --value="cloudspace_srv_01"

  if [[ "$redis_install" == "true" ]]; then
  $SUDO -u www-data php "$install_dir/occ" config:system:set memcache.local --value='\OC\Memcache\Redis'
  $SUDO -u www-data php "$install_dir/occ" config:system:set memcache.distributed --value='\OC\Memcache\Redis'
  $SUDO -u www-data php "$install_dir/occ" config:system:set memcache.locking --value='\OC\Memcache\Redis'
  $SUDO -u www-data php "$install_dir/occ" config:system:set redis host --value="$DEFAULT_REDIS_HOST"
  $SUDO -u www-data php "$install_dir/occ" config:system:set redis port --value="$DEFAULT_REDIS_PORT"
  fi

  $SUDO -u www-data php "$install_dir/occ" maintenance:update:htaccess
}

setup_cron() {
  log "Richte Cronjob für Nextcloud ein …"
  local cron_entry="*/5 * * * * php -f $install_dir/cron.php"
  (crontab -u www-data -l 2>/dev/null || true; echo "$cron_entry") | crontab -u www-data -
  log "Cronjob eingerichtet: $cron_entry"
}

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
  logpath = ${install_dir}/data/nextcloud.log
  EOF

  $SUDO systemctl restart fail2ban
}

# ─── Platzhalter für Werte‑Anpassung ──────────────────────────

just_adjust_values() {
  gum style --foreground "$NRS_CYAN" "🛠️  Dies ist ein Platzhalter für das nachträgliche Anpassen von Werten."
  gum style --foreground "$NRS_GRAY" "Du kannst später hier die Logik einbauen, um z.B. nur PHP- oder MariaDB-Werte zu ändern, ohne die gesamte Installation neu zu starten."
  gum style --foreground "$NRS_GOLD" "Aktuell wird nur eine Zusammenfassung der aktuellen Werte angezeigt (die du ändern könntest)."
  gum confirm "Zurück zum Hauptmenü?" --affirmative "Ja" && return
}

# ─── Hauptmenü ──────────────────────────────────────────────────

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

# ─── Hauptinstallationsroutine ──────────────────────────────────

install_full() {
  clear
  show_banner
  ask_values

  # Exportiere alle benötigten Variablen (für Subshells, falls nötig)
  export DOMAIN SERVER_IP PROXY_IP ADMIN_USER ADMIN_PASSWORD \
  DB_NAME DB_USER DB_PASSWORD PHP_UPLOAD_MAX PHP_POST_MAX \
  PHP_MEMORY_LIMIT PHP_MAX_EXEC PHP_MAX_INPUT INNODB_POOL \
  INNODB_LOG MYSQL_MAX_CONN FAIL2BAN_MAXRETRY FAIL2BAN_BANTIME \
  FAIL2BAN_FINDTIME install_dir \
  apache_install mariadb_install redis_install fail2ban_install \
  proxy_use php_optimize mariadb_optimize fail2ban_optimize

  clear
  show_banner
  log "Starte Nextcloud-Installation mit den gewählten Optionen."

  # Schritt 1: Abhängigkeiten
  run_with_spinner "📦 Schritt 1: Abhängigkeiten werden installiert" install_dependencies

  # Schritt 2: MariaDB sichern
  if [[ "$mariadb_install" == "true" ]]; then
  run_with_spinner "🔐 Schritt 2: MariaDB wird gesichert" secure_mariadb "$DB_PASSWORD"
  run_with_spinner "🗄️  Schritt 3: Datenbank wird angelegt" create_nextcloud_db
  else
  echo "⏩  Schritte 2–3 übersprungen (keine MariaDB)."
  fi

  # Schritt 4: Nextcloud herunterladen
  run_with_spinner "📥 Schritt 4: Nextcloud wird heruntergeladen" download_nextcloud "$install_dir"

  # Schritt 5: Apache konfigurieren
  if [[ "$apache_install" == "true" && -n "$DOMAIN" ]]; then
  run_with_spinner "🔧 Schritt 5: Apache wird konfiguriert" configure_apache "$DOMAIN" "$install_dir"
  else
  echo "⏩  Schritt 5 übersprungen (Apache nicht installiert oder keine Domain)."
  fi

  # Schritt 6: Nextcloud installieren
  run_with_spinner "⚡ Schritt 6: Nextcloud wird installiert" run_nextcloud_install "$install_dir" "$DOMAIN"

  # Schritt 7: PHP optimieren
  if [[ "$php_optimize" == "true" ]]; then
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

  # Schritt 10: Redis konfigurieren
  if [[ "$redis_install" == "true" ]]; then
  run_with_spinner "📦 Schritt 10: Redis wird konfiguriert" configure_redis
  else
  echo "⏩  Schritt 10 übersprungen (Redis nicht installiert)."
  fi

  # Schritt 11: Nextcloud config erweitern
  run_with_spinner "🔧 Schritt 11: Nextcloud config.php wird erweitert" extend_nextcloud_config

  # Cronjob (immer)
  run_with_spinner "📅 Cronjob wird eingerichtet" setup_cron

  # Fail2ban
  if [[ "$fail2ban_install" == "true" ]]; then
  run_with_spinner "🔐 Fail2ban wird konfiguriert" configure_fail2ban
  else
  echo "⏩  Fail2ban übersprungen (nicht installiert)."
  fi

  # Berechtigungen (kein Spinner, da kurz)
  echo "▶️  Berechtigungen final setzen …"
  $SUDO chown -R www-data:www-data "$install_dir"
  $SUDO chmod -R 755 "$install_dir"
  echo "✅ Berechtigungen gesetzt."

  # Maintenance Repair
  echo "▶️  Maintenance Repair ausführen …"
  $SUDO -u www-data php "$install_dir/occ" maintenance:repair --include-expensive || true
  echo "✅ Maintenance Repair abgeschlossen."

  echo ""
  gum style --border rounded --border-foreground "$NRS_GOLD" --padding "1 4" --foreground "$NRS_WHITE" "
  ✨  Nextcloud wurde erfolgreich installiert und optimiert!

  🔗  ${DOMAIN:-localhost} (später mit HTTPS über Caddy)
  👤  Benutzername: $ADMIN_USER
  🔑  Passwort:     $(gum style --foreground "$NRS_GOLD" --bold "$ADMIN_PASSWORD")

  ⚡   ${redis_install:+Redis aktiv, }${fail2ban_install:+Fail2ban aktiv, }Optimierungen nach Wahl.
  📅  Cronjob läuft alle 5 Minuten.
  📁  Installationsverzeichnis: $install_dir
  📄  Log-Datei: $LOG_FILE
  "

  log "Installation erfolgreich abgeschlossen."
  exit 0
}

# ─── Skript‑Start ──────────────────────────────────────────────

echo "ℹ️  Prüfe und installiere benötigte Basis‑Tools (curl, gpg, sudo) …"
sleep 1
check_prerequisites

clear
show_banner
main_menu
