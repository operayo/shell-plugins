# cfuse – zsh entry point (oh-my-zsh plugin or plain `source`).

source "${0:A:h}/cfuse.sh"

_cfuse() {
  local first=$words[2] off=0
  [[ $first == (-r|--remove) ]] && first=remove
  case $first in
    help|-h|--help) (( CURRENT == 3 )) && compadd -- list discover remove switch; return ;;
    list|-l|--list) (( CURRENT == 3 )) && compadd -- --check; return ;;
    discover|-d|--discover) return ;;
    remove) off=1 ;;
  esac
  # Position within <name> [region [origin]], shifted by one after `remove`.
  case $(( CURRENT - off )) in
    2) compadd -- ${(f)"$(_cfuse_names)"}; (( off )) || compadd -- ${=_CFUSE_COMMANDS} ;;
    3) compadd -- ${(f)"$(_cfuse_regions_for "$words[2+off]")"} ;;
    4) compadd -- ${(f)"$(_cfuse_origins_for "$words[2+off]" "$words[3+off]")"} ;;
  esac
}

(( $+functions[compdef] )) && compdef _cfuse cfuse
