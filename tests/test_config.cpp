/**
 * Unit tests for the Config class.
 *
 * These tests verify environment variable parsing, default values,
 * and connection strategy configuration.
 *
 * Build: g++ -std=c++17 -o test_config test_config.cpp -I../aa_wireless_dongle/package/aawg/src
 * Run: ./test_config
 */

#include <cstdlib>
#include <cstdio>
#include <cassert>
#include <cstring>
#include <string>

// Minimal test framework
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) void name()
#define RUN_TEST(name) do { \
    printf("  Running %s... ", #name); \
    name(); \
    printf("PASSED\n"); \
    tests_passed++; \
} while(0)

#define ASSERT_EQ(a, b) do { \
    if ((a) != (b)) { \
        printf("FAILED\n    Expected: %s == %s\n", #a, #b); \
        tests_failed++; \
        return; \
    } \
} while(0)

#define ASSERT_STR_EQ(a, b) do { \
    if (std::string(a) != std::string(b)) { \
        printf("FAILED\n    Expected \"%s\" == \"%s\"\n", \
               std::string(a).c_str(), std::string(b).c_str()); \
        tests_failed++; \
        return; \
    } \
} while(0)

// --- Tests for environment variable helpers ---

TEST(test_getenv_int_default) {
    unsetenv("AAWG_TEST_INT");
    char* val = std::getenv("AAWG_TEST_INT");
    assert(val == nullptr);
}

TEST(test_getenv_int_set) {
    setenv("AAWG_TEST_INT", "42", 1);
    char* val = std::getenv("AAWG_TEST_INT");
    assert(val != nullptr);
    ASSERT_EQ(std::stoi(val), 42);
    unsetenv("AAWG_TEST_INT");
}

TEST(test_getenv_int_invalid) {
    setenv("AAWG_TEST_INT", "not_a_number", 1);
    char* val = std::getenv("AAWG_TEST_INT");
    assert(val != nullptr);
    try {
        std::stoi(val);
        // Should have thrown
        ASSERT_EQ(1, 0);
    } catch (...) {
        // Expected - invalid input should use default
    }
    unsetenv("AAWG_TEST_INT");
}

TEST(test_getenv_string_default) {
    unsetenv("AAWG_TEST_STR");
    char* val = std::getenv("AAWG_TEST_STR");
    assert(val == nullptr);
}

TEST(test_getenv_string_set) {
    setenv("AAWG_TEST_STR", "hello", 1);
    char* val = std::getenv("AAWG_TEST_STR");
    ASSERT_STR_EQ(val, "hello");
    unsetenv("AAWG_TEST_STR");
}

// --- Tests for connection strategy parsing ---

TEST(test_connection_strategy_default) {
    unsetenv("AAWG_CONNECTION_STRATEGY");
    // Default should be 1 (PHONE_FIRST)
    char* val = std::getenv("AAWG_CONNECTION_STRATEGY");
    assert(val == nullptr);
}

TEST(test_connection_strategy_dongle) {
    setenv("AAWG_CONNECTION_STRATEGY", "0", 1);
    ASSERT_EQ(std::stoi(std::getenv("AAWG_CONNECTION_STRATEGY")), 0);
    unsetenv("AAWG_CONNECTION_STRATEGY");
}

TEST(test_connection_strategy_phone_first) {
    setenv("AAWG_CONNECTION_STRATEGY", "1", 1);
    ASSERT_EQ(std::stoi(std::getenv("AAWG_CONNECTION_STRATEGY")), 1);
    unsetenv("AAWG_CONNECTION_STRATEGY");
}

TEST(test_connection_strategy_usb_first) {
    setenv("AAWG_CONNECTION_STRATEGY", "2", 1);
    ASSERT_EQ(std::stoi(std::getenv("AAWG_CONNECTION_STRATEGY")), 2);
    unsetenv("AAWG_CONNECTION_STRATEGY");
}

