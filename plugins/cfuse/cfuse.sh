# cfuse – keep several Cloud Foundry logins side by side via CF_HOME.
# Shared core for bash and zsh; load it through cfuse.bash or cfuse.plugin.zsh.
#
# A login lives in $CFUSE_HOME/<key>, key = <name>[@<region>[@<origin>]].
# Without region cf asks for the API endpoint; without origin cf uses the
# default identity provider and cfuse records the origin found in the token.
#
# Tokens are only decoded to show origin, user and expiry: never printed,
# never passed as command arguments, never written anywhere else.

# Subcommands; these can't be used as landscape names.
_CFUSE_COMMANDS="list discover remove help"
# Valid login keys; every part starts with a letter or digit (no "." / "..").
_CFUSE_KEY_RE='^[A-Za-z0-9][A-Za-z0-9_.-]*(@[a-z0-9][a-z0-9-]*(@[A-Za-z0-9][A-Za-z0-9_.-]*)?)?$'
# awk helper: login key of a landscapes line ("name [region [origin]]  # comment").
_CFUSE_AWK_KEY='function linekey(   b, f, n, k) {
  b = $0; sub(/#.*/, "", b); n = split(b, f, " ")
  if (!n) return ""
  k = f[1]; if (n > 1) k = k "@" f[2]; if (n > 2) k = k "@" f[3]
  return k
}'

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

# _cfuse_valid name|region|origin <value>
_cfuse_valid() {
  case "$2" in
    ""|[!A-Za-z0-9]*) return 1 ;;
  esac
  case "$1" in
    region) case "$2" in *[!a-z0-9-]*) return 1 ;; esac ;;
    *) case "$2" in *[!A-Za-z0-9_.-]*) return 1 ;; esac ;;
  esac
}

# All valid login keys: configured landscapes plus saved logins.
_cfuse_keys() {
  local cfg root
  cfg="$(_cfuse_config)"
  root="$(_cfuse_root)"
  {
    [ -f "$cfg" ] && awk "$_CFUSE_AWK_KEY"' { k = linekey(); if (k != "") print k }' "$cfg"
    [ -d "$root" ] && find "$root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
  } | awk -F@ -v re="$_CFUSE_KEY_RE" -v cmds=" $_CFUSE_COMMANDS " \
        '$0 ~ re && index(cmds, " " $1 " ") == 0' |
    sort -t@ -k1,1 -k2,2 -k3,3 -u
}

_cfuse_names() {
  _cfuse_keys | cut -d@ -f1 | sort -u
}

_cfuse_regions_for() {
  _cfuse_keys | awk -F@ -v n="$1" '$1 == n && NF > 1 { print $2 }' | sort -u
}

_cfuse_origins_for() {
  _cfuse_keys | awk -F@ -v n="$1" -v r="$2" '$1 == n && $2 == r && NF > 2 { print $3 }' | sort -u
}

# Keys matching name and, if given, region and origin.
_cfuse_matches() {
  _cfuse_keys | awk -F@ -v n="$1" -v r="$2" -v o="$3" \
    '$1 == n && (r == "" || $2 == r) && (o == "" || $3 == o)'
}

_cfuse_b64d() {
  if printf 'eA==' | base64 -d >/dev/null 2>&1; then base64 -d; else base64 -D; fi
}

# Decoded claims (JSON) of the access token saved in a login folder; empty if none.
# The token only ever travels through pipes.
_cfuse_claims() {
  local json="$1/.cf/config.json"
  [ -f "$json" ] || return 0
  sed -n 's/.*"AccessToken": *"\([^"]*\)".*/\1/p' "$json" |
    sed 's/^[Bb]earer //' | cut -d. -f2 | tr '_-' '/+' |
    awk 'NF { while (length($0) % 4) $0 = $0 "="; print }' |
    _cfuse_b64d 2>/dev/null
}

# _cfuse_claim <claims> <name>: one string or number claim, printable chars only.
_cfuse_claim() {
  printf '%s' "$1" | sed -n 's/.*"'"$2"'": *"\{0,1\}\([^",}]*\).*/\1/p' | head -1 | tr -cd '[:print:]'
}

# _cfuse_status <dir> <claims> <check>
_cfuse_status() {
  local exp now
  if ! grep -q '"AccessToken": *"[^"]' "$1/.cf/config.json" 2>/dev/null; then
    echo "not logged in"
  elif [ "$3" = 1 ]; then
    if CF_HOME="$1" cf oauth-token >/dev/null 2>&1; then echo "logged in"; else echo "login needed"; fi
  elif [ -z "$2" ]; then
    echo "unknown"
  else
    exp="$(_cfuse_claim "$2" exp)"
    now="$(date +%s)"
    if [ -n "$exp" ] && [ "$exp" -gt "$now" ]; then echo "logged in"; else echo "token expired"; fi
  fi
}

