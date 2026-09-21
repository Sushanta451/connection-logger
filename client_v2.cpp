#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <chrono>
#include <iostream>
#include <thread>

bool sendAll(int sock, const char* data, std::size_t length)
{
    std::size_t sent{ 0 };
    while (sent < length)
    {
        ssize_t n{ send(sock, data + sent, length - sent, 0) };
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

    int yes{ 1 };
    setsockopt(sock, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));

    sockaddr_in server{};
    server.sin_family = AF_INET;
    server.sin_port = htons(8080);
    inet_pton(AF_INET, "127.0.0.1", &server.sin_addr);

    if (connect(sock, reinterpret_cast<sockaddr*>(&server), sizeof(server)) == -1)
    {
        std::cerr << "connect failed: " << std::strerror(errno) << '\n';
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