#!/usr/bin/env bash
#
# Tests for the sdk script. Runs on Linux and macOS with bash 3.2+.
# Usage: bash test/sdk_test.sh

SCRIPT=$(cd "$(dirname "$0")/.." && pwd)/sdk-switch.sh
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdk-test.XXXXXX") || exit 1
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS=0
FAIL=0

ok() {
  PASS=$((PASS + 1))
  printf 'ok   - %s\n' "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf 'FAIL - %s\n' "$1"
  [ -n "${2:-}" ] && printf '       %s\n' "$2"
}

eq() {
  if [ "$2" = "$3" ]; then
    ok "$1"
  else
    fail "$1" "expected: [$3] got: [$2]"
  fi
}

contains() {
  case $2 in
    *"$3"*) ok "$1" ;;
    *)      fail "$1" "'$3' not found in: $2" ;;
  esac
}

not_contains() {
  case $2 in
    *"$3"*) fail "$1" "'$3' unexpectedly found in: $2" ;;
    *)      ok "$1" ;;
  esac
}

new_home() {
  TEST_HOME=$TMP_ROOT/home-$1
  rm -rf "$TEST_HOME"
  mkdir -p "$TEST_HOME"
  CONF=$TEST_HOME/.config/sdk/sdk.conf
  unset JAVA_HOME
}

make_jdk() {
  local dir=$1 ver=$2
  mkdir -p "$dir/bin"
  printf '#!/bin/sh\nexit 0\n' > "$dir/bin/java"
  chmod 755 "$dir/bin/java"
  printf '#!/bin/sh\nexit 0\n' > "$dir/bin/java.exe"
  printf 'JAVA_VERSION="%s"\n' "$ver" > "$dir/release"
}

write_conf() {
  mkdir -p "${CONF%/*}"
  printf '%s\n' "$@" > "$CONF"
}

run() {
  HOME=$TEST_HOME bash "$SCRIPT" "$@"
}

# ---------------------------------------------------------------------------
# Syntax
# ---------------------------------------------------------------------------

if bash -n "$SCRIPT" 2>/dev/null; then
  ok "script syntax"
else
  fail "script syntax" "$(bash -n "$SCRIPT" 2>&1)"
fi

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

new_home list
A=$TEST_HOME/jdk-a
B=$TEST_HOME/jdk-b
make_jdk "$A" 21.0.2
make_jdk "$B" 17.0.9
write_conf "jdk21=$A" "jdk17=$B"

out=$(run list 2>&1)
contains "list shows names" "$out" "jdk21"
contains "list shows version" "$out" "21.0.2"
contains "list shows path" "$out" "$A"

out=$(HOME=$TEST_HOME JAVA_HOME=$A bash "$SCRIPT" list 2>&1)
contains "list marks active" "$out" "*"
contains "list marks default" "$out" "d"

# ---------------------------------------------------------------------------
# use and emission
# ---------------------------------------------------------------------------

out=$(run --emit use jdk17 2>/dev/null)
status=$?
eq "use status" "$status" "0"
contains "use JAVA_HOME" "$out" "export JAVA_HOME='$B'"
contains "use PATH" "$out" "export PATH='$B/bin:"

lines=$(printf '%s\n' "$out" | wc -l | tr -d ' ')
eq "emit only exports" "$lines" "2"

out=$(run --emit use nao-existe 2>/dev/null)
status=$?
if [ "$status" -ne 0 ] && [ -z "$out" ]; then
  ok "use of nonexistent name fails without stdout"
else
  fail "use of nonexistent name fails without stdout" "status=$status stdout=[$out]"
fi

# ---------------------------------------------------------------------------
# reset (first valid entry)
# ---------------------------------------------------------------------------

write_conf "quebrada=$TEST_HOME/nao-existe" "jdk21=$A" "jdk17=$B"

out=$(run --emit reset 2>/dev/null)
contains "reset picks first valid entry" "$out" "JAVA_HOME='$A'"

