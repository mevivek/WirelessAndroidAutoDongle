#!/bin/sh
#
# Run every test in this directory:
#
#     tests/run.sh
#
# Needs nothing but a POSIX shell, coreutils and g++. shellcheck is used when it
# is installed and skipped when it is not.
#
# The init scripts run under busybox ash on the device; the tests drive them with
# dash, the closest POSIX shell available on a build host. Set TEST_SH to override
# that shell. It must be a single executable, so on a device use TEST_SH=/bin/ash.
#
set -u

unset CDPATH
TESTS_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

total=0
failed=0

for suite in \
	h1_conf_sourcing_test.sh \
	h5_hostapd_passphrase_test.sh \
	wifi_password_persistence_test.sh \
	host_compile_test.sh \
	shellcheck_test.sh; do
	echo "== $suite"
	total=$((total + 1))
	if ! /bin/sh "$TESTS_DIR/$suite"; then
		failed=$((failed + 1))
	fi
	echo
done

if [ "$failed" -ne 0 ]; then
	echo "FAILED: $failed of $total suites"
	exit 1
fi

echo "OK: $total suites passed"
