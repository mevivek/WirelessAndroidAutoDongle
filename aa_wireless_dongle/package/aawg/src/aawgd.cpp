#include <stdio.h>
#include <unistd.h>

#include "common.h"
#include "bluetoothHandler.h"
#include "proxyHandler.h"
#include "uevent.h"
#include "usb.h"

int main(void) {
    Logger::instance()->info("AA Wireless Dongle\n");

    // The monitor loop sits in an uninterruptible read() on a netlink socket, so this thread
    // can neither be joined nor asked to stop. It is kept joinable and alive for the lifetime
    // of the process instead: every exit below goes through _exit(), which runs neither
    // ~thread() - std::terminate on a joinable thread - nor the static destructors that the
    // monitor thread is still using.
    std::optional<std::thread> ueventThread = UeventMonitor::instance().start();

    ConnectionStrategy connectionStrategy = Config::instance()->getConnectionStrategy();

    try {
        // Global init
        UsbManager::instance().init();
        BluetoothHandler::instance().init();

        if (connectionStrategy == ConnectionStrategy::DONGLE_MODE) {
            BluetoothHandler::instance().powerOn();
        }
    }
    catch (DBus::Error& e) {
        Logger::instance()->info("Dbus error during startup, exiting: %s: %s\n", e.name().c_str(), e.message().c_str());
        _exit(1);
    }
    catch (std::exception& e) {
        Logger::instance()->info("Unhandled exception during startup, exiting: %s\n", e.what());
        _exit(1);
    }

    while (true) {
        Logger::instance()->info("Connection Strategy: %d\n", connectionStrategy);

        // Per connection setup and processing
        if (connectionStrategy == ConnectionStrategy::USB_FIRST) {
            Logger::instance()->info("Waiting for the accessory to connect first\n");
            UsbManager::instance().enableDefaultAndWaitForAccessory();
        }

        // Arm the retry state before the server can accept a connection, so that a stop
        // request coming from the proxy thread cannot be lost.
        BluetoothHandler::instance().prepareConnectWithRetry();

        AAWProxy proxy;
        std::optional<std::thread> proxyThread = proxy.startServer(Config::instance()->getWifiInfo().port);

        if (!proxyThread) {
            Logger::instance()->info("Could not start the tcp server, giving up\n");
            _exit(1);
        }

        if (connectionStrategy != ConnectionStrategy::DONGLE_MODE) {
            // proxyThread is already sitting in accept() and nothing can cancel it, so this has
            // to be handled right here: letting the error unwind out of the loop would destroy a
            // joinable thread and call std::terminate before any outer handler could run.
            try {
                BluetoothHandler::instance().powerOn();
            }
            catch (DBus::Error& e) {
                Logger::instance()->info("Failed to power on the bluetooth adapter, exiting: %s: %s\n", e.name().c_str(), e.message().c_str());
                _exit(1);
            }
        }

        std::optional<std::thread> btConnectionThread = BluetoothHandler::instance().connectWithRetry();

        proxyThread->join();

        if (btConnectionThread) {
            BluetoothHandler::instance().stopConnectWithRetry();
            btConnectionThread->join();
        }

        UsbManager::instance().disableGadget();

        if (connectionStrategy != ConnectionStrategy::DONGLE_MODE) {
            // sleep for a couple of seconds before retrying
            sleep(2);
        }
    }

    return 0;
}
