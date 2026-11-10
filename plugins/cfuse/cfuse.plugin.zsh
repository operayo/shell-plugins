# cfuse – zsh entry point (oh-my-zsh plugin or plain `source`).

source "${0:A:h}/cfuse.sh"

_cfuse() {
  if (( CURRENT == 2 )); then
    compadd -- ${(f)"$(_cfuse_names)"} --list --discover --help
  fi
}

(( $+functions[compdef] )) && compdef _cfuse cfuse
