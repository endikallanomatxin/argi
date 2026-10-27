Packet := (.kind: Int32)

implement#(.T: Type) Init#(Packet, (.value: T)) (
    .Result : Type = Packet
    .init   = (.args: (.value: T)) -> (.result: Result) { result = (.kind = 1) }
)

implement Init#(Packet, (.value: Int32)) (
    .Result : Type = Packet
    .init   = (.args: (.value: Int32)) -> (.result: Result) { result = (.kind = 2) }
)

main := () -> (.status_code: Int32 = 0) {
    integer :: Int32 = 42
    byte :: UInt8 = 7
    specialized ::= Packet(.value = integer)
    generic ::= Packet(.value = byte)
    if specialized.kind != 2 or generic.kind != 1 { abort }
}
