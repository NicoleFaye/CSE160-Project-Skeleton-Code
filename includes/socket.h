#ifndef __SOCKET_H__
#define __SOCKET_H__

#include "packet.h"

enum{
    MAX_NUM_OF_SOCKETS = 10,
    ROOT_SOCKET_ADDR = 255,
    ROOT_SOCKET_PORT = 255,
    SOCKET_BUFFER_SIZE = 128,

    MAX_DATA_PAYLOAD_SIZE = PACKET_MAX_PAYLOAD_SIZE-2,

    //TCP RELATED VALUES
    //MAX_TRANSMISSION_SIZE = 64, //The number of packets that are transferable in a single TCP connection
    SYN = 1, //Establish Connection
    ACK = 2, //Acknowledge a recieved packet
    FIN = 3  //Close Connection
};

enum socket_state{
    CLOSED,
    LISTEN,
    ESTABLISHED,
    FINISHED,
    SYN_SENT,
    SYN_RCVD,
};

enum data_worth{
    READABLE,
    ARBITRARY
};


typedef nx_uint8_t nx_socket_port_t;
typedef uint8_t socket_port_t;

typedef nx_struct TCP_PAYLOAD{
    nx_uint8_t flag; //The type of TCP command
    nx_socket_port_t destPort; //The port I'm attempting to connect to
    nx_socket_port_t srcPort; //The port I'm connecting from
}TCP_PAYLOAD;

typedef nx_struct DATA_PAYLOAD{
    nx_uint8_t port;
    nx_uint8_t size;
    nx_uint8_t array[MAX_DATA_PAYLOAD_SIZE];
}DATA_PAYLOAD;

// socket_addr_t is a simplified version of an IP connection.
typedef nx_struct socket_addr_t{
    nx_socket_port_t port;
    nx_uint16_t addr;
}socket_addr_t;


// File descripter id. Each id is associated with a socket_store_t
typedef uint8_t socket_t;

// State of a socket. 
typedef struct socket_store_t{
    uint8_t flag;
    enum socket_state state;
    socket_port_t src;
    socket_addr_t dest;

    // This is the sender portion.
    enum data_worth dat;
    char* msg;
    uint8_t msgSize;
    pack lastPack;

    uint8_t sendBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastWritten; //buff index
    uint8_t lastAck; //pack seq
    uint8_t lastAckIndex;
    uint8_t lastSent; //last pack sent

    uint8_t totalSent; //total number of bytes sent
    uint8_t transferSize; //total number of bytes that are supposed to be sent

    // This is the receiver portion
    uint8_t rcvdBuff[SOCKET_BUFFER_SIZE];
    uint8_t lastRead; //buff index
    uint8_t lastRcvd; //buff index
    uint8_t nextExpected; //pack seq
    uint8_t totalRcvd; //total number of bytes recieved

    uint16_t RTT;
    uint16_t timeout;
    uint8_t resentCount;

    uint8_t effectiveWindow;
}socket_store_t;

#endif
