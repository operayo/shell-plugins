#!/usr/bin/env bash
# Tests for plugins/cfuse/cfuse.sh, run in bash and zsh: tests/cfuse_test.sh
#
# Everything runs against throwaway HOME / CFUSE_CONFIG / CFUSE_HOME folders;
# cf and btp are never called.
#
# The invalid-byte cases only bite where awk quotes the offending line in its
# error message (macOS awk in a UTF-8 locale); elsewhere they pass trivially.

CFUSE="$(cd "$(dirname "$0")/.." && pwd)/plugins/cfuse/cfuse.sh"
LOCALE="${CFUSE_TEST_LOCALE:-en_US.UTF-8}"
T="$(mktemp -d)" || exit 1
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home"
cfg="$T/home/landscapes"
footer='* active in this shell · origin in () = read from the token · landscapes: ~/landscapes'
pass=0
fail=0

# run <shell> <command...>: output in $T/out and $T/err, exit status in $rc.
run() {
  local sh="$1" flags
  shift
  case "$sh" in
    bash) flags="--noprofile --norc" ;;
    zsh) flags="-f" ;;
  esac
  # shellcheck disable=SC2086
  env -i HOME="$T/home" PATH="$PATH" LANG="$LOCALE" CFUSE_CONFIG="$cfg" CFUSE_HOME="$T/home/.cfuse" \
    "$sh" $flags -c '. "$1"; shift; "$@"' _ "$CFUSE" "$@" > "$T/out" 2> "$T/err" < /dev/null
  rc=$?
}

ok() {
  pass=$((pass + 1))
}

ko() {
  fail=$((fail + 1))
  echo "FAIL [$sh] $1"
}

# same <label> <out|err>: the captured stream equals $T/exp.
same() {
  if cmp -s "$T/exp" "$T/$2"; then
    ok
  else
    ko "$1"
    diff "$T/exp" "$T/$2" | cat -v | sed 's/^/    /'
  fi
}

# status <label> <expected>
status() {
  if [ "$rc" = "$2" ]; then ok; else ko "$1 (exit $rc, expected $2)"; fi
}

# clean <label>: no control characters reach the terminal – stdout is free of
# C0 and DEL, stderr is printable ASCII only.
clean() {
  local n m
  n="$(LC_ALL=C tr -cd '\000-\010\013-\037\177' < "$T/out" | wc -c)"
  m="$(LC_ALL=C tr -d '\040-\176\n' < "$T/err" | wc -c)"
  if [ "$n" -eq 0 ] && [ "$m" -eq 0 ]; then
    ok
  else
    ko "$1 ($((n)) control bytes on stdout, $((m)) non-printable bytes on stderr)"
  fi
}

# Does this awk give up on a byte that is invalid in the locale?
awk_aborts() {
  ! printf 'a # \374b\n' | LANG="$LOCALE" awk '{ sub(/#.*/, "") } 1' > /dev/null 2>&1
}

for sh in bash zsh; do
  command -v "$sh" > /dev/null 2>&1 || { echo "skip: $sh not found"; continue; }

  # --- behaviour that has to stay as it is ---

  printf 'first eu10\nsecond eu20 sap.ids  # comment\n' > "$cfg"
  run "$sh" cfuse list
  {
    fmt='%-1s  %-6s  %-6s  %-7s  %-4s  %s\n'
    printf "$fmt" ' ' NAME REGION ORIGIN USER STATUS
    printf "$fmt" ' ' first eu10 - - 'not logged in'
    printf "$fmt" ' ' second eu20 sap.ids - 'not logged in'
    printf '\n%s\n' "$footer"
  } > "$T/exp"
  same "list: table" out
  : > "$T/exp"
  same "list: no warning for a clean file" err
  status "list: exit status" 0

  printf 'good eu10\nlist eu10\nbad! eu10\n.hidden eu10\n' > "$cfg"
  run "$sh" cfuse list
  {
    fmt='%-1s  %-4s  %-6s  %-6s  %-4s  %s\n'
    printf "$fmt" ' ' NAME REGION ORIGIN USER STATUS
    printf "$fmt" ' ' good eu10 - - 'not logged in'
    printf '\n%s\n' "$footer"
  } > "$T/exp"
  same "list: invalid and reserved entries are left out" out
  printf 'cfuse: skipping invalid or reserved entries in %s: list@eu10 bad!@eu10 .hidden@eu10\n' "$cfg" > "$T/exp"
  same "list: warning names the skipped entries" err

  # A Latin-1 byte in a comment: which lines are read must not change.
  printf 'first eu10\nkunde eu10 # M\374ller GmbH\nlast eu20\n' > "$cfg"
  run "$sh" _cfuse_keys
  if awk_aborts; then
    printf 'first@eu10\n' > "$T/exp"
  else
    printf 'first@eu10\nkunde@eu10\nlast@eu20\n' > "$T/exp"
  fi
  same "keys: lines read from a file with an invalid byte" out

  run "$sh" cfuse remove nosuch -y
  status "remove: nothing to remove" 1

  printf 'keep eu10\ngone eu20  # comment\n' > "$cfg"
  run "$sh" cfuse remove gone -y
  status "remove: exit status" 0
  printf 'keep eu10\n' > "$T/exp"
  if cmp -s "$T/exp" "$cfg"; then ok; else ko "remove: line is deleted from the landscapes file"; fi

  # --- nothing from the landscapes file may control the terminal ---

  printf 'ok eu10\nx\033]0;title\007\033[2J\033[HFAKE eu10\n' > "$cfg"
  run "$sh" cfuse list
  clean "list: raw escape sequences in a rejected entry"

  printf 'ok eu10\ny\\e[2J\\x1b[H\\0033[2JFAKE eu10\n' > "$cfg"
  run "$sh" cfuse list
  clean "list: backslash escapes in a rejected entry"
  printf 'cfuse: skipping invalid or reserved entries in %s: y\\e[2J\\x1b[H\\0033[2JFAKE@eu10\n' "$cfg" > "$T/exp"
  same "list: backslash escapes are shown as written" err

  printf 'ok eu10\nx\377\033]0;title\007\033[2J\033[HFAKE eu10\n' > "$cfg"
  cp "$cfg" "$T/cfg.orig"
  run "$sh" cfuse list
  clean "list: escape sequences after an invalid byte"
  run "$sh" cfuse remove nosuch -y
  clean "remove: escape sequences after an invalid byte"
  status "remove: exit status with an invalid byte" 1
  run "$sh" _cfuse_cfg_edit 'FNR == NR { next } linekey() == key { next } { print }' -v key=nosuch@eu10
  clean "edit: escape sequences after an invalid byte"
  if cmp -s "$cfg" "$T/cfg.orig"; then ok; else ko "edit: landscapes file left as it was"; fi
done

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
