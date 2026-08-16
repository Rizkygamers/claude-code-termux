#!/data/data/com.termux/files/usr/bin/bash
# claude-code-android installer (Termux on aarch64 Android).
#
# Installs Anthropic's official linux-arm64 claude binary, patched via
# glibc-runner so it runs under Android's bionic kernel. A wrapper at
# $PREFIX/bin/claude auto-checks for new versions once per day on launch
# (--update-now forces an immediate check) and re-patches if needed.
#
# Two yes/no questions up front, then unattended. Approx 5-10 minutes
# depending on connection. The first download is ~233 MB.
#
# Re-running this script is safe. On a device that already has the v2.9
# launcher it refreshes the launcher in place (no re-download); on a pinned
# npm install it routes you to migrate.sh; otherwise it installs while
# preserving any existing ~/.claude. Day-to-day updates happen automatically
# through the launcher.
#
# Tracking the upstream issue this works around:
#   https://github.com/anthropics/claude-code/issues/50270

set -euo pipefail

info(){ printf '\033[0;36m[info]\033[0m  %s\n' "$1"; }
ok(){   printf '\033[0;32m[ok]\033[0m    %s\n' "$1"; }
warn(){ printf '\033[0;33m[warn]\033[0m  %s\n' "$1" >&2; }
fail(){ printf '\033[0;31m[fail]\033[0m  %s\n' "$1" >&2; exit 1; }

# DNS ETIMEOUT fix: preload sets Bun's c-ares resolver to a live nameserver (the wrapper loads it via BUN_OPTIONS).
CC_SETDNS="$HOME/.local/share/claude/setdns.js"
CC_SETDNS_JS='try { require("dns").setServers(["8.8.8.8", "8.8.4.4"]); } catch (e) {}'
write_setdns() {
  [ -s "$1" ] && return 0
  printf '%s\n' "$CC_SETDNS_JS" > "$1" 2>/dev/null
}

# --- Preflight ---
[ -z "${PREFIX:-}" ] && fail "PREFIX unset. Run this inside Termux, not adb shell."
[ "$(uname -m)" = "aarch64" ] || fail "aarch64 only. uname -m reports: $(uname -m)"

# Android's low-memory killer can SIGKILL the whole process tree during the heavy
# glibc install if this runs inside a claude session under memory pressure. A
# plain Termux shell is safer.
if [ -n "${CLAUDE_CODE_EXECPATH:-}" ] || [ -n "${CLAUDECODE:-}" ]; then
  warn "You appear to be running inside a claude session; Android may kill the"
  warn "install under memory pressure. A plain Termux shell is safer."
  read -r -p "Continue anyway? [y/N] " LMK
  case "${LMK,,}" in y|yes) ;; *) fail "Stopped. Open a fresh Termux session and re-run." ;; esac
fi

# --- Classify any prior claude state, then route or pick an install mode ---
# One classifier covers every real prior state instead of a blunt
# "anything-exists, refuse" gate. Outcomes:
#   already_v29  v2.9-family wrapper present            -> nothing to do
#   pinned       npm @anthropic-ai/claude-code present  -> migrate.sh (safe npm removal)
#   inplace      official native install, or leftover ~/.claude with no working
#                binary                                 -> install here, preserving data
#   fresh        no claude footprint at all             -> clean install
CC_NPM_PKG="$PREFIX/lib/node_modules/@anthropic-ai/claude-code"
CC_BINLINK="$PREFIX/bin/claude"
CC_VERSIONS="$HOME/.local/share/claude/versions"

