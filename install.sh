#!/usr/bin/env bash
#
# install.sh — set up github.com/Ujstor/tmux-config on this host.
#
#   curl -sSL https://raw.githubusercontent.com/Ujstor/tmux-config/master/install.sh | bash
#   curl -sSL https://raw.githubusercontent.com/Ujstor/tmux-config/master/install.sh | bash -s -- --build-tmux
#   ./install.sh --help
#
# In order it:
#   1. makes sure a tmux >= 3.2 is on this box (the distro package by default; a
#      source build only when you ask for one)
#   2. backs up ~/.tmux.conf, then installs this repo's .tmux.conf and tmux.sh
#   3. installs TPM *and* every plugin the config lists, non-interactively —
#      no prefix+I step, which is the whole point: without the plugins the
#      config comes up bare and looks broken
#   4. reloads any tmux server that is already running
#
# Safe to re-run. Every step is idempotent, nothing is deleted, and anything it
# replaces is backed up next to the original first.

set -euo pipefail

REPO_URL="https://github.com/Ujstor/tmux-config.git"
REPO_BRANCH="master"

# The config needs tmux >= 3.2, for two things it actually uses:
#   * `#{E:...}` format expansion  — the catppuccin v2 status line
#   * `terminal-features`          — the clipboard block
# Ubuntu 22.04 ships 3.2a, Ubuntu 24.04 ships 3.4, Debian 12 ships 3.3a, so the
# distro package clears the bar nearly everywhere. That is why the default is to
# USE it rather than to rip it out and build a private copy.
TMUX_MIN_VERSION="3.2"

# An explicit PIN used only by --build-tmux. This is a pinned version, not
# "latest": the previous script called it "latest" in a comment while resolving
# whatever the GitHub API returned that minute, so two runs a week apart could
# install two different tmuxes. Bump this line deliberately.
TMUX_SOURCE_VERSION="${TMUX_SOURCE_VERSION:-3.7c}"

BUILD_TMUX="${TMUX_BUILD:-0}"
SKIP_PLUGINS="${TMUX_SKIP_PLUGINS:-0}"
FORCE=0

TPM_REPO="https://github.com/tmux-plugins/tpm"
TPM_DIR="$HOME/.tmux/plugins/tpm"
CONF_DST="$HOME/.tmux.conf"
# ~/tmux.sh, not somewhere tidier, because that is where `bind q` and `bind a`
# in .tmux.conf look for it. Change both or neither.
TMUXSH_DST="$HOME/tmux.sh"

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
NOTES=()

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }
note() { NOTES+=("$*"); }

usage() {
	cat <<'EOF'
Usage: install.sh [options]

  --build-tmux           Build the pinned tmux from source into /usr/local
                         instead of using the distro package. Opt-in on
                         purpose: it is slow, needs a compiler toolchain, and
                         is unnecessary on any distro shipping tmux >= 3.2.
                         The distro tmux is left in place either way.
  --tmux-version VER     Version to build with --build-tmux (default: pinned).
  --skip-plugins         Install TPM but do not clone the plugins.
  --force                Replace ~/.tmux.conf even when it is a symlink
                         (e.g. managed by a dotfiles repo). Backed up first.
  -h, --help             This text.

Environment equivalents: TMUX_BUILD=1, TMUX_SOURCE_VERSION=3.7c,
TMUX_SKIP_PLUGINS=1.

Piping from curl? Pass flags after `--`:
  curl -sSL .../install.sh | bash -s -- --build-tmux
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
	--build-tmux) BUILD_TMUX=1 ;;
	--tmux-version)
		[ $# -ge 2 ] || die "--tmux-version needs a value"
		TMUX_SOURCE_VERSION="$2"
		shift
		;;
	--tmux-version=*) TMUX_SOURCE_VERSION="${1#*=}" ;;
	--skip-plugins) SKIP_PLUGINS=1 ;;
	--force) FORCE=1 ;;
	-h | --help)
		usage
		exit 0
		;;
	*) die "unknown option: $1 (try --help)" ;;
	esac
	shift
