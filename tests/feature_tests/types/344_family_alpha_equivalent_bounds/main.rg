Related#(.Left: Type, .Right: Type): Contract = ()

PointerArguments := #(.Item: Type: Related#(&Item, Int32)) (.value: Item)

accept_pointer := #(.Family: #(.T: Type: Related#(&T, Int32)) Type) () -> () {}

Arguments := #(.Item: Type: ImplicitlyCopyable#(Item)) (.value: Item)

make := #(.Family: #(.T: Type: ImplicitlyCopyable#(T)) Type) () -> (.result: Family#(Int32)) {
    result = (.value = 42)
}

compute := () -> (.result: Int32) {
    value ::= make#(.Family = Arguments)()
    result = value.value
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    accept_pointer#(.Family = PointerArguments)()
    status_code = compute()
}
