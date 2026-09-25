#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <chrono>
#include <iostream>
#include <thread>

#ifdef MSG_NOSIGNAL
constexpr int send_flags{ MSG_NOSIGNAL };  // Linux: suppress SIGPIPE per send
#else
constexpr int send_flags{ 0 };             // macOS/BSD: SO_NOSIGPIPE did it
#endif

bool sendAll(int sock, const char* data, std::size_t length)
{
    std::size_t sent{ 0 };
    while (sent < length)
    {
        ssize_t n{ send(sock, data + sent, length - sent, send_flags) };
        if (n == -1)
        {
            if (errno == EINTR) continue;
            return false;
        }
        sent += static_cast<std::size_t>(n);
    }
    return true;
}

int main(int argc, char* argv[])
{
    bool slow{ argc > 1 && std::strcmp(argv[1], "slow") == 0 };

    int sock{ socket(AF_INET, SOCK_STREAM, 0) };
    if (sock == -1) { std::cerr << "socket failed\n"; return 1; }

    // Don't let a write to a closed peer kill the process with SIGPIPE.
    // macOS/BSD do this with a socket option; Linux has no such option and
    // uses the MSG_NOSIGNAL flag on each send instead (see SEND_FLAGS below).
#ifdef SO_NOSIGPIPE
    int yes{ 1 };
    if (setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes)) == -1)
    {
        std::cerr << "setsockopt failed: " << std::strerror(errno) << '\n';
        close(sock);
        return 1;
    }
#endif

    sockaddr_in server{};
    server.sin_family = AF_INET;
    server.sin_port = htons(8080);
    if (inet_pton(AF_INET, "127.0.0.1", &server.sin_addr) != 1)
    {
        std::cerr << "invalid address\n";
        close(sock);
        return 1;
    }

    if (connect(sock, reinterpret_cast<sockaddr*>(&server), sizeof(server)) == -1)
    {
        std::cerr << "connect failed: " << std::strerror(errno) << '\n';
        close(sock);
        return 1;
    }

    const char* parts[]{ "Hello", ", ", "world!" };

    for (const char* part : parts)
    {
        if (!sendAll(sock, part, std::strlen(part)))
        {
            std::cerr << "send failed\n";
            break;
        }
        std::cout << "sent: [" << part << "]\n";

        if (slow)
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }

    close(sock);
    return 0;
}