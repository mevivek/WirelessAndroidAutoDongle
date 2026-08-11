#!/bin/sh
#
# H5: S39hostapd_conf must never write a wpa_passphrase hostapd will reject.
#
# The templates hardcode wpa=2 / wpa_key_mgmt=WPA-PSK, and hostapd rejects any
# passphrase outside 8..63 characters at config parse time. hostapd is started
# from pre-up in etc/network/interfaces, so a rejected config means busybox
# iface_up() returns early and 10.0.0.1 is never assigned: no SSID, no IP, no
# DHCP, while the daemon still advertises credentials for that network.
#
set -u
. "$(dirname -- "$0")/lib.sh"

# $1 label, $2 template, $3 fixture ("" for no config file at all)
generate() {
	root=$(new_sandbox "h5-$1") || exit 1
	cp "$2" "$root/etc/hostapd.conf.in"
	if [ -n "$3" ]; then
		cp "$FIXTURES/$3" "$root/etc/aawgd.conf"
	fi

	conf=$root/var/run/hostapd.conf
	# A fresh environment: on the device S39 runs as a child of rcS, which has
	# already exported these, but a manual `S39hostapd_conf start` has not.
	env -u AAWG_CONF_SOURCED -u AAWG_WIFI_PASSWORD -u AAWG_COUNTRY_CODE \
		-u AAWG_CONNECTION_STRATEGY \
		"$TEST_SH" "$root/etc/init.d/S39hostapd_conf" start >/dev/null 2>"$root/stderr"
	rc=$?
	err=$(cat "$root/stderr")
	# Only an active setting counts; both templates ship a commented example.
	passphrase=$(sed -n 's/^wpa_passphrase=//p' "$conf")
	passphrase_lines=$(grep -c '^wpa_passphrase=' "$conf" || true)
}

# $1 label, $2 template, $3 fixture, $4 expected passphrase or "" for any
# generated one, $5 configured value that must not survive (may be empty)
check_case() {
	generate "$1" "$2" "$3"

	assert_eq "$1: S39hostapd_conf exits 0" 0 "$rc"
	assert_eq "$1: writes exactly one active wpa_passphrase" 1 "$passphrase_lines"
	assert_between "$1: passphrase length is within WPA2 limits" \
		"$(printf '%s' "$passphrase" | wc -c | tr -d ' ')" 8 63

	if [ -n "$4" ]; then
		assert_eq "$1: keeps the configured passphrase" "$4" "$passphrase"
	fi
	if [ -n "$5" ]; then
		assert_ne "$1: replaces the unusable configured passphrase" "$5" "$passphrase"
	fi
}

for template in \
	"$OVERLAY/etc/hostapd.conf.in" \
	"$REPO_ROOT/aa_wireless_dongle/board/raspberrypi4/rootfs_overlay/etc/hostapd.conf.in"; do
	board=$(basename "$(dirname "$(dirname "$(dirname "$template")")")")

	# A legal passphrase must be written through unchanged.
	check_case "$board-valid" "$template" pw-valid.conf MySecurePass123 ""
	# Too short: hostapd would refuse to start (REVIEW.md H5, "aa1234").
	check_case "$board-short" "$template" pw-short.conf "" aa1234
	# 64 characters, one over the limit.
	check_case "$board-too-long" "$template" pw-too-long.conf "" \
		0123456789012345678901234567890123456789012345678901234567890123
	# "Pa$sword" in an unquoted assignment: the shell expands $sword to nothing
	# and the passphrase silently becomes the 2-character "Pa" (REVIEW.md H5).
	check_case "$board-truncated-by-expansion" "$template" pw-unquoted-expansion.conf "" Pa
	# No passphrase configured: the boot-time random one must be used.
	check_case "$board-unset" "$template" no-password.conf "" ""
	# H1 and H5 together: a config too broken to source must still leave a
	# working access point behind.
	check_case "$board-unparsable-conf" "$template" unbalanced-quote.conf "" ""
done

# Other settings must still be emitted, so the guard has not broken the generator.
generate country "$OVERLAY/etc/hostapd.conf.in" no-password.conf
assert_contains "country: AAWG_COUNTRY_CODE is written" "$(cat "$conf")" "country_code=GB"
assert_contains "country: the template is preserved" "$(cat "$conf")" "ssid=AAWirelessDongle"

# A rejected passphrase must be diagnosable rather than silently swapped out.
generate warns "$OVERLAY/etc/hostapd.conf.in" pw-short.conf
assert_contains "short: warns on stderr" "$err" "WARNING"

summary