done

have() { command -v "$1" >/dev/null 2>&1; }

# Root only where root is genuinely needed, and never assume sudo exists.
as_root() {
	if [ "$(id -u)" -eq 0 ]; then
		"$@"
	elif have sudo; then
		sudo "$@"
	else
		return 127
	fi
}

# version_ge A B -> true when A >= B. `sort -V` orders 3.2 < 3.4 < 3.5a < 3.7c.
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

tmux_version() { tmux -V 2>/dev/null | awk '{print $2}' | sed 's/^next-//'; }

PKG=""
detect_pkg() {
	for p in apt-get dnf yum pacman zypper apk brew; do
		have "$p" && {
			PKG="$p"
			return 0
		}
	done
	return 1
}

APT_UPDATED=0
pkg_install() { # pkg_install <debian-names...>  (best effort elsewhere)
	[ $# -gt 0 ] || return 0
	case "$PKG" in
	apt-get)
		if [ "$APT_UPDATED" -eq 0 ]; then
			as_root apt-get update -qq || return 1
			APT_UPDATED=1
		fi
		as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
		;;
	dnf | yum) as_root "$PKG" install -y "$@" ;;
	pacman) as_root pacman -S --needed --noconfirm "$@" ;;
	zypper) as_root zypper --non-interactive install "$@" ;;
	apk) as_root apk add --no-cache "$@" ;;
	brew) brew install "$@" ;;
	*) return 1 ;;
	esac
}

# ── 1. tmux ──────────────────────────────────────────────────────────────────
build_tmux_from_source() {
	local v="$TMUX_SOURCE_VERSION" work
	log "building tmux $v from source (--build-tmux)"

	# NOTE: nothing here removes the distro tmux. The previous version of this
	# script ran `sudo rm -rf /usr/local/bin/tmux /usr/bin/tmux
	# /usr/local/share/tmux /usr/share/tmux` and then symlinked its own build
	# over /usr/bin/tmux. That deletes a dpkg/rpm-owned file behind the package
	# manager's back and breaks anything depending on the packaged tmux.
	case "$PKG" in
	apt-get) pkg_install build-essential bison pkg-config libevent-dev libncurses-dev ||
		die "could not install the build dependencies" ;;
	dnf | yum) pkg_install gcc make bison pkgconf-pkg-config libevent-devel ncurses-devel || die "could not install the build dependencies" ;;
	pacman) pkg_install base-devel bison libevent ncurses || die "could not install the build dependencies" ;;
	apk) pkg_install build-base bison pkgconf libevent-dev ncurses-dev || die "could not install the build dependencies" ;;
	*) warn "unknown package manager: install libevent, ncurses and a C toolchain yourself" ;;
	esac

	work="$(mktemp -d)"
	# shellcheck disable=SC2064
	trap "rm -rf '$work'" RETURN
	curl -fsSL --proto '=https' --tlsv1.2 \
		"https://github.com/tmux/tmux/releases/download/${v}/tmux-${v}.tar.gz" |
		tar -xz -C "$work" || die "could not download tmux $v"
	(
		cd "$work/tmux-${v}"
		./configure --prefix=/usr/local >/dev/null
		make -j"$(nproc 2>/dev/null || echo 2)" >/dev/null
		as_root make install >/dev/null
	) || die "the tmux $v build failed"

	hash -r 2>/dev/null || true
	log "tmux: built $v into /usr/local/bin/tmux"
	if [ "$(command -v tmux)" != "/usr/local/bin/tmux" ]; then
		note "PATH still resolves tmux to $(command -v tmux) ($(tmux_version)); put /usr/local/bin ahead of /usr/bin to use the build."
	fi
}

