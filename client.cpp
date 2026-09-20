#include <sys/socket.h>  // socket, connect, getsockname
#include <netinet/in.h>  // sockaddr_in
#include <arpa/inet.h>   // inet_pton, inet_ntop, htons, ntohs
#include <unistd.h>      // close
#include <cerrno>
#include <cstring>
#include <iostream>

int main(){
    

    //create socket
    int sock{socket(AF_INET,SOCK_STREAM,0)};
    if(sock == -1){
        std::cerr << "SOCK FAILED:" << std::strerror(errno) << std::endl;
        return 1;
    }

    sockaddr_in server{};
    server.sin_family = AF_INET;
    server.sin_port = htons(8080);

    if(inet_pton(AF_INET,"127.0.0.1", &server.sin_addr) != 1){
        std::cerr<<"invalid adress" << std::endl;
        close(sock);
        return 1;
    }

    std::cout <<"conncting to 127.0.01" << std::endl;

    if (connect(sock, reinterpret_cast<sockaddr*>(&server), sizeof(server)) == -1)
    {
        std::cerr << "connect() failed: " << std::strerror(errno) << '\n';
        close(sock);
        return 1;
    }

    std::cout <<"connected" << std::endl;

    sockaddr_in mine{};
    socklen_t mineLen{ sizeof(mine) };

    if (getsockname(sock, reinterpret_cast<sockaddr*>(&mine), &mineLen) == 0)
    {
        char ip[INET_ADDRSTRLEN]{};
        inet_ntop(AF_INET, &mine.sin_addr, ip, sizeof(ip));
        std::cout << "My end of the connection: "
                  << ip << ':' << ntohs(mine.sin_port) << '\n';
    }

    close(sock);
    return 0;

}