plain := (.value: Int32) -> (.result: Int32) { result = value }
Borrowed := (.value: &Int32)
borrowed := (.value: Borrowed) -> (.result: Int32) { result = value.value& }
identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
plain_identity := identity#(Int32)
borrowed_identity := identity#(Borrowed)
check := #(.F: Function) () -> (.result: Bool) {
    #if is_plain_data(.type = inputs_of#(F)) and is_plain_data(.type = result_of#(F)) {
        result = true
    } #else { result = false }
}
main := () -> () {
    if check#(plain)() {} else { abort }
    if check#(borrowed)() { abort }
    if check#(plain_identity)() {} else { abort }
    if check#(borrowed_identity)() { abort }
    if check#(plain_identity)() {} else { abort }
}
