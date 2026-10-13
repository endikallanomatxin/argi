drops :: Int32 = 0
record_drop := () -> () { drops = drops + 1 }
record_specialized_drop := () -> () { drops = drops + 10 }
Owner#(.T: Type): Type = (.value: T)
implement#(.T: Type) Deinit#(Owner#(T)) (
    .deinit = (.self: $&Owner#(T)) -> () { record_drop() }
)
implement Deinit#(Owner#(Int32)) (
    .deinit = (.self: $&Owner#(Int32)) -> () { record_specialized_drop() }
)
create := () -> () {
    first ::= Owner#(Int32)(42)
    second ::= Owner#(UInt8)(7)
    deinit($&first)
}
main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 11 { abort }
}