out=$(run list 2>&1)
contains "list flags invalid entry" "$out" "[invalid]"

out=$(run --emit use quebrada 2>/dev/null)
status=$?
if [ "$status" -ne 0 ] && [ -z "$out" ]; then
  ok "use of invalid entry fails without stdout"
else
  fail "use of invalid entry fails without stdout" "status=$status stdout=[$out]"
fi

# ---------------------------------------------------------------------------
# PATH: cleanup and no accumulation
# ---------------------------------------------------------------------------

out=$(PATH="$B/bin:$A/bin:/usr/bin:/bin" run --emit use jdk21 2>/dev/null)
eval "$out"
case $PATH in
  "$A/bin:"*) ok "PATH prefixed with the new JDK" ;;
  *)          fail "PATH prefixed with the new JDK" "$PATH" ;;
esac
case ":$PATH:" in
  *":$B/bin:"*) fail "old PATH removed" "$PATH" ;;
  *)            ok "old PATH removed" ;;
esac

PATH=/usr/bin:/bin
for name in jdk21 jdk17 jdk21; do
  out=$(run --emit use "$name" 2>/dev/null)
  eval "$out"
done
count=$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -c "^$A/bin$")
eq "PATH does not accumulate after switches" "$count" "1"

# ---------------------------------------------------------------------------
# current
# ---------------------------------------------------------------------------

out=$(HOME=$TEST_HOME JAVA_HOME=$A PATH="$A/bin:/usr/bin:/bin" bash "$SCRIPT" current 2>&1)
contains "current shows name" "$out" "jdk21"
contains "current shows JAVA_HOME" "$out" "$A"

unset JAVA_HOME
out=$(run current 2>&1)
contains "current without JAVA_HOME" "$out" "No active JDK"

# ---------------------------------------------------------------------------
# Configuration: spaces, quotes, CRLF, and errors
# ---------------------------------------------------------------------------

new_home quoting
SPACE_DIR="$TEST_HOME/jdk with space"
QUOTE_DIR="$TEST_HOME/jdk'quote"
make_jdk "$SPACE_DIR" 11
make_jdk "$QUOTE_DIR" 8
write_conf "jdk11=$SPACE_DIR" "jdk8=$QUOTE_DIR"

out=$(run --emit use jdk11 2>/dev/null)
contains "path with spaces" "$out" "JAVA_HOME='$SPACE_DIR'"
eval "$out"
eq "path with spaces applied" "$JAVA_HOME" "$SPACE_DIR"

out=$(run --emit use jdk8 2>/dev/null)
contains "path with quotes" "$out" "JAVA_HOME="
eval "$out"
eq "path with quotes applied" "$JAVA_HOME" "$QUOTE_DIR"

new_home crlf
C=$TEST_HOME/jdk-crlf
make_jdk "$C" 21.0.2
mkdir -p "${CONF%/*}"
printf 'jdk21=%s\r\n' "$C" > "$CONF"
out=$(run --emit use jdk21 2>/dev/null)
contains "config with CRLF" "$out" "JAVA_HOME='$C'"

new_home duplicates
make_jdk "$A" 21.0.2
write_conf "jdk21=$A" "jdk21=$B" "relativa=foo"
out=$(run list 2>&1)
contains "duplicate name warned" "$out" "duplicate"
contains "relative path warned" "$out" "non-absolute"

# ---------------------------------------------------------------------------
# Missing configuration and install
# ---------------------------------------------------------------------------

new_home missing
out=$(run --emit use jdk21 2>/dev/null)
status=$?
if [ "$status" -ne 0 ] && [ -z "$out" ]; then
  ok "use without conf fails"
else
  fail "use without conf fails" "status=$status stdout=[$out]"
fi
if [ ! -e "$CONF" ]; then
  ok "use does not create conf implicitly"
else
  fail "use does not create conf implicitly"
fi

out=$(run install --shell bash 2>&1)
status=$?
eq "install status" "$status" "0"
if [ -f "$CONF" ]; then
  ok "install creates conf"
