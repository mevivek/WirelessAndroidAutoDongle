#include <dirent.h>
#include <errno.h>
#include <string.h>
#include <atomic>
#include <future>

#include "common.h"
#include "uevent.h"
#include "usb.h"

constexpr const char* defaultGadgetName = "default";
constexpr const char* accessoryGadgetName = "accessory";

/*static*/ std::string UsbManager::s_udcName;

UsbManager& UsbManager::instance() {
    static UsbManager instance;
    return instance;
}

void UsbManager::init() {
    // Init does not actually do anything but provides an intuitive place to cause the constructor call earlier than first use.
}

UsbManager::UsbManager() {
    Logger::instance()->info("Initializing USB Manager\n");

    disableGadget();

    DIR* dirSysClassUdc = opendir("/sys/class/udc/");
    if (dirSysClassUdc == NULL) {
        Logger::instance()->info("USB Manager: Error opening /sys/class/udc/: %s\n", strerror(errno));
        return;
    }
    
    struct dirent* dirEntry = NULL;
    while ((dirEntry = readdir(dirSysClassUdc)) != NULL) {
        if (dirEntry->d_name[0] == '.') {
            continue;
        }

        s_udcName = dirEntry->d_name;
    }

    closedir(dirSysClassUdc);

    if (s_udcName.empty()) {
        Logger::instance()->info("USB Manager: Did not find a valid UDC to use\n");
    } else {
        Logger::instance()->info("USB Manager: Found UDC %s\n", s_udcName.c_str());
    }
}

int UsbManager::writeGadgetFile(std::string gadgetName, std::string relativeFilePath, const char* content) {
    std::string gadgetFilePath = "/sys/kernel/config/usb_gadget/" + gadgetName + "/" + relativeFilePath;
    FILE* gadgetFile = fopen(gadgetFilePath.c_str(), "w");
    if (gadgetFile == NULL) {
        int error = errno;
        Logger::instance()->info("USB Manager: Error opening %s: %s\n", gadgetFilePath.c_str(), strerror(error));
        return error ? error : EIO;
    }

    int error = 0;
    if (fputs(content, gadgetFile) == EOF || fputc('\n', gadgetFile) == EOF) {
        error = errno ? errno : EIO;
    }
    if (fclose(gadgetFile) != 0 && error == 0) {
        error = errno ? errno : EIO;
    }

    return error;
}

bool UsbManager::enableGadget(std::string gadgetName) {
    if (s_udcName.empty()) {
        Logger::instance()->info("USB Manager: Cannot bind gadget %s, no UDC was found\n", gadgetName.c_str());
        return false;
    }

    int error = writeGadgetFile(gadgetName, "UDC", s_udcName.c_str());
    if (error != 0) {
        Logger::instance()->info("USB Manager: Error binding gadget %s to UDC %s: %s\n", gadgetName.c_str(), s_udcName.c_str(), strerror(error));
        return false;
    }

    return true;
}

bool UsbManager::disableGadget(std::string gadgetName) {
    int error = writeGadgetFile(gadgetName, "UDC", "");
    // The kernel reports a gadget that is not bound to any UDC as ENODEV, which is not a failure here.
    if (error != 0 && error != ENODEV) {
        Logger::instance()->info("USB Manager: Error unbinding gadget %s from UDC: %s\n", gadgetName.c_str(), strerror(error));
        return false;
    }

    return true;
}

void UsbManager::switchToAccessoryGadget() {
    disableGadget(defaultGadgetName);
    std::this_thread::sleep_for(std::chrono::milliseconds(100)); // 0.1 second, keep the gadget disabled for a short time to let the host recognize the change
    if (enableGadget(accessoryGadgetName)) {
        Logger::instance()->info("USB Manager: Switched to accessory gadget from default\n");
    }
}

void UsbManager::disableGadget() {
    disableGadget(defaultGadgetName);
    disableGadget(accessoryGadgetName);

    Logger::instance()->info("USB Manager: Disabled all USB gadgets\n");
}

bool UsbManager::enableDefaultAndWaitForAccessory(std::chrono::milliseconds timeout) {
    std::shared_ptr<std::promise<void>> accessoryPromise = std::make_shared<std::promise<void>>();
    std::weak_ptr<std::promise<void>> accessoryPromiseWeak = accessoryPromise;
    std::shared_ptr<std::atomic<bool>> accessoryWanted = std::make_shared<std::atomic<bool>>(true);
    std::future<void> accessoryFuture = accessoryPromise->get_future();

    UeventMonitor::instance().addHandler([accessoryPromiseWeak, accessoryWanted](UeventEnv env) {
        std::shared_ptr<std::promise<void>> accessoryPromise = accessoryPromiseWeak.lock();

        // If the promise is no longer active, nothing to do.
        if (!accessoryPromise) {
            return true;
        }

        if (auto it = env.find("DEVNAME"); it == env.end() || it->second != "usb_accessory") {
            return false;
        }

        if (auto it = env.find("ACCESSORY"); it == env.end() || it->second != "START") {
            return false;
        }

        // The request may have been abandoned while this event was in flight.
        if (!accessoryWanted->exchange(false)) {
            return true;
        }

        // Got an accessory start event
        Logger::instance()->info("USB Manager: Received accessory start request\n");
        UsbManager::instance().switchToAccessoryGadget();
        accessoryPromise->set_value();

        return true;
    });

    if (!enableGadget(defaultGadgetName)) {
        accessoryWanted->store(false);
        return false;
    }

    Logger::instance()->info("USB Manager: Enabled default gadget\n");

    if (timeout == std::chrono::milliseconds(0)) {
        accessoryFuture.wait();
        return true;
    } else {
        std::future_status status = accessoryFuture.wait_for(timeout);

        if (status == std::future_status::ready) {
            return true;
        } else if (!accessoryWanted->exchange(false)) {
            // The handler claimed the request just as the wait timed out, let it finish.
            accessoryFuture.wait();
            return true;
        } else {
            Logger::instance()->info("USB Manager: Timeout waiting for accessory start request\n");
            return false;
        }
    }
}
