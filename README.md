# osint-toolbox

A single Docker image that bundles three command-line OSINT tools behind one
launcher. Run them from an interactive menu, or feed a list of targets and get
one Markdown report back. Everything runs inside the container, so your host
system stays clean and nothing is installed on it permanently.

---

## ⚠️ Disclaimer — read before use

This is a **research and educational project**. It wraps existing open-source
tools that query **publicly available** sources (public profiles, public
breach indexes, DNS/WHOIS, search engines).

**Public does not mean consequence-free.** Aggregating and cross-referencing
public information about a person can still be unlawful depending on **why** you
do it and **where** you are. Depending on jurisdiction, using it to stalk,
harass, profile, dox, or otherwise target an individual without authorization
can expose you to civil and criminal liability (for example under GDPR and
anti-stalking or computer-misuse laws). The lawful purpose is what matters, not
the fact that the data is reachable.

Use this project **only** to:

- investigate your own accounts and digital footprint,
- perform security research with explicit authorization, or
- learn how OSINT techniques and tooling work.

**Do not** use it to target other people without their consent. You are solely
responsible for how you use it; the authors accept no liability for misuse. If
you are unsure whether your intended use is lawful, do not proceed.

---

## What's inside

| Tool | Purpose | Input |
|------|---------|-------|
| [mosint](https://github.com/alpkeskin/mosint) | Email OSINT (breaches, linked services, pastes) | email |
| [gosearch](https://github.com/ibnaleem/gosearch) | Username across 300+ sites + breach data | username |
| [user-scanner](https://github.com/kaifcodec/user-scanner) | Username **and** email across 1000+ platforms | username / email |

All three are non-interactive, which is why they work both in the menu and in
batch mode. Each tool keeps its own upstream license; this project is only a
packaging/automation layer around them.

---

## Prerequisites

- **Docker** installed and running. Verify with:
  ```bash
  docker --version
  ```
  If this fails, install Docker Engine first (see docs.docker.com). Nothing else
  is required on the host: Go, Python and the tools all live inside the image.

---

## 1. Build the image

Clone the repo, then build from the folder that contains the `Dockerfile`:

```bash
git clone https://github.com/<your-user>/osint-toolbox.git
cd osint-toolbox
docker build -t osint-toolbox .
```

The first build takes a few minutes: it compiles the Go tools and installs the
Python one. You only build once; after that, starting a container is instant.

> **What build does.** It reads the `Dockerfile` recipe and produces a reusable
> *image* named `osint-toolbox`. An image is a frozen environment; each time you
> run it you get a fresh, isolated *container*.

---

## 2. Interactive mode (menu)

```bash
docker run --rm -it osint-toolbox
```

Pick a number, type the target, read the results. `q` quits.

- `-it` gives the container an interactive terminal. **It is required for the
  menu** — without it the menu prints once and then exits, because there is no
  input stream to read your choice from.
- `--rm` deletes the container when you exit. The *image* stays, so the next run
  is instant.

Before running a tool, the launcher echoes the exact command (e.g.
`+ gosearch -u alice`) so you can see precisely what is executed.

---

## 3. Batch mode (a list → one report)

Batch mode runs the tools over many targets unattended and writes a single
Markdown report, organized by target and by tool.

### 3.1 Prepare a list

One target per line. A line with `@` is treated as an email, otherwise as a
username. Blank lines and lines starting with `#` are ignored. See
[`targets.example.txt`](targets.example.txt):

```
# usernames
alice
bob_dev
# emails
someone@example.com
```

### 3.2 Run it

Batch mode does **not** need `-it`. It needs two *mounts* (`-v`): one for the
input list, one for the output directory.

```bash
mkdir -p ~/osint-out

docker run --rm \
  -v "$HOME/targets.txt:/opt/osint/targets.txt:ro" \
  -v "$HOME/osint-out:/opt/osint/out" \
  osint-toolbox batch --targets /opt/osint/targets.txt --outdir /opt/osint/out
```

The report appears on **your machine** at `~/osint-out/report-YYYYMMDD-HHMMSS.md`.

### 3.3 How mounts work (and where the report goes)

A mount is a bridge between a host path and a container path:

```
-v  <path on your PC>  :  <path inside the container>
```

- The left side is on **your machine** — this is where you look for results.
- The right side exists **only inside the container**, which is destroyed by
  `--rm`. A path like `/opt/osint/out` is meaningless in your normal shell.

So **always look on the left-hand side** (here `~/osint-out`) for your report.
Without the output mount, anything the container writes disappears with it —
that is the whole point of a disposable container, and the mount is the
controlled exception that lets you keep exactly the files you want.

Two things that must line up:

- Create the host output directory first (`mkdir -p ~/osint-out`); otherwise
  Docker creates it as `root` and you may not be able to write to it.
- The path you mount the list to and the `--targets` value must be identical
  (`/opt/osint/targets.txt` in both). Paths are **case-sensitive** on Linux:
  `searchList.txt` and `searchlist.txt` are different files, and if the source
  path does not exist Docker silently creates it as an empty **directory**,
  which then shows up as "file not found".

### 3.4 Options

| Flag | Meaning |
|------|---------|
| `--targets FILE` | the list file (required) |
| `--outdir DIR` | where to write the report (default `out`) |
| `--timeout N` | max seconds per tool, so one slow tool can't stall the list (default 300) |

---

## 4. mosint needs a config file

`mosint` starts but stops immediately unless it finds `~/.mosint.yaml`, because
most of its lookups need API keys. Create it once on the host:

```bash
curl -fsSL https://raw.githubusercontent.com/alpkeskin/mosint/master/example-config.yaml -o ~/.mosint.yaml
chmod 600 ~/.mosint.yaml
```

You can leave the API keys empty — mosint will use the key-less services and
skip the rest. Then mount the config into the container:

```bash
docker run --rm -it -v "$HOME/.mosint.yaml:/root/.mosint.yaml:ro" osint-toolbox
```

The same `-v` for the config can be added to the batch command.

---

## 5. Convenience alias

To avoid retyping the long batch command, add a shell alias:

```bash
echo 'alias osint-batch='\''docker run --rm \
  -v "$HOME/targets.txt:/opt/osint/targets.txt:ro" \
  -v "$HOME/osint-out:/opt/osint/out" \
  osint-toolbox batch --targets /opt/osint/targets.txt --outdir /opt/osint/out'\''' >> ~/.bashrc
source ~/.bashrc
# then just: osint-batch
```

Adjust the host paths to match your real file locations.

---

## 6. Housekeeping

```bash
docker images                 # list images
docker rmi osint-toolbox      # remove this image
docker system df              # how much space Docker uses
docker system prune           # remove stopped containers, unused data
```

With `--rm`, containers never pile up; only the image stays until you remove it.

---

## How it works

- The `Dockerfile` builds the image: a Go base, plus Python and the three tools.
- `osint-launcher.sh` is the entrypoint. With no arguments it shows the menu;
  with `batch ...` it hands off to the Python runner.
- `osint-batch.py` reads the list, runs the right tools per target type, strips
  terminal color codes, and writes the Markdown report.

To add a tool, install it in the `Dockerfile` and add one `add_tool` line in the
launcher (and, if you want it in batch, one entry in `tools_for` in the Python).

---

## License

This packaging layer is provided as-is for research and education. Each bundled
tool remains under its own upstream license — review them before redistributing.
Add a license of your choice (e.g. MIT) before publishing your fork.
