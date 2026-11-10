# cfuse

Keep several Cloud Foundry logins (e.g. different SAP BTP landscapes) active at
the same time — one per terminal — and switch with a single word.

```console
$ cfuse
Landscapes (~/.config/cfuse/landscapes):
   cust           eu10
 * dev            eu20-001
   prod           eu20-005

$ cfuse prod
CF_HOME → ~/.cfuse/prod
Not logged in – starting login…
...
```

Works in **zsh** and **bash** (incl. macOS bash 3.2 and dev containers).

## How it works

The cf CLI stores its login in `$CF_HOME/.cf/config.json` (default `~/.cf`).
`cfuse <name>` sets `CF_HOME=~/.cfuse/<name>` for the current shell, so every
name has its own token, API endpoint and org/space target. If that name is not
logged in yet (or the token has expired), it runs `cf login --sso -a <api>`.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/operayo/shell-plugins/main/install.sh | bash -s cfuse
```

oh-my-zsh users then add `cfuse` to `plugins=(...)` in `~/.zshrc`. Open a new
terminal afterwards. See the [main README](../../README.md#install) for what the
installer does.

**zsh plugin managers** (instead of the installer):

```sh
# antidote (.zsh_plugins.txt)
operayo/shell-plugins path:plugins/cfuse
# zinit
zinit ice pick"plugins/cfuse/cfuse.plugin.zsh"; zinit light operayo/shell-plugins
```

**Manually:** `source …/plugins/cfuse/cfuse.plugin.zsh` in `~/.zshrc` (after
`compinit`) or `source …/plugins/cfuse/cfuse.bash` in `~/.bashrc`.

## Configure landscapes

The installer creates `~/.config/cfuse/landscapes` from
[`landscapes.example`](landscapes.example). Edit it: one `name region` per line. The region is the part of the CF API endpoint
between `api.cf.` and `.hana.ondemand.com`:

```
dev   eu20-001     # https://api.cf.eu20-001.hana.ondemand.com
prod  eu20-005
```

Find your regions in the BTP Cockpit (subaccount → Overview → *Cloud Foundry
Environment* → API Endpoint), or let `cfuse --discover` list them (needs the
[btp CLI](https://tools.hana.ondemand.com/#cloud-btpcli) and `jq`, and
`btp login --sso` first):

```console
$ cfuse --discover
acme-dev eu20-001   # ACME Dev (org: acme-dev-org)
```

## Usage

| Command | Effect |
|---|---|
| `cfuse` | List landscapes and saved logins; `*` marks the active one |
| `cfuse <name>` | Switch this shell to `<name>`, log in if needed |
| `cfuse <name> <region>` | Same, for a name not in the config (or to override it) |
| `cfuse --discover` | Print config lines for all CF environments the btp CLI sees |
| `cfuse --help` | Help |
| `unset CF_HOME` | Back to the default `~/.cf` login |

`Tab` completes names in both shells.

| Variable | Default | Purpose |
|---|---|---|
| `CFUSE_CONFIG` | `~/.config/cfuse/landscapes` | Landscapes file |
| `CFUSE_HOME` | `~/.cfuse` | Where the per-name logins live |
| `CFUSE_SSO` | `1` | `0` = user/password login instead of `--sso` |

## Good to know

- The region only matters when a login starts. An existing login keeps the
  endpoint it was created with; run `cf login` again (or delete
  `~/.cfuse/<name>`) after changing its region.
- `CF_HOME` is per shell. A new terminal starts on the default `~/.cf` login
  until you run `cfuse`.
- Plain scripts, CI jobs and IDE tasks don't load your shell rc file; set
  `CF_HOME=~/.cfuse/<name>` there directly.
- cf plugins (e.g. `multiapps` for `cf deploy`) are installed per `CF_HOME`,
  so install them once per name.

## Dev containers

Install it in the container (needs `git` and `curl`), e.g. in `devcontainer.json`:

```jsonc
"postCreateCommand": "curl -fsSL https://raw.githubusercontent.com/operayo/shell-plugins/main/install.sh | bash -s cfuse"
```

Logins live inside the container and are lost on rebuild. To keep them, mount
a volume on `~/.cfuse`:

```jsonc
"mounts": ["source=cfuse-logins,target=/home/vscode/.cfuse,type=volume"]
```

To share landscapes with the team, commit a landscapes file to the project and
point `CFUSE_CONFIG` at it (`"remoteEnv": { "CFUSE_CONFIG": "${containerWorkspaceFolder}/.cfuse-landscapes" }`).
