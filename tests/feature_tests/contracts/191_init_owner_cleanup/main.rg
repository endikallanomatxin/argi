drops :: Int32 = 0
Owner: Type = (.value: Int32)
Owner deinit(.self: $&Owner) -> () := { drops = drops + 1 }
implement Init#(Owner) (
    .Args: Type = (.value: Int32)
    .Result: Type = Owner
    .init = (.args: Args) -> (.result: Result) { result = (.value = args.value) }
)
create := () -> () { value ::= Owner(.value = 42) }
main := () -> (.status_code: Int32 = 0) {
    create()
    if drops != 1 { abort }
}
