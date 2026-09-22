#!/bin/sh
# Adaptable tmux resize script by percentage
#
# Installed at ~/tmux.sh by install.sh, because that is the path `bind q` and
# `bind a` in .tmux.conf call. Move it and you must move both binds too.
#
# Layout types supported (-l):
#
# main-horizontal: top pane is main pane, panes split left to right on the bottom
# main-vertical: left pane is maine pane, right panes split top to bottom on the
#                right side
#
# Options:
#
# -l layout-name (required): the name of the layout, "main-horizontal" or "main-vertical"
# -p percentage (required): an integer of the percentage of the client width/height to set
# -t target-window (optional): the tmux target for the window, can be an fnmatch(1) of the
#                              window name, index, or id
#
# Example usage:
#
# Case 1: Resize to a main-horizontal, main pane 66% of client height
# $ ./tmux.sh -p 66 -l main-horizontal
#
# Case 2: Same as Case 1, target "devel" window
# $ ./tmux.sh -p 66 -l main-horizontal -t devel
#
# Case 3: Resize to a main-horizontal, main pane half width
# $ ./tmux.sh -p 50 -l main-vertical
#
# Case 4: Same as Case 3, target "mywindow"
# $ ./tmux.sh -p 50 -l main-vertical -t mywindow
#
# Author: Tony Narlock
# Website: https://devel.tech
# License: MIT
#
# Local changes: every expansion is quoted, both required options are now
# actually enforced (a bare `tmux.sh` used to reach `tmux setw` with empty
# arguments and fail there), and `expr` is replaced with POSIX arithmetic.

usage() {
	printf 'Usage: %s -l <main-horizontal|main-vertical> -p <percentage> [-t target-window]\n' "$0" >&2
}

lflag=
pflag=
layout_name=
percentage=
target=

while getopts l:p:t: name; do
	case $name in
	l)
		lflag=1
		layout_name="$OPTARG"
		;;
	p)
		pflag=1
		percentage="$OPTARG"
		;;
	t)
		target="$OPTARG"
		;;
	?)
		usage
		exit 2
		;;
	esac
done

if [ -z "$lflag" ] || [ -z "$pflag" ]; then
	usage
	exit 2
fi

if ! [ "$percentage" -eq "$percentage" ] 2>/dev/null; then
	printf 'Percentage (-p) must be an integer\n' >&2
	exit 1
fi

case "$layout_name" in
main-horizontal | main-vertical) ;;
*)
	printf 'layout name must be main-horizontal or main-vertical\n' >&2
	exit 1
	;;
esac

# Measure the window that is being resized: with -t that is the TARGET, not
# the one this runs from (a 200-column target measured from an 80-column window
# got a main pane of 40 instead of 100).
if [ "$layout_name" = "main-vertical" ]; then
	MAIN_SIZE_OPTION='main-pane-width'
	dimension=$(tmux display -p ${target:+-t "$target"} '#{window_width}')
else
	MAIN_SIZE_OPTION='main-pane-height'
	dimension=$(tmux display -p ${target:+-t "$target"} '#{window_height}')
fi

if [ -z "$dimension" ]; then
	printf 'tmux.sh: no tmux window to resize (run it from inside tmux)\n' >&2
	exit 1
fi

MAIN_PANE_SIZE=$((dimension * percentage / 100))

if [ -n "$target" ]; then
	tmux setw -t "$target" "$MAIN_SIZE_OPTION" "$MAIN_PANE_SIZE"
	tmux select-layout -t "$target" "$layout_name"
else
	tmux setw "$MAIN_SIZE_OPTION" "$MAIN_PANE_SIZE"
	tmux select-layout "$layout_name"
fi

exit 0
