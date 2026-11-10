# cfuse

Keep several Cloud Foundry logins (e.g. different SAP BTP landscapes) active at
the same time — one per terminal — and switch with a single command.

```console
$ cfuse
   customer       eu10
 * operayo        eu20-001
   operayo        eu10-005

$ cfuse operayo eu10-005
CF_HOME → ~/.cfuse/operayo@eu10-005
Not logged in – starting login…
...
```

Works in **zsh** and **bash** (incl. macOS bash 3.2 and dev containers).

## How it works

The cf CLI stores its login in `$CF_HOME/.cf/config.json` (default `~/.cf`).
`cfuse <name> <region>` sets `CF_HOME=~/.cfuse/<name>@<region>` for the current
shell, so every name + region has its own token, API endpoint and org/space
target. If it is not logged in yet (or the token has expired), it runs
`cf login --sso -a https://api.cf.<region>.hana.ondemand.com`.

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

## Usage

| Command | Short | Effect |
|---|---|---|
| `cfuse <name> <region>` | | Switch this shell to `<name>` on `<region>`, log in if needed |
| `cfuse <name>` | | Same, with the region looked up (see below) |
| `cfuse list` | `cfuse`, `-l` | List logins and landscapes; `*` marks the active one |
| `cfuse discover` | `-d` | Print landscape lines for all CF environments the btp CLI sees |
| `cfuse help [command]` | `-h` | Help; also `cfuse <command> --help` |
| `unset CF_HOME` | | Back to the default `~/.cf` login |

The long options `--list`, `--discover` and `--help` work too. `list`,
`discover` and `help` are reserved and can't be used as landscape names.

`Tab` completes commands and names, after a name its regions, and after
`help` the command names, in both shells.

**Which region `cfuse <name>` uses:** the regions known for that name — from
the landscapes file and from saved logins — are combined:

- exactly one → that one
- several → `cfuse` lists them and asks which (Enter cancels)
- none → a login without region (`~/.cfuse/<name>`); cf asks for the API endpoint

So with a single landscape per name, typing the name is enough; with several,
add the region or pick one.

## Landscapes (optional)

`~/.config/cfuse/landscapes` gives your landscapes short names, so `cfuse`
can list and complete them before your first login. The installer creates it
from [`landscapes.example`](landscapes.example) with all entries commented out.
One `name region` per line; a name may appear once per region:

```
operayo   eu20-001     # https://api.cf.eu20-001.hana.ondemand.com
operayo   eu10-005
customer  eu10
```

The region is the part of the CF API endpoint between `api.cf.` and
`.hana.ondemand.com`. Find it in the BTP Cockpit (subaccount → Overview →
*Cloud Foundry Environment* → API Endpoint), or let `cfuse discover` list
them (needs the [btp CLI](https://tools.hana.ondemand.com/#cloud-btpcli) and
`jq`, and `btp login --sso` first):

```console
$ cfuse discover
acme-dev eu20-001   # ACME Dev (org: acme-dev-org)
```

Without the file, `cfuse <name> <region>` works just the same, and logins you
have made show up in the list and in completion.

| Variable | Default | Purpose |
|---|---|---|
| `CFUSE_CONFIG` | `~/.config/cfuse/landscapes` | Landscapes file |
| `CFUSE_HOME` | `~/.cfuse` | Where the logins live |
| `CFUSE_SSO` | `1` | `0` = user/password login instead of `--sso` |

## Good to know

- `CF_HOME` is per shell. A new terminal starts on the default `~/.cf` login
  until you run `cfuse`.
- Plain scripts, CI jobs and IDE tasks don't load your shell rc file; set
  `CF_HOME=~/.cfuse/<name>@<region>` there directly.
- cf plugins (e.g. `multiapps` for `cf deploy`) are installed per `CF_HOME`,
  so install them once per login.
- Logins from older cfuse versions (`~/.cfuse/<name>`) still work as logins
  without region; log in once with `cfuse <name> <region>` to switch to the
  new layout.

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
