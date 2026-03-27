#!/bin/sh
#
# Integration tests for init scripts
# Tests configuration generation and validation logic
#

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

pass() {
    PASS=$((PASS + 1))
    printf "  PASS: %s\n" "$1"
}

fail() {
    FAIL=$((FAIL + 1))
    printf "  FAIL: %s\n" "$1"
}

assert_contains() {
    if echo "$1" | grep -q "$2"; then
        pass "$3"
    else
        fail "$3 (expected to contain '$2')"
    fi
}

assert_not_contains() {
    if echo "$1" | grep -q "$2"; then
        fail "$3 (should not contain '$2')"
    else
        pass "$3"
    fi
}

echo "=== Init Script Tests ==="

# Test 1: Shell scripts use POSIX-compatible syntax
echo ""
echo "[POSIX Compliance]"

for script in "$ROOT_DIR"/aa_wireless_dongle/board/common/rootfs_overlay/etc/init.d/*; do
    name=$(basename "$script")
    if grep -n 'source ' "$script" > /dev/null 2>&1; then
        fail "$name uses 'source' instead of '.'"
    else
        pass "$name uses POSIX-compatible sourcing"
    fi
done

# Test 2: hostapd.conf.in has expected structure
echo ""
echo "[hostapd.conf.in Validation]"

HOSTAPD_CONF="$ROOT_DIR/aa_wireless_dongle/board/common/rootfs_overlay/etc/hostapd.conf.in"
if [ -f "$HOSTAPD_CONF" ]; then
    CONTENT=$(cat "$HOSTAPD_CONF")
    assert_contains "$CONTENT" "ctrl_interface=" "Has ctrl_interface"
    assert_contains "$CONTENT" "interface=wlan0" "Has wlan0 interface"
    assert_contains "$CONTENT" "wpa=2" "Has WPA2 enabled"
    assert_contains "$CONTENT" "wpa_key_mgmt=WPA-PSK" "Has WPA-PSK key management"
    assert_contains "$CONTENT" "rsn_pairwise=CCMP" "Has CCMP cipher"
    assert_contains "$CONTENT" "ssid=" "Has SSID setting"
    assert_contains "$CONTENT" "#wpa_passphrase" "Default password is commented out"
else
    fail "hostapd.conf.in not found"
fi

# Test 3: dnsmasq.conf has expected settings
echo ""
echo "[dnsmasq.conf Validation]"

DNSMASQ_CONF="$ROOT_DIR/aa_wireless_dongle/board/common/rootfs_overlay/etc/dnsmasq.conf"
if [ -f "$DNSMASQ_CONF" ]; then
    CONTENT=$(cat "$DNSMASQ_CONF")
    assert_contains "$CONTENT" "interface=wlan0" "Has wlan0 interface"
    assert_contains "$CONTENT" "dhcp-range=" "Has DHCP range"
    assert_contains "$CONTENT" "dhcp-authoritative" "Is authoritative"
else
    fail "dnsmasq.conf not found"
fi

# Test 4: bluetooth main.conf settings
echo ""
echo "[Bluetooth Configuration]"

BT_CONF="$ROOT_DIR/aa_wireless_dongle/board/common/rootfs_overlay/etc/bluetooth/main.conf"
if [ -f "$BT_CONF" ]; then
    CONTENT=$(cat "$BT_CONF")
    assert_contains "$CONTENT" "JustWorksRepairing" "Has JustWorksRepairing"
    assert_contains "$CONTENT" "DeviceID" "Has DeviceID setting"
else
    fail "bluetooth main.conf not found"
fi

# Test 5: S92usb_gadget uses device serial
echo ""
echo "[USB Gadget Script]"

USB_SCRIPT="$ROOT_DIR/aa_wireless_dongle/board/common/rootfs_overlay/etc/init.d/S92usb_gadget"
if [ -f "$USB_SCRIPT" ]; then
    CONTENT=$(cat "$USB_SCRIPT")
    assert_contains "$CONTENT" "serial-number" "Uses device serial number"
    assert_contains "$CONTENT" "mountpoint" "Checks if configfs mounted"
    assert_contains "$CONTENT" "firmware/devicetree" "Reads device serial dynamically"
else
    fail "S92usb_gadget not found"
fi

echo ""
echo "========================================"
printf "Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "========================================"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
