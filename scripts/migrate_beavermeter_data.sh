#!/bin/zsh
set -euo pipefail
umask 077

source "${0:A:h}/lib/install_common.sh"
bm_initialize

mkdir -p "$config_dir" "$log_dir"
chmod 700 "$config_dir"

migrate_private_file() {
  local source_path="$1"
  local destination_path="$2"
  local description="$3"

  if [[ -e "$destination_path" ]]; then
    chmod 600 "$destination_path"
    print "Keeping existing BeaverMeter $description."
    return
  fi
  if [[ -f "$source_path" ]]; then
    cp -p "$source_path" "$destination_path"
    chmod 600 "$destination_path"
    print "Migrated $description from CodexWeek."
  fi
}

migrate_private_file "$legacy_config_dir/config.env" "$config_dir/config.env" "configuration"
migrate_private_file "$legacy_config_dir/deepseek-platform-token" "$config_dir/deepseek-platform-token" "DeepSeek credential"

legacy_snapshot="$legacy_config_dir/codex-week-snapshot.json"
snapshot="$config_dir/beaver-meter-snapshot.json"
if [[ -e "$snapshot" ]]; then
  chmod 600 "$snapshot"
  print "Keeping existing BeaverMeter snapshot."
elif [[ -f "$legacy_snapshot" ]]; then
  schema_version="$(/usr/bin/plutil -extract schemaVersion raw -o - "$legacy_snapshot" 2>/dev/null || true)"
  if [[ "$schema_version" == "5" ]]; then
    cp -p "$legacy_snapshot" "$snapshot"
    chmod 600 "$snapshot"
    print "Migrated schema v5 snapshot from CodexWeek."
  else
    print "Skipped legacy snapshot because it is not schema v5."
  fi
fi

if [[ -d "$legacy_log_dir" ]]; then
  for source_path in "$legacy_log_dir"/*(.N); do
    destination_path="$log_dir/${source_path:t}"
    if [[ ! -e "$destination_path" ]]; then
      cp -p "$source_path" "$destination_path"
    fi
  done
fi
