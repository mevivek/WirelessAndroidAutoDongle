#!/bin/sh
#
# ShellCheck over every init script, under the busybox-ash contract recorded in
# .shellcheckrc at the top of the repository.
#
# The gate is error severity. These scripts carry warning- and style-level
# findings that predate this harness (cd without || exit in S92usb_gadget, a
# variable in a printf format string in several of them), so those are printed as
# advisory instead of failing a build nobody could get green. Raise --severity
# here once they are fixed. Do not add them to .shellcheckrc: they are real.
#
set -u
. "$(dirname -- "$0")/lib.sh"

SCRIPTS=$(find "$REPO_ROOT/aa_wireless_dongle/board" \
	-path '*/rootfs_overlay/etc/init.d/*' -type f | sort)

if [ -z "$SCRIPTS" ]; then
	fail "shellcheck" "found no init scripts to check"
	summary
	exit
fi

count=$(printf '%s\n' "$SCRIPTS" | wc -l | tr -d ' ')

if ! command -v shellcheck >/dev/null 2>&1; then
	skip "shellcheck: $count init scripts" \
		"shellcheck is not installed (Debian/Ubuntu: apt-get install shellcheck)"
	summary
	exit
fi

if [ ! -f "$REPO_ROOT/.shellcheckrc" ]; then
	fail "shellcheck" ".shellcheckrc is missing, the busybox-ash contract would not be applied"
	summary
	exit
fi

oldifs=$IFS
IFS='
'
for script in $SCRIPTS; do
	IFS=$oldifs
	rel=${script#"$REPO_ROOT"/}
	if errors=$(shellcheck --format=gcc --severity=error "$script" 2>&1) &&
		[ -z "$errors" ]; then
		pass "shellcheck: $rel"
	else
		fail "shellcheck: $rel" "$(printf '%s\n' "$errors" | sed "s#^$REPO_ROOT/##")"
	fi
	shellcheck --format=gcc --severity=warning "$script" 2>/dev/null \
		>>"$WORK/advisory" || true
	IFS='
'
done
IFS=$oldifs

if [ -s "$WORK/advisory" ]; then
	echo "      advisory (not gating), warning severity and above:"
	sed "s#^$REPO_ROOT/##; s/^/          /" "$WORK/advisory"
fi

summary
