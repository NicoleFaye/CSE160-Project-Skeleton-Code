/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

//Project implemented by Winnie Crumpton

#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;
}

implementation{
   pack sendPackage;

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   event void Boot.booted(){
      call AMControl.start();

      dbg(GENERAL_CHANNEL, "Booted\n");
   }

   event void AMControl.startDone(error_t err){
      if(err == SUCCESS){
         dbg(GENERAL_CHANNEL, "Radio On\n");
      }else{
         //Retry until successful
         call AMControl.start();
      }
   }

   event void AMControl.stopDone(error_t err){}

   //Receive function implemented by Winnie Crumpton
   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      dbg(GENERAL_CHANNEL, "Packet Received\n");
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
		if(myMsg->dest == TOS_NODE_ID){ //Checks to see if the current node is the destination of the packet
			dbg(FLOODING_CHANNEL, "Packet has reached the destination: this = %d, dest = %d\n", TOS_NODE_ID, myMsg->dest);	
			dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); //Submit the payload to the general channel
			return msg;
		}
		else if(myMsg->src == TOS_NODE_ID){ //Checks to see if the current node is the source node of the packet
			dbg(FLOODING_CHANNEL, "Packet has returned to the source: remaining TTL = %d\n", myMsg->TTL);
			return msg;
		}
		else{ //The Packet is transferable
			if(myMsg->TTL > 0){ //Checks the packets remaining pings
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE); //Copy the packet to the send pointer
				call Sender.send(sendPackage, AM_BROADCAST_ADDR); //ping neighboring nodes
				//dbg(FLOODING_CHANNEL, "Packet forwarded, TTL = %d\n", myMsg->TTL); //Unneccesary but useful debugging output
				return msg;
			}
			else{ //Packet Death has occured
				dbg(FLOODING_CHANNEL, "Packet death at node %d\n", TOS_NODE_ID);
				return msg;
			}
		}
         dbg(GENERAL_CHANNEL, "You should not be seeing this.");
         return msg;
      }
      dbg(GENERAL_CHANNEL, "Unknown Packet Type %d\n", len);
      return msg;
   }


   event void CommandHandler.ping(uint16_t destination, uint8_t *payload){
      dbg(GENERAL_CHANNEL, "PING EVENT \n");
      makePack(&sendPackage, TOS_NODE_ID, destination, 8, 0, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
      call Sender.send(sendPackage, AM_BROADCAST_ADDR); //Send the packet to all neighbors
   }

   event void CommandHandler.printNeighbors(){}

   event void CommandHandler.printRouteTable(){}

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   event void CommandHandler.setTestServer(){}

   event void CommandHandler.setTestClient(){}

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }
}
