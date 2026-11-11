# cfuse – zsh entry point (oh-my-zsh plugin or plain `source`).

source "${0:A:h}/cfuse.sh"

_cfuse() {
  local first=$words[2]
  [[ $first == (-r|--remove) ]] && first=remove
  case $CURRENT in
    2) compadd -- ${=_CFUSE_COMMANDS} ${(f)"$(_cfuse_names)"} ;;
    3)
      case $first in
        help|-h|--help) compadd -- list discover remove switch ;;
        remove) compadd -- ${(f)"$(_cfuse_names)"} ;;
        *) compadd -- ${(f)"$(_cfuse_regions_for "$first")"} ;;
      esac
      ;;
    4) [[ $first == remove ]] && compadd -- ${(f)"$(_cfuse_regions_for "$words[3]")"} ;;
  esac
}

(( $+functions[compdef] )) && compdef _cfuse cfuse
