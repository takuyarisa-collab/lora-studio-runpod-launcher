#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY="takuyarisa-collab/lora-studio"
readonly CODEX_INSTALL_URL="https://chatgpt.com/codex/install.sh"
readonly DEFAULT_PARENT="${LORA_STUDIO_PARENT:-/workspace}"

log() { printf '[first-boot] %s\n' "$*"; }
die() { printf '[first-boot] ERROR: %s\n' "$*" >&2; exit 1; }
trap 'die "command failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

as_root() {
  if (( EUID == 0 )); then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    die 'Root privileges are required, but sudo is not installed. Re-run as root.'
  fi
}

apt_install() {
  local missing=() package
  for package in "$@"; do
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'ok installed' || missing+=("$package")
  done
  ((${#missing[@]})) || return 0
  as_root apt-get update
  DEBIAN_FRONTEND=noninteractive as_root apt-get install -y --no-install-recommends "${missing[@]}"
}

install_gh() {
  command -v gh >/dev/null 2>&1 && return
  log 'Installing GitHub CLI from the official package repository.'
  as_root install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | as_root tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  as_root chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' "$(dpkg --print-architecture)" | as_root tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  as_root apt-get update
  DEBIAN_FRONTEND=noninteractive as_root apt-get install -y gh
}

install_node() {
  local major=''
  if command -v node >/dev/null 2>&1; then
    major="$(node --version | sed -E 's/^v([0-9]+).*/\1/')"
  fi
  [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 20 )) && return
  if dpkg-query -W -f='${Status}' libnode-dev 2>/dev/null | grep -q 'ok installed'; then
    as_root apt-get remove -y libnode-dev
  fi
  curl -fsSL https://deb.nodesource.com/setup_20.x | as_root bash -
  DEBIAN_FRONTEND=noninteractive as_root apt-get install -y nodejs
}

install_codex() {
  export PATH="$HOME/.local/bin:$PATH"
  command -v codex >/dev/null 2>&1 && return
  curl -fsSL "$CODEX_INSTALL_URL" | sh
  hash -r
}

main() {
  [[ -r /etc/os-release ]] || die 'Unsupported system: /etc/os-release is missing.'
  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == ubuntu || "${ID_LIKE:-}" == *debian* ]] || die "Expected Ubuntu/Debian; found ${PRETTY_NAME:-unknown}."
  log "Running as $(id -un) (uid=$EUID)."

  apt_install ca-certificates curl git wget
  install_gh
  install_node
  install_codex

  if ! command -v curl >/dev/null || ! command -v git >/dev/null || ! command -v wget >/dev/null; then
    die 'Base tool verification failed.'
  fi
  command -v gh >/dev/null || die 'GitHub CLI verification failed.'
  command -v codex >/dev/null || die 'Codex CLI verification failed.'
  (( $(node --version | sed -E 's/^v([0-9]+).*/\1/') >= 20 )) || die 'Node.js 20+ verification failed.'

  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    log 'GitHub browser authentication is the first required manual step.'
    gh auth login --hostname github.com --git-protocol https --web
  fi

  mkdir -p "$DEFAULT_PARENT"
  local repo_dir="$DEFAULT_PARENT/lora-studio"
  if [[ -d "$repo_dir/.git" ]]; then
    log "Using existing repository: $repo_dir"
  elif [[ -e "$repo_dir" ]]; then
    die "$repo_dir exists but is not a Git repository; refusing to overwrite it."
  else
    gh repo clone "$REPOSITORY" "$repo_dir"
  fi

  "$repo_dir/runpod/scripts/bootstrap.sh"
  log "Environment ready in $repo_dir."
  if ! codex login status >/dev/null 2>&1; then
    log 'Codex ChatGPT browser authentication is the second required manual step.'
    codex login
  fi
  log 'Authentication complete; launching Codex.'
  cd "$repo_dir"
  exec codex
}

main "$@"
