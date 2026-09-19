#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <string_view>

int main()
{
    
    int listener{ socket(AF_INET, SOCK_STREAM, 0) };
    if (listener == -1) { std::cerr << "socket failed\n"; return 1; }

    int yes{ 1 };
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8080);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(listener, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == -1)
    {
        std::cerr << "bind failed: " << std::strerror(errno) << '\n';
        return 1;
    }
    if (listen(listener, SOMAXCONN) == -1) { std::cerr << "listen failed\n"; return 1; }

    std::cout << "Listening on 8080...\n";

    int conn{ accept(listener, nullptr, nullptr) };
    if (conn == -1) { std::cerr << "accept failed\n"; return 1; }

    std::cout << "Client connected.\n\n";

    // --- New: the receive loop ---
    char buffer[1024];
    int chunk{ 0 };

    while (true)
    {
        ssize_t n{ recv(conn, buffer, sizeof(buffer), 0) };

        if (n == 0)
        {
            std::cout << "\nClient closed the connection.\n";
            break;
        }

        if (n == -1)
        {
            if (errno == EINTR) continue;
            std::cerr << "recv failed: " << std::strerror(errno) << '\n';
            break;
        }

        ++chunk;
        std::cout << "chunk " << chunk << ": " << n << " bytes  ["
                  << std::string_view(buffer, static_cast<std::size_t>(n))
                  << "]\n";
    }

    close(conn);
    close(listener);
    return 0;
}