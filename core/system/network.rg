Network : Type = ()

once Network init() -> (.result: Network) := {
    result = ()

}

-- Consider whether all network protocols belong here too.
-- Perhaps they do not belong under system.

---
-- socket :: Family → SocketType → ProtocolNumber → IO Socket
-- Creates a low-level socket.
-- connect :: Socket → SockAddr → IO ()
-- Connects a socket to a remote address.
-- bind :: Socket → SockAddr → IO ()
-- Binds a socket to a local address.
-- listen :: Socket → Int → IO ()
-- Puts a socket into listening mode with the given backlog.
-- accept :: Socket → IO (Socket, SockAddr)
-- Accepts an incoming connection and returns a new socket and the client address.
-- recv :: Socket → Int → IO ByteString
-- Receives up to N bytes from the socket.
-- send :: Socket → ByteString → IO Int
-- Sends data through the socket and returns the number of bytes sent.
---