_cfuse_list() {
  local check="$1" cfg root keys bad name region origin key dir claims user st mark
  cfg="$(_cfuse_config)"
  root="$(_cfuse_root)"
  if [ -f "$cfg" ]; then
    bad="$(awk -F@ "$_CFUSE_AWK_KEY"' { k = linekey(); if (k == "") next; split(k, p, "@")
             if (k !~ re || index(cmds, " " p[1] " ")) print k }' \
           re="$_CFUSE_KEY_RE" cmds=" $_CFUSE_COMMANDS " "$cfg" | paste -sd' ' -)"
    [ -z "$bad" ] || echo "cfuse: skipping invalid or reserved entries in $cfg: $bad" >&2
  fi
  keys="$(_cfuse_keys)"
  if [ -z "$keys" ]; then
    echo "No landscapes yet. Add \"name region\" lines to $cfg,"
    echo "or run: cfuse <name> <region>    (or cfuse discover after btp login --sso)"
    return
  fi
  {
    printf ' \tNAME\tREGION\tORIGIN\tUSER\tSTATUS\n'
    printf '%s\n' "$keys" | while IFS=@ read -r name region origin; do
      key="$name${region:+@$region}${origin:+@$origin}"
      dir="$root/$key"
      claims="$(_cfuse_claims "$dir")"
      user="$(_cfuse_claim "$claims" user_name)"
      if [ -z "$origin" ]; then
        origin="$(_cfuse_claim "$claims" origin)"
        [ -z "$origin" ] || origin="($origin)"
      fi
      st="$(_cfuse_status "$dir" "$claims" "$check")"
      mark=" "
      [ "$CF_HOME" = "$dir" ] && mark="*"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$mark" "$name" "${region:--}" "${origin:--}" "${user:--}" "$st"
    done
  } | awk -F'\t' '
      { for (i = 1; i <= 6; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) } }
      END { for (r = 1; r <= NR; r++) {
              line = ""
              for (i = 1; i < 6; i++) line = line sprintf("%-" w[i] "s  ", c[r, i])
              print line c[r, 6] } }'
  echo
  echo "* active in this shell · origin in () = read from the token · landscapes: $(printf '%s' "$cfg" | sed "s|^$HOME|~|")"
}

# Ask which of several keys to use; prints the choice, fails on cancel.
_cfuse_pick() {
  local name="$1" matches="$2" count choice
  count="$(printf '%s\n' "$matches" | grep -c .)"
  echo "'$name' has several logins:" >&2
  printf '%s\n' "$matches" |
    awk -F@ '{ printf "  %d) %-12s %s\n", NR, (NF > 1 ? $2 : "-"), (NF > 2 ? $3 : "-") }' >&2
  printf 'Choose [1-%d]: ' "$count" >&2
  read -r choice
  case "$choice" in
    ''|*[!0-9]*) return 1 ;;
  esac
  [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ] || return 1
  printf '%s\n' "$matches" | sed -n "${choice}p"
}

# Resolve <name> [region [origin]] to a login key; asks when several match.
_cfuse_resolve() {
  local name="$1" region="$2" origin="$3" matches
  if ! _cfuse_valid name "$name"; then
    echo "cfuse: invalid name '$name' (letters, digits, . _ -; must start with a letter or digit)" >&2
    return 1
  fi
  if _cfuse_is_command "$name"; then
    echo "cfuse: '$name' is a command, not a landscape name" >&2
    return 1
  fi
  if [ -n "$region" ] && ! _cfuse_valid region "$region"; then
    echo "cfuse: invalid region '$region'" >&2
    return 1
  fi
  if [ -n "$origin" ] && ! _cfuse_valid origin "$origin"; then
    echo "cfuse: invalid origin '$origin'" >&2
    return 1
  fi
  matches="$(_cfuse_matches "$name" "$region" "$origin")"
  case "$(printf '%s' "$matches" | grep -c .)" in
    0) printf '%s\n' "$name${region:+@$region}${origin:+@$origin}" ;;
    1) printf '%s\n' "$matches" ;;
    *) _cfuse_pick "$name" "$matches" || { echo "cfuse: cancelled" >&2; return 1; } ;;
  esac
}

# _cfuse_cfg_edit <awk program>: rewrite the landscapes file in place
# (cat >, so a symlinked file stays a symlink). Extra args go to awk.
_cfuse_cfg_edit() {
  local cfg tmp prog="$1"
  shift
  cfg="$(_cfuse_config)"
  [ -f "$cfg" ] || return 0
  tmp="$(mktemp)" || return 1
  if awk "$@" "$_CFUSE_AWK_KEY $prog" "$cfg" "$cfg" > "$tmp"; then
    cat "$tmp" > "$cfg"
  fi
  rm -f "$tmp"
}

