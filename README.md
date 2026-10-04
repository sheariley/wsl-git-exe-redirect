# wsl-git-exe-redirect

A drop-in `git` wrapper for WSL. It runs Windows' `git.exe` for repositories on
your Windows drives (`/mnt/c`, `/mnt/d`, …) and WSL's own `/usr/bin/git`
everywhere else.

Using Linux git on a Windows-hosted repo is slow (every file access crosses the
WSL/Windows boundary) and can disagree with Windows tools about line endings,
file modes and credentials. This wrapper picks the right git for you
automatically, in interactive shells, scripts, editors and any other program
that runs `git`.

```console
$ cd ~/projects/app && git --version
git version 2.43.0
$ cd /mnt/c/src/app && git --version
git version 2.45.1.windows.1
```

## Requirements

- WSL 2 with Windows interop enabled (the default)
- [Git for Windows](https://gitforwindows.org/) installed on the Windows side
- Git installed in the WSL distro (`sudo apt install git`)
- `bash`, `realpath` and `wslpath` (present on standard WSL distros)

## Installation

The wrapper is a single script named `git`. It must be on `PATH` **before**
`/usr/bin`. `/usr/local/bin` is the recommended location: it comes before
`/usr/bin` in the default `PATH` for login shells, non-interactive shells,
cron, systemd services and `sudo`.

### Option 1: Copy the script

```bash
git clone https://github.com/sheariley/wsl-git-exe-redirect.git
sudo install -m 755 -o root -g root wsl-git-exe-redirect/git /usr/local/bin/git
hash -r   # forget the old git location in open shells
```

Or without cloning:

```bash
curl -fsSL https://raw.githubusercontent.com/sheariley/wsl-git-exe-redirect/master/git -o /tmp/git-wrapper
sudo install -m 755 -o root -g root /tmp/git-wrapper /usr/local/bin/git && rm /tmp/git-wrapper
hash -r
```

### Option 2: Symlink to a clone

This means updates are just a `git pull` in the clone:

```bash
git clone https://github.com/sheariley/wsl-git-exe-redirect.git ~/wsl-git-exe-redirect
chmod +x ~/wsl-git-exe-redirect/git
sudo ln -sf ~/wsl-git-exe-redirect/git /usr/local/bin/git
hash -r
```

Keep the clone on the Linux filesystem (e.g. under `~`) rather than under
`/mnt/c`, so reading the script on every `git` call stays fast. Note that
anyone who can edit the clone controls what runs when root uses `git`.

### Without sudo

Put the script in `~/.local/bin/git` instead. On most distros `~/.profile`
puts that directory first on `PATH`, which covers your interactive shells and
the programs they start, but not cron jobs, systemd services or `sudo`.

### Remove any older aliases or functions

If you previously set up an `alias git=…` or a `git()` function in
`~/.bashrc` (or similar), remove it so it doesn't shadow the wrapper.

### Verify

```bash
type -a git                     # /usr/local/bin/git should be listed before /usr/bin/git
cd ~ && git --version           # WSL git
cd /mnt/c && git --version      # x.y.z.windows.N
```

To see exactly what the wrapper runs, trace it:

```bash
bash -x "$(command -v git)" -C /mnt/c/src/app status 2>&1 | grep exec
# + exec '/mnt/c/Program Files/Git/cmd/git.exe' -C 'C:\src\app' status
```

## Customization

All settings are variables at the top of the script.

| Variable     | Default                                | Purpose |
|--------------|----------------------------------------|---------|
| `WSL_GIT`    | `/usr/bin/git`                         | The Linux git binary. Must be a full path, not `git`, or the wrapper would call itself. |
| `WIN_GIT`    | `/mnt/c/Program Files/Git/cmd/git.exe` | The Windows git binary, as a WSL path. Change it if Git for Windows is installed elsewhere (e.g. Scoop: `/mnt/c/Users/<you>/scoop/shims/git.exe`). |
| `WIN_DRIVES` | `cd`                                   | Lower-case drive letters whose repositories use `git.exe`. For example, `cde` adds `/mnt/e`. |

Run `wslpath -u 'C:\path\to\git.exe'` to convert a Windows path for `WIN_GIT`.

If your distro mounts drives somewhere other than `/mnt` (the `root` setting in
`/etc/wsl.conf`), change `/mnt/` in `is_win_path()` to match.

### Environment variables passed to git.exe

Windows programs don't inherit Linux environment variables unless they're
listed in `WSLENV`. The wrapper adds every `GIT_*` variable that is set, with
these exceptions near the end of the script:

- **Paths** (`GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, …) are converted
  to Windows paths.
- **Linux commands** (`GIT_EDITOR`, `GIT_SEQUENCE_EDITOR`, `GIT_PAGER`,
  `GIT_ASKPASS`, `GIT_SSH`, `GIT_SSH_COMMAND`, `GIT_EXTERNAL_DIFF`,
  `GIT_PROXY_COMMAND`) and `GIT_EXEC_PATH` are not passed, because
  `git.exe` can't run Linux programs. Git for Windows uses its own
  configuration for these instead.

Edit the `case` patterns in that loop to change which variables are passed or
converted.

## How it works

### Which git runs

The wrapper finds the location git itself would work in, then checks whether
it's on one of the `WIN_DRIVES`:

1. The current directory, changed by any `-C <path>` options (several `-C`
   options combine the way git combines them).
2. `--work-tree` / `GIT_WORK_TREE`, if set.
3. `--git-dir` / `GIT_DIR`, if set (this wins over the work tree).
4. For commands that create something new, the destination decides instead:
   - `git clone <repository> <directory>`
   - `git init <directory>`
   - `git worktree add <path>`
   - `git submodule add <repository> <path>`

Paths are normalized and symlinks resolved before the check, so a symlink in
your Linux home that points into `/mnt/c` routes to `git.exe`.

### Argument parsing

Arguments are parsed with git's own rules, so the wrapper finds the right
values whatever form you use:

- `--git-dir=<path>` and `--git-dir <path>` (likewise for other options)
- Grouped short options: `-qb main`, `-j4`
- Shortened long options: `--dep 1` for `--depth 1`
- Options after the positional arguments: `git clone <url> <dir> --depth 1`
- `--` and `--end-of-options`

`git submodule add` follows the stricter rules of git's `git-submodule`
script instead: full option names only, and options must come before
`<repository>`.

### Path conversion

`git.exe` can't open WSL paths like `/mnt/c/src/app`. When the wrapper runs
`git.exe`, it converts with `wslpath -w`:

- Any argument that is a path on a `WIN_DRIVES` drive: `/mnt/c/a` → `C:\a`
- `--option=/mnt/c/a` → `--option=C:\a`, and `-c key=/mnt/c/a` → `-c key=C:\a`
- Path options (`-C`, `--git-dir`, `--work-tree`, and the destination of the
  commands above) are made absolute, so a relative path still works when you
  start from a Linux directory. A path outside the Windows drives becomes
  `\\wsl.localhost\<distro>\…`.

## Limitations

- **Pathspecs don't choose the git.** `git status /mnt/c/src/app/file.txt`
  run from `~` uses WSL git, just as real git would look for a repository in
  `~`. Use `-C` or `cd` first.
- **Linux paths passed to `git.exe` stay as they are.** `git add ~/file` inside
  a `/mnt/c` repo fails, as it would for any path outside the repository.
- **Mixing sides breaks links.** A worktree or submodule created on the other
  side from its repository stores paths that only one of the two gits can
  follow. The wrapper prints a warning to stderr in that case but still runs
  the command.
- **Look-alike values get converted.** A non-path argument shaped exactly like
  `/mnt/c/…` or `key=/mnt/c/…` (for example `-m "x=/mnt/c/y"`) is converted
  too.
- **Option lists are copied from git 2.43 / 2.45.** The lists for `clone`,
  `init` and `worktree add` include options that take a value. If a future
  git release adds a new one, add it to `long_with_arg` (and `long_opts`), or
  the destination directory could be misread.
- **Only `git` invocations are covered.** Programs that call `/usr/bin/git`
  by full path, or bundle their own git, bypass the wrapper.

## Uninstall

```bash
sudo rm /usr/local/bin/git   # or ~/.local/bin/git
hash -r
```

## License

[MIT](LICENSE) © 2026 Shea Riley
