# cfuse – zsh entry point (oh-my-zsh plugin or plain `source`).

source "${0:A:h}/cfuse.sh"

_cfuse() {
  case $CURRENT in
    2) compadd -- ${(f)"$(_cfuse_names)"} --list --discover --help ;;
    3) compadd -- ${(f)"$(_cfuse_regions_for "$words[2]")"} ;;
  esac
}

(( $+functions[compdef] )) && compdef _cfuse cfuse
