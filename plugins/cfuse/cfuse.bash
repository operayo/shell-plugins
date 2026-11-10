# cfuse – bash entry point; add `source /path/to/cfuse.bash` to ~/.bashrc.

source "$(dirname "${BASH_SOURCE[0]}")/cfuse.sh"

_cfuse_complete() {
  local IFS=$'\n' words
  case "$COMP_CWORD" in
    1) words="${_CFUSE_COMMANDS// /$'\n'}"$'\n'"$(_cfuse_names)" ;;
    2)
      case "${COMP_WORDS[1]}" in
        help|-h|--help) words=$'list\ndiscover\nswitch' ;;
        *) words="$(_cfuse_regions_for "${COMP_WORDS[1]}")" ;;
      esac
      ;;
    *) return 0 ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _cfuse_complete cfuse