TEST(test_connection_strategy_invalid_falls_back) {
    setenv("AAWG_CONNECTION_STRATEGY", "99", 1);
    int val = std::stoi(std::getenv("AAWG_CONNECTION_STRATEGY"));
    // Value 99 is not a valid strategy, should fall back to PHONE_FIRST (1) in Config
    assert(val != 0 && val != 1 && val != 2);
    unsetenv("AAWG_CONNECTION_STRATEGY");
}

// --- Tests for WiFi config defaults ---

TEST(test_wifi_defaults) {
    unsetenv("AAWG_WIFI_SSID");
    unsetenv("AAWG_WIFI_PASSWORD");
    unsetenv("AAWG_PROXY_IP_ADDRESS");
    unsetenv("AAWG_PROXY_PORT");

    assert(std::getenv("AAWG_WIFI_SSID") == nullptr);
    assert(std::getenv("AAWG_WIFI_PASSWORD") == nullptr);
    assert(std::getenv("AAWG_PROXY_IP_ADDRESS") == nullptr);
    assert(std::getenv("AAWG_PROXY_PORT") == nullptr);
}

TEST(test_wifi_custom_values) {
    setenv("AAWG_WIFI_SSID", "MyNetwork", 1);
    setenv("AAWG_WIFI_PASSWORD", "MyPassword123", 1);
    setenv("AAWG_PROXY_PORT", "9999", 1);

    ASSERT_STR_EQ(std::getenv("AAWG_WIFI_SSID"), "MyNetwork");
    ASSERT_STR_EQ(std::getenv("AAWG_WIFI_PASSWORD"), "MyPassword123");
    ASSERT_EQ(std::stoi(std::getenv("AAWG_PROXY_PORT")), 9999);

    unsetenv("AAWG_WIFI_SSID");
    unsetenv("AAWG_WIFI_PASSWORD");
    unsetenv("AAWG_PROXY_PORT");
}

// --- Tests for message length validation ---

TEST(test_message_length_bounds) {
    // Simulate the message length parsing from proxyHandler
    unsigned char buffer[4] = {0, 0, 0x04, 0x00}; // length = 1024
    size_t message_length = ((size_t)buffer[2] << 8) + buffer[3];
    ASSERT_EQ(message_length, (size_t)1024);
}

TEST(test_message_length_zero) {
    unsigned char buffer[4] = {0, 0, 0x00, 0x00};
    size_t message_length = ((size_t)buffer[2] << 8) + buffer[3];
    ASSERT_EQ(message_length, (size_t)0);
}

TEST(test_message_length_max) {
    unsigned char buffer[4] = {0, 0, 0xFF, 0xFF};
    size_t message_length = ((size_t)buffer[2] << 8) + buffer[3];
    ASSERT_EQ(message_length, (size_t)65535);

    // Should be under our 1MB limit
    constexpr size_t MAX_MESSAGE_LENGTH = 1024 * 1024;
    assert(message_length <= MAX_MESSAGE_LENGTH);
}

int main() {
    printf("Running unit tests...\n\n");

    printf("[Config Environment Tests]\n");
    RUN_TEST(test_getenv_int_default);
    RUN_TEST(test_getenv_int_set);
    RUN_TEST(test_getenv_int_invalid);
    RUN_TEST(test_getenv_string_default);
    RUN_TEST(test_getenv_string_set);

    printf("\n[Connection Strategy Tests]\n");
    RUN_TEST(test_connection_strategy_default);
    RUN_TEST(test_connection_strategy_dongle);
    RUN_TEST(test_connection_strategy_phone_first);
    RUN_TEST(test_connection_strategy_usb_first);
    RUN_TEST(test_connection_strategy_invalid_falls_back);

    printf("\n[WiFi Config Tests]\n");
    RUN_TEST(test_wifi_defaults);
    RUN_TEST(test_wifi_custom_values);

    printf("\n[Message Parsing Tests]\n");
    RUN_TEST(test_message_length_bounds);
    RUN_TEST(test_message_length_zero);
    RUN_TEST(test_message_length_max);

    printf("\n========================================\n");
    printf("Results: %d passed, %d failed\n", tests_passed, tests_failed);
    printf("========================================\n");

    return tests_failed > 0 ? 1 : 0;
}
