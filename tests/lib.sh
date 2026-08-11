#!/bin/sh
#
# Shared helpers. Sourced by every *_test.sh in this directory.
#

unset CDPATH
TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(cd -- "$TESTS_DIR/.." && pwd)
OVERLAY=$REPO_ROOT/aa_wireless_dongle/board/common/rootfs_overlay
# shellcheck disable=SC2034  # used by the test scripts that source this file
FIXTURES=$TESTS_DIR/fixtures

# The device runs busybox ash. It is not available on a build host, so drive the
# scripts with dash, the closest POSIX shell. Override with TEST_SH to run the
# same tests against busybox ash on the device.
if [ -z "${TEST_SH:-}" ]; then
	if [ -x /bin/dash ]; then
		TEST_SH=/bin/dash
	else
		TEST_SH=/bin/sh
	fi
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/aawg-tests.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'rm -rf "$WORK"; exit 1' INT TERM

tests_total=0
tests_failed=0

pass() {
	tests_total=$((tests_total + 1))
	echo "PASS  $1"
}

fail() {
	tests_total=$((tests_total + 1))
	tests_failed=$((tests_failed + 1))
	echo "FAIL  $1"
	if [ -n "${2:-}" ]; then
		echo "$2" | sed 's/^/          /'
	fi
}

skip() {
	echo "SKIP  $1"
	if [ -n "${2:-}" ]; then
		echo "          $2"
	fi
}

assert_eq() {
	if [ "$2" = "$3" ]; then
		pass "$1"
	else
		fail "$1" "expected [$2], got [$3]"
	fi
}

assert_ne() {
	if [ "$2" != "$3" ]; then
		pass "$1"
	else
		fail "$1" "expected anything but [$2]"
	fi
}

assert_contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1" "expected to contain [$3], got:
$2" ;;
	esac
}

assert_not_contains() {
	case "$2" in
	*"$3"*) fail "$1" "expected not to contain [$3], got:
$2" ;;
	*) pass "$1" ;;
	esac
}

assert_between() {
	case "$2" in
	'' | *[!0-9]*)
		fail "$1" "expected a number in $3..$4, got [$2]"
		return
		;;
	esac
	if [ "$2" -ge "$3" ] && [ "$2" -le "$4" ]; then
		pass "$1"
	else
		fail "$1" "expected $3..$4, got $2"
	fi
}

summary() {
	echo "      $((tests_total - tests_failed))/$tests_total assertions passed"
	[ "$tests_failed" -eq 0 ]
}

# Build a throwaway root holding runnable copies of the init scripts.
#
# The scripts hard-code /etc and /var/run and call the busybox-ash `source`
# builtin, which dash does not have. Both are rewritten here so the scripts can
# run unprivileged on a host; `source` and `.` are the same builtin in ash, and
# the logic under test is untouched. The rewrites are then verified, so a test
# can never silently exercise a file it failed to redirect.
#
# Prints the root on stdout.
sandbox_refers() {
	if grep -qF -- "$2" "$root/etc/init.d/$1"; then
		return 0
	fi
	echo "harness error: $1 no longer refers to ${2#"$root"}" >&2
	return 1
}

new_sandbox() {
	root=$WORK/$1
	mkdir -p "$root/etc/init.d" "$root/var/run" || return 1

	for script in rcS_aawgd_conf S39hostapd_conf; do
		sed -e "s#/etc/#$root/etc/#g" \
			-e "s#/var/run/#$root/var/run/#g" \
			-e "s#^\([[:space:]]*\)source #\1. #" \
			"$OVERLAY/etc/init.d/$script" >"$root/etc/init.d/$script" || return 1
		chmod +x "$root/etc/init.d/$script"
	done

	sandbox_refers rcS_aawgd_conf "$root/etc/aawgd.conf" || return 1
	sandbox_refers rcS_aawgd_conf "$root/var/run/aawg_wifi_password" || return 1
	sandbox_refers S39hostapd_conf "$root/etc/init.d/rcS_aawgd_conf" || return 1
	sandbox_refers S39hostapd_conf "$root/etc/hostapd.conf.in" || return 1
	sandbox_refers S39hostapd_conf "$root/var/run/hostapd.conf" || return 1

	if grep -qE '^[[:space:]]*source ' "$root/etc/init.d/"*; then
		echo "harness error: an ash 'source' builtin survived the rewrite" >&2
		return 1
	fi

	echo "$root"
}
