# cfuse – bash entry point; add `source /path/to/cfuse.bash` to ~/.bashrc.

source "$(dirname "${BASH_SOURCE[0]}")/cfuse.sh"

_cfuse_complete() {
  local IFS=$'\n' words first="${COMP_WORDS[1]}" off=0
  COMPREPLY=()
  case "$first" in -r|--remove) first=remove ;; esac
  case "$first" in
    help|-h|--help) [ "$COMP_CWORD" -eq 2 ] && words=$'list\ndiscover\nremove\nswitch' ;;
    list|-l|--list) [ "$COMP_CWORD" -eq 2 ] && words='--check' ;;
    discover|-d|--discover) ;;
    *)
      [ "$first" = remove ] && off=1
      # Position within <name> [region [origin]], shifted by one after `remove`.
      case $((COMP_CWORD - off)) in
        1)
          words="$(_cfuse_names)"
          [ "$off" = 1 ] || words="${_CFUSE_COMMANDS// /$'\n'}"$'\n'"$words"
          ;;
        2) words="$(_cfuse_regions_for "${COMP_WORDS[1 + off]}")" ;;
        3) words="$(_cfuse_origins_for "${COMP_WORDS[1 + off]}" "${COMP_WORDS[2 + off]}")" ;;
      esac
      ;;
  esac
  [ -n "$words" ] || return 0
  COMPREPLY=($(compgen -W "$words" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _cfuse_complete cfuse