ensure_tmux() {
	detect_pkg || warn "no known package manager found; skipping automatic installs"

	if [ "$BUILD_TMUX" = "1" ]; then
		build_tmux_from_source
		return
	fi

	if have tmux && version_ge "$(tmux_version)" "$TMUX_MIN_VERSION"; then
		log "tmux: using the one already installed — $(tmux_version) at $(command -v tmux) (>= $TMUX_MIN_VERSION)"
	else
		if have tmux; then
			info "tmux $(tmux_version) is older than the $TMUX_MIN_VERSION this config needs; trying the package manager"
		else
			info "no tmux found; installing the distro package"
		fi
		pkg_install tmux || warn "could not install tmux with $PKG"
		hash -r 2>/dev/null || true
		have tmux || die "tmux is still not installed. Install it, or re-run with --build-tmux."
		if version_ge "$(tmux_version)" "$TMUX_MIN_VERSION"; then
			log "tmux: installed the distro package — $(tmux_version) at $(command -v tmux)"
		else
			die "the distro only offers tmux $(tmux_version), below the $TMUX_MIN_VERSION this config needs. Re-run with --build-tmux."
		fi
	fi

	# Leftover from the old destructive install path: the packaged binary was
	# deleted and replaced by a symlink to a source build, so dpkg/rpm now
	# disagrees with what is on disk.
	if [ -L /usr/bin/tmux ] && [ "$(readlink -f /usr/bin/tmux 2>/dev/null)" = "/usr/local/bin/tmux" ]; then
		note "/usr/bin/tmux is a symlink to /usr/local/bin/tmux — an earlier version of this script deleted the packaged binary. To restore it: sudo apt-get install --reinstall tmux"
	fi
}

# ── 2. payload ───────────────────────────────────────────────────────────────
SRC_DIR=""
CLONE_DIR=""
resolve_payload() {
	local here="${BASH_SOURCE[0]:-}"
	if [ -n "$here" ] && [ -f "$here" ]; then
		here="$(cd "$(dirname "$here")" && pwd)"
		if [ -f "$here/.tmux.conf" ] && [ -f "$here/tmux.sh" ]; then
			SRC_DIR="$here"
			log "config: using this checkout — $SRC_DIR"
			return
		fi
	fi
	have git || { pkg_install git || die "git is required"; }
	CLONE_DIR="$(mktemp -d)"
	log "config: fetching $REPO_URL ($REPO_BRANCH)"
	git clone -q --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$CLONE_DIR/repo" ||
		die "could not clone $REPO_URL"
	SRC_DIR="$CLONE_DIR/repo"
}
cleanup() {
  # `return 0` is load-bearing. Run from a checkout CLONE_DIR is empty, so
  # `[ -n "" ]` returns 1 as the trap's last command — and under `set -e`
  # that becomes the SCRIPT's exit status. The install succeeds and the
  # caller still sees failure, which breaks any `&&` chain or CI gate.
  [ -n "$CLONE_DIR" ] && rm -rf "$CLONE_DIR"
  return 0
}
trap cleanup EXIT

# install_file SRC DST MODE — never clobbers without a timestamped backup, and
# refuses to silently eat a symlink that a dotfiles repo probably owns.
install_file() {
	local src="$1" dst="$2" mode="$3" bak
	if [ -L "$dst" ]; then
		if [ "$FORCE" != "1" ]; then
			warn "$dst is a symlink -> $(readlink "$dst")"
			warn "  left alone. Either update that file from this repo, or re-run with --force."
			note "$dst was NOT updated (symlink; use --force)."
			return 0
		fi
		bak="$dst.symlink.bak.$STAMP"
		cp -P -- "$dst" "$bak"
		info "backed up the symlink $dst -> $bak"
	elif [ -e "$dst" ]; then
		if cmp -s -- "$src" "$dst"; then
			info "$dst is already up to date"
			return 0
		fi
		bak="$dst.bak.$STAMP"
		cp -p -- "$dst" "$bak"
		info "backed up $dst -> $bak"
	fi
	install -m "$mode" -- "$src" "$dst"
	info "installed $dst"
}

