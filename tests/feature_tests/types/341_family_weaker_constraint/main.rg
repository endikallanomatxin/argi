Unrestricted := <.T: Type> (.value: T)

make := <.Family: <.T: Type: ImplicitlyCopyable<T>> Type> () -> (.result: Family<Int32>) {
    result = (.value = 42)
}

compute := () -> (.result: Int32) {
    value ::= make<.Family = Unrestricted>()
    result = value.value
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = compute()
}
