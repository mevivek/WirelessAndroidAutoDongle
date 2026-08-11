#!/bin/sh
#
# H1: a malformed or missing /etc/aawgd.conf must not abort the shell that
# sources rcS_aawgd_conf.
#
# rcS:8 sources rcS_aawgd_conf into its own shell and only then runs
# /etc/init.d/S??*. POSIX makes a non-interactive shell abort when a dot-file
# cannot be parsed, so an unparsable aawgd.conf used to kill rcS before any
# service started. Exit status alone does not show that: what matters is that the
# calling shell is still alive afterwards.
#
set -u
. "$(dirname -- "$0")/lib.sh"

# Stands in for rcS:8, plus a child process to prove allexport really exported.
write_driver() {
	cat >"$1/drive_rcs" <<EOF
#!/bin/sh
unset AAWG_CONF_SOURCED AAWG_COUNTRY_CODE AAWG_CONNECTION_STRATEGY AAWG_WIFI_PASSWORD
. $1/etc/init.d/rcS_aawgd_conf
echo "conf_rc=\$?"
echo "PARENT_STILL_ALIVE"
sh -c 'echo "country=\$AAWG_COUNTRY_CODE"; echo "strategy=\$AAWG_CONNECTION_STRATEGY"; echo "password=\$AAWG_WIFI_PASSWORD"; echo "password_length=\${#AAWG_WIFI_PASSWORD}"'
EOF
	chmod +x "$1/drive_rcs"
}

# $1 label, $2 fixture ("" for no config file at all)
run_case() {
	root=$(new_sandbox "h1-$1") || exit 1
	if [ -n "$2" ]; then
		cp "$FIXTURES/$2" "$root/etc/aawgd.conf"
	fi
	write_driver "$root"
	out=$("$TEST_SH" "$root/drive_rcs" 2>"$root/stderr")
	rc=$?
	err=$(cat "$root/stderr")
}

field() {
	printf '%s\n' "$out" | sed -n "s/^$1=//p"
}

# $1 label, $2 fixture, $3 "warn" or "quiet"
check_case() {
	run_case "$1" "$2"

	assert_eq "$1: driver shell exits 0" 0 "$rc"
	assert_contains "$1: calling shell survives the sourcing" "$out" "PARENT_STILL_ALIVE"
	assert_contains "$1: rcS_aawgd_conf itself returns success" "$out" "conf_rc=0"
	# Whatever the config says, hostapd must still get a usable WPA2 passphrase.
	assert_between "$1: exports a passphrase of legal length" "$(field password_length)" 8 63

	if [ "$3" = warn ]; then
		assert_contains "$1: warns on stderr" "$err" "WARNING"
		# Nothing from a rejected file may leak into the environment.
		assert_eq "$1: rejected config sets no variables" "" "$(field country)"
	else
		assert_not_contains "$1: no spurious warning" "$err" "WARNING"
	fi
}

check_case valid valid.conf quiet
check_case unbalanced-quote unbalanced-quote.conf warn
check_case stray-paren stray-paren.conf warn
check_case missing "" warn
check_case empty empty.conf quiet

# The valid fixture's values must reach the environment of child processes, which
# is what every S??* script and the daemon rely on.
run_case valid-values valid.conf
assert_eq "valid: AAWG_COUNTRY_CODE reaches the environment" "DE" "$(field country)"
assert_eq "valid: AAWG_CONNECTION_STRATEGY reaches the environment" "2" "$(field strategy)"
assert_eq "valid: AAWG_WIFI_PASSWORD reaches the environment" "MySecurePass123" "$(field password)"

# Control. If an unguarded dot-file did not abort the caller on this shell, the
# survival assertions above would pass for the broken code too and prove nothing.
root=$(new_sandbox h1-control) || exit 1
cp "$FIXTURES/unbalanced-quote.conf" "$root/etc/aawgd.conf"
cat >"$root/unguarded" <<EOF
#!/bin/sh
. $root/etc/aawgd.conf
echo "PARENT_STILL_ALIVE"
EOF
out=$("$TEST_SH" "$root/unguarded" 2>/dev/null)
assert_not_contains "control: unguarded sourcing does abort the caller" "$out" "PARENT_STILL_ALIVE"

summary
