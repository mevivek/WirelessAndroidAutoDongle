#!/bin/sh
#
# A generated Wifi password must stay the same for the whole boot.
#
# rcS sources rcS_aawgd_conf once and every S??* inherits AAWG_WIFI_PASSWORD from
# it, but `S93aawgd restart` and `S39hostapd_conf start` are fresh processes with
# AAWG_CONF_SOURCED unset, so they source it again. Minting a new password there
# leaves the daemon advertising a PSK the running hostapd has never heard of, and
# the phone's handshake then fails with nothing in the logs to say why.
#
# /var/run is a tmpfs, so the password is still new on the next boot.
#
set -u
. "$(dirname -- "$0")/lib.sh"

# Stands in for a service that sources the configuration in its own shell.
write_driver() {
	cat >"$1/drive" <<EOF
#!/bin/sh
. $1/etc/init.d/rcS_aawgd_conf
echo "password=\$AAWG_WIFI_PASSWORD"
EOF
	chmod +x "$1/drive"
}

# Prints the password one such shell ends up with.
source_conf() {
	env -u AAWG_CONF_SOURCED -u AAWG_WIFI_PASSWORD -u AAWG_COUNTRY_CODE \
		-u AAWG_CONNECTION_STRATEGY \
		"$TEST_SH" "$1/drive" 2>/dev/null | sed -n 's/^password=//p'
}

setup() {
	root=$(new_sandbox "$1") || exit 1
	cp "$FIXTURES/$2" "$root/etc/aawgd.conf"
	write_driver "$root"
	pwfile=$root/var/run/aawg_wifi_password
}

# No password configured: the one generated at boot must be reused afterwards.
setup persist-generated no-password.conf
first=$(source_conf "$root")
second=$(source_conf "$root")

assert_between "generated password has a usable length" "${#first}" 8 63
assert_eq "a later shell reuses the generated password" "$first" "$second"
assert_eq "the password is persisted verbatim" "$first" "$(cat "$pwfile")"

# It is a live credential and /var/run is shared, so no other account may read it.
assert_eq "the persisted password is not group or world readable" \
	"-rw-------" "$(ls -l "$pwfile" | cut -c1-10)"

# Reboot: /var/run is a tmpfs, so the file is gone and the password is new.
rm -f "$pwfile"
third=$(source_conf "$root")
assert_between "the next boot's password has a usable length" "${#third}" 8 63
assert_ne "the next boot mints a different password" "$first" "$third"

# A configured password still wins over anything left in /var/run.
setup configured-wins pw-valid.conf
printf 'StaleFromAnEarlierBoot\n' >"$pwfile"
assert_eq "a configured password wins over the persisted one" \
	"MySecurePass123" "$(source_conf "$root")"

# A configured password hostapd would reject is replaced, and the replacement has
# to be as stable as any other generated one.
setup rejected-is-stable pw-short.conf
rejected_first=$(source_conf "$root")
rejected_second=$(source_conf "$root")
assert_ne "the unusable configured password is not used" "aa1234" "$rejected_first"
assert_between "its replacement has a usable length" "${#rejected_first}" 8 63
assert_eq "its replacement is reused by a later shell" "$rejected_first" "$rejected_second"

summary
