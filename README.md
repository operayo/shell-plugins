# shell-plugins

Small shell helpers for everyday developer work. Each plugin lives in its own
folder under `plugins/` and works in zsh and bash unless noted.

| Plugin | What it does |
|---|---|
| [cfuse](plugins/cfuse/README.md) | Several Cloud Foundry logins side by side, switch with `cfuse <name>` |

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/operayo/shell-plugins/main/install.sh | bash
```

This clones the repo to `~/.shell-plugins` (override with `SHELL_PLUGINS_DIR`)
and installs all plugins. For specific plugins only: `… | bash -s cfuse`.

Or from your own clone: `git clone https://github.com/operayo/shell-plugins.git && ./shell-plugins/install.sh`

What the installer does, per plugin:

- **oh-my-zsh:** links the plugin into `$ZSH_CUSTOM/plugins/` and tells you to
  add its name to `plugins=(...)` in `~/.zshrc`
- **zsh without oh-my-zsh:** adds a marked `source` line to `~/.zshrc`
- **bash** (if `~/.bashrc` exists or bash is your shell): adds a marked
  `source` line to `~/.bashrc`
- **config:** copies `<file>.example` to `~/.config/<plugin>/<file>` if it
  doesn't exist yet

Re-running it is safe. Run it again after moving your clone, and it fixes the
paths. To update: run the `curl` line again, or `git pull` in your clone.

To uninstall: remove the plugin from `plugins=(...)` / delete the lines marked
`# shell-plugins:<name>` from your rc files.

## Adding a plugin

```
plugins/<name>/
├── <name>.sh            # shared logic, bash + zsh compatible
├── <name>.plugin.zsh    # zsh entry: sources <name>.sh, adds completion
├── <name>.bash          # bash entry: sources <name>.sh, adds completion
├── <file>.example       # optional, installed to ~/.config/<name>/<file>
└── README.md
```

`install.sh` picks up new plugin folders automatically.

Keep personal settings (endpoints, names, tokens) out of the repo — read them
from a config file under `~/.config/<name>/` instead.

## Maintainer

Madhusudhanan Perumalswamy ([@mperumalswamy](https://github.com/mperumalswamy))

## License

[MIT](LICENSE) © operayo GmbH