# ── 3. TPM + plugins ─────────────────────────────────────────────────────────
ensure_tpm() {
	have git || { pkg_install git || die "git is required to install TPM"; }
	if [ -d "$TPM_DIR/.git" ]; then
		info "TPM already present at $TPM_DIR"
		git -C "$TPM_DIR" pull --ff-only -q 2>/dev/null || warn "could not update TPM (keeping the existing checkout)"
	else
		if [ -e "$TPM_DIR" ]; then
			mv -- "$TPM_DIR" "$TPM_DIR.bak.$STAMP"
			info "moved a non-git $TPM_DIR aside"
		fi
		mkdir -p -- "$(dirname "$TPM_DIR")"
		git clone -q "$TPM_REPO" "$TPM_DIR" || die "could not clone TPM"
		info "cloned TPM into $TPM_DIR"
	fi
}

install_plugins() {
	# The step the old script left to the user. `prefix + I` inside a running
	# session was the documented way, so a fresh box had TPM but no plugins:
	# no theme, no resurrect, no yank — which reads as "the config is broken".
	# This entry point needs no session and no keypress.
	local runner="$TPM_DIR/bin/install_plugins"
	[ -x "$runner" ] || {
		warn "$runner is missing; skipping plugin install"
		return 0
	}
	log "installing plugins listed in $CONF_DST"
	if "$runner"; then :; else
		warn "TPM reported a problem; re-run install.sh, or use prefix + I inside tmux"
		note "plugin install did not finish cleanly."
	fi
}

verify_plugins() {
	local missing=() name
	while read -r name; do
		[ -n "$name" ] || continue
		[ -d "$HOME/.tmux/plugins/$name" ] || missing+=("$name")
	done < <(awk '/^[ \t]*set(-option)? +-g +@plugin/ {gsub(/["'\'']/,"",$4); sub(/#.*/,"",$4); n=split($4,p,"/"); print p[n]}' "$CONF_DST")
	if [ ${#missing[@]} -gt 0 ]; then
		warn "not installed: ${missing[*]}"
		note "missing plugins: ${missing[*]}"
	else
		info "all plugins present under ~/.tmux/plugins"
	fi
}

# ── run ──────────────────────────────────────────────────────────────────────
ensure_tmux
resolve_payload

log "installing config"
install_file "$SRC_DIR/.tmux.conf" "$CONF_DST" 0644
install_file "$SRC_DIR/tmux.sh" "$TMUXSH_DST" 0755

log "installing TPM"
ensure_tpm
if [ "$SKIP_PLUGINS" = "1" ]; then
	info "--skip-plugins: not cloning plugins"
else
	install_plugins
	verify_plugins
fi

# Optional but genuinely used by the config: `tree` backs @sidebar-tree-command,
# and a clipboard tool is what the copy binds reach for on a graphical box.
# Never fatal — the config degrades on its own if they are absent.
if ! have tree; then
	pkg_install tree >/dev/null 2>&1 || note "'tree' is not installed; the sidebar plugin (prefix + e) will be empty."
fi
if [ -n "${WAYLAND_DISPLAY:-}" ] && ! have wl-copy; then
	pkg_install wl-clipboard >/dev/null 2>&1 || note "Wayland session without wl-clipboard; copy falls back to OSC 52."
elif [ -n "${DISPLAY:-}" ] && ! have xclip && ! have xsel; then
	pkg_install xclip >/dev/null 2>&1 || note "X11 session without xclip/xsel; copy falls back to OSC 52."
fi

# Pick up the new config in sessions that are already open.
if tmux ls >/dev/null 2>&1; then
	if tmux source-file "$CONF_DST" >/dev/null 2>&1; then
		info "reloaded the config in the running tmux server"
	else
		note "could not reload the running server; use prefix + r."
	fi
fi

echo
log "done — tmux $(tmux_version), config at $CONF_DST"
info "prefix is C-Space; prefix + r reloads; prefix + I updates plugins"
if [ ${#NOTES[@]} -gt 0 ]; then
	echo
	warn "worth knowing:"
	for n in "${NOTES[@]}"; do printf '    - %s\n' "$n"; done
fi
