#pragma once

#include <condition_variable>
#include <map>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

#include "bluetoothCommon.h"

class BluezAdapterProxy;
class AAWirelessProfile;
class HSPHSProfile;
class BLEAdvertisement;

class BluetoothHandler {
public:
    static BluetoothHandler& instance();

    void init();
    void powerOn();
    void powerOff();

    // Must be called before the tcp server can accept a connection, so that a stop
    // request arriving before connectWithRetry() is not lost.
    void prepareConnectWithRetry();
    std::optional<std::thread> connectWithRetry();
    void stopConnectWithRetry();

    // Answers from state that connectDevice() observed earlier, without issuing any dbus
    // call, so that it is safe to call from the dbus dispatcher thread.
    bool isDevicePaired(const DBus::Path& path);

private:
    BluetoothHandler() {};
    BluetoothHandler(BluetoothHandler const&);
    BluetoothHandler& operator=(BluetoothHandler const&);

    DBus::ManagedObjects getBluezObjects();

    void initAdapter();
    void setPower(bool on);
    void setPairable(bool pairable);
    void exportProfiles();
    void connectDevice();

    void startAdvertising();
    void stopAdvertising();

    void retryConnectLoop();

    std::mutex m_connectRetryMutex;
    std::condition_variable m_connectRetryCv;
    bool m_stopRequested = false;

    // Written by connectDevice() on the retry thread, read by isDevicePaired() on the dbus
    // dispatcher thread. Guarded by its own mutex, which is never held across a dbus call.
    std::mutex m_pairedStateMutex;
    std::map<std::string, bool> m_pairedState;

    std::shared_ptr<DBus::Dispatcher> m_dispatcher;
    std::shared_ptr<DBus::Connection> m_connection;
    std::shared_ptr<BluezAdapterProxy> m_adapter;

    std::shared_ptr<AAWirelessProfile> m_aawProfile;
    std::shared_ptr<HSPHSProfile> m_hspProfile;

    std::shared_ptr<BLEAdvertisement> m_leAdvertisement;

    std::string m_adapterAlias;
};
