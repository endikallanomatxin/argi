plain ::= #run () -> (.left: Int32, .right: Int32) {
    left = 20
    right = 22
}
host ::= #run (.system: System) -> (.left: Int32, .right: Int32) {
    left = 19
    right = 23
}

compute := #(.T: Type) (.value: T) -> (.result: T) {
    result = #run () -> (.result: T) { result = 42 }
}

main := () -> (.status_code: Int32) {
    if plain.left + plain.right != 42 { abort }
    if host.left + host.right != 42 { abort }
    status_code = compute#(Int32)(.value = 0)
}
