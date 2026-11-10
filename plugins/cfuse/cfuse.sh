# cfuse – keep several Cloud Foundry logins side by side via CF_HOME.
# Shared core for bash and zsh; load it through cfuse.bash or cfuse.plugin.zsh.

_cfuse_config() {
  printf '%s\n' "${CFUSE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cfuse/landscapes}"
}

_cfuse_root() {
  printf '%s\n' "${CFUSE_HOME:-$HOME/.cfuse}"
}

# Region configured for a name, empty if none.
_cfuse_region() {
  local cfg
  cfg="$(_cfuse_config)"
  [ -f "$cfg" ] || return 0
  awk -v n="$1" '!/^[[:space:]]*(#|$)/ && $1 == n { print $2; exit }' "$cfg"
}

# Region of the API a saved login targets, read from its cf config.
_cfuse_saved_region() {
  local json="$1/.cf/config.json"
  [ -f "$json" ] || return 0
  sed -n 's/.*"Target": *"https:\/\/api\.cf\.\([^.]*\)\..*/\1 (saved login)/p' "$json"
}

# All known names: configured landscapes plus saved logins.
_cfuse_names() {
  local cfg root
  cfg="$(_cfuse_config)"
  root="$(_cfuse_root)"
  {
    [ -f "$cfg" ] && awk '!/^[[:space:]]*(#|$)/ { print $1 }' "$cfg"
    [ -d "$root" ] && find "$root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  } | sort -u
}

_cfuse_list() {
  local root name region mark
  root="$(_cfuse_root)"
  echo "Landscapes ($(_cfuse_config)):"
  _cfuse_names | while IFS= read -r name; do
    [ -n "$name" ] || continue
    region="$(_cfuse_region "$name")"
    [ -n "$region" ] || region="$(_cfuse_saved_region "$root/$name")"
    mark=" "
    [ "$CF_HOME" = "$root/$name" ] && mark="*"
    printf ' %s %-14s %s\n' "$mark" "$name" "${region:-(saved login)}"
  done
}

# Print "name region" lines for every CF environment the btp CLI can see.
_cfuse_discover() {
  local cmd guid sub disp
  for cmd in btp jq; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "cfuse: '$cmd' not found" >&2; return 1; }
  done
  btp --format json list accounts/subaccount >/dev/null 2>&1 \
    || { echo "cfuse: btp not logged in – run 'btp login --sso' first" >&2; return 1; }

  echo "# Paste into $(_cfuse_config) and rename as you like"
  while IFS=$'\t' read -r guid sub disp; do
    btp --format json list accounts/environment-instance -sa "$guid" 2>/dev/null |
      jq -r --arg sub "$sub" --arg disp "$disp" '
        (.environmentInstances // .value // [])[]
        | select(.environmentType == "cloudfoundry")
        | (.labels | if type == "string" then fromjson else . end) as $l
        | ($l["API Endpoint:"] // $l["API Endpoint"] // "")
        | capture("api\\.cf\\.(?<r>[^.]+)\\.hana") .r
        | "\($sub) \(.)   # \($disp) (org: \($l["Org Name:"] // $l["Org Name"] // "?"))"'
  done < <(btp --format json list accounts/subaccount |
             jq -r '.value[] | [.guid, .subdomain, .displayName] | @tsv')
}

_cfuse_help() {
  cat <<'EOF'
Usage: cfuse                 list landscapes (* = active in this shell)
       cfuse <name> [region] switch to <name>, log in if needed
       cfuse --discover      print "name region" lines from the btp CLI
       cfuse --help

Landscapes: one "name region" per line in $CFUSE_CONFIG
            (default ~/.config/cfuse/landscapes), e.g. "dev eu20-001".
Logins:     stored per name under $CFUSE_HOME (default ~/.cfuse).
Login mode: SSO by default; set CFUSE_SSO=0 for user/password login.
EOF
}

cfuse() {
  case "$1" in
    ""|-l|--list) _cfuse_list; return ;;
    -d|--discover) _cfuse_discover; return ;;
    -h|--help) _cfuse_help; return ;;
    -*) echo "cfuse: unknown option '$1'" >&2; _cfuse_help >&2; return 1 ;;
  esac

  local name="$1" region api
  case "$name" in
    *[!A-Za-z0-9_.-]*) echo "cfuse: invalid name '$name'" >&2; return 1 ;;
  esac
  region="${2:-$(_cfuse_region "$name")}"
  case "$region" in
    *[!a-z0-9-]*) echo "cfuse: invalid region '$region'" >&2; return 1 ;;
  esac
  [ -n "$region" ] && api="https://api.cf.$region.hana.ondemand.com"

  export CF_HOME="$(_cfuse_root)/$name"
  mkdir -p "$CF_HOME" || return
  echo "CF_HOME → $CF_HOME"

  if ! cf oauth-token >/dev/null 2>&1; then
    echo "Not logged in – starting login…"
    local args=()
    [ "${CFUSE_SSO:-1}" = 0 ] || args+=(--sso)
    [ -n "$api" ] && args+=(-a "$api")
    cf login "${args[@]}" || return
  fi
  cf target | grep -E '^(API endpoint|user|org|space):'
}
