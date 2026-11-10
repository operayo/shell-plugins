# cfuse – keep several Cloud Foundry logins side by side via CF_HOME.
# Shared core for bash and zsh; load it through cfuse.bash or cfuse.plugin.zsh.
#
# A login lives in $CFUSE_HOME/<name>@<region>, or $CFUSE_HOME/<name> when no
# region is known (cf then asks for the API endpoint).

# Subcommands; these can't be used as landscape names.
_CFUSE_COMMANDS="list discover help"

_cfuse_config() {
  printf '%s\n' "${CFUSE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cfuse/landscapes}"
}

_cfuse_root() {
  printf '%s\n' "${CFUSE_HOME:-$HOME/.cfuse}"
}

_cfuse_is_command() {
  case " $_CFUSE_COMMANDS " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

# All login keys (name@region or name): configured landscapes plus saved logins.
_cfuse_keys() {
  local cfg root
  cfg="$(_cfuse_config)"
  root="$(_cfuse_root)"
  {
    [ -f "$cfg" ] && awk '!/^[[:space:]]*(#|$)/ { print ($2 == "" ? $1 : $1 "@" $2) }' "$cfg"
    [ -d "$root" ] && find "$root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  } | awk -F@ -v cmds=" $_CFUSE_COMMANDS " 'index(cmds, " " $1 " ") == 0' | sort -u
}

_cfuse_names() {
  _cfuse_keys | sed 's/@.*//' | sort -u
}

# Known regions for a name, one per line.
_cfuse_regions_for() {
  _cfuse_keys | awk -F@ -v n="$1" '$1 == n && NF == 2 { print $2 }'
}

# Region of the API a saved login targets, read from its cf config.
_cfuse_saved_region() {
  local json="$1/.cf/config.json"
  [ -f "$json" ] || return 0
  sed -n 's/.*"Target": *"https:\/\/api\.cf\.\([^.]*\)\..*/\1/p' "$json"
}

_cfuse_list() {
  local cfg root keys key name region mark skipped
  cfg="$(_cfuse_config)"
  root="$(_cfuse_root)"
  if [ -f "$cfg" ]; then
    skipped="$(awk -v cmds=" $_CFUSE_COMMANDS " '!/^[[:space:]]*(#|$)/ && index(cmds, " " $1 " ") { print $1 }' "$cfg" | sort -u | paste -sd' ' -)"
    [ -z "$skipped" ] || echo "cfuse: skipping '$skipped' in $cfg – reserved command names" >&2
  fi
  keys="$(_cfuse_keys)"
  if [ -z "$keys" ]; then
    echo "No landscapes yet. Add \"name region\" lines to $cfg,"
    echo "or run: cfuse <name> <region>    (or cfuse discover after btp login --sso)"
    return
  fi
  printf '%s\n' "$keys" | while IFS= read -r key; do
    name="${key%%@*}"
    case "$key" in
      *@*) region="${key#*@}" ;;
      *) region="$(_cfuse_saved_region "$root/$key")"; region="${region:-?} (no region set)" ;;
    esac
    mark=" "
    [ "$CF_HOME" = "$root/$key" ] && mark="*"
    printf ' %s %-14s %s\n' "$mark" "$name" "$region"
  done
}

# Ask which of several regions to use; prints the choice, fails on cancel.
_cfuse_pick() {
  local name="$1" regions="$2" count i=0 choice r
  count="$(printf '%s\n' "$regions" | grep -c .)"
  echo "'$name' has several regions:" >&2
  printf '%s\n' "$regions" | while IFS= read -r r; do
    i=$((i + 1))
    printf '  %d) %s\n' "$i" "$r" >&2
  done
  printf 'Region [1-%d]: ' "$count" >&2
  read -r choice
  case "$choice" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] || return 1
  printf '%s\n' "$regions" | sed -n "${choice}p"
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
  case "$1" in
    list) cat <<'EOF'
Usage: cfuse list            (also: cfuse, cfuse -l, cfuse --list)

List all logins: landscapes from the landscapes file plus logins you have
made, one line per name and region. * marks the login active in this shell.
EOF
    ;;
    discover) cat <<EOF
Usage: cfuse discover        (also: cfuse -d, cfuse --discover)

Print "name region" lines for every Cloud Foundry environment the btp CLI
can see, ready to paste into $(_cfuse_config).
Needs: btp (logged in via 'btp login --sso') and jq.
Covers the global account btp currently targets ('btp target' to switch).

Example: cfuse discover >> $(_cfuse_config)
EOF
    ;;
    switch) cat <<'EOF'
Usage: cfuse <name> [region]

Switch this shell to the login <name>@<region>; log in (SSO) if needed.
Without region, the regions known for <name> (landscapes file and saved
logins) are used: one → that one, several → you pick, none → cf asks for
the API endpoint.

Examples: cfuse operayo eu20-001
          cfuse operayo
EOF
    ;;
    *) cat <<'EOF'
Usage: cfuse <command>
       cfuse <name> [region]

Commands:
  list, -l          list logins (default; * = active in this shell)
  discover, -d      print landscape lines from the btp CLI
  help, -h          this help

  <name> [region]   switch this shell to a login, log in if needed

Run 'cfuse help <command>' or 'cfuse <command> --help' for details
('cfuse help switch' for <name> [region]).

Landscapes: "name region" lines in $CFUSE_CONFIG
            (default ~/.config/cfuse/landscapes), e.g. "operayo eu20-001".
Logins:     stored under $CFUSE_HOME (default ~/.cfuse) as <name>@<region>.
Login mode: SSO by default; set CFUSE_SSO=0 for user/password login.
EOF
    ;;
  esac
}

_cfuse_switch() {
  local name="$1" region="$2" regions key api
  case "$name" in
    *[!A-Za-z0-9_.-]*) echo "cfuse: invalid name '$name'" >&2; return 1 ;;
  esac
  if [ -z "$region" ]; then
    regions="$(_cfuse_regions_for "$name")"
    case "$(printf '%s' "$regions" | grep -c .)" in
      0) ;;
      1) region="$regions" ;;
      *) region="$(_cfuse_pick "$name" "$regions")" || { echo "cfuse: cancelled" >&2; return 1; } ;;
    esac
  fi
  case "$region" in
    *[!a-z0-9-]*) echo "cfuse: invalid region '$region'" >&2; return 1 ;;
  esac

  key="$name"
  if [ -n "$region" ]; then
    key="$name@$region"
    api="https://api.cf.$region.hana.ondemand.com"
  fi

  export CF_HOME="$(_cfuse_root)/$key"
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

cfuse() {
  local cmd
  case "$1" in
    ""|list|-l|--list) cmd=list ;;
    discover|-d|--discover) cmd=discover ;;
    help|-h|--help) _cfuse_help "$2"; return ;;
    -*) echo "cfuse: unknown option '$1'" >&2; _cfuse_help >&2; return 1 ;;
    *) cmd=switch ;;
  esac

  case "$2" in
    -h|--help) _cfuse_help "$cmd"; return ;;
  esac

  case "$cmd" in
    list|discover)
      if [ -n "$2" ]; then
        if _cfuse_is_command "$1"; then
          echo "cfuse: '$1' is a command, not a landscape name" >&2
        else
          echo "cfuse: unexpected argument '$2'" >&2
        fi
        echo "Run 'cfuse help $cmd' for usage." >&2
        return 1
      fi
      "_cfuse_$cmd"
      ;;
    switch) _cfuse_switch "$1" "$2" ;;
  esac
}
