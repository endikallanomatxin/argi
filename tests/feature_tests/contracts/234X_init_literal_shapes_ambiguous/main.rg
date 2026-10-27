Packet := (.value: Int32)

implement Init#(Packet) (
    .init = (.value: Int32) -> (.result: Packet) { result = (.value = value) }
)

implement Init#(Packet) (
    .init = (.value: UInt64) -> (.result: Packet) { result = (.value = 0) }
)

main := () -> () { packet ::= Packet(.value = 10) }
