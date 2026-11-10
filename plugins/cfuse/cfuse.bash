# cfuse – bash entry point; add `source /path/to/cfuse.bash` to ~/.bashrc.

source "$(dirname "${BASH_SOURCE[0]}")/cfuse.sh"

_cfuse_complete() {
  [ "$COMP_CWORD" -eq 1 ] || return 0
  local IFS=$'\n'
  COMPREPLY=($(compgen -W "$(_cfuse_names)"$'\n--list\n--discover\n--help' -- "${COMP_WORDS[1]}"))
}

complete -F _cfuse_complete cfuse
