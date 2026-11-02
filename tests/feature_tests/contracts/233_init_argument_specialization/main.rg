Packet := #(.T: Type) (.kind: Int32)

PacketInitArgs: Type = #(.T: Type) (.value: T)

implement#(.T: Type) Init#(Packet#(T), PacketInitArgs#(T)) (
    .Result : Type = Packet#(T)

    .init = PacketInitArgs#(T) -> (.result: Result) { result = (.kind = 1) }
)

PacketInitArgs2: Type = PacketInitArgs#(Int32)

implement Init#(Packet#(Int32), PacketInitArgs2) (
    .Result : Type = Packet#(Int32)

    .init = PacketInitArgs2 -> (.result: Result) { result = (.kind = 2) }
)

main := () -> (.status_code: Int32 = 0) {
    integer :: Int32 = 42
    byte :: UInt8 = 7
    specialized ::= Packet(.value = integer)
    generic ::= Packet(.value = byte)
    if specialized.kind != 2 or generic.kind != 1 { abort }
}
