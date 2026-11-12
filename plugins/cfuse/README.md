# cfuse

Keep several Cloud Foundry logins (e.g. different SAP BTP landscapes and
identity providers) active at the same time — one per terminal — and switch
with a single command.

```console
$ cfuse
   NAME      REGION    ORIGIN            USER                 STATUS
*  operayo   eu20-001  operayo-platform  me@operayo.de        logged in
   operayo   eu20-001  sap.ids           me@operayo.de        token expired
   customer  eu10      -                 -                    not logged in

* active in this shell · origin in () = read from the token · landscapes: ~/.config/cfuse/landscapes

$ cfuse operayo eu20-001 sap.ids
CF_HOME → ~/.cfuse/operayo@eu20-001@sap.ids
...
```

Works in **zsh** and **bash** (incl. macOS bash 3.2 and dev containers).

## How it works

The cf CLI stores its login in `$CF_HOME/.cf/config.json` (default `~/.cf`).
`cfuse <name> <region> <origin>` sets
`CF_HOME=~/.cfuse/<name>@<region>@<origin>` for the current shell, so every
landscape + identity provider has its own token, API endpoint and org/space
target. If it is not logged in yet (or the token has expired), it runs
`cf login --sso -a https://api.cf.<region>.hana.ondemand.com --origin <origin>`.

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
| `cfuse <name> [region [origin]]` | | Switch this shell to a login, log in if needed (see below) |
| `cfuse list [--check]` | `cfuse`, `-l` | Table of logins; `*` marks the active one |
| `cfuse discover` | `-d` | Print landscape lines for all CF environments the btp CLI sees |
| `cfuse remove <name> [region [origin]]` | `-r` | Delete a saved login and its landscapes line (asks first; `-y` skips) |
| `cfuse help [command]` | `-h` | Help; also `cfuse <command> --help` |
| `unset CF_HOME` | | Back to the default `~/.cf` login |

The long options `--list`, `--discover`, `--remove` and `--help` work too.
`list`, `discover`, `remove` and `help` are reserved and can't be used as
landscape names.

`Tab` completes commands and names, then regions, then origins, in both
shells (and after `remove` the same; after `help` the command names).

**Which login `cfuse <name> [region [origin]]` uses:** every known login —
from the landscapes file and from saved logins — that matches what you typed
counts:

- exactly one → that one
- several → `cfuse` lists them (region + origin) and asks which (Enter cancels)
- none → a new login from your arguments

So with one login per name, typing the name is enough; otherwise add region
and origin or pick one.

**Origin (identity provider):** `sap.ids` is the default SAP IdP; a custom
IdP has its own origin key (BTP Cockpit → subaccount → Security → Trust
Configuration). With an origin, `cfuse` logs in with `--origin <origin>`.
Without one, cf uses the default login page (where you may pick the IdP), and
right after the login `cfuse` reads the origin from the new token and records
it: the login folder becomes `<name>@<region>@<origin>` and the landscapes
line gets the origin as third column. From then on it's known — and older
logins without origin are upgraded the same way the next time you switch to
them. If a folder for that origin already exists, the fresh login replaces it.

**List columns:** ORIGIN in `()` is read from the token, not configured.
STATUS is read locally from the saved token: `logged in`, `token expired`
(usually fine — cf refreshes it on the next command), `not logged in`, or
`unknown` (token not readable). `cfuse list --check` asks the server for every
login instead (`cf oauth-token`, needs network, ~1–2 s per login): `logged in`
or `login needed`.

**Removing:** `cfuse remove operayo eu20-001 sap.ids` deletes the saved login
(`~/.cfuse/operayo@eu20-001@sap.ids`: token, target and cf plugins installed
under it) and the matching line in the landscapes file, after showing both and
asking. Nothing on BTP changes. If the current shell used that login,
`CF_HOME` is unset; other terminals still on it need a new `cfuse`.

## Landscapes (optional)

`~/.config/cfuse/landscapes` gives your landscapes short names, so `cfuse`
can list and complete them before your first login. The installer creates it
from [`landscapes.example`](landscapes.example) with all entries commented out.
One `name region [origin]` per line, `#` starts a comment:

```
operayo   eu20-001   operayo-platform   # https://api.cf.eu20-001.hana.ondemand.com
operayo   eu20-001   sap.ids
customer  eu10                          # origin added after the first login
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

Names, regions and origins must start with a letter or digit and may contain
letters, digits, `.`, `_` and `-` (regions: lowercase). Invalid or reserved
entries are skipped with a warning.

Without the file, `cfuse <name> <region>` works just the same, and logins you
have made show up in the list and in completion.

| Variable | Default | Purpose |
|---|---|---|
| `CFUSE_CONFIG` | `~/.config/cfuse/landscapes` | Landscapes file |
| `CFUSE_HOME` | `~/.cfuse` | Where the logins live (kept at mode `700`) |
| `CFUSE_SSO` | `1` | `0` = user/password login instead of `--sso` |

## Security

- Tokens stay where cf puts them (`config.json`, mode `600`). `cfuse` only
  decodes the readable claims (origin, user, expiry) for display — through
  pipes, never as command arguments, never printed or copied elsewhere.
- `~/.cfuse` is kept at mode `700`, so other users on the machine can't list
  your login names (which often contain customer names).
- Values from the landscapes file or the token are validated before they're
  used as folder names, so a shared landscapes file can't point outside
  `~/.cfuse`.
- Several logins mean several live tokens on disk; remove the ones you no
  longer need with `cfuse remove`.

## Good to know

- `CF_HOME` is per shell. A new terminal starts on the default `~/.cf` login
  until you run `cfuse`.
- Plain scripts, CI jobs and IDE tasks don't load your shell rc file; set
  `CF_HOME=~/.cfuse/<name>@<region>@<origin>` there directly.
- cf plugins (e.g. `multiapps` for `cf deploy`) are installed per `CF_HOME`,
  so install them once per login.
- Logins from older cfuse versions (`~/.cfuse/<name>` or
  `~/.cfuse/<name>@<region>`) keep working; ones with a region get their
  origin added the next time you switch to them.

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
