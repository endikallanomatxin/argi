calls :: Int32 = 0
default_value := () -> (.result: Int32) {
    calls = calls + 1
    result = 2
}
sum := (.left: Int32, .right: Int32 = default_value()) -> (.result: Int32) {
    result = left + right
}

prepare := #(.F: Function) (.left: Int32) -> (.result: inputs_of#(F)) {
    assume left := left
    result = prepare_args#(F)(.args = ())
}

main := () -> () {
    assume left := 40
    args ::= prepare_args#(sum)(.args = ())
    if calls != 1 { abort }
    if invoke#(sum)(.args = ~args) != 42 { abort }
    if calls != 1 { abort }
    generic_args ::= prepare#(sum)(.left = 40)
    if invoke#(sum)(.args = ~generic_args) != 42 { abort }
    if calls != 2 { abort }
}
