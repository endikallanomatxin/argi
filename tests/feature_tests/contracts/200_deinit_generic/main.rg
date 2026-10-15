drops :: Int32 = 0
record_drop := () -> () { drops = drops + 1 }
Owner#(.T: Type): Type = (.value: T)
implement#(.T: Type) Deinit#(Owner#(T)) (
    .deinit = (.self: $&Owner#(T)) -> () { record_drop() }
)
create := () -> () { first ::= Owner#(Int32)(42) second ::= Owner#(UInt8)(7) }
main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 2 { abort }
}
