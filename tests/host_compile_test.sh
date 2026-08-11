#!/bin/sh
#
# Host syntax check for the daemon translation units that have no external
# dependencies, so the warnings that -Wall -Wextra now catches cannot come back
# unnoticed without a cross toolchain.
#
# Only these two are listed: common.cpp needs the generated protobuf headers, and
# the bluetooth* units plus proxyHandler.cpp reach dbus-cxx.h through
# bluetoothCommon.h. Add a file here as soon as it builds without those.
#
set -u
. "$(dirname -- "$0")/lib.sh"

SRC=$REPO_ROOT/aa_wireless_dongle/package/aawg/src
CXX=${CXX:-g++}

if ! command -v "$CXX" >/dev/null 2>&1; then
	skip "host compile" "$CXX is not installed"
	summary
	exit
fi

for unit in usb.cpp uevent.cpp; do
	out=$("$CXX" -std=gnu++17 -Wall -Wextra -fsyntax-only "$SRC/$unit" 2>&1)
	rc=$?
	if [ "$rc" -ne 0 ]; then
		fail "$unit: parses" "$out"
	elif [ -n "$out" ]; then
		# -Wall -Wextra do not affect the exit status, so diagnostics are
		# only visible here. Fix the warning; do not silence it.
		fail "$unit: no -Wall -Wextra warnings" "$out"
	else
		pass "$unit: compiles clean with -Wall -Wextra"
	fi
done

summary
