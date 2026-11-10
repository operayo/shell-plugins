# cfuse – zsh entry point (oh-my-zsh plugin or plain `source`).

source "${0:A:h}/cfuse.sh"

_cfuse() {
  case $CURRENT in
    2) compadd -- ${=_CFUSE_COMMANDS} ${(f)"$(_cfuse_names)"} ;;
    3)
      if [[ $words[2] == (help|-h|--help) ]]; then
        compadd -- list discover switch
      else
        compadd -- ${(f)"$(_cfuse_regions_for "$words[2]")"}
      fi
      ;;
  esac
}

(( $+functions[compdef] )) && compdef _cfuse cfuse
