accept_c_text := (.text: &CChar) -> (.ok: Bool = true) {}

forward_text := <.Value: Type> (.value: Value) -> (.ok: Bool) {
    ok = accept_c_text(.text = "contextual text").ok
}

known ::= #run () -> (.result: Bool) {
    result = forward_text(.value = true).ok
}

main := () -> () {
    if accept_c_text(.text = "direct text").ok {} else { abort }
    if forward_text(.value = true).ok {} else { abort }
    if known {} else { abort }
}
