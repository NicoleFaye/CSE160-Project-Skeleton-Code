interface CommandHandler{
   // Events
   event void ping(uint16_t destination, uint8_t *payload);
   event void printNeighbors();
   event void printRouteTable();
   event void printLinkState();
   event void printDistanceVector();
   event void setTestServer(uint8_t port);
   event void setTestClient(uint16_t dest, uint8_t srcPort, uint8_t destPort, uint16_t num);
   event void setAppServer();
   event void setAppClient();
   event void closeConnection(uint16_t dest, uint8_t srcPort, uint8_t destPort);
   event void setServer(uint8_t port);
   event void setClient(uint16_t dest, uint8_t srcPort, uint8_t destPort);
   event void sendMsg(uint8_t port, uint8_t* msg, uint8_t length);
}
