#include <sys/socket.h>  
#include <netinet/in.h>  
#include <arpa/inet.h>   
#include <unistd.h>     
#include <cerrno>
#include <cstring>
#include <iostream>


int main(){

    //create a socket
    int listener{socket(AF_INET,SOCK_STREAM,0)};

    //check for errors
    if(listener == -1){
        std::cerr << "Socket failed" << std::strerror(errno) << std::endl;
        return 1;  
    }


    //if we close the socket, it take about 1-2 minutes to actually turn off because tcp
    //still waits for all bytes to arrive. with this we are able to tell it, dont wait, restart
    //immediately.
    int yes = 1;
    if(setsockopt(listener,SOL_SOCKET,SO_REUSEADDR,&yes, sizeof(yes)) == -1){
        std::cerr<<"setsocktopt() failed" << std::strerror(errno) << std::endl;
        close(listener);
        return 1;
    }

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(8080);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    
    //claim the socket, if its already being used then close it.
   if (bind(listener, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == -1)
    {
        std::cerr << "bind() failed: " << std::strerror(errno) << '\n';
        close(listener);
        return 1;
    }
    

    //opens up tcp
    if(listen(listener,SOMAXCONN) == -1){
        std::cerr<< "Listen" << std::strerror(errno) << std::endl;
        close(listener);
        return 1;
    }

    std::cout <<"wait for client" << std::endl;

    sockaddr_in client{};
    socklen_t clientlength = sizeof(client);

    int conn = accept(listener,reinterpret_cast<sockaddr*>(&client),&clientlength);

    if(conn == -1){
        std::cerr<<"ACCEPT FAILED" << std::strerror(errno) << std::endl;
        close(listener);
        return 1;
    }

    char ip[INET_ADDRSTRLEN]{};
    inet_ntop(AF_INET,&client.sin_addr,ip,sizeof(ip));

    std::cout << "Connection from " << ip << ':' << ntohs(client.sin_port) << '\n';
    std::cout << "Listening socket is descriptor " << listener << '\n';
    std::cout << "Connected socket is descriptor " << conn << '\n';

    close(conn);
    close(listener);
    return 0;




}