Network : Type = ()

-- No se si meter también aquí todos los protocolos de red
-- O eso igual no corresponde a system

---
-- socket :: Family → SocketType → ProtocolNumber → IO Socket
-- Crea un socket de bajo nivel.
-- connect :: Socket → SockAddr → IO ()
-- Conecta un socket a una dirección remota.
-- bind :: Socket → SockAddr → IO ()
-- Asocia un socket a una dirección local.
-- listen :: Socket → Int → IO ()
-- Pone un socket en modo escucha, con backlog dado.
-- accept :: Socket → IO (Socket, SockAddr)
-- Acepta una conexión entrante, devolviendo un nuevo socket y la dirección del cliente.
-- recv :: Socket → Int → IO ByteString
-- Recibe hasta N bytes del socket.
-- send :: Socket → ByteString → IO Int
-- Envía datos por el socket; devuelve cuántos bytes se enviaron.
---
