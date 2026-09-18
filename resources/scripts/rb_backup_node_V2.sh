#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CONFIGURATION
# ============================================================

BACKUP_BASE_DIR="/root/backup"
BACKUP_HISTORY_DIR="/root/backup"
VERSION=1
BACKUP_STATUS="RUNNING"
BACKUP_ERROR=""

DATE=$(date '+%Y-%m-%d_%H%M%S')
HOSTNAME=$(hostname)
SHORT_HOSTNAME="${HOSTNAME%%.*}"

# ============================================================
# HELP
# ============================================================

show_help() {
    cat <<EOF
  Usage:
    $0
    $0 --s3 [S3CMD_CONFIG]
    $0 --local PATH
    $0 --help

  Description:
    Performs a complete backup of the system: commands, files and PostgreSQL.

  Options:
    -s, --s3 [S3CMD_CONFIG]
        Perform the complete backup and upload the resulting
        .tar.gz archive to S3.

        If S3CMD_CONFIG is not specified, the default is:
        ${S3CMD_CONFIG}

    -l, --local PATH
        Perform the complete backup and store both the backup
        directory and the resulting .tar.gz archive in PATH.

        The backup history remains stored in:
        ${BACKUP_HISTORY_DIR}/backup_history.csv

    -h, --help
        Show this help message.

  Examples:
    $0
      Full backup to:
      /tmp/backup
    $0 --s3
      Full backup and upload to S3 using:
      ${S3CMD_CONFIG}
    $0 --s3 /root/.s3cfg_initial
      Full backup and upload using the specified s3cmd config.
    $0 --local /backup
      Full backup stored in:
      /backup
      Backup history stored in:
      ${BACKUP_HISTORY_DIR}/backup_history.csv
EOF
}

# ============================================================
# COMMAND-LINE ARGUMENTS
# ============================================================

BACKUP_DESTINATION="local"

