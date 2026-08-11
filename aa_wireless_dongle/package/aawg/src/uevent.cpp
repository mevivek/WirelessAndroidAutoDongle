#include <unistd.h>
#include <string.h>
#include <sys/socket.h>
#include <linux/netlink.h>

#include "common.h"
#include "uevent.h"

constexpr ssize_t NETLINK_MSG_SIZE = 8 * 1024;

UeventMonitor& UeventMonitor::instance() {
    static UeventMonitor instance;
    return instance;
}

void UeventMonitor::monitorLoop(int nl_socket) {
    char msg[NETLINK_MSG_SIZE + 1];

    while (true) {
        struct sockaddr_nl peerAddress = {};
        struct iovec iov = {
            .iov_base = msg,
            .iov_len = (size_t)NETLINK_MSG_SIZE,
        };
        struct msghdr header = {};
        header.msg_name = &peerAddress;
        header.msg_namelen = sizeof(peerAddress);
        header.msg_iov = &iov;
        header.msg_iovlen = 1;

        ssize_t len = recvmsg(nl_socket, &header, 0);

        if (len < 0) {
            Logger::instance()->info("Read from netlink socket failed: %s\n", strerror(errno));
            continue;
        }
        else if (len == 0) {
            continue;
        }

        // Only the kernel may send us uevents, anything else is spoofed.
        if (header.msg_namelen != sizeof(peerAddress) || peerAddress.nl_pid != 0) {
            Logger::instance()->info("Ignoring netlink message from pid %u\n", peerAddress.nl_pid);
            continue;
        }

        char* end = msg + len;
        *end = '\0';

        // printf("length: %ld msg: %s\n", len, msg);

        // Parse the env from message
        UeventEnv envMap;
        char* current = msg;
        while (current < end) {
            if (char* split = strchr(current, '='); split != NULL && split > current) {
                std::string envName(current, split - current);
                std::string envValue(split + 1);

                envMap.emplace(envName, envValue);
                // printf("%s = %s\n", envName.c_str(), envValue.c_str());
            }

            current += strlen(current) + 1;
        }

        // Call the handlers. They are taken out of the list first so that they can be invoked
        // without holding the lock, since a handler may call back into code that adds handlers.
        std::list<std::function<bool(UeventEnv)>> pending;
        {
            std::lock_guard<std::mutex> lock(handlersMutex);
            pending.swap(handlers);
        }

        for (auto it = pending.begin(); it != pending.end();) {
            if ((*it)(envMap)) {
                it = pending.erase(it);
            } else {
                ++it;
            }
        }

        {
            std::lock_guard<std::mutex> lock(handlersMutex);
            handlers.splice(handlers.begin(), pending);
        }
    }
}

void UeventMonitor::addHandler(std::function<bool(UeventEnv)> handler) {
    std::lock_guard<std::mutex> lock(handlersMutex);
    handlers.push_back(handler);
}

std::optional<std::thread> UeventMonitor::start() {
    Logger::instance()->info("Starting uevent monitoring\n");

    int nl_sock;
    if ((nl_sock = socket(AF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC, NETLINK_KOBJECT_UEVENT)) < 0) {
        Logger::instance()->info("creating socket failed for netlink socket: %s\n", strerror(errno));
        return std::nullopt;
    }

    struct sockaddr_nl address = {
        .nl_family = AF_NETLINK,
        .nl_pad = 0,
        .nl_pid = (unsigned int)getpid(),
        .nl_groups = -1u
    };

    if (bind(nl_sock, (struct sockaddr*)&address, sizeof(address)) < 0) {
        Logger::instance()->info("bind failed for netlink socket: %s\n", strerror(errno));
        close(nl_sock);
        return std::nullopt;
    }

    int opt = 1;
    if (setsockopt(nl_sock, SOL_SOCKET, SO_PASSCRED, &opt, sizeof(opt))) {
        Logger::instance()->info("setsockopt failed to set SO_PASSCRED for netlink socket: %s\n", strerror(errno));
        close(nl_sock);
        return std::nullopt;
    }

    Logger::instance()->info("Uevent monitoring started\n");

    return std::thread(&UeventMonitor::monitorLoop, this, nl_sock);
}