cc_has_versions(){ [ -d "$CC_VERSIONS" ] && ls "$CC_VERSIONS"/*.*.* >/dev/null 2>&1; }
cc_is_wrapper(){ [ -f "$CC_BINLINK" ] && [ ! -L "$CC_BINLINK" ]; }
cc_is_npm_link(){ [ -L "$CC_BINLINK" ] && readlink "$CC_BINLINK" | grep -q 'node_modules/@anthropic-ai/claude-code'; }

if cc_has_versions && cc_is_wrapper; then
  state="already_v29"
elif [ -d "$CC_NPM_PKG" ] || cc_is_npm_link; then
  state="pinned"
elif cc_has_versions || [ -e "$HOME/.local/bin/claude" ] || [ -d "$HOME/.local/share/claude" ] \
     || [ -e "$HOME/.claude" ] || [ -e "$HOME/.claude.json" ]; then
  state="inplace"
else
  state="fresh"
fi

if [ "$state" = already_v29 ]; then
  # An existing v2.9 launcher is present. The launcher only changes when this
  # script rewrites it (the daily auto-update refreshes the binary, not the
  # launcher), so re-running install.sh is how an existing install picks up
  # launcher improvements such as the self-healing rollback. Refresh in place:
  # skip the heavy first-time steps (packages, glibc, binary download) and go
  # straight to rewriting the launcher and settings.
  info "existing v2.9 install detected; refreshing the launcher to the current version"
  REFRESH=1
  PATCHELF="$PREFIX/glibc/bin/patchelf"
  GLIBC_LD="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
  { [ -x "$PATCHELF" ] && [ -f "$GLIBC_LD" ]; } || fail "glibc-runner is missing; cannot refresh the launcher. Install it (pkg install glibc-runner patchelf-glibc) and re-run."
  VERSIONS_DIR="$HOME/.local/share/claude/versions"
  WRAPPER="$PREFIX/bin/claude"
  BINARY="(existing install retained)"
  LATEST="(existing)"
  FRESH=0
  RECOMMENDED=0
  mkdir -p "$HOME/.claude"
fi
if [ "$state" = pinned ]; then
  info "An older pinned v2.x install is present."
  info "To upgrade WITHOUT losing your sessions, login, or settings, use the"
  info "migration script instead of this installer:"
  printf '\n    curl -fsSL https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/migrate.sh -o migrate.sh\n    bash migrate.sh\n\n'
  info "This installer does not remove npm installs; migrate.sh does that safely."
  exit 0
fi

# Everything from here to the settings step is the heavy first-time install
# (questions, packages, glibc, the ~233 MB binary download). On a refresh of an
# existing v2.9 launcher, skip all of it and go straight to rewriting the
# launcher and settings.
if [ "${REFRESH:-0}" != 1 ]; then

cat <<BANNER

  claude-code-android installer
  =============================
  Two yes/no questions up front, then unattended install (5-10 minutes).
  When it finishes, you'll type 'claude' to start.

BANNER

# --- Q1: Fresh Termux? ---
cat <<'Q1'
Q1. Is this a fresh Termux install?

  Brand new Termux installs need their package index brought up to date
  before installing anything else. The script refreshes the package index
  and upgrades base packages, taking the new defaults for any system config
  files that ship updates. Safe on a fresh Termux: nothing of yours to lose yet.

  If you have been using Termux a while and customized system configs
  under $PREFIX/etc/ (sshd_config, openssl.cnf, etc.), say no and the
  script will keep your changes during the upgrade.

  This choice applies only to THIS install run. It does NOT change how
  your future pkg upgrade commands behave.

Q1
read -r -p "Fresh Termux? [Y/n] " Q1
Q1="${Q1:-Y}"
case "${Q1,,}" in
  y|yes) FRESH=1 ;;
  n|no)  FRESH=0 ;;
  *) fail "Q1: answer 'y' or 'n'; got '$Q1'" ;;
esac
ok "Q1: $([ $FRESH = 1 ] && echo fresh || echo keep)"
echo

# --- Q2: Recommended packages? ---
cat <<'Q2'
Q2. Install recommended packages?

  Claude Code launches with just the patched binary, but many of its
  built-in tools assume common Linux utilities exist. Without these you
  will hit "command not found" errors when:

    - The Bash tool tries to run git, curl, jq, python, make
    - Claude tries to clone a repo, build with clang, or parse JSON
    - You want SSH from inside a Claude session (openssh client)

  These are the same utilities a typical PC running Claude Code already
  has. Without them on Termux, you spend the first hour hitting
  "pkg install <thing>" prompts.

  Packages: git, gh, wget, jq, python, openssh, tree, proot, termux-api,
  proot-distro, make, clang, file, xxd, htop, bat, fzf (17 packages,
  roughly 200 MB additional disk).

Q2
read -r -p "Install recommended packages? [Y/n] " Q2
Q2="${Q2:-Y}"
case "${Q2,,}" in
  y|yes) RECOMMENDED=1 ;;
  n|no)  RECOMMENDED=0 ;;
  *) fail "Q2: answer 'y' or 'n'; got '$Q2'" ;;
esac
ok "Q2: $([ $RECOMMENDED = 1 ] && echo yes || echo no)"
echo

# --- Pre-install: fresh asserts, or in-place preservation ---
if [ "$state" = inplace ]; then
  # A prior claude config is present (official native install, or a leftover
  # ~/.claude after a removed claude). Install in place and keep the user's
  # data: ~/.claude (sessions, login, agents, hooks) is never removed, and
  # settings.json is merged, not overwritten.
  RUNNING="$( { pgrep -x claude; pgrep -f '@anthropic-ai/claude-code'; } 2>/dev/null | sort -un | grep -vw "$$" | grep -vw "${PPID:-0}" | tr '\n' ' ' || true )"
  if [ -n "${RUNNING// /}" ]; then
    fail "claude appears to be running (PIDs: $RUNNING). Close all claude sessions, then re-run."
  fi
  if [ -e "$HOME/.claude/settings.json" ]; then
    cp -a "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.pre-v29.bak" 2>/dev/null \
      && ok "backed up existing settings.json -> settings.json.pre-v29.bak"
  fi
  ok "existing claude config will be preserved (installing in place)"
else
  [ -e "$PREFIX/bin/claude" ]        && fail "\$PREFIX/bin/claude already exists. Use migrate.sh, or 'termux-reset' for a clean install."
  [ -e "$HOME/.local/share/claude" ] && fail "\$HOME/.local/share/claude already exists. Use migrate.sh for an in-place upgrade."
  ok "clean state confirmed"
fi

# --- apt non-interactive options based on Q1 ---
export DEBIAN_FRONTEND=noninteractive
if [ "$FRESH" = 1 ]; then
  APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confnew"
else
  APT_OPTS="-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold"
fi

# --- Pin a Termux mirror if none is selected (avoids an interactive stall) ---
# On a brand-new Termux with no chosen mirror, the package tooling can stop on a
# mirror-selection prompt. Selecting the default first keeps the run unattended.
# Only acts when nothing is chosen yet, so it never overrides a working mirror.
if [ ! -e "$PREFIX/etc/termux/chosen_mirrors" ] && [ -e "$PREFIX/etc/termux/mirrors/default" ]; then
  ln -sf "$PREFIX/etc/termux/mirrors/default" "$PREFIX/etc/termux/chosen_mirrors" 2>/dev/null || true
fi

# --- Termux: bring base packages current ---
# apt-get (not pkg/apt) for the scripted steps: apt-get has a stable CLI and
# does not print apt's "does not have a stable CLI interface" script warning.
info "apt-get update"
apt-get update $APT_OPTS >/dev/null || fail "apt-get update failed"

info "apt-get full-upgrade (fixes any bootstrap/current library mismatches)"
apt-get full-upgrade $APT_OPTS >/dev/null || fail "apt-get full-upgrade failed"

info "apt-get install curl jq"
apt-get install $APT_OPTS curl jq >/dev/null || fail "apt-get install curl/jq failed"
ok "base tools installed"

# --- glibc-runner + patchelf-glibc ---
info "apt-get install glibc-repo (enables Termux glibc-packages source)"
apt-get install $APT_OPTS glibc-repo >/dev/null || fail "glibc-repo install failed"
apt-get update $APT_OPTS >/dev/null || fail "apt-get update after glibc-repo failed"

info "apt-get install glibc-runner patchelf-glibc (~50 MB download)"
apt-get install $APT_OPTS glibc-runner patchelf-glibc >/dev/null || fail "glibc-runner install failed"

PATCHELF="$PREFIX/glibc/bin/patchelf"
GLIBC_LD="$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
[ -x "$PATCHELF" ] || fail "patchelf not found at $PATCHELF after install"
[ -f "$GLIBC_LD" ] || fail "glibc ld.so not found at $GLIBC_LD after install"
ok "glibc-runner + patchelf installed"

# --- Resolve latest claude version, download, verify, patch ---
# SYNC:BEGIN resolve-download-patch (kept byte-identical to migrate.sh: checked by scripts/check-sync.sh)
info "resolving latest claude version from npm registry"
LATEST="$(curl -fsSL --max-time 10 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | jq -r .version 2>/dev/null)"
if [ -z "$LATEST" ] || [ "$LATEST" = "null" ]; then
  fail "could not query npm registry for the latest claude version"
fi
if ! printf '%s' "$LATEST" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  fail "npm registry returned an unexpected version string: $LATEST"
fi
ok "latest claude version: $LATEST"

VERSIONS_DIR="$HOME/.local/share/claude/versions"
BINARY="$VERSIONS_DIR/$LATEST"
WRAPPER="$PREFIX/bin/claude"
mkdir -p "$VERSIONS_DIR" "$HOME/.claude"

DL_BASE="https://downloads.claude.ai/claude-code-releases/$LATEST"

info "downloading $LATEST linux-arm64 binary (~235 MB)"
curl -fsSL --max-time 300 "$DL_BASE/linux-arm64/claude" -o "$BINARY.tmp" \
  || { rm -f "$BINARY.tmp"; fail "binary download failed"; }

info "verifying checksum against published manifest"
EXP="$(curl -fsSL --max-time 10 "$DL_BASE/manifest.json" 2>/dev/null | jq -er '.platforms["linux-arm64"].checksum' 2>/dev/null || true)"
ACT="$(sha256sum "$BINARY.tmp" | cut -d' ' -f1)"
if [ -z "$EXP" ]; then
  rm -f "$BINARY.tmp"
  fail "could not read checksum from manifest"
fi
if [ "$EXP" != "$ACT" ]; then
  rm -f "$BINARY.tmp"
  fail "checksum mismatch: expected $EXP, got $ACT"
fi
ok "checksum verified"

chmod +x "$BINARY.tmp"
LD_PRELOAD='' "$PATCHELF" --set-interpreter "$GLIBC_LD" "$BINARY.tmp" \
  || { rm -f "$BINARY.tmp"; fail "patchelf failed to set ELF interpreter"; }
mv "$BINARY.tmp" "$BINARY"
# SYNC:END resolve-download-patch
ok "binary patched and installed at $BINARY"

write_setdns "$CC_SETDNS"
[ -s "$CC_SETDNS" ] && ok "DNS resolver preload installed ($CC_SETDNS)" \
  || warn "could not write $CC_SETDNS; DNS ETIMEOUT workaround inactive."

# Smoke-test the freshly installed binary. Some upstream releases pass
# "--version" but crash on full launch, from one of two distinct causes:
# Android's seccomp filter blocking a syscall (Android 10 statx or pidfd_open
# -> SIGSYS), or a null deref in Termux's glibc-runner epoll_pwait2 shim under
# the Bun 1.4 runtime (-> SIGSEGV), which is not a blocked syscall. Probe with --init-only
# (it boots the full runtime and exits 0 on a healthy binary). On pass, record
# it as verified so the wrapper's first launch skips the re-test; on fail, warn
# with a working path forward instead of a cryptic crash on first launch.
info "smoke-testing the installed binary"
ST_ERR="$VERSIONS_DIR/.smoke-stderr"
ST_HOME="$VERSIONS_DIR/.smoke-home"
ST_CRASHED=0
ST_LIMIT="${CC_SMOKE_TIMEOUT:-45}"
rm -rf "$ST_HOME"; mkdir -p "$ST_HOME/.claude"
ST_STARTED="$(date +%s)"
if HOME="$ST_HOME" LD_PRELOAD='' timeout -s KILL "$ST_LIMIT" "$BINARY" --init-only </dev/null >/dev/null 2>"$ST_ERR"; then
  ST_RC=0
else
  ST_RC=$?
fi
ST_ELAPSED=$(( $(date +%s) - ST_STARTED ))
rm -rf "$ST_HOME"
if grep -qE 'Bad system call|oh no: Bun has crashed|panic\(|bun\.report' "$ST_ERR" 2>/dev/null; then
  ST_CRASHED=1
  rm -f "$ST_ERR"
  warn "Claude Code $LATEST crashes on this device. This is a known upstream"
  warn "regression in some releases, not an install problem. The install is"
  warn "complete, but this version will not launch here."
  warn "To get a working Claude Code now:"
  warn "  - run  ./install-pinned.sh   to pin a known-good build, or"
  warn "  - run Claude Code inside proot-distro Ubuntu (see the README)."
elif [ "$ST_ELAPSED" -ge "$ST_LIMIT" ]; then
  rm -f "$ST_ERR"
  warn "Could not fully verify Claude Code $LATEST on this device: the launch"
  warn "probe timed out, which can happen on a slow or loaded device. The"
  warn "install is complete; the launcher re-checks on first run and will use"
  warn "this build if it starts."
elif { [ "$ST_RC" -gt 128 ] && [ "$ST_RC" -le 159 ]; }; then
  ST_CRASHED=1
  rm -f "$ST_ERR"
  warn "Claude Code $LATEST crashes on this device. This is a known upstream"
  warn "regression in some releases, not an install problem. The install is"
  warn "complete, but this version will not launch here."
  warn "To get a working Claude Code now:"
  warn "  - run  ./install-pinned.sh   to pin a known-good build, or"
  warn "  - run Claude Code inside proot-distro Ubuntu (see the README)."
else
  rm -f "$ST_ERR"
  printf '%s\n' "$LATEST" > "$VERSIONS_DIR/.verified"
  ok "binary launches cleanly on this device"
fi

fi  # end heavy first-time install (skipped on a refresh)

# --- ~/.claude/settings.json ---
# autoUpdates:false disables claude's in-process updater; the wrapper handles
# updates instead. No env.LD_PRELOAD: a bionic preload set here leaks into the
# Bash tool's subprocesses and breaks claude's bundled grep/rg/ugrep, which
# re-exec the raw glibc binary and then mis-resolve libc. The wrapper already
# clears LD_PRELOAD before exec, so the binary itself is unaffected.
# Known trade-off: without the preload, claude's subprocesses also lose
# termux-exec, so a directly-run "#!/usr/bin/env ..." script cannot find its
# interpreter (Android has no /usr/bin/env). Grep correctness wins; the common
# cases (bash/python/node FILE, and tools called by name) still work.
SF="$HOME/.claude/settings.json"
if [ -e "$SF" ]; then
  TMP="$(mktemp "${TMPDIR:-$PREFIX/tmp}/cc-settings.XXXXXX")"
  if jq 'del(.env.LD_PRELOAD) | .autoUpdates=false | if (.env // {}) == {} then del(.env) else . end' "$SF" > "$TMP" 2>/dev/null; then
    cat "$TMP" > "$SF"     # write THROUGH a possible symlink rather than replacing it
    rm -f "$TMP"
    ok "settings.json updated (existing keys preserved; stale LD_PRELOAD removed)"
  else
    rm -f "$TMP"
    warn "settings.json is not valid JSON; leaving it untouched."
    warn "Set  \"autoUpdates\": false  by hand and remove any env.LD_PRELOAD."
  fi
else
  cat > "$SF" <<'EOF'
{
  "autoUpdates": false
}
EOF
  ok "settings.json written"
fi

# --- Wrapper at $PREFIX/bin/claude ---
# Once per 24h on launch, checks npm for a newer version. If found,
# downloads, verifies checksum, patchelfs, swaps. --update-now forces
# an immediate check, bypassing the rate limit. Any failure (network,
# checksum, patchelf) is reported to stderr and the cached binary is
# used. Repairs the ELF interpreter for any candidate it must test; the
# already-verified binary takes the zero-cost fast path and skips that work.
# Unsets LD_PRELOAD before exec so the glibc binary doesn't crash on
# libtermux-exec's unversioned libc.so dependency.
# SYNC:BEGIN wrapper-heredoc (kept byte-identical to migrate.sh: checked by scripts/check-sync.sh)
cat > "$WRAPPER" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
VERSIONS_DIR="$VERSIONS_DIR"
GLIBC_LD="$GLIBC_LD"
PATCHELF="$PATCHELF"
STAMP="\$VERSIONS_DIR/.last-update-check"
BLOCKLIST="\$VERSIONS_DIR/.blocklist"
VERIFIED="\$VERSIONS_DIR/.verified"
RATE_LIMIT=86400

retry_update_soon() {
  retry_at=\$(( \$(date +%s) - RATE_LIMIT + 3600 ))
  touch -d "@\$retry_at" "\$STAMP" 2>/dev/null || rm -f "\$STAMP"
}

CC_SETDNS="$HOME/.local/share/claude/setdns.js"
CC_SETDNS_JS='try { require("dns").setServers(["8.8.8.8", "8.8.4.4"]); } catch (e) {}'
write_setdns() {
  [ -s "\$1" ] && return 0
  printf '%s\n' "\$CC_SETDNS_JS" > "\$1" 2>/dev/null
}

# Smoke test: returns 0 if the binary launches on this device, 1 if it
# DEFINITELY crashes here (a fatal signal or a known Bun/seccomp crash banner),
# and 2 if the result is inconclusive (the probe timed out, could not exec, or
# the file is empty). Why this exists: upstream has shipped binaries that pass
# "--version" but die on full launch, either from Android's seccomp filter
# (Android 10 statx or pidfd_open -> SIGSYS) or from a null deref in Termux's
# glibc-runner epoll_pwait2 shim under Bun 1.4 (-> SIGSEGV). We probe the full
# runtime with --init-only (it boots the HTTP thread and worker pool and exits
# 0 offline on a healthy binary) and refuse to promote or run anything that
# dies. Only a DEFINITE crash (return 1) is ever blocklisted; an inconclusive
# result (return 2, e.g. a probe that timed out on a slow or thermally
# throttled device) is never blocklisted, so a good build is not permanently
# rejected by a transient hiccup. If a future release drops --init-only the
# probe exits a benign non-zero with no signal and no crash banner, treated as
# healthy (return 0): not rejected, never a false fail.
smoke_test() {
  st_err="\$VERSIONS_DIR/.smoke-stderr"
  st_home="\$VERSIONS_DIR/.smoke-home"
  if [ ! -s "\$1" ]; then return 2; fi
  # Probe in an isolated HOME so we never load the user's hooks (--init-only
  # fires SessionStart/SessionEnd), never depend on login, and never write to
  # the real ~/.claude. The crash we detect is a syscall, independent of config.
  rm -rf "\$st_home"; mkdir -p "\$st_home/.claude"
  st_limit="\${CC_SMOKE_TIMEOUT:-45}"
  st_started=\$(date +%s)
  HOME="\$st_home" LD_PRELOAD= timeout -s KILL "\$st_limit" "\$1" --init-only </dev/null >/dev/null 2>"\$st_err"
  st_rc=\$?
  st_elapsed=\$(( \$(date +%s) - st_started ))
  rm -rf "\$st_home"
  # A known crash banner is authoritative even if it appeared near the timeout.
  if grep -qE 'Bad system call|oh no: Bun has crashed|panic\(|bun\.report' "\$st_err" 2>/dev/null; then
    rm -f "\$st_err"; return 1
  fi
  # timeout exit conventions vary. Elapsed time is the portable signal.
  if [ "\$st_elapsed" -ge "\$st_limit" ]; then rm -f "\$st_err"; return 2; fi
  if [ "\$st_rc" -gt 128 ] && [ "\$st_rc" -le 159 ]; then rm -f "\$st_err"; return 1; fi
  if [ "\$st_rc" -eq 126 ] || [ "\$st_rc" -eq 127 ]; then rm -f "\$st_err"; return 2; fi
  rm -f "\$st_err"
  return 0
}

force_update=0
args=()
for a in "\$@"; do
  if [ "\$a" = "--update-now" ]; then
    force_update=1
  else
    args+=("\$a")
  fi
done

should_check=0
if [ "\$force_update" = 1 ]; then
  should_check=1
elif [ ! -f "\$STAMP" ]; then
  should_check=1
else
  now=\$(date +%s)
  last=\$(stat -c%Y "\$STAMP" 2>/dev/null || echo 0)
  [ \$((now - last)) -ge \$RATE_LIMIT ] && should_check=1
fi

if [ "\$should_check" = 1 ]; then
  # One-updater lock: only one claude process downloads at a time. A second
  # launch during the (up to 5 min) download skips the update and runs the
  # cached binary instead of racing on a shared staging file. A crashed
  # updater's lock is stolen after 15 min so updates can never wedge forever.
  LOCK="\$VERSIONS_DIR/.update.lock"
  if [ -d "\$LOCK" ]; then
    lock_age=\$(( \$(date +%s) - \$(stat -c%Y "\$LOCK" 2>/dev/null || echo 0) ))
    [ "\$lock_age" -ge 900 ] && rmdir "\$LOCK" 2>/dev/null
  fi
  if mkdir "\$LOCK" 2>/dev/null; then
    # A SIGKILL during download bypasses normal cleanup. Sweep stale staging
    # files on every serialized update check; a live download is only minutes old.
    cleanup_now=\$(date +%s 2>/dev/null || echo "")
    case "\$cleanup_now" in ""|*[!0-9]*) cleanup_now=0 ;; esac
    for stale_tmp in "\$VERSIONS_DIR"/*.tmp; do
      [ -f "\$stale_tmp" ] && [ ! -L "\$stale_tmp" ] || continue
      stale_mtime=\$(stat -c%Y "\$stale_tmp" 2>/dev/null || echo "")
      case "\$stale_mtime" in ""|*[!0-9]*) continue ;; esac
      [ \$(( cleanup_now - stale_mtime )) -gt 86400 ] && rm -f "\$stale_tmp" 2>/dev/null
    done
    touch "\$STAMP"
    latest=\$(curl -fsSL --max-time 5 https://registry.npmjs.org/@anthropic-ai/claude-code/latest 2>/dev/null | jq -r .version 2>/dev/null || echo "")
    if [ -n "\$latest" ] && printf '%s' "\$latest" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\$'; then
      new_bin="\$VERSIONS_DIR/\$latest"
      # Per-process staging path (never a shared name) so two updaters cannot
      # clobber each other's in-flight download.
      tmp="\$new_bin.\$\$.tmp"
      if [ ! -f "\$new_bin" ] && ! grep -qxF "\$latest" "\$BLOCKLIST" 2>/dev/null; then
        dl="https://downloads.claude.ai/claude-code-releases/\$latest"
        if curl -fsSL --max-time 300 "\$dl/linux-arm64/claude" -o "\$tmp" 2>/dev/null && [ -s "\$tmp" ]; then
          exp=\$(curl -fsSL --max-time 5 "\$dl/manifest.json" 2>/dev/null | jq -er '.platforms["linux-arm64"].checksum' 2>/dev/null || echo "")
          act=\$(sha256sum "\$tmp" 2>/dev/null | cut -d' ' -f1)
          if [ -z "\$exp" ]; then
            rm -f "\$tmp"
            retry_update_soon
            echo "[claude] update: could not read release manifest, using cached" >&2
          elif [ "\$exp" != "\$act" ]; then
            rm -f "\$tmp"
            retry_update_soon
            echo "[claude] update: checksum mismatch on \$latest, using cached" >&2
          else
            chmod +x "\$tmp"
            if ! LD_PRELOAD= "\$PATCHELF" --set-interpreter "\$GLIBC_LD" "\$tmp" 2>/dev/null; then
              rm -f "\$tmp"
              echo "[claude] update: patchelf failed on \$latest, using cached" >&2
            else
              smoke_test "\$tmp"; sc=\$?
              if [ "\$sc" -eq 0 ]; then
                mv "\$tmp" "\$new_bin"
                printf '%s\n' "\$latest" > "\$VERIFIED"
                # Retain N-1 (latest + previous) for rollback. Only version-named
                # binaries are removed, never a staging .tmp or the lock dir.
                prev=\$(ls -1 "\$VERSIONS_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\$' | sort -V | tail -2 | head -1)
                for old in "\$VERSIONS_DIR"/*; do
                  base=\$(basename "\$old")
                  printf '%s' "\$base" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\$' || continue
                  [ -f "\$old" ] && [ "\$base" != "\$latest" ] && [ "\$base" != "\$prev" ] && rm -f "\$old"
                done
              elif [ "\$sc" -eq 1 ]; then
                rm -f "\$tmp"
                printf '%s\n' "\$latest" >> "\$BLOCKLIST"
                echo "[claude] update: \$latest crashes on launch (failed smoke test), keeping cached" >&2
              else
                rm -f "\$tmp"
                echo "[claude] update: could not verify \$latest on this device, keeping cached" >&2
              fi
            fi
          fi
        else
          rm -f "\$tmp" 2>/dev/null
          retry_update_soon
          echo "[claude] update: download incomplete, using cached" >&2
        fi
      fi
    else
      retry_update_soon
      echo "[claude] update: could not query npm registry, using cached" >&2
    fi
    rmdir "\$LOCK" 2>/dev/null
  fi
fi

# Pick the highest installed version that actually launches on this device.
# Self-healing rollback: skip blocklisted versions; the already-verified-good
# version runs with no re-test (zero startup cost); any other candidate is
# re-patched and smoke-tested, and if it crashes it is blocklisted and we fall
# back to the next-highest. This rescues a device that auto-updated to a binary
# that crashes here (e.g. a bad release that landed before this wrapper shipped)
# with no user action.
verified=\$(cat "\$VERIFIED" 2>/dev/null || echo "")
bin=""
fallback=""
for cand in \$(ls -1 "\$VERSIONS_DIR" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\$' | sort -Vr); do
  grep -qxF "\$cand" "\$BLOCKLIST" 2>/dev/null && continue
  cpath="\$VERSIONS_DIR/\$cand"
  [ -f "\$cpath" ] || continue
  if [ "\$cand" = "\$verified" ]; then bin="\$cpath"; break; fi
  interp=\$(LD_PRELOAD= "\$PATCHELF" --print-interpreter "\$cpath" 2>/dev/null || echo unknown)
  [ "\$interp" = "\$GLIBC_LD" ] || LD_PRELOAD= "\$PATCHELF" --set-interpreter "\$GLIBC_LD" "\$cpath" 2>/dev/null
  smoke_test "\$cpath"; sc=\$?
  if [ "\$sc" -eq 0 ]; then
    printf '%s\n' "\$cand" > "\$VERIFIED"
    bin="\$cpath"
    break
  elif [ "\$sc" -eq 1 ]; then
    echo "[claude] \$cand crashes on this device; rolling back to the previous version" >&2
    printf '%s\n' "\$cand" >> "\$BLOCKLIST"
  else
    # Inconclusive (e.g. the probe timed out on a slow device): do not blocklist,
    # but remember the highest such build as a last resort so we still launch.
    [ -z "\$fallback" ] && fallback="\$cpath"
    echo "[claude] could not verify \$cand on this device; trying an older version first" >&2
  fi
done
# Nothing probed clean, but a build merely failed to prove itself (never
# crashed): run the highest such build rather than refuse. An inconclusive
# probe is not a crash.
[ -z "\$bin" ] && [ -n "\$fallback" ] && bin="\$fallback"
if [ -z "\$bin" ]; then
  echo "[claude] no working claude binary found in \$VERSIONS_DIR. Re-run install.sh." >&2
  exit 1
fi

write_setdns "\$CC_SETDNS"
if [ -s "\$CC_SETDNS" ]; then
  # Bun resolves relative preloads from its physical CWD; default realpath resolves
  # symlinks to match that assumption and avoids its node_modules walk to / (cosmetic EACCES).
  # The absolute fallback keeps DNS working if relative-path resolution fails.
  cc_preload=\$(realpath --relative-to="\$PWD" "\$CC_SETDNS" 2>/dev/null) || cc_preload=""
  case "\$cc_preload" in
    ./*|../*) ;;
    "") cc_preload="\$CC_SETDNS" ;;
    /*) cc_preload="\$CC_SETDNS" ;;
    *) cc_preload="./\$cc_preload" ;;
  esac
  export BUN_OPTIONS="--preload \$cc_preload\${BUN_OPTIONS:+ \$BUN_OPTIONS}"
fi
unset LD_PRELOAD
exec "\$bin" "\${args[@]}"
EOF
# SYNC:END wrapper-heredoc
chmod +x "$WRAPPER"
ok "wrapper installed at $WRAPPER"

# --- Native-install launcher discovery ---
# Claude Code sees the binary under ~/.local/share/claude/versions, treats it as
# a native install, and expects a launcher at ~/.local/bin/claude with
# ~/.local/bin on PATH. Without them it prints "Native installation ... not in
# your PATH" notices at startup. Set both up the way claude's own message
# prescribes. The launcher points at this wrapper so every invocation still
# routes through it; ~/.local/bin is appended to PATH so $PREFIX/bin stays first.
mkdir -p "$HOME/.local/bin"
ln -sfn "$WRAPPER" "$HOME/.local/bin/claude"
if ! grep -Fq 'native-install launcher discovery' "$HOME/.bashrc" 2>/dev/null; then
  printf '\n# claude-code-android: native-install launcher discovery\nexport PATH="$PATH:$HOME/.local/bin"\n' >> "$HOME/.bashrc"
  ok "added ~/.local/bin to PATH in ~/.bashrc"
else
  ok "PATH already includes ~/.local/bin in ~/.bashrc"
fi

# --- Recommended packages (Q2) ---
if [ "$RECOMMENDED" = 1 ]; then
  info "installing recommended packages (this is the longest step)"
  apt-get install $APT_OPTS git gh wget jq python openssh tree proot \
    termux-api proot-distro make clang file xxd htop bat fzf >/dev/null \
    || fail "recommended package install failed"
  ok "recommended packages installed"
fi

# --- Verify ---
hash -r 2>/dev/null || true
if VER="$(claude --version 2>&1)"; then
  ok "claude --version: $VER"
elif [ "${REFRESH:-0}" = 1 ]; then
  warn "the refreshed launcher could not find a working Claude Code version on this device."
  warn "run  ./install-pinned.sh  to pin a known-good build, or use proot-distro Ubuntu (see the README)."
elif [ "${ST_CRASHED:-0}" = 1 ]; then
  cat <<DONE

Install complete, but this Claude Code release cannot run on this device.

  Wrapper:   $WRAPPER
  Binary:    $BINARY
  Settings:  $HOME/.claude/settings.json

The installer finished successfully, but the native Claude Code binary crashes
on this Android version. Do not start claude; it will not work here.

To get a working Claude Code:

  On this Android version you need pinned Claude Code 2.1.112, the last
  release that runs here.

  Upstream cause and status:
  https://github.com/anthropics/claude-code/issues/50270

  Full explanation and other options:
  https://github.com/ferrumclaudepilgrim/claude-code-android

DONE
  PINNED_URL="https://raw.githubusercontent.com/ferrumclaudepilgrim/claude-code-android/main/install-pinned.sh"
  print_pinned_command() {
    printf '\nTo install the working pinned release manually:\n\n'
    printf '  curl -fsSL %s -o install-pinned.sh\n' "$PINNED_URL"
    printf '  bash install-pinned.sh\n\n'
  }
  if [ -t 0 ]; then
    printf 'Install pinned Claude Code 2.1.112 now? [Y/n] '
    if read -r PIN_REPLY; then
      PIN_REPLY="${PIN_REPLY:-Y}"
    else
      PIN_REPLY=n
    fi
    case "${PIN_REPLY,,}" in
      y|yes)
        if PIN_SCRIPT="$(mktemp "${TMPDIR:-$PREFIX/tmp}/install-pinned.XXXXXX")"; then
          if curl -fsSL "$PINNED_URL" -o "$PIN_SCRIPT"; then
            if bash "$PIN_SCRIPT"; then
              ok "pinned Claude Code 2.1.112 installed"
            else
              warn "the optional pinned install failed; the native install is still complete."
              print_pinned_command
            fi
          else
            warn "could not download install-pinned.sh; the native install is still complete."
            print_pinned_command
          fi
          rm -f "$PIN_SCRIPT"
        else
          warn "could not create a temporary file for install-pinned.sh."
          print_pinned_command
        fi
        ;;
      *)
        info "pinned install declined; the native install is still complete."
        print_pinned_command
        ;;
    esac
  else
    info "stdin is not interactive, so the optional pinned install was not started."
    print_pinned_command
  fi
  exit 0
else
  fail "claude --version failed: $VER"
fi

# --- Done ---
cat <<DONE

Install complete.

  Wrapper:   $WRAPPER
  Binary:    $BINARY
  Settings:  $HOME/.claude/settings.json

The wrapper auto-checks for a new claude release once per day on launch.
To force an immediate check at any time:  claude --update-now

Open a new Termux session then type:

  claude