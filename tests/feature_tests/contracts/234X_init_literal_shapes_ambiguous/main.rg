Packet := (.value: Int32)

PacketInitArgs: Type = (.value: Int32)

implement Init#(Packet, PacketInitArgs) (
    .Result : Type = Packet

    .init = PacketInitArgs -> (.result: Result) { result = (.value = value) }
)

PacketInitArgs2: Type = (.value: UInt64)

implement Init#(Packet, PacketInitArgs2) (
    .Result : Type = Packet

    .init = PacketInitArgs2 -> (.result: Result) { result = (.value = 0) }
)

main := () -> () { packet ::= Packet(.value = 10) }
