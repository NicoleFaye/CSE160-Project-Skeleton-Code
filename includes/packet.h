//Author: UCM ANDES Lab
//$Author: abeltran2 $
//$LastChangedBy: abeltran2 $

#ifndef PACKET_H
#define PACKET_H


# include "protocol.h"
#include "channels.h"

enum{
	PACKET_HEADER_LENGTH = 8,
	PACKET_MAX_PAYLOAD_SIZE = 28 - PACKET_HEADER_LENGTH,
	MAX_TTL = 10,
	NEIGHBOR_LIFESPAN = 3, //the number of missed neighbor updates before assumed death
	INFINITE_COST = 0,

	//TCP RELATED VALUES
	MAX_TRANSMISSION_SIZE = 64, //The number of packets that are transferable in a single TCP connection
	SYN = 1, //Establish Connection
	ACK = 2, //Acknowledge a recieved packet
	FIN = 3  //Close Connection

};


typedef nx_struct pack{
	nx_uint16_t dest;
	nx_uint16_t src;
	nx_uint16_t seq;		//Sequence Number
	nx_uint8_t TTL;		//Time to Live
	nx_uint8_t protocol;
	nx_uint8_t payload[PACKET_MAX_PAYLOAD_SIZE];
}pack;


//PROJECT 1
//Neighbor Discovery
typedef nx_struct neighbor{
	nx_uint16_t id;
	nx_uint16_t TTL; //used in neighbor death detection
}neighbor;

//PROJECT 2
//DVR-RIP
typedef nx_struct route{
	nx_uint16_t dest;
	nx_uint16_t next;
	nx_uint8_t cost;
}route;

//PROJECT 3
//TCP
typedef nx_struct SockPack{
	nx_uint16_t status; //SYN/ACK/FIN
	nx_uint16_t TTL; //used in ACK Packet timeouts for loss detection

	pack payload;
}socketPacket;

typedef nx_struct socket{
	nx_uint16_t src; //THIS ID
	nx_uint16_t srcPort; //THIS PORT#

	nx_uint16_t dest; //DEST ID
	nx_uint16_t destPort; //DEST PORT#

	SockPack Inbound[MAX_TRANSMISSION_SIZE]; //Inbound Queue
	SockPack Outbound[MAX_TRANSMISSION_SIZE]; //Outbound Queue
}socket;


/*
 * logPack
 * 	Sends packet information to the general channel.
 * @param:
 * 		pack *input = pack to be printed.
 */
void logPack(pack *input){
	dbg(GENERAL_CHANNEL, "Src: %hhu Dest: %hhu Seq: %hhu TTL: %hhu Protocol:%hhu  Payload: %s\n",
	input->src, input->dest, input->seq, input->TTL, input->protocol, input->payload);
}

enum{
	AM_PACK=6
};

#endif