else
  fail "install creates conf"
fi
if grep -q '^# jdk21=' "$CONF" 2>/dev/null; then
  ok "template contains commented example"
else
  fail "template contains commented example"
fi

new_home preserve
make_jdk "$A" 21.0.2
write_conf "# customized" "jdk21=$A"
before=$(cat "$CONF")
run install --shell bash >/dev/null 2>&1
eq "install preserves existing conf" "$(cat "$CONF")" "$before"

new_home idempotent
make_jdk "$A" 21.0.2
write_conf "jdk21=$A"
run install --shell bash >/dev/null 2>&1
run install --shell bash >/dev/null 2>&1

case $(uname -s) in
  Darwin|MINGW*) RC=$TEST_HOME/.bash_profile ;;
  *)             RC=$TEST_HOME/.bashrc ;;
esac

if grep -q '^# >>> sdk >>>$' "$RC" 2>/dev/null; then
  ok "sdk block in rc"
else
  fail "sdk block in rc" "$RC"
fi
count=$(grep -c '^# >>> sdk >>>$' "$RC" 2>/dev/null || true)
eq "rc block is idempotent" "$count" "1"

if [ -x "$TEST_HOME/.local/bin/sdk" ]; then
  ok "binary installed and executable"
else
  fail "binary installed and executable"
fi
if [ -f "$TEST_HOME/.config/sdk/sdk.sh" ]; then
  ok "helper installed"
else
  fail "helper installed"
fi

BIN=$TEST_HOME/.local/bin/sdk
size_before=$(wc -c < "$BIN")
HOME=$TEST_HOME "$BIN" install --shell bash >/dev/null 2>&1
size_after=$(wc -c < "$BIN")
eq "self-copy does not truncate the binary" "$size_after" "$size_before"

# ---------------------------------------------------------------------------
# Helper in bash
# ---------------------------------------------------------------------------

new_home helper
make_jdk "$A" 21.0.2
make_jdk "$B" 17.0.9
write_conf "jdk21=$A" "jdk17=$B"
run install --shell bash >/dev/null 2>&1

out=$(HOME=$TEST_HOME PATH="$TEST_HOME/.local/bin:$PATH" \
  bash -c '. "$HOME/.config/sdk/sdk.sh"; printf "DEF=%s\n" "$JAVA_HOME"' 2>&1)
contains "helper applies default in bash" "$out" "DEF=$A"

out=$(HOME=$TEST_HOME PATH="$TEST_HOME/.local/bin:$PATH" \
  bash -c '. "$HOME/.config/sdk/sdk.sh"; sdk use jdk17; printf "AT=%s\n" "$JAVA_HOME"' 2>&1)
contains "helper switches in bash" "$out" "AT=$B"

# ---------------------------------------------------------------------------
# Helper in zsh
# ---------------------------------------------------------------------------

if command -v zsh >/dev/null 2>&1; then
  out=$(HOME=$TEST_HOME PATH="$TEST_HOME/.local/bin:$PATH" \
    zsh -c '. "$HOME/.config/sdk/sdk.sh"; sdk use jdk17; printf "AT=%s\n" "$JAVA_HOME"' 2>&1)
  contains "helper switches in zsh" "$out" "AT=$B"

  new_home zsh-install
  out=$(HOME=$TEST_HOME zsh -c "\"$SCRIPT\" install; exit 0" 2>&1)
  if [ -f "$TEST_HOME/.zshrc" ] && grep -q '^# >>> sdk >>>$' "$TEST_HOME/.zshrc"; then
    ok "install detects zsh session and uses .zshrc"
  else
    fail "install detects zsh session and uses .zshrc" "$out"
  fi
else
  printf 'skip - zsh not found\n'
fi

# ---------------------------------------------------------------------------
# invalid shell
# ---------------------------------------------------------------------------

new_home invalid-shell
run install --shell fish >/dev/null 2>&1
status=$?
if [ "$status" -ne 0 ]; then
  ok "install rejects invalid shell"
