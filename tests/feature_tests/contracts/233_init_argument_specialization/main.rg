Packet := #(.T: Type) (.kind: Int32)

implement#(.T: Type) Init#(Packet#(T)) (
    .init = (.value: T) -> (.result: Packet#(T)) { result = (.kind = 1) }
)

implement Init#(Packet#(Int32)) (
    .init = (.value: Int32) -> (.result: Packet#(Int32)) { result = (.kind = 2) }
)

main := () -> (.status_code: Int32 = 0) {
    integer :: Int32 = 42
    byte :: UInt8 = 7
    specialized ::= Packet(.value = integer)
    generic ::= Packet(.value = byte)
    if specialized.kind != 2 or generic.kind != 1 { abort }
}