# Record a detected origin: move the login folder to <name>@<region>@<origin>
# and add the origin to the matching landscapes line.
_cfuse_adopt() {
  local name="$1" region="$2" origin="$3" newdir
  newdir="$(_cfuse_root)/$name@$region@$origin"
  [ -d "$newdir" ] && rm -rf "$newdir"
  mv "$CF_HOME" "$newdir" || return 1
  export CF_HOME="$newdir"
  # Pass 1 notes whether a line with the origin exists; pass 2 then either
  # drops the origin-less line (duplicate) or appends the origin to it.
  _cfuse_cfg_edit '
    FNR == NR { if (linekey() == full) has = 1; next }
    linekey() == plain {
      if (has) next
      if (match($0, /[[:space:]]*#/)) { print substr($0, 1, RSTART - 1) " " o substr($0, RSTART); next }
      print $0 " " o; next
    }
    { print }' -v plain="$name@$region" -v full="$name@$region@$origin" -v o="$origin"
  echo "origin $origin detected – saved as $name@$region@$origin"
}

_cfuse_switch() {
  local key name region origin shown api root
  key="$(_cfuse_resolve "$@")" || return 1
  IFS=@ read -r name region origin <<< "$key"
  [ -n "$region" ] && api="https://api.cf.$region.hana.ondemand.com"

  root="$(_cfuse_root)"
  mkdir -p "$root" && chmod 700 "$root" || return
  export CF_HOME="$root/$key"
  mkdir -p "$CF_HOME" || return
  echo "CF_HOME → $CF_HOME"

  if ! cf oauth-token >/dev/null 2>&1; then
    echo "Not logged in – starting login…"
    local args=()
    [ "${CFUSE_SSO:-1}" = 0 ] || args+=(--sso)
    [ -n "$api" ] && args+=(-a "$api")
    [ -n "$origin" ] && args+=(--origin "$origin")
    cf login "${args[@]}" || return
  fi

  shown="$origin"
  if [ -z "$origin" ]; then
    shown="$(_cfuse_claim "$(_cfuse_claims "$CF_HOME")" origin)"
    if [ -n "$region" ]; then
      if _cfuse_valid origin "$shown"; then
        _cfuse_adopt "$name" "$region" "$shown"
      else
        echo "cfuse: couldn't read the origin from the token – keeping $key" >&2
        shown=""
      fi
    fi
  fi
  cf target | grep -E '^(API endpoint|user|org|space):'
  [ -z "$shown" ] || printf 'origin:         %s\n' "$shown"
}

# cfuse remove <name> [region [origin]] [-y]: delete a saved login and its landscapes line.
_cfuse_remove() {
  local yes=0 name="" region="" origin="" arg key dir cfg has_dir=0 has_line=0 answer
  for arg in "$@"; do
    case "$arg" in
      -y|--yes) yes=1 ;;
      -h|--help) _cfuse_help remove; return ;;
      -*) echo "cfuse: unknown option '$arg'" >&2; return 1 ;;
      *)
        if [ -z "$name" ]; then name="$arg"
        elif [ -z "$region" ]; then region="$arg"
        elif [ -z "$origin" ]; then origin="$arg"
        else echo "cfuse: unexpected argument '$arg'" >&2; return 1
        fi
        ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "cfuse: remove needs a name. Run 'cfuse help remove' for usage." >&2
    return 1
  fi

  key="$(_cfuse_resolve "$name" "$region" "$origin")" || return 1
  dir="$(_cfuse_root)/$key"
  cfg="$(_cfuse_config)"

  [ -d "$dir" ] && has_dir=1
  if [ -f "$cfg" ] && awk -v key="$key" "$_CFUSE_AWK_KEY"' linekey() == key { f = 1 } END { exit !f }' "$cfg"; then
    has_line=1
  fi
  if [ "$has_dir" = 0 ] && [ "$has_line" = 0 ]; then
    echo "cfuse: nothing to remove for '${key//@/ }'" >&2
    return 1
  fi

  echo "Remove ${key//@/ }:"
  [ "$has_dir" = 1 ] && echo "  - saved login  $dir"
  [ "$has_line" = 1 ] && echo "  - line         \"${key//@/ }\" in $cfg"
  if [ "$yes" = 0 ]; then
    printf 'Continue? [y/N] '
    read -r answer
    case "$answer" in
      y|Y|yes|YES) ;;
      *) echo "cfuse: cancelled" >&2; return 1 ;;
    esac
  fi

  [ "$has_dir" = 1 ] && rm -rf "$dir"
  [ "$has_line" = 1 ] && _cfuse_cfg_edit 'FNR == NR { next } linekey() == key { next } { print }' -v key="$key"
  if [ "$CF_HOME" = "$dir" ]; then
    unset CF_HOME
    echo "This shell used that login – CF_HOME unset (back to ~/.cf)."
  fi
  echo "Removed."
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
Usage: cfuse list [--check]    (also: cfuse, cfuse -l, cfuse --list; -c = --check)

