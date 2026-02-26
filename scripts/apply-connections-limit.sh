#!/usr/bin/env bash

set -euo pipefail

new_limit="${1:-100}"
target_file="${2:-}"

if ! [[ "${new_limit}" =~ ^[0-9]+$ ]]; then
  echo "Invalid limit '${new_limit}'. It must be an integer." >&2
  exit 1
fi

if [[ -n "${target_file}" ]]; then
  if [[ ! -f "${target_file}" ]]; then
    echo "Configured connections file not found: ${target_file}" >&2
    exit 1
  fi
  candidate_file="${target_file}"
else
  mapfile -t candidates < <(
    rg -l --hidden --glob '!**/.git/**' \
      '"(max_connections|maxConnections|connections)"[[:space:]]*:[[:space:]]*20' \
      server || true
  )

  if ((${#candidates[@]} == 0)); then
    echo "Could not auto-detect a connections file in ./server." >&2
    echo "Set repository variable DS_CONNECTIONS_FILE or workflow input connections_file." >&2
    exit 1
  fi

  if ((${#candidates[@]} > 1)); then
    echo "Multiple candidate files found. Set DS_CONNECTIONS_FILE or workflow input connections_file." >&2
    printf ' - %s\n' "${candidates[@]}" >&2
    exit 1
  fi

  candidate_file="${candidates[0]}"
fi

before_hash="$(sha256sum "${candidate_file}" | awk '{print $1}')"

perl -0777 -i -pe "
  s/(\"max_connections\"\\s*:\\s*)\\d+/\\1${new_limit}/g;
  s/(\"maxConnections\"\\s*:\\s*)\\d+/\\1${new_limit}/g;
  s/(\"connections\"\\s*:\\s*)20/\\1${new_limit}/g;
" "${candidate_file}"

after_hash="$(sha256sum "${candidate_file}" | awk '{print $1}')"

if [[ "${before_hash}" == "${after_hash}" ]]; then
  echo "No connection-limit change was applied in ${candidate_file}." >&2
  exit 1
fi

echo "Updated concurrent connections limit to ${new_limit} in ${candidate_file}"
rg -n --max-count 5 '"(max_connections|maxConnections|connections)"[[:space:]]*:' "${candidate_file}" || true
