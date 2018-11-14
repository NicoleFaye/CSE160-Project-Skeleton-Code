/**
 * ANDES Lab - University of California, Merced
 * This class provides the basic functions of a network node.
 *
 * @author UCM ANDES Lab
 * @date   2013/09/03
 *
 */

#include <Timer.h>
#include "includes/CommandMsg.h"
#include "includes/packet.h"
#include "includes/socket.h"

configuration NodeC{
}
implementation {
    components MainC;
    components Node;
    components new AMReceiverC(AM_PACK) as GeneralReceive;

    //LISTS
    components new ListC(neighbor,64) as nListC;
    components new ListC(neighbor,64) as nRefresherC;
    components new ListC(pack,64) as prevPacksC;
    components new ListC(route,64) as routeTableC;
    components new ListC(route,64) as forwardTableC;
    components new ListC(socket_store_t,MAX_NUM_OF_SOCKETS) as socketsC;

    //TIMERS
    components new TimerMilliC() as ntimerC;
    components new TimerMilliC() as rtimerC;
    components new TimerMilliC() as TCPtimerC;


    Node -> MainC.Boot;

    Node.Receive -> GeneralReceive;

    components ActiveMessageC;
    Node.AMControl -> ActiveMessageC;

    components new SimpleSendC(AM_PACK);
    Node.Sender -> SimpleSendC;

    components CommandHandlerC;
    Node.CommandHandler -> CommandHandlerC;

    //LISTS
    Node.nList -> nListC;
    Node.nRefresher -> nRefresherC;
    Node.prevPacks -> prevPacksC;
    Node.routeTable -> routeTableC;
    Node.forwardTable -> forwardTableC;
    Node.sockets -> socketsC;

    //TIMERS
    Node.ntimer -> ntimerC;
    Node.rtimer -> rtimerC;
    Node.TCPtimer -> TCPtimerC;
}