Table of all logins: landscapes from the landscapes file plus logins you
have made. * marks the login active in this shell.

ORIGIN  identity provider; in () when read from the token, not configured.
USER    user of the saved login.
STATUS  logged in / token expired / not logged in – read locally from the
        saved token. "token expired" usually just means cf refreshes it on
        the next command. --check asks the server for each login instead
        (cf oauth-token; needs network, ~1–2 s per login): logged in /
        login needed.
EOF
    ;;
    discover) cat <<EOF
Usage: cfuse discover        (also: cfuse -d, cfuse --discover)

Print "name region" lines for every Cloud Foundry environment the btp CLI
can see, ready to paste into $(_cfuse_config).
Needs: btp (logged in via 'btp login --sso') and jq.
Covers the global account btp currently targets ('btp target' to switch).
Add an origin as third column yourself if a landscape needs a specific IdP.

Example: cfuse discover >> $(_cfuse_config)
EOF
    ;;
    remove) cat <<EOF
Usage: cfuse remove <name> [region [origin]] [-y]    (also: cfuse -r, cfuse --remove)

Delete a saved login (~/.cfuse/<name>@<region>@<origin>: token, target,
cf plugins) and its line in $(_cfuse_config). Nothing on BTP is changed.
Missing parts are looked up like for switching (asks if several match).
Asks before deleting; -y / --yes skips the question.

Examples: cfuse remove operayo eu10-005 sap.ids
          cfuse remove operayo -y
EOF
    ;;
    switch) cat <<'EOF'
Usage: cfuse <name> [region [origin]]

Switch this shell to a login; log in (SSO) if needed.
Every known login matching what you typed counts: one → used, several →
you pick, none → a new login from your arguments.
origin = identity provider key (e.g. sap.ids, or your custom IdP's key);
cf login gets --origin <origin>. Without it, cf uses the default IdP and
cfuse saves the origin it finds in the token, so it's known from then on.

Examples: cfuse operayo eu20-001 operayo-platform
          cfuse operayo eu20-001
          cfuse operayo
EOF
    ;;
    *) cat <<'EOF'
Usage: cfuse <command>
       cfuse <name> [region [origin]]

Commands:
  list, -l          table of logins (default; * = active in this shell)
  discover, -d      print landscape lines from the btp CLI
  remove, -r        delete a saved login and its landscapes line
  help, -h          this help

  <name> [region [origin]]   switch this shell to a login, log in if needed

Run 'cfuse help <command>' or 'cfuse <command> --help' for details
('cfuse help switch' for <name> [region [origin]]).

Landscapes: "name region [origin]" lines in $CFUSE_CONFIG
            (default ~/.config/cfuse/landscapes), e.g. "operayo eu20-001 sap.ids".
Logins:     stored under $CFUSE_HOME (default ~/.cfuse) as <name>@<region>@<origin>.
Login mode: SSO by default; set CFUSE_SSO=0 for user/password login.
EOF
    ;;
  esac
}

cfuse() {
  case "$1" in
    ""|list|-l|--list)
      case "$2" in
        "") _cfuse_list 0 ;;
        -c|--check) _cfuse_list 1 ;;
        -h|--help) _cfuse_help list ;;
        *)
          if [ "$1" = list ]; then
            echo "cfuse: 'list' is a command, not a landscape name" >&2
          else
            echo "cfuse: unexpected argument '$2'" >&2
          fi
          echo "Run 'cfuse help list' for usage." >&2
          return 1
          ;;
      esac
      ;;
    discover|-d|--discover)
      case "$2" in
        "") _cfuse_discover ;;
        -h|--help) _cfuse_help discover ;;
        *)
          if [ "$1" = discover ]; then
            echo "cfuse: 'discover' is a command, not a landscape name" >&2
          else
            echo "cfuse: unexpected argument '$2'" >&2
          fi
          echo "Run 'cfuse help discover' for usage." >&2
          return 1
          ;;
      esac
      ;;
    remove|-r|--remove) shift; _cfuse_remove "$@" ;;
    help|-h|--help) _cfuse_help "$2" ;;
    -*) echo "cfuse: unknown option '$1'" >&2; _cfuse_help >&2; return 1 ;;
    *)
      case "$2" in
        -h|--help) _cfuse_help switch; return ;;
      esac
      if [ -n "$4" ]; then
        echo "cfuse: unexpected argument '$4'. Run 'cfuse help switch' for usage." >&2
        return 1
      fi
      _cfuse_switch "$1" "$2" "$3"
      ;;
  esac
}
