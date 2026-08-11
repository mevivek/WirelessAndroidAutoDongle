#pragma once

#include <string>
#include <chrono>

class UsbManager {
public:
    static UsbManager& instance();

    void init();
    bool enableDefaultAndWaitForAccessory(std::chrono::milliseconds timeout = std::chrono::milliseconds(0));
    void switchToAccessoryGadget();
    void disableGadget();

private:
    UsbManager();
    UsbManager(UsbManager const&);
    UsbManager& operator=(UsbManager const&);

    int writeGadgetFile(std::string gadgetName, std::string relativeFilePath, const char* content);
    bool enableGadget(std::string name);
    bool disableGadget(std::string name);

    static std::string s_udcName; 
};