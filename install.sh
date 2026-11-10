#!/usr/bin/env bash
# shell-plugins installer.
#   ./install.sh [plugin...]                     from a checkout
#   curl -fsSL https://raw.githubusercontent.com/operayo/shell-plugins/main/install.sh | bash [-s plugin...]
# Safe to re-run: after a `git pull` or after moving the checkout.
set -euo pipefail

REPO_URL="${SHELL_PLUGINS_REPO:-https://github.com/operayo/shell-plugins.git}"
MARK="# shell-plugins:"

say() { printf '%s\n' "$*"; }

# Use the checkout this script lives in; when piped (curl | bash), clone or update one.
src="${BASH_SOURCE[0]:-}"
if [ -n "$src" ] && [ -f "$src" ] && [ -d "$(dirname "$src")/plugins" ]; then
  root="$(cd "$(dirname "$src")" && pwd -P)"
else
  root="${SHELL_PLUGINS_DIR:-$HOME/.shell-plugins}"
  if [ -d "$root/.git" ]; then
    say "Updating $root"
    git -C "$root" pull --ff-only -q
  else
    say "Cloning into $root"
    git clone -q "$REPO_URL" "$root"
  fi
fi

if [ $# -gt 0 ]; then
  names=("$@")
else
  names=()
  for d in "$root"/plugins/*/; do names+=("$(basename "$d")"); done
fi

# Add or update the marked source line for a plugin in an rc file.
ensure_source() {
  local rc="$1" entry="$2" tag="$MARK$3" line
  line="[ -f \"${entry/#$HOME/\$HOME}\" ] && source \"${entry/#$HOME/\$HOME}\"  $tag"
  [ -f "$rc" ] || : > "$rc"
  if grep -qF "$tag" "$rc"; then
    # Rewrite in place (cat >) so symlinked dotfiles stay symlinks.
    local tmp
    tmp="$(mktemp)"
    awk -v tag="$tag" -v line="$line" 'index($0, tag) { print line; next } { print }' "$rc" > "$tmp"
    cat "$tmp" > "$rc"
    rm -f "$tmp"
    say "  updated $rc"
  else
    printf '\n%s\n' "$line" >> "$rc"
    say "  added to $rc"
  fi
}

omz="${ZSH:-$HOME/.oh-my-zsh}"
omz_custom="${ZSH_CUSTOM:-$omz/custom}"

for name in "${names[@]}"; do
  dir="$root/plugins/$name"
  [ -d "$dir" ] || { say "Unknown plugin '$name'" >&2; exit 1; }
  say "$name:"

  if [ -f "$dir/$name.plugin.zsh" ]; then
    if [ -d "$omz" ]; then
      target="$omz_custom/plugins/$name"
      if [ -e "$target" ] && [ ! -L "$target" ]; then
        say "  skipped oh-my-zsh link: $target exists and is not a link"
      else
        mkdir -p "$omz_custom/plugins"
        ln -sfn "$dir" "$target"
        say "  linked $target"
        grep -v '^[[:space:]]*#' "$HOME/.zshrc" 2>/dev/null | grep -qw "$name" ||
          say "  → add '$name' to plugins=(...) in ~/.zshrc"
      fi
    elif [ -f "$HOME/.zshrc" ] || [ "$(basename "${SHELL:-}")" = zsh ]; then
      ensure_source "$HOME/.zshrc" "$dir/$name.plugin.zsh" "$name"
    fi
  fi

  if [ -f "$dir/$name.bash" ] && { [ -f "$HOME/.bashrc" ] || [ "$(basename "${SHELL:-}")" = bash ]; }; then
    ensure_source "$HOME/.bashrc" "$dir/$name.bash" "$name"
  fi

  # foo.example → ~/.config/<plugin>/foo, never overwriting.
  for ex in "$dir"/*.example; do
    [ -f "$ex" ] || continue
    cfg="${XDG_CONFIG_HOME:-$HOME/.config}/$name/$(basename "$ex" .example)"
    if [ ! -e "$cfg" ]; then
      mkdir -p "$(dirname "$cfg")"
      cp "$ex" "$cfg"
      say "  created $cfg – edit it"
    fi
  done
done

say "Done. Open a new terminal to use it."