else
  fail "install rejects invalid shell"
fi

# ---------------------------------------------------------------------------
# uninstall
# ---------------------------------------------------------------------------

new_home uninstall
make_jdk "$A" 21.0.2
write_conf "jdk21=$A"
printf 'before-bash\n' > "$TEST_HOME/.bashrc"
printf 'before-profile\n' > "$TEST_HOME/.bash_profile"
printf 'before-zsh\n' > "$TEST_HOME/.zshrc"
run install --shell bash >/dev/null 2>&1
printf 'after-bash\n' >> "$TEST_HOME/.bashrc"
if ! grep -q '^# >>> sdk >>>$' "$TEST_HOME/.bash_profile" 2>/dev/null; then
  {
    printf '# >>> sdk >>>\n'
    printf '[ -r "$HOME/.config/sdk/sdk.sh" ] && . "$HOME/.config/sdk/sdk.sh"\n'
    printf '# <<< sdk <<<\n'
  } >> "$TEST_HOME/.bash_profile"
fi
{
  printf '# >>> sdk >>>\n'
  printf '[ -r "$HOME/.config/sdk/sdk.sh" ] && . "$HOME/.config/sdk/sdk.sh"\n'
  printf '# <<< sdk <<<\n'
  printf 'after-zsh\n'
} >> "$TEST_HOME/.zshrc"

bash_before=$(cat "$TEST_HOME/.bashrc")
out=$(printf 'n\n' | run uninstall 2>&1)
status=$?
eq "uninstall cancel status" "$status" "0"
contains "uninstall cancel message" "$out" "cancelled"
eq "uninstall cancel keeps rc" "$(cat "$TEST_HOME/.bashrc")" "$bash_before"
if [ -x "$TEST_HOME/.local/bin/sdk" ] && [ -f "$TEST_HOME/.config/sdk/sdk.sh" ] && [ -f "$CONF" ]; then
  ok "uninstall cancel keeps files"
else
  fail "uninstall cancel keeps files"
fi

out=$(printf 'y\n' | run uninstall 2>&1)
status=$?
eq "uninstall status" "$status" "0"
contains "uninstall shows before" "$out" "before:"
contains "uninstall shows after" "$out" "after:"
contains "uninstall shows rc block" "$out" "# >>> sdk >>>"
contains "uninstall announces config" "$out" "config: $CONF"

if [ ! -e "$TEST_HOME/.local/bin/sdk" ] && [ ! -e "$TEST_HOME/.config/sdk/sdk.sh" ] && [ ! -e "$CONF" ]; then
  ok "uninstall removes files"
else
  fail "uninstall removes files"
fi
if [ ! -e "$TEST_HOME/.config/sdk" ]; then
  ok "uninstall removes empty config directory"
else
  fail "uninstall removes empty config directory"
fi

for f in "$TEST_HOME/.bashrc" "$TEST_HOME/.bash_profile" "$TEST_HOME/.zshrc"; do
  if grep -q '^# >>> sdk >>>$' "$f" 2>/dev/null; then
    fail "uninstall clears rc: $f"
  else
    ok "uninstall clears rc: $f"
  fi
done
contains "uninstall keeps rc content" "$(cat "$TEST_HOME/.bashrc")" "after-bash"
contains "uninstall keeps zsh content" "$(cat "$TEST_HOME/.zshrc")" "after-zsh"

out=$(printf 'y\n' | run uninstall 2>&1)
status=$?
eq "uninstall idempotent status" "$status" "0"
contains "uninstall idempotent message" "$out" "nothing to remove"

new_home uninstall-malformed
printf 'keep-1\n# >>> sdk >>>\nkeep-2\n' > "$TEST_HOME/.bashrc"
malformed_before=$(cat "$TEST_HOME/.bashrc")
out=$(printf 'y\n' | run uninstall 2>&1)
status=$?
eq "uninstall malformed status" "$status" "0"
contains "uninstall malformed warns" "$out" "without '# <<< sdk <<<'"
not_contains "uninstall malformed has no preview" "$out" "before:"
eq "uninstall malformed keeps file" "$(cat "$TEST_HOME/.bashrc")" "$malformed_before"

