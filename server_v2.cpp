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
    
    int listener{socket(AF_INET,SOCK_STREAM,0)};
    
    if(listener == -1){
        std::cerr<< "socket failed" << std::endl;
        return 1;
    }

    int yes{1};
    if (setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) == -1) {
        std::cerr << "setsockopt failed: " << std::strerror(errno) << '\n';
        return 1;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8080);      // host byte order -> network byte order
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if(bind(listener,reinterpret_cast<sockaddr*>(&addr),sizeof(addr)) == -1){
        std::cerr << "Bind failed" << std::strerror(errno) << std::endl;
        return 1;
    }

    if(listen(listener,SOMAXCONN) == -1){
        std::cerr << "Listen failed" << std::endl;
    }

    std::cout << "Listening to port 8080" << std::endl;

    int conn{accept(listener,nullptr,nullptr)};

    if(conn == -1){
        std::cerr << "accept failed" << std::endl;
        return 1;
    }

    std::cout << "Client connected" << std::endl;

    char buffer[1024];
    int chuck{0};

    while(true){
        ssize_t n{recv(conn,buffer,sizeof(buffer),0)};
        
        if(n == 0){
            std::cout << "Client closed the connection" << std::endl;
        }

        if(n == -1){
            if(errno == EINTR){
                continue;
            }
            std::cerr << "recv failed" << std::strerror(errno)<< std::endl;
        }

        chuck++;
        std::cout << "chuck " << chuck << ":" << n << "bytes [ " <<
        string_view(buffer, static_cast<std::size_t>(n)) << "]" << std::endl;
    }

    close(conn);
    close(listener);
    return 0;



   
}