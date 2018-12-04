/*
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */
#include <stdlib.h>
#include <string.h>
#include <Timer.h>
#include "includes/command.h"
#include "includes/packet.h"
#include "includes/socket.h"
#include "includes/CommandMsg.h"
#include "includes/sendInfo.h"
#include "includes/channels.h"

module Node{
   uses interface Boot;

   uses interface SplitControl as AMControl;
   uses interface Receive;

   uses interface SimpleSend as Sender;

   uses interface CommandHandler;

   //LISTS
   uses interface List<neighbor> as nList; //P1
   uses interface List<neighbor> as nRefresher; //P1
   uses interface List<pack> as prevPacks; //P1
   uses interface List<route> as routeTable; //P2
   uses interface List<route> as forwardTable; //P2
   uses interface List<socket_store_t> as sockets; //P3

   //TIMERS
   uses interface Timer<TMilli> as ntimer; //P1
   uses interface Timer<TMilli> as rtimer; //P2
   uses interface Timer<TMilli> as TCPtimer; //P3
}

implementation{
   pack sendPackage;
   uint16_t currentSeq = 0;


   uint16_t nextPort = 0;
   

   // Prototypes
   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t Protocol, uint16_t seq, uint8_t *payload, uint8_t length);

   void socketBoot();

   uint8_t get_available_socket();

   socket_store_t* findSocket(uint8_t port);
   socket_store_t* findSocketAddr(uint16_t addr);

   bool transferDone(socket_store_t* sock);

   void exclusiveBroadcast(uint16_t exception);

   void smartPing();

   uint8_t sizeOfString(char* str);

   char*  append(char* s, char c, uint8_t len);

	//LIST COMMANDS
   uint8_t arrSize(uint8_t* arr);
   void fillArray(uint8_t* arr);


   event void Boot.booted(){
      call AMControl.start();
      socketBoot();
      call ntimer.startPeriodic(200000);
      call rtimer.startPeriodic(200000);
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

   event void ntimer.fired(){ //NEIGHBOR REFRESH TIMER
   		//INITIALIZE VARS
   		bool found;
   		bool empty;
   		neighbor n;
   		neighbor nr;
   		neighbor* np;
   		uint16_t i;
   		uint16_t j;
   		uint16_t nsize;
   		uint16_t nrsize;
  		nsize = call nList.size();
  		nrsize = call nRefresher.size();

  		//NEIGHBOR REFRESH PROCCESS
   		//dbg(GENERAL_CHANNEL, "refreshing nList %d. . . ", TOS_NODE_ID);

   		for(i = 0; i < nsize; i++){ //reduce TTL for all neighbors 
   			np = call nList.getAddr(i);
   			np->TTL--;
   		}

   		//compare refresh table with neighbor table to make additions and refreshes
		empty = call nRefresher.isEmpty();
   		while(!empty){
   			nr = call nRefresher.popfront(); //this implimentation also wipes the refresher list.
   			found = FALSE;

   			for(j = 0; j < nsize; j++){
   				np = call nList.getAddr(j);
   				if(np->id == nr.id){ //The neighbor was already in the neighborList
   					np->TTL = NEIGHBOR_LIFESPAN; //refresh the neighbors TTL
   					found = TRUE; //flag neighbor as found
   					j = nsize; //cancel the loop
   				}
   			}

   			if(found == FALSE){ //if the neighbor wasn't already in the nList
   				nr.TTL = NEIGHBOR_LIFESPAN;
   				call nList.pushfront(nr); //now it is
   			}

   			empty = call nRefresher.isEmpty();
   		}

   		for(i = 0; i < nsize; i++){ //wipe lost neighbors from the nList
   			n = call nList.popfront(); //pull n from front
   			if(n.TTL > 0){ //if n isn't dead
   				call nList.pushback(n); //push n to the back
   			}
   		}

   		//send neighbor refresh packet
   		makePack(&sendPackage, TOS_NODE_ID, TOS_NODE_ID, MAX_TTL, 6, currentSeq, "neighbor command", PACKET_MAX_PAYLOAD_SIZE);
   		call Sender.send(sendPackage, AM_BROADCAST_ADDR); //request neighbors for the new list
   		currentSeq++;
   }

   event void rtimer.fired(){
   		bool found;
   		bool empty;
   		neighbor n;
   		route r;
   		route* rp;
   		uint16_t id;
   		uint16_t i;
   		uint16_t j;
   		uint16_t fsize;
   		uint16_t nsize;
   		uint16_t rsize;
  		nsize = call nList.size();
		fsize = call forwardTable.size();
		rsize = call routeTable.size();

   		//ROUTE CHECKING
   		for(i = 0; i < nsize; i++){ //nested for loops for addition handling
   			n = call nList.get(i);
   			found = FALSE;
   			for(j = 0; j < fsize; j++){ //checking for existence within the forwarding table
   				//dbg(GENERAL_CHANNEL, "route pre-pull\n");
   				r = call forwardTable.get(j);
   				if(r.dest == n.id){
   					found = TRUE; //the entry exists
   					j = fsize;
   				}
   			}
   			if(found == FALSE){ //if the entry doesn't exist
   				r.dest = n.id;
   				r.next = n.id;
   				r.cost = 1;
   				call forwardTable.pushback(r);
   				call routeTable.pushback(r);
   				fsize = call forwardTable.size();

   				makePack(&sendPackage, TOS_NODE_ID, n.id, 1, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
   				exclusiveBroadcast(n.id);
   				currentSeq++;
   			}
   		}

   		for(i = 0; i < fsize; i++){ //nested for loops for elimination handling
   			r = call forwardTable.popfront();
   			found = FALSE;
   			for(j = 0; j < nsize; j++){ //checking for existence within the neighbor list
   				n = call nList.get(j);
   				if(r.next == n.id && r.dest == n.id){
   					found = TRUE; //the entry exists
   					call forwardTable.pushback(r); //re-add the route to the forwarding table
   					j = nsize;
   				}
   			}
   			if(found == FALSE){ //if the entry doesn't exist then the neighbor is dead
   				r.cost = INFINITE_COST;
   				id = r.dest;
   				//dbg(GENERAL_CHANNEL, "node %d has died\n", id);

   				for(j = 0; j < rsize; j++){
   					rp = call routeTable.getAddr(j);
   					if(rp->next == id){
   						rp->cost = INFINITE_COST;
   						makePack(&sendPackage, TOS_NODE_ID, rp->dest, INFINITE_COST, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
   						exclusiveBroadcast(id);
   						currentSeq++;
   					}
   				}
   			}
   		}
   }



   event void TCPtimer.fired(){//PROJECT 3// use this in set up functions -> call TCPtimer.startPeriodic(30000);
   		uint8_t i;
   		socket_store_t* sock;

   		/*
   		for(i = 0; i < call sockets.maxSize(); i++){
   			sock = call sockets.getAddr(i);

   			if(sock->state == ESTABLISHED){
   				if(call TCPtimer.getNow() >= sock->timeout){ //if timed out
   					if(sock->resentCount >= 2){
   						sock->state = CLOSED;
   						continue;
   					}

   					makePack(&sendPackage, sock->lastPack.src, sock->lastPack.dest, sock->lastPack.TTL, sock->lastPack.protocol, sock->lastPack.seq, sock->lastPack.payload, PACKET_MAX_PAYLOAD_SIZE);
   					smartPing();

   					sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2);
   					sock->resentCount++;

   					continue;
   				}


   			}
   			if(sock->state == LISTEN){
   				if(call TCPtimer.getNow() >= sock->timeout){ //if timed out
   					if(sock->resentCount >= 2){
   						sock->state = CLOSED;
   						continue;
   					}

   					makePack(&sendPackage, sock->lastPack.src, sock->lastPack.dest, sock->lastPack.TTL, sock->lastPack.protocol, sock->lastPack.seq, sock->lastPack.payload, PACKET_MAX_PAYLOAD_SIZE);
   					smartPing();

   					sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2);
   					sock->resentCount++;

   					continue;
   				}
   			}
   		}   */		
   } 



   event message_t* Receive.receive(message_t* msg, void* payload, uint8_t len){
      if(len==sizeof(pack)){
         pack* myMsg=(pack*) payload;
         //dbg(GENERAL_CHANNEL, "Packet Received, Protocol: %d\n", myMsg->protocol);
		
		if(myMsg->protocol != PROTOCOL_ROUTEUPDATE && myMsg->TTL <= 0) //drop dead packs except DVR updates (0 == infinity)
			return msg;

		//PROTOCOL FOR NEIGHBOR DISCOVERY
		if(myMsg->protocol == PROTOCOL_NEIGHBORPING){ //packet recieved from a node running discovery
			//dbg(NEIGHBOR_CHANNEL, "%d -> %d", myMsg->dest, TOS_NODE_ID); //log the path of recieving packet
			makePack(&sendPackage, TOS_NODE_ID, myMsg->dest, myMsg->TTL-1, PROTOCOL_NEGHBORREPLY, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
			call Sender.send(sendPackage, myMsg->dest);
			return msg;
		}
		if(myMsg->protocol == PROTOCOL_NEGHBORREPLY){ //packet is a neighbor reply
			if(myMsg->dest == TOS_NODE_ID){ //packet has returned to dest
				neighbor n;
				n.id = myMsg->src; //UPDATE THE NEIGHBOR LIST
				n.TTL = NEIGHBOR_LIFESPAN;
				call nRefresher.pushfront(n);

				//dbg(NEIGHBOR_CHANNEL, "Neighbor List %d Updated \n", TOS_NODE_ID);
				return msg;
			}
			return msg;
		}

		//PROTOCOL FOR ROUTING TABLE UPDATES
		if(myMsg->protocol == PROTOCOL_ROUTEUPDATE){ //PROTOCOL FOR RECIEVING A ROUTE UPDATE
			route r;
			route* rp;
			bool found = FALSE;
			uint16_t i;
			uint16_t size;
			size = call routeTable.size();

			//dbg(ROUTING_CHANNEL, "route update recived\n");
			if(myMsg->dest == TOS_NODE_ID){ //if this is a path to me then don't forward it.
				return msg;
			}

			for(i = 0; i < size; i++){
				rp = call routeTable.getAddr(i); 
				if(myMsg->dest == rp->dest){ //if the route is already established
					found = TRUE;
					if(myMsg->src == rp->next){ //if this is my current preffered route
						if(myMsg->TTL == INFINITE_COST) //if the path is broken
						{
							//set my path to broken and tell my neighbors
							//rp->next = NULL; 
							rp->cost = INFINITE_COST;
						}
						else{ //if the path isn't broken
							//update the route table and my neighbors
							rp->cost = myMsg->TTL;
							rp->cost += 1;
						}
						makePack(&sendPackage, TOS_NODE_ID, rp->dest, rp->cost, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
						exclusiveBroadcast(myMsg->src);
						currentSeq++;
						return msg;
					}
					else{ //if this is not my preffered route
						if(myMsg->TTL == INFINITE_COST)//If their path is broken
						{
							if(rp->cost == INFINITE_COST){ //if mine is broken
								return msg; //give up lmao
							}
							makePack(&sendPackage, TOS_NODE_ID, rp->dest, rp->cost, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
							//call Sender.send(sendPackage, myMsg->src);
							//currentSeq++;
							return msg;
						}
						if(rp->cost == INFINITE_COST){ //if my path is broken
							//change the route and tell my neighbors
							rp->next = myMsg->src;
							rp->cost = myMsg->TTL;
							rp->cost += 1;
							makePack(&sendPackage, TOS_NODE_ID, rp->dest, rp->cost, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
							exclusiveBroadcast(myMsg->src);
							currentSeq++;
							return msg;
						}
						if(myMsg->TTL+1 < rp->cost){ //if the new path is more efficient
							//dbg(GENERAL_CHANNEL, "new path found, old cost: %d, new cost: %d\n", rp->cost, myMsg->TTL);
							//change the route and tell my neighbors
							rp->next = myMsg->src;
							rp->cost = myMsg->TTL;
							rp->cost += 1;
							makePack(&sendPackage, TOS_NODE_ID, rp->dest, rp->cost, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
							exclusiveBroadcast(myMsg->src);
							currentSeq++;
							return msg;
						}
					}
				}
			}
			if(!found){
				//make a new route here
				r.dest = myMsg->dest;
				r.next = myMsg->src;
				r.cost = myMsg->TTL;
				r.cost += 1;
				call routeTable.pushfront(r); //add it to the route table
				makePack(&sendPackage, TOS_NODE_ID, r.dest, r.cost, PROTOCOL_ROUTEUPDATE, currentSeq, "route update", PACKET_MAX_PAYLOAD_SIZE);
				exclusiveBroadcast(myMsg->src); //forward it to neighbors
				currentSeq++;
				//dbg(ROUTING_CHANNEL, "new route broadcasted\n");
			}
			return msg;
		}


		//PROTOCOL FOR TCP PACKETS
		if(myMsg->protocol == PROTOCOL_TCP){

			if(myMsg->src == TOS_NODE_ID)
				return msg;

			if(myMsg->dest == TOS_NODE_ID){ //meant for me

				TCP_PAYLOAD reply;
				TCP_PAYLOAD* control;
				socket_store_t* sock;

				//dbg(TRANSPORT_CHANNEL, "TCP PACKET ARRIVED\n");

				
				control = (TCP_PAYLOAD*) myMsg->payload; //cast it

				sock = findSocket(control->destPort); //find the corresponding port
				if(sock == NULL) //shit broke
					return msg;

				if(control->flag == SYN){ //It's an attempt to establish connection
					//respond with SYN and ACK if self is server, respond with Data if self is client.

					socket_store_t* sock = findSocket(control->destPort); //find the corresponding port
					if(sock == NULL) //shit broke
						return msg;

					dbg(TRANSPORT_CHANNEL, "SYN PACKET from %d\n", myMsg->src);

					if(sock->state == CLOSED){ //This node is server
						sock->state = SYN_RCVD; //Set node to response phase of handshake
						sock->dest.port = control->srcPort;
						sock->dest.addr = myMsg->src;
						sock->RTT = call TCPtimer.getNow();

						reply.flag = ACK;
						reply.destPort = control->srcPort;
						reply.srcPort = sock->src;

						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq+1, (uint8_t*)&reply, sizeof(TCP_PAYLOAD));
						smartPing(); //Send ACK Packet

						sock->lastPack = sendPackage;

						dbg(TRANSPORT_CHANNEL, "ACK SENT TO CLIENT\n");

						return msg;
					}
					return msg;
				}

				if(control->flag == ACK){ //ACC PACC BOIIII

					dbg(TRANSPORT_CHANNEL, "ACK PACKET from %d, port:%d\n", myMsg->src, sock->src);



					if(sock->state == ESTABLISHED){ //Send new data packet until transmission is complete
						uint8_t remainder = sock->transferSize - sock->totalSent;
						DATA_PAYLOAD data;
						
						sock->lastAck = myMsg->seq;
						data.port = control->srcPort;

						//dbg(TRANSPORT_CHANNEL, "Transfer Size: %d, Total Sent: %d, Remainder: %d\n", sock->transferSize, sock->totalSent, remainder);

						if(sock->dat == READABLE){ //If the data to be sent contains a message


							if(remainder <= MAX_DATA_PAYLOAD_SIZE){ //send whatever is left
								uint8_t i;
								uint8_t j = 0;
								data.size = remainder;

								for(i = sock->totalSent; i < sock->transferSize; i++){
									data.array[j] = (uint8_t)sock->msg[i];
									j++;
								}
								

								makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, PACKET_MAX_PAYLOAD_SIZE);
								smartPing();
								currentSeq++;

								sock->lastPack = sendPackage;

								dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 2\n");

								sock->totalSent += remainder;
								sock->state = FINISHED;
								return msg;
							}
							else{ //send it allllllllllll
								uint8_t i;
								uint8_t j = 0;
								uint8_t bytes[MAX_DATA_PAYLOAD_SIZE];
								data.size = MAX_DATA_PAYLOAD_SIZE;

								for(i = sock->totalSent; i < sock->totalSent+MAX_DATA_PAYLOAD_SIZE; i++){
									data.array[j] = (uint8_t)sock->msg[i];
									j++;
								}


								makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, PACKET_MAX_PAYLOAD_SIZE);
								smartPing();
								currentSeq++;

								sock->lastPack = sendPackage;

								sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2); //set new timeout
								sock->resentCount = 0;

								dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 1\n");

								sock->totalSent += MAX_DATA_PAYLOAD_SIZE;
								return msg;
							}
							return msg;
						}
						else if(sock->dat == ARBITRARY){ //If the data to be sent is arbitrary

							if(remainder <= MAX_DATA_PAYLOAD_SIZE){ //send whatever is left
								data.size = remainder;
								fillArray(data.array);

								makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, PACKET_MAX_PAYLOAD_SIZE);
								smartPing();
								currentSeq++;

								sock->lastPack = sendPackage;

								//dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 2\n");

								sock->totalSent += remainder;
								sock->state = FINISHED;
								return msg;
							}
							else{ //send it allllllllllll
								uint8_t bytes[MAX_DATA_PAYLOAD_SIZE];
								data.size = MAX_DATA_PAYLOAD_SIZE;
								fillArray(data.array);


								makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, PACKET_MAX_PAYLOAD_SIZE);
								smartPing();
								currentSeq++;

								sock->lastPack = sendPackage;

								sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2); //set new timeout
								sock->resentCount = 0;

								//dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 1\n");

								sock->totalSent += MAX_DATA_PAYLOAD_SIZE;
								return msg;
							}
						}

						
						return msg;
					}

					/*if(sock->state == FINISHED){ //Not Used
						//Another function closes the connection so idk why this is even here
						//could be useful in a future implimentation

						reply.flag = FIN;
						reply.srcPort = sock->src;
						reply.destPort = sock->dest.port;

						makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCP, currentSeq, (uint8_t*)&reply, sizeof(TCP_PAYLOAD));
						smartPing();
						currentSeq++;

						sock->state = CLOSED;

						return msg;
					}*/

					if(sock->state == SYN_SENT){

						dbg(TRANSPORT_CHANNEL, "Client Established\n");

						sock->state = ESTABLISHED;
						sock->lastAck = myMsg->seq;
						sock->totalSent = 0;
						sock->RTT = call TCPtimer.getNow() - sock->RTT;
						dbg(TRANSPORT_CHANNEL, "RTT = %d\n", sock->RTT);

						reply.flag = ACK;
						reply.destPort = control->srcPort;
						reply.srcPort = sock->src;

						makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq+1, (uint8_t*)&reply, sizeof(TCP_PAYLOAD));
						smartPing(); //Send ACK Packet

						sock->lastPack = sendPackage;

						return msg;
					}

					if(sock->state == SYN_RCVD){

						sock->state = LISTEN;
						sock->totalRcvd = 0;
						sock->RTT = call TCPtimer.getNow() - sock->RTT;
						dbg(TRANSPORT_CHANNEL, "RTT = %d\n", sock->RTT);

						if(sock->dat == ARBITRARY){
							reply.flag = ACK;
							reply.destPort = control->srcPort;
							reply.srcPort = sock->src;

							makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq+1, (uint8_t*)&reply, sizeof(TCP_PAYLOAD));
							smartPing(); //Send ACK Packet

							sock->lastPack = sendPackage;
						}

						return msg;

					}

				}

				if(control->flag == FIN){ //lol bye :)
					dbg(TRANSPORT_CHANNEL, "FIN PACKET from %d\n", myMsg->src);

					sock->state = CLOSED;
					return msg;
				}
			}
			else{ //not meant for me, just forward it.

				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL - 1, PROTOCOL_TCP, myMsg->seq, myMsg->payload, arrSize(myMsg->payload));
				smartPing();
			}


			//IMPLIMENT THIS FOR PROJECT 3

			/*
			*	When Transmitting an ACK packet:
			*	Make the SEQ of the ACK pack be the SEQ of the recieved pack + 1
			*	"This is the next packet I expect from you."
			*
			*	Consider making a TCPLayer.nc File
			*/

			return msg;

		}

		if(myMsg->protocol == PROTOCOL_TCPDATA){ //used for actual data transmission on a TCP closeConnection

			dbg(TRANSPORT_CHANNEL, "TCPDATA PACK RECIEVED\n");

			if(myMsg->dest == TOS_NODE_ID){
			
				TCP_PAYLOAD reply;
				DATA_PAYLOAD* data;
				uint8_t i;
				uint8_t size;
				uint8_t bytes;
				socket_store_t* sock;

				data = (DATA_PAYLOAD*)myMsg->payload;

				sock = findSocket(data->port);

				bytes = data->size;

				if(sock->dat == READABLE){
					dbg(TRANSPORT_CHANNEL, "Reading data (Port: %d) PackSize: %d\n", sock->src, bytes);
					for(i = 0; i < bytes; i++){
						sock->msg = append(sock->msg, (char)data->array[i], sock->totalRcvd);
						sock->totalRcvd++;
					}

					size = sizeOfString(sock->msg);

					if(sock->msg[size-1] == '\n' && sock->msg[size-2] == '\r'){
						dbg(TRANSPORT_CHANNEL, "Message from %d: %s", myMsg->src, sock->msg);
						sock->msg = "";
					}

				}
				else if(sock->dat == ARBITRARY){
					dbg(TRANSPORT_CHANNEL, "Reading data (Port: %d) PackSize: %d\n", sock->src, bytes);
					for(i = 0; i < bytes; i++){
						sock->totalRcvd++;
						dbg(TRANSPORT_CHANNEL, "%d\n", sock->totalRcvd);
					}
					dbg(TRANSPORT_CHANNEL, "Done.\n");
				}

				reply.flag = ACK;
				reply.srcPort = sock->src;
				reply.destPort = sock->dest.port;

				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_TCP, myMsg->seq+1, (uint8_t*)&reply, sizeof(TCP_PAYLOAD));
				smartPing();

				sock->lastPack = sendPackage;

				sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2); //set new timeout
				sock->resentCount = 0;

				return msg;
			}
			else{
				dbg(TRANSPORT_CHANNEL, "TCP DATA PACK FORWARDED\n");
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, PROTOCOL_TCPDATA, myMsg->seq, myMsg->payload, arrSize(myMsg->payload));
				smartPing();
				return msg;
			}
			return msg;
		}

		
		//PROTOCOL FOR NORMAL PING
		if(myMsg->dest == TOS_NODE_ID){ //Checks to see if the current node is the destination of the packet
			//protocol = ping
			if(myMsg->protocol == PROTOCOL_PING) {
				dbg(FLOODING_CHANNEL, "Packet has reached the destination: %d.\n", TOS_NODE_ID);	
				dbg(GENERAL_CHANNEL, "Package Payload: %s\n", myMsg->payload); //Submit the payload to the general channel
				makePack(&sendPackage, TOS_NODE_ID, myMsg->src, MAX_TTL, PROTOCOL_PINGREPLY, currentSeq, "Thanks! <3", PACKET_MAX_PAYLOAD_SIZE);
				smartPing(); //ping neighboring nodes
				currentSeq++;
				return msg;
			}
			//protocol = ping reply
			else if(myMsg->protocol == PROTOCOL_PINGREPLY){
				dbg(FLOODING_CHANNEL, "Ping reply recieved! \n");
				dbg(GENERAL_CHANNEL, "Payload: %s \n", myMsg->payload);
				return msg;
			}
			return msg;
		}
		else if(myMsg->src == TOS_NODE_ID){ //Checks to see if the current node is the source node of the packet
			//dbg(FLOODING_CHANNEL, "Packet has returned to the source: remaining TTL = %d\n", myMsg->TTL);
			return msg;
		}
		else{ //The Packet is transferable
			uint16_t i; //CHECK IF IT EXISTS IN THE PREVPACKS LIST
			uint16_t size = call prevPacks.size();
			pack prev;
			for(i=0; i<size; i++){
				prev = call prevPacks.get(i);
				if(myMsg->src == prev.src && myMsg->seq == prev.seq){
					return msg;
				}
			}
			if(myMsg->TTL > 0){ //Checks the packets remaining pings
				makePack(&sendPackage, myMsg->src, myMsg->dest, myMsg->TTL-1, myMsg->protocol, myMsg->seq, myMsg->payload, PACKET_MAX_PAYLOAD_SIZE); //Copy the packet to the send pointer
				smartPing(); //ping neighboring nodes
				call prevPacks.pushfront(sendPackage);
				//dbg(FLOODING_CHANNEL, "Packet forwarded, TTL = %d\n", myMsg->TTL); //Unneccesary but useful debugging output
				return msg;
			}
			else{ //Packet Death has occured
				//dbg(FLOODING_CHANNEL, "Packet death at node %d\n", TOS_NODE_ID);
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
   	  makePack(&sendPackage, TOS_NODE_ID, destination, MAX_TTL, PROTOCOL_PING, currentSeq, payload, PACKET_MAX_PAYLOAD_SIZE);
   	  smartPing();
   	  currentSeq++;
   	  
   }

   event void CommandHandler.printNeighbors(){
   		uint16_t  i;
   		neighbor n; //initialize the variables before loop
   		uint16_t size = call nList.size();
   		dbg(NEIGHBOR_CHANNEL, "Neighbors of %d include: \n", TOS_NODE_ID);
   		
   		for (i=0; i< size; i++)
   		{
   				n = call nList.get(i);
   				dbg(NEIGHBOR_CHANNEL,  "%d \n", n.id); //output the ID of the neighbor node
   		}
   	}

   event void CommandHandler.printRouteTable(){
   		uint16_t  i;
   		route r; //initialize the variables before loop
   		uint16_t size = call routeTable.size();
   		dbg(ROUTING_CHANNEL, "Routes of node %d include: \n", TOS_NODE_ID);
   		for (i=0; i< size; i++)
   		{
   			r = call routeTable.get(i);
   			if(r.cost == INFINITE_COST){ //if cost is infinite print it
   				dbg(ROUTING_CHANNEL,  "dest: %d, next: %d, cost: infinity \n", r.dest, r.next);
   			}
   			else{
   				dbg(ROUTING_CHANNEL,  "dest: %d, next: %d, cost: %d \n", r.dest, r.next, r.cost); //output the ID of the neighbor node
   			}
   		}
   }

   event void CommandHandler.printLinkState(){}

   event void CommandHandler.printDistanceVector(){}

   // PROJECT 3
   //set up a server at this node to recieve data from a client node
   event void CommandHandler.setTestServer(uint8_t port){
   		//Self = Server
   		//set up inbound timer here
   		//socket
   		socket_store_t* sock;
   		uint8_t sock_index = get_available_socket(); //get the index of an available socket
   		
   		sock = call sockets.getAddr(sock_index); //Socket has been aquired

   		sock->src = port; //Assign the socket to the provided port value
   		sock->dat = ARBITRARY; //Arbitrary Data

   		call TCPtimer.startPeriodic(1000); //start TCP timer
   }


   // PROJECT 3
   //Establish a connection with a server node and transmit arbitrary bytes of data
   event void CommandHandler.setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t num){
		//Self = Client
		//num = the nuber of bytes being transmitted
		//set up outbound timer here

		uint8_t i;
		socket_store_t* sock;
		TCP_PAYLOAD control;
   		uint8_t sock_index = get_available_socket(); //get the index of an available socket
   		sock = call sockets.getAddr(sock_index); //Socket has been aquired

   		sock->src = srcPort; //Assign the socket to the provided port value
   		sock->dest.port = destPort;
   		sock->dest.addr = dest;
   		sock->transferSize = num;
   		sock->totalSent = 0;
   		sock->dat = ARBITRARY; //Arbitrary Data

   		control.flag = SYN;
   		control.destPort = destPort;
   		control.srcPort = srcPort;

   		makePack(&sendPackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, currentSeq, (uint8_t*)&control, sizeof(TCP_PAYLOAD));
   		smartPing(); //send a syn pack to establish connection
   		currentSeq++;

   		sock->lastPack = sendPackage;

   		sock->state = SYN_SENT; //set status to awaiting ACK

   		call TCPtimer.startPeriodic(1000); //start TCP timer

   		sock->RTT = call TCPtimer.getNow();

   } 

   event void CommandHandler.setAppServer(){}

   event void CommandHandler.setAppClient(){}


   // PROJECT 3
   //Close a connection to a server node
   event void CommandHandler.closeConnection(uint16_t dest, uint8_t srcPort, uint8_t destPort){
   		//self = Client
   		TCP_PAYLOAD control;
   		socket_store_t* sock = findSocket(srcPort);

   		control.flag = FIN;
   		control.srcPort = sock->src;
   		control.destPort = destPort;

   		makePack(&sendPackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, currentSeq, (uint8_t*)&control, sizeof(TCP_PAYLOAD));
   		smartPing();
   		currentSeq++;

   		sock->state = CLOSED;
   		sock->src = NULL;

   }



   //PROJECT 4

   event void CommandHandler.setServer(uint8_t port){
   		socket_store_t* sock;
   		uint8_t sock_index = get_available_socket(); //get the index of an available socket
   		
   		sock = call sockets.getAddr(sock_index); //Socket has been aquired

   		sock->src = port; //Assign the socket to the provided port value
   		sock->dat = READABLE;


   		call TCPtimer.startPeriodic(1000); //start TCP timer

   		sock->RTT = call TCPtimer.getNow();
   }

   event void CommandHandler.setClient(uint16_t dest, uint8_t srcPort, uint8_t destPort){
   		uint8_t i;
		socket_store_t* sock;
		TCP_PAYLOAD control;
   		uint8_t sock_index = get_available_socket(); //get the index of an available socket
   		sock = call sockets.getAddr(sock_index); //Socket has been aquired

   		sock->src = srcPort; //Assign the socket to the provided port value
   		sock->dest.port = destPort;
   		sock->dest.addr = dest;
   		sock->dat = READABLE;
   		sock->totalSent = 0;

   		control.flag = SYN;
   		control.destPort = destPort;
   		control.srcPort = srcPort;

   		makePack(&sendPackage, TOS_NODE_ID, dest, MAX_TTL, PROTOCOL_TCP, currentSeq, (uint8_t*)&control, sizeof(TCP_PAYLOAD));
   		smartPing(); //send a syn pack to establish connection
   		currentSeq++;

   		sock->state = SYN_SENT; //set status to awaiting ACK

   		call TCPtimer.startPeriodic(1000); //start TCP timer

   		sock->RTT = call TCPtimer.getNow();

   }

   event void CommandHandler.sendMsg(uint8_t port, uint8_t* msg, uint8_t len){
   		uint8_t i;
   		uint8_t length = 0;
   		char temp[128] = "";
   		socket_store_t* sock;
   		uint8_t remainder;
		DATA_PAYLOAD data;

		sock = findSocket(port);

		i = 1;
		while((char)msg[i] != '\n'){
			temp[i-1] = (char)msg[i];
			length++;
			i++;
		}

		temp[i-1] = '\n';
		length++;

		sock->msg = temp;
		sock->msgSize = length;

   		sock->transferSize = sock->msgSize;
   		sock->totalSent = 0;
   		data.port = sock->dest.port;
   		remainder = sock->transferSize - sock->totalSent;

   		sock->state = ESTABLISHED;
   		sock->dat = READABLE;

		if(remainder <= MAX_DATA_PAYLOAD_SIZE){ //send whatever is left
			uint8_t i;
			uint8_t j = 0;
			data.size = remainder;

			for(i = sock->totalSent; i < sock->transferSize; i++){
				data.array[j] = (uint8_t)sock->msg[i];
				j++;
			}

			makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, sizeof(DATA_PAYLOAD));
			smartPing();
			currentSeq++;

			//dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 2\n");

			sock->totalSent += remainder;
			sock->state = FINISHED;
			return;
		}
		else{ //send it allllllllllll
			uint8_t i;
			uint8_t j = 0;
			uint8_t bytes[MAX_DATA_PAYLOAD_SIZE];
			data.size = MAX_DATA_PAYLOAD_SIZE;

			for(i = sock->totalSent; i < sock->totalSent+MAX_DATA_PAYLOAD_SIZE; i++){
				data.array[j] = (uint8_t)sock->msg[i];
				j++;
			}


			makePack(&sendPackage, TOS_NODE_ID, sock->dest.addr, MAX_TTL, PROTOCOL_TCPDATA, currentSeq, (uint8_t*)&data, sizeof(DATA_PAYLOAD));
			smartPing();
			currentSeq++;

			sock->timeout = call TCPtimer.getNow() + (sock->RTT * 2); //set new timeout
			sock->resentCount = 0;

			//dbg(TRANSPORT_CHANNEL, "TCPDATA PACK SENT 1\n");

			sock->state = ESTABLISHED;

			sock->totalSent += MAX_DATA_PAYLOAD_SIZE;
			return;
		}  		
		
   }


   void handleNeighborDeath(uint16_t index){

   }

   void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length){
      Package->src = src;
      Package->dest = dest;
      Package->TTL = TTL;
      Package->seq = seq;
      Package->protocol = protocol;
      memcpy(Package->payload, payload, length);
   }

   void exclusiveBroadcast(uint16_t exception){ //broadcasts to all neighbors except the exception
   		uint16_t i;
   		uint16_t size;
   		neighbor n;
   		size = call nList.size();
   		for(i = 0; i < size; i++){
   			n = call nList.get(i);
   			if(n.id != exception){
   				call Sender.send(sendPackage, n.id);
   			}
   		}
   }

   void smartPing(){ //Pings the current sendPackage using DVR table
   		int rsize;
   	  	int i;
   	 	bool found;
   		route r;
   		route cheapest;

   	  	if(call routeTable.isEmpty()){ //If there is no routing table
      		call Sender.send(sendPackage, AM_BROADCAST_ADDR); //Send the packet to all neighbors
      		return;
   	  	}
   	 	else{
   	    	rsize = call routeTable.size();
   	    	found = FALSE;

   	    	for(i = 0; i < rsize; i++){ //Search DVR table
        		r = call routeTable.get(i);
   	  			if(sendPackage.dest == r.dest){ //If matching route is found
   	  				if(found == FALSE && r.cost != 0){
   	  					found = TRUE;
   	  					cheapest = r;
   	  				}
   	  				else if(found == TRUE){
   	  					if(r.cost < cheapest.cost && r.cost != 0)
   	  						cheapest = r;
   	  				}
   	  			}
   	   		}
   	   		if(found){ 
   	   			call Sender.send(sendPackage, cheapest.next); //forward neatly
   				return;
   	   		}
   	   		if(!found){
   	   			call Sender.send(sendPackage, AM_BROADCAST_ADDR); //Flood!
   	   			return;
   	   		}
   	  	}
   }

   void socketBoot(){ //initializes all sockets to CLOSED durring Boot
   		uint8_t i = 0;
   		socket_store_t sock;
   		uint16_t size = call sockets.maxSize();
   		sock.state = CLOSED;
   		sock.totalRcvd = 0;
   		for(i = 0; i < size; i++)
   		{
   			call sockets.pushfront(sock);
   		}
   }

   uint8_t get_available_socket(){ //returns the index of the first available (closed) socket
   		uint8_t i = 0;
   		socket_store_t sock;
   		uint16_t size = call sockets.maxSize(); //look through every socket
   		for(i = 0; i < size; i++)
   		{
   			sock = call sockets.get(i);
   			if(sock.state == CLOSED){ //the first available socket index gets returned
   				return i;
   			}
   		}
   }

   socket_store_t* findSocket(uint8_t port){ //returns the index of a socket with the corresponding port ID
   		uint8_t i = 0;
   		socket_store_t* sock;
   		uint16_t size = call sockets.maxSize(); //look through every socket
   		for(i = 0; i < size; i++)
   		{
   			sock = call sockets.getAddr(i);
   			if(sock->src == port){ //the first available socket index gets returned
   				return sock;
   			}
   		}
   }

   socket_store_t* findSocketAddr(uint16_t addr){ //returns the index of a socket with the corresponding address
   		uint16_t i = 0;
   		socket_store_t* sock;
   		uint16_t size = call sockets.size(); //look through every socket
   		for(i = 0; i < size; i++)
   		{
   			//dbg(TRANSPORT_CHANNEL, "Looking at index %d\n", i);
   			sock = call sockets.getAddr(i);
   			if(sock->dest.addr == addr){ //the first available socket index gets returned
   				return sock;
   			}
   		}
   }

   bool transferDone(socket_store_t* sock){
   		if(sock->totalSent >= sock->transferSize)
   			return TRUE;
   		else
   			return FALSE;
   }


   uint8_t sizeOfString(char* str){
   		uint8_t offset = 0;
   		uint8_t count = 0;

   		while(*(str + offset) != '\0'){
   			offset++;
   			count++;
   		}

   		return count;
   }


   char* append(char* s, char c, uint8_t len)
	{
		/*
		s[len] = c;
		s[len+1] = '\0';
		return s;
		*/

		uint8_t i;
		char r[len+2];
		
		for(i = 0; i < len; i++){
			r[i] = s[i];
		}

		r[len] = c;

		r[len+1] = '\0';

        return r;
	}

   //LIST FUNCTIONS

   uint8_t arrSize(uint8_t* arr){
  		return sizeof(arr)/sizeof(uint8_t);
   		//return 20;
   }

   void fillArray(uint8_t* arr){
   		uint8_t i;
   		uint8_t size = arrSize(arr);

   		for(i = 0; i < size; i++){
   			arr[i] = 1;
   		}
   }





}




