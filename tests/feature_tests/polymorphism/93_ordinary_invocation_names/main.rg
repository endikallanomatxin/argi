invoke := (.x: Int32) -> (.result: Int32) { result = x + 1 }
prepare_args := (.x: Int32) -> (.result: Int32) { result = x * 2 }
forward := #(.T: Type) (.x: T) -> (.result: T) {
    result = invoke(.x = prepare_args(.x = x))
}
main := () -> () {
    if invoke(.x = 41) != 42 { abort }
    if forward#(Int32)(.x = 20) != 41 { abort }
}
