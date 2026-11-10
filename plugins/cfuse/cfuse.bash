# cfuse – bash entry point; add `source /path/to/cfuse.bash` to ~/.bashrc.

source "$(dirname "${BASH_SOURCE[0]}")/cfuse.sh"

_cfuse_complete() {
  local IFS=$'\n' words
  case "$COMP_CWORD" in
    1) words="$(_cfuse_names)"$'\n--list\n--discover\n--help' ;;
    2) words="$(_cfuse_regions_for "${COMP_WORDS[1]}")" ;;
    *) return 0 ;;
  esac
  COMPREPLY=($(compgen -W "$words" -- "${COMP_WORDS[COMP_CWORD]}"))
}

complete -F _cfuse_complete cfuse
