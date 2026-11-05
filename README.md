# A minimalist JDK-switching tool for controlled environments

A single script to switch between already installed JDKs, without `sudo` and
without changing the system. Works on **Linux**, **macOS**, and **Windows**
(via Git Bash/MINGW64), with **bash 3.2+** and **zsh**.

- The list of JDKs lives in `~/.config/sdk/sdk.conf`, in the format `name=path`.
- The **first valid entry** is the default applied to every new shell.
- Switching applies **only to the current session**.
- `JAVA_HOME` and `PATH` are adjusted; the `bin` of other listed JDKs is
  removed from `PATH` before prefixing the new one.

[`sdk-switch.sh`](./sdk-switch.sh) is intentionally minimalist: it is a simplified
installation alternative for controlled environments where JDK versions are installed
exclusively through corporate app stores (for example, Jamf Self Service+ App).

To use the tool, you only need the script [`sdk-switch.sh`](./sdk-switch.sh). If you
cannot clone the repository or download the script (due to web proxy limitations),
simply copy and paste its contents into a new file on your machine, then run
`chmod 755 <created-file>` (I suggest saving it as a file named `sdk-switch.sh`).
Then run `./sdk-switch.sh install` and read the instructions.

## Requirements

- bash 3.2 or higher (the native macOS version).
- zsh is optional, only for the integration.
- Linux, macOS, or Windows with Git Bash (MINGW64). On Windows, `cmd` and
  PowerShell are not supported.

## Installation

In the repository:

```sh
./sdk-switch.sh install
```

The command:

1. creates `~/.config/sdk/sdk.conf` with a commented example (if it does not exist yet);
2. copies the script itself to `~/.local/bin/sdk` (mode `755`, without the
   `install` utility);
3. generates `~/.config/sdk/sdk.sh`, which defines the `sdk()` function;
4. inserts a delimited block into the rc file of the **shell that ran install**:
   - bash on Linux → `~/.bashrc`
   - bash on macOS or Git Bash → `~/.bash_profile` (and `~/.bashrc`, if it exists)
   - zsh → `~/.zshrc`
5. warns if `~/.local/bin` is not in `PATH`.

If `sdk.conf` already exists, it is preserved; the rest is installed/updated.

Reload the session:

```sh
source ~/.bashrc     # or ~/.zshrc, ~/.bash_profile
```

To use bash **and** zsh, run `./sdk-switch.sh install` once in each shell
(the configuration is preserved on the second run).

The shell is detected from the parent process. In special cases (CI, wrappers),
force it with:

```sh
./sdk-switch.sh install --shell bash
./sdk-switch.sh install --shell zsh
```

## Windows (Git Bash)

Use Git Bash (MINGW64) from Git for Windows; `cmd` and PowerShell are not
supported. From Git Bash, run:

```sh
./sdk-switch.sh install
```

Paths in `sdk.conf` may use POSIX form (`/c/Program Files/...`) or Windows
form (`C:\Program Files\...`); both are accepted and normalized internally.
`JAVA_HOME` and `PATH` are exported in POSIX form, which is what Git Bash
uses.

Windows JDKs provide `bin/java.exe`; `sdk` detects it automatically.

```conf
jdk21=/c/Program Files/Java/jdk-21
jdk17=C:\Program Files\Java\jdk-17
```

## Configuration

`~/.config/sdk/sdk.conf`:

```conf
# name=path; the first valid entry is the default
jdk21=/opt/jdk-21
jdk17=/home/sidney/jdks/temurin-17
```

macOS:

```conf
jdk21=/Library/Java/JavaVirtualMachines/temurin-21/Contents/Home
jdk17=/Library/Java/JavaVirtualMachines/temurin-17/Contents/Home
```

Rules:

- Blank lines and lines starting with `#` are ignored.
- The name must match `[A-Za-z0-9._-]+` and be unique.
- The path must be absolute or start with `~/`; spaces are allowed.
- An entry is valid if the directory exists and `bin/java` is executable.
- Invalid entries are flagged, but they do not prevent the others from being used.

## Usage

```sh
sdk list                 # lists the JDKs, with active (*) and default (d)
sdk use jdk17            # activates jdk17 in this session
sdk use                  # interactive menu
sdk current              # shows the active JDK
sdk reset                # goes back to the first valid entry
sdk uninstall            # removes the integration and configuration
sdk help                 # help
```

Without the installed function, you can still apply it manually:

```sh
eval "$(sdk --emit use jdk17)"
```

## How it works

The executable in `~/.local/bin/sdk` is bash and cannot change the environment of
the parent shell. That is why `sdk install` generates `~/.config/sdk/sdk.sh`,
loaded by the rc files:

```sh
sdk() {
  ...
  use|reset|"")
    _out=$(command sdk --emit "$@") || return $?
    eval "$_out"
    ;;
}
```

The internal `--emit` mode prints only:

```sh
export JAVA_HOME='...'
export PATH='...'
```

When the helper is loaded, `sdk reset` is applied silently, making each
new session go back to the first valid entry.

## Updating

Run `./sdk-switch.sh install` again. `sdk.conf` is not changed; the binary,
helper, and rc block are updated idempotently.

## Uninstallation

```sh
sdk uninstall
```

The command shows a before/after preview of every rc file that contains an sdk
block, lists the files that will be removed, and asks for confirmation. It
removes the binary, the helper, the rc blocks, and `~/.config/sdk/sdk.conf`;
`~/.config/sdk` is removed only if it is empty.

Open a new shell (or run `unset -f sdk`) to drop the helper function from the
current session. `JAVA_HOME` and `PATH` are not reverted.

## Limitations

- Switching does not affect already open terminals or processes (IDEs,
  Maven/Gradle daemons, other shells).
- There is no automatic JDK discovery: the list is manual.
- Entries from other managers in `PATH` that are not in the list are not
  removed.
- `JAVA_HOME` is always overwritten, including when set by SDKMAN or an IDE.
- On Windows, only Git Bash (MINGW64) is supported; MSYS2, Cygwin, `cmd`, and
  PowerShell are out of scope.
- Windows path comparison is best-effort: UNC paths, 8.3 names, and
  case-insensitive differences may not match.
- Real validation on macOS depends on running the script on a Mac machine.
- Git Bash compatibility has not yet been validated on a real Windows machine.

## Tests

```sh
bash test/sdk_test.sh
```

The tests use a temporary `HOME` and cover parsing, PATH, `use`/`reset`,
installation, idempotency, the helper in bash/zsh, and constructs incompatible
with bash 3.2 / BSD.