new_home uninstall-multi
printf 'top\n# >>> sdk >>>\nA\n# <<< sdk <<<\nmiddle\n# >>> sdk >>>\nB\n# <<< sdk <<<\nbottom\n' > "$TEST_HOME/.bashrc"
out=$(printf 'y\n' | run uninstall 2>&1)
count=$(printf '%s\n' "$out" | grep -c '^  before:$')
eq "uninstall previews every block" "$count" "2"
eq "uninstall removes every block" "$(cat "$TEST_HOME/.bashrc")" "$(printf 'top\nmiddle\nbottom')"

new_home uninstall-keep-dir
make_jdk "$A" 21.0.2
write_conf "jdk21=$A"
run install --shell bash >/dev/null 2>&1
printf 'keep-me\n' > "$TEST_HOME/.config/sdk/other"
out=$(printf 'y\n' | run uninstall 2>&1)
status=$?
eq "uninstall with extra file status" "$status" "0"
contains "uninstall keeps non-empty directory" "$out" "directory kept"
if [ -f "$TEST_HOME/.config/sdk/other" ] && [ -d "$TEST_HOME/.config/sdk" ]; then
  ok "uninstall preserves unrelated config file"
else
  fail "uninstall preserves unrelated config file"
fi

new_home uninstall-partial
mkdir -p "$TEST_HOME/.config/sdk"
printf '#!/usr/bin/env bash\n_SDK_HELPER_LOADED=1\n' > "$TEST_HOME/.config/sdk/sdk.sh"
out=$(printf 'y\n' | run uninstall 2>&1)
status=$?
eq "uninstall partial status" "$status" "0"
if [ ! -e "$TEST_HOME/.config/sdk/sdk.sh" ]; then
  ok "uninstall partial removes helper"
else
  fail "uninstall partial removes helper"
fi

new_home uninstall-eof
make_jdk "$A" 21.0.2
write_conf "jdk21=$A"
run install --shell bash >/dev/null 2>&1
eof_before=$(cat "$TEST_HOME/.bashrc")
out=$(run uninstall < /dev/null 2>&1)
status=$?
eq "uninstall eof status" "$status" "0"
contains "uninstall eof cancels" "$out" "cancelled"
eq "uninstall eof keeps rc" "$(cat "$TEST_HOME/.bashrc")" "$eof_before"

new_home uninstall-self
make_jdk "$A" 21.0.2
write_conf "jdk21=$A"
run install --shell bash >/dev/null 2>&1
BIN=$TEST_HOME/.local/bin/sdk
out=$(printf 'y\n' | HOME=$TEST_HOME "$BIN" uninstall 2>&1)
status=$?
eq "uninstall from installed binary status" "$status" "0"
if [ ! -e "$BIN" ]; then
  ok "uninstall removes running binary"
else
  fail "uninstall removes running binary"
fi

new_home uninstall-args
out=$(run uninstall extra 2>&1)
status=$?
eq "uninstall rejects unknown argument" "$status" "2"
contains "uninstall unknown argument message" "$out" "unknown argument"

out=$(run --emit uninstall 2>&1)
status=$?
eq "uninstall rejects emit" "$status" "2"
contains "uninstall emit message" "$out" "does not apply to 'uninstall'"

# ---------------------------------------------------------------------------
# Compatibility: forbidden constructs
# ---------------------------------------------------------------------------

for pat in 'readlink -f' 'sed -i' 'mapfile' 'declare -A' 'realpath' 'stat -c'; do
  if grep -v '^[[:space:]]*#' "$SCRIPT" | grep -q "$pat"; then
    fail "no forbidden construct: $pat"
  else
    ok "no forbidden construct: $pat"
  fi
done

if grep -q '/usr/bin/install' "$SCRIPT"; then
  fail "does not use the install utility"
else
  ok "does not use the install utility"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
