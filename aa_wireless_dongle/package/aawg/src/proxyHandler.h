#pragma once

#include <pthread.h>
#include <atomic>
#include <mutex>
#include <optional>
#include <thread>

class AAWProxy {
public:
    ~AAWProxy();

    std::optional<std::thread> startServer(int32_t port);

private:
    enum class ProxyDirection {
        TCP_to_USB,
        USB_to_TCP
    };

    void handleClient(int server_fd);
    void forward(ProxyDirection direction, std::atomic<bool>& should_exit);
    void stopForwarding(std::atomic<bool>& should_exit);

    ssize_t readFully(int fd, unsigned char *buf, size_t nbyte);
    ssize_t readMessage(int fd, unsigned char *buf, size_t nbyte);

    int m_usb_fd = -1;
    int m_tcp_fd = -1;

    std::optional<std::thread> m_usb_tcp_thread = std::nullopt;
    std::optional<std::thread> m_tcp_usb_thread = std::nullopt;

    // Each forwarding thread publishes its own handle here while it is running, so that
    // the peer can be signalled without touching a thread that is being joined.
    std::mutex m_forward_threads_mutex;
    pthread_t m_usb_tcp_pthread = 0;
    pthread_t m_tcp_usb_pthread = 0;

    std::atomic<bool> m_log_communication = false;
};
