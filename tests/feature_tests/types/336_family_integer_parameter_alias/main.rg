Count := UIntNative

Items := <.count: Count> (.values: [count]Int32)

Nested := <.Family: <.count: Count> Type> (.flag: Bool)

make := <.Family: <.count: UIntNative> Type> () -> (.result: Family<.count = 2>) {
    result = (.values = (20, 22))
}

accept_nested := <.Outer: <.Family: <.count: UIntNative> Type> Type> () -> () {}

compute := () -> (.result: Int32) {
    values ::= make<.Family = Items>()
    accept_nested<.Outer = Nested>()
    result = values.values[0] + values.values[1]
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = compute()
}
