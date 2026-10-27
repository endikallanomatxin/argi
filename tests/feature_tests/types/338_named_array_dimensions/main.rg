count := 2

sum := #(.N: UIntNative) (.values: [N]Int32) -> (.result: Int32) {
    result = values[0] + values[1]
}

compute := () -> (.result: Int32) {
    values: [count]Int32 = (20, 22)
    ordinary: Array#(.n = count, .t: Int32) = values
    result = sum(.values = ordinary)
}

known ::= #run () -> (.result: Int32) { result = compute() }

main := () -> (.status_code: Int32) {
    if known != 42 { abort }
    status_code = compute()
}
