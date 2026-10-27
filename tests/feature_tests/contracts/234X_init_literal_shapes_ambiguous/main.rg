Packet := (.value: Int32)

implement Init#(Packet, (.value: Int32)) (
    .Result : Type = Packet
    .init   = (.args: (.value: Int32)) -> (.result: Result) { result = (.value = args.value) }
)

implement Init#(Packet, (.value: UInt64)) (
    .Result : Type = Packet
    .init   = (.args: (.value: UInt64)) -> (.result: Result) { result = (.value = 0) }
)

main := () -> () { packet ::= Packet(.value = 10) }
