# cfuse – bash entry point; add `source /path/to/cfuse.bash` to ~/.bashrc.

source "$(dirname "${BASH_SOURCE[0]}")/cfuse.sh"

_cfuse_complete() {
  local IFS=$'\n' words first="${COMP_WORDS[1]}"
  case "$first" in -r|--remove) first=remove ;; esac
  case "$COMP_CWORD" in
    1) words="${_CFUSE_COMMANDS// /$'\n'}"$'\n'"$(_cfuse_names)" ;;
    2)
      case "$first" in
        help|-h|--help) words=$'list\ndiscover\nremove\nswitch' ;;
        remove) words="$(_cfuse_names)" ;;
        *) words="$(_cfuse_regions_for "$first")" ;;
      esac
      ;;
    3) [ "$first" = remove ] || return 0
       words="$(_cfuse_regions_for "${COMP_WORDS[2]}")" ;;
    *) return 0 ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _cfuse_complete cfuse