parse_arguments() {
  if (($# == 0)); then
    BACKUP_DESTINATION="local"
    return 0
  fi

  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -s|--s3)
      BACKUP_DESTINATION="s3"
      shift
      if (($# > 0)); then
        if [[ "$1" == -* ]]; then
          echo "ERROR: Unexpected option after --s3: $1" >&2
          exit 2
        fi
        S3CMD_CONFIG="$1"
        shift
      fi
      ;;
    -l|--local)
      BACKUP_DESTINATION="local"
      shift
      if (($# == 0)); then
        echo "ERROR: --local requires a destination path." >&2
        exit 2
      fi
      if [[ "$1" == -* ]]; then
        echo "ERROR: --local requires a destination path." >&2
        exit 2
      fi
      BACKUP_BASE_DIR="$1"
      shift
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      echo >&2
      show_help >&2
      exit 2
      ;;
  esac
  if (($# > 0)); then
    echo "ERROR: Unexpected argument: $1" >&2
    echo >&2
    show_help >&2
    exit 2
  fi
}

# ============================================================
# S3
# ============================================================

S3CMD_CONFIG="/root/.s3cfg_initial"
S3_CONFIG="/etc/druid/_common/common.runtime.properties"
S3_BUCKET=""

get_s3_bucket() {
  if [[ ! -f "$S3_CONFIG" ]]; then
    echo "ERROR: Druid configuration file does not exist:" >&2
    echo "$S3_CONFIG" >&2
    return 1
  fi
  S3_BUCKET=$(
    awk -F= '
        $1 == "druid.storage.bucket" {
            gsub(/^[ \t]+|[ \t]+$/, "", $2)
            print $2
            exit
        }
    ' "$S3_CONFIG"
  )
  if [[ -z "$S3_BUCKET" ]]; then
    echo "ERROR: Unable to determine S3 bucket from:" >&2
    echo "$S3_CONFIG" >&2
    return 1
  fi
  echo "S3 bucket: $S3_BUCKET"
}

backup_to_s3() {
  local backup_archive="${BKP_DIR_BASE}.tar.gz"
  local s3_destination
  echo
  printf '=%.0s' {1..80}
  echo
  echo "S3 BACKUP"
  printf '=%.0s' {1..80}
  echo
  if [[ ! -f "$backup_archive" ]]; then
    echo "ERROR: Backup archive does not exist:" >&2
    echo "$backup_archive" >&2
    return 1
  fi
  if [[ ! -f "$S3CMD_CONFIG" ]]; then
    echo "ERROR: S3 configuration file does not exist:" >&2
    echo "$S3CMD_CONFIG" >&2
    return 1
  fi
  get_s3_bucket
  s3_destination="s3://${S3_BUCKET}/backup/"
  execute_command \
    "Upload backup archive to S3" \
    nice -n 19 \
    ionice -c2 -n7 \
    s3cmd \
    -c "$S3CMD_CONFIG" \
    sync \
    "$backup_archive" \
    "$s3_destination"
  echo
  echo "Backup uploaded to S3:"
  echo "$s3_destination"
}


# ============================================================
# COMPRESS BACKUP
# ============================================================

compress_backup() {
  local backup_archive="${BKP_DIR_BASE}.tar.gz"
  local parent_dir
  local backup_name
  parent_dir=$(dirname "$BKP_DIR_BASE")
  backup_name=$(basename "$BKP_DIR_BASE")
  echo
  printf '=%.0s' {1..80}
  echo
  echo "COMPRESS BACKUP"
  printf '=%.0s' {1..80}
  echo
  execute_command \
    "Compress backup directory" \
    tar \
    -czpf \
    "$backup_archive" \
    -C \
    "$parent_dir" \
    "$backup_name"
  execute_command "Synchronize backup archive to disk" sync
  echo
  echo "Backup archive created:"
  echo "$backup_archive"
}

# ============================================================
# COMMANDS BACKUP
# ============================================================

COMMAND_NAMES=(
  "O.S. Information"
  "Mount"
  "Disks"
  "Installed RPM packages"
  "Installed packages via DNF"
  "DNF transaction history"
  "Available services (exists)"
  "Enabled services (configure to launch)"
  "Running services (running)"
  "Software checksums (/usr/local/bin/)"
  "List /usr/local/bin"
)

COMMANDS=(
  "cat"
  "findmnt"
  "lsblk"
  "rpm"
  "dnf"
  "dnf"
  "systemctl"
  "systemctl"
  "systemctl"
  "sha256sum"
  "ls"
)

COMMAND_ARGS=(
  "/etc/os-release"
  ""
  ""
  "-qa"
  "list installed"
  "history"
  "list-unit-files --type=service"
  "list-unit-files --type=service --state=enabled"
  "list-units --type=service --state=running"
  "/usr/local/bin/*"
  "-lah /usr/local/bin/"
)

backup_commands() {
  local output_dir="${BKP_DIR_BASE}/commands"
  mkdir -p "$output_dir"
  for i in "${!COMMANDS[@]}"; do
    local name="${COMMAND_NAMES[$i]}"
    local command="${COMMANDS[$i]}"
    local args="${COMMAND_ARGS[$i]}"
    local output_file
    output_file="${output_dir}/${name//[^a-zA-Z0-9_-]/_}.txt"
    if [[ -n "$args" ]]; then
      execute_command "$name" "$command" $args > "$output_file" 2>&1
    else
      execute_command "$name" "$command" > "$output_file" 2>&1
    fi
    echo "Output: $output_file"
  done
}

# ============================================================
# FILES BACKUP
# ============================================================

FILES_ETC=(
  "/etc"
)

FILES_ROOT=(
  "/root/.bash*"
  "/root/.install-*"
  "/root/.s3cfg_*"
  "/root/.wget-hsts"
  "/root/rb_init_conf.yml"
)

FILES_VAR=(
  "/var/www/rb-rails/config/*"
  "/var/lib/consul"
  "/var/snmp"
  "/var/chef/backup"
  "/var/chef/data"
  "/var/chef/nodes"
  "/var/chef/solo"
  "/var/opt/opscode/nginx/ca"
  "/var/opt/opscode/nginx/etc"
  "/var/opt/opscode/chef_version_history.txt"
)

backup_category() {
  local category="$1"
  local array_name="$2"
  local -n paths="$array_name"
  echo
  printf '=%.0s' {1..80}
  echo
  echo "BACKUP: $category"
  printf '=%.0s' {1..80}
  echo
  local expanded_paths=()
  local path
  local match
  local matches
  for path in "${paths[@]}"; do
    shopt -s nullglob
    matches=( $path )
    shopt -u nullglob
    if ((${#matches[@]} == 0)); then
        echo "WARNING: No matches for $path"
        continue
    fi
    for match in "${matches[@]}"; do
        expanded_paths+=( "$match" )
    done
  done
  if ((${#expanded_paths[@]} == 0)); then
    echo "WARNING: Nothing to backup for $category"
    return 0
  fi
  execute_command \
    "Backup files for category '$category'" \
    rsync \
    -aAXR \
    "${expanded_paths[@]}" \
    "${BKP_DIR_BASE}/files/"
  echo "Backup OK: $category"
}

backup_files() {
  mkdir -p "${BKP_DIR_BASE}/files"
  backup_category "etc"  FILES_ETC
  backup_category "root" FILES_ROOT
  backup_category "var"  FILES_VAR
}

# ============================================================
# DATABASE BACKUP
# ============================================================

PG_SERVICE="postgresql"
PG_HOST="master.postgresql.service"
PG_USER="postgres"
PG_DATA_DIR="/var/lib/pgsql/data"

backup_database() {
  local database_dir="${BKP_DIR_BASE}/database"
  local pg_dump_file
  local pg_copy_dir
  local postgres_stopped=false
  mkdir -p "$database_dir"

  restart_postgresql() {
    if [[ "$postgres_stopped" == true ]]; then
      echo
      echo "Ensuring PostgreSQL service is started..."
      if ! execute_command "Start PostgreSQL service" systemctl start "$PG_SERVICE"; then
        echo "ERROR: Unable to restart PostgreSQL service" >&2
        return 1
      fi
      postgres_stopped=false
    fi
  }

  trap restart_postgresql RETURN

  # --------------------------------------------------------
  # Logical PostgreSQL backup
  # --------------------------------------------------------

  echo
  printf '=%.0s' {1..80}
  echo
  echo "POSTGRESQL LOGICAL BACKUP"
  printf '=%.0s' {1..80}
  echo
  pg_dump_file="${database_dir}/${HOSTNAME}-postgresql-logical-${DATE}.sql"

  execute_command \
    "PostgreSQL logical backup" \
    --output "$pg_dump_file" \
    nice -n 19 \
    ionice -c2 -n7 \
    pg_dumpall \
    -h "$PG_HOST" \
    -U "$PG_USER" \
    -c

  execute_command "Synchronize logical PostgreSQL backup to disk" sync
  echo "Backup OK: $pg_dump_file"

  # --------------------------------------------------------
  # Physical PostgreSQL backup
  # --------------------------------------------------------

  echo
  printf '=%.0s' {1..80}
  echo
  echo "POSTGRESQL DATA DIRECTORY BACKUP"
  printf '=%.0s' {1..80}
  echo
  pg_copy_dir="${database_dir}/${HOSTNAME}-postgresql-data-${DATE}"
  mkdir -p "$pg_copy_dir"

  execute_command "Stop PostgreSQL service" systemctl stop "$PG_SERVICE"
  postgres_stopped=true

  execute_command \
    "Backup PostgreSQL data directory" \
    nice -n 19 \
    ionice -c2 -n7 \
    rsync -aAX \
    "${PG_DATA_DIR}/" \
    "${pg_copy_dir}/"

  execute_command "Synchronize PostgreSQL physical backup to disk" sync
  echo "Backup OK: $pg_copy_dir"

  restart_postgresql
  trap - RETURN
  echo
  echo "PostgreSQL backup completed successfully."
}

# ============================================================
# GENERIC COMMAND EXECUTOR
# ============================================================

execute_command() {
  local description="$1"
  shift
  local output_file=""
  if [[ "$1" == "--output" ]]; then
    output_file="$2"
    shift 2
  fi
  echo
  printf '=%.0s' {1..80}
  echo
  echo "$description"
  printf '=%.0s' {1..80}
  echo
  echo -n "COMMAND:"
  printf ' %q' "$@"
  echo
  echo
  local status
  if [[ -n "$output_file" ]]; then
    mkdir -p "$(dirname "$output_file")"
    ( cd / 
    "$@" ) > "$output_file"
    status=$?
  else
    ( cd / 
    "$@" )
    status=$?
  fi
  echo
  echo "EXIT STATUS: $status"
  if ((status != 0)); then
    echo "ERROR: $description" >&2
    return "$status"
  fi
  echo "OK: Command completed successfully"
  return 0
}

# ============================================================
# BACKUP INFO
# ============================================================

create_backup_structure() {
  mkdir -p "${BKP_DIR_BASE}/files" "${BKP_DIR_BASE}/database" "${BKP_DIR_BASE}/commands"
}

create_backup_info() {
    local info_file="${BKP_DIR_BASE}/backup.info"
    mkdir -p "$BACKUP_HISTORY_DIR"
    printf '%s\n' \
        "VERSION=${VERSION}" \
        "DATE=${DATE}" \
        "HOSTNAME=${HOSTNAME}" \
        "SHORT_HOSTNAME=${SHORT_HOSTNAME}" \
        "BACKUP_DIR=${BKP_DIR_BASE}" \
        "DESTINATION=${BACKUP_DESTINATION}" \
        "STATUS=${BACKUP_STATUS}" \
        > "$info_file"
    echo
    echo "========================================"
    echo "BACKUP INFO CREATED"
    echo "$info_file"
    echo "========================================"
}

update_backup_result() {
    local info_file="${BKP_DIR_BASE}/backup.info"
    local history_file="${BACKUP_HISTORY_DIR}/backup_history.csv"
    local error="${BACKUP_ERROR//$'\n'/ }"

    # --------------------------------------------------------
    # Update backup.info
    # --------------------------------------------------------

    printf '%s\n' \
        "VERSION=${VERSION}" \
        "DATE=${DATE}" \
        "HOSTNAME=${HOSTNAME}" \
        "SHORT_HOSTNAME=${SHORT_HOSTNAME}" \
        "BACKUP_DIR=${BKP_DIR_BASE}" \
        "DESTINATION=${BACKUP_DESTINATION}" \
        "STATUS=${BACKUP_STATUS}" \
        "ERROR=${error}" \
        > "$info_file"

    # --------------------------------------------------------
    # Create history header if necessary
    # --------------------------------------------------------

    if [[ ! -f "$history_file" ]]; then
      printf '%s\n' "DATE,VERSION,HOSTNAME,SHORT_HOSTNAME,BACKUP_DIR,DESTINATION,STATUS,ERROR" > "$history_file"
    fi


    # --------------------------------------------------------
    # Add ONE final entry to history
    # --------------------------------------------------------

    printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$DATE" \
        "$VERSION" \
        "$HOSTNAME" \
        "$SHORT_HOSTNAME" \
        "$BKP_DIR_BASE" \
        "$BACKUP_DESTINATION" \
        "$BACKUP_STATUS" \
        "$error" \
        >> "$history_file"

    echo
    echo "========================================"
    echo "BACKUP RESULT"
    echo "========================================"
    echo "Status:      $BACKUP_STATUS"
    echo "Destination: $BACKUP_DESTINATION"
    if [[ -n "$error" ]]; then
        echo "Error:       $error"
    fi
    echo "========================================"
}

# ============================================================
# CLUSTER
# ============================================================

CONSUL_POSTGRESQL_CHECK_URL="http://localhost:8500/v1/health/checks/postgresql"
POSTGRESQL_ROLE=""

get_postgresql_checks() {
  curl -fsS "$CONSUL_POSTGRESQL_CHECK_URL"
}

get_serf_members() {
  serf members
}

collect_cluster_metadata() {
  local cluster_file="${BKP_DIR_BASE}/cluster.info"
  local postgresql_checks=""
  local serf_members=""
  local local_role=""
  local consul_status="OK"
  local consul_error=""
  echo
  printf '=%.0s' {1..80}
  echo
  echo "CLUSTER METADATA"
  printf '=%.0s' {1..80}
  echo

  echo "Collecting PostgreSQL health checks..."
  if postgresql_checks=$(get_postgresql_checks 2>&1); then
    echo "TEST: '$SHORT_HOSTNAME'"
    local_role=$(
      printf '%s\n' "$postgresql_checks" |
      sed 's/},{/}\n{/g' |
      grep '"Node":"'"$SHORT_HOSTNAME"'"' |
      grep -o '\\"role\\":\\"[^"]*"' |
      sed 's/.*\\"role\\":\\"\([^"]*\)\\"/\1/'
    )
    if [[ -n "$local_role" ]]; then
      POSTGRESQL_ROLE="$local_role"
    else
      POSTGRESQL_ROLE="unknown"
      consul_status="ERROR"
      consul_error="Unable to determine PostgreSQL role for node '$SHORT_HOSTNAME'"
    fi
  else
    POSTGRESQL_ROLE="unknown"
    consul_status="ERROR"
    consul_error="$postgresql_checks"
  fi

  echo "Collecting Serf members..."
  if serf_members=$(get_serf_members 2>&1); then
    :
  else
    serf_members="ERROR: Unable to get Serf members $serf_members"
  fi
    
  {
    echo "CLUSTER INFORMATION"
    echo "==================="
    echo
    echo "Local hostname:"
    echo "$HOSTNAME"
    echo
    echo "Short hostname:"
    echo "$SHORT_HOSTNAME"
    echo
    echo "PostgreSQL role:"
    echo "$POSTGRESQL_ROLE"
    echo
    echo "Consul status:"
    echo "$consul_status"
    echo
    if [[ -n "$consul_error" ]]; then
      echo "Consul error:"
      echo "$consul_error"
      echo
    fi
    echo "PostgreSQL health checks:"
    echo "$postgresql_checks"
    echo
    echo "Serf members:"
    echo "$serf_members"
  } > "$cluster_file"

  if [[ "$consul_status" == "ERROR" ]]; then
    echo
    echo "WARNING: Unable to determine PostgreSQL cluster role."
    echo "PostgreSQL backup will be skipped."
    echo
    echo "Cluster information saved to:"
    echo "$cluster_file"
  else
    echo
    echo "PostgreSQL role detected: $POSTGRESQL_ROLE"
    echo
    echo "Cluster information saved to:"
    echo "$cluster_file"
  fi
  return 0
}

# ============================================================
# MAIN
# ============================================================

main() {
  create_backup_structure
  create_backup_info
  collect_cluster_metadata

  echo
  printf '=%.0s' {1..80}
  echo
  echo "POSTGRESQL CLUSTER ROLE"
  printf '=%.0s' {1..80}
  echo
  echo "Local PostgreSQL role: $POSTGRESQL_ROLE"

  case "$POSTGRESQL_ROLE" in
    master)
      echo
      echo "This node is the PostgreSQL MASTER."
      echo "Starting PostgreSQL backup..."
      backup_database
      ;;
    *)
      echo
      echo "This node is NOT confirmed as the PostgreSQL MASTER."
      echo "PostgreSQL backup skipped."
      ;;
  esac

  backup_commands
  backup_files
  compress_backup

  case "$BACKUP_DESTINATION" in
    local)
      echo
      echo "Backup destination: LOCAL"
      echo "Backup directory:"
      echo "$BKP_DIR_BASE"
      echo
      echo "Backup archive:"
      echo "${BKP_DIR_BASE}.tar.gz"
      ;;
    s3)
      echo
      echo "Backup destination: S3"
      backup_to_s3
      ;;
    *)
      echo "ERROR: Invalid backup destination: $BACKUP_DESTINATION" >&2
      return 1
      ;;
  esac
}

parse_arguments "$@"

BKP_DIR_BASE="${BACKUP_BASE_DIR}/${DATE}-${SHORT_HOSTNAME}"

if main; then
  BACKUP_STATUS="SUCCESS"
  update_backup_result
else
  BACKUP_STATUS="FAILED"
  BACKUP_ERROR="One or more backup operations failed"
  update_backup_result
  exit 1
fi