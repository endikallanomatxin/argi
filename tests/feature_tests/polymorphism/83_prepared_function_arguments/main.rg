default_calls :: Int32 = 0
producer_calls :: Int32 = 0

next_default := (.amount: Int32) -> (.result: Int32) {
    default_calls = default_calls + 1
    result = amount
}

with_default := (.value: Int32 = next_default().result, .extra: Int32) -> (.result: Int32) {
    result = value + extra
}

produce := () -> (.result: inputs_of#(with_default)) {
    producer_calls = producer_calls + 1
    assume amount := 40
    result = (.extra = 2)
}

Token := (.value: Int32)
read_token := (.token: &Token) -> (.result: Int32) { result = token&.value }

nothing := () -> () {}
pair := (.value: Int32) -> (.first: Int32, .second: Int32) {
    first = value
    second = value + 1
}
identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
fixed := identity#(Int32)

main := () -> () {
    assume amount := 40
    prepared: inputs_of#(with_default) = (.extra = 2)
    if default_calls != 1 { abort }
    if invoke#(with_default)(.args = ~prepared).result != 42 { abort }
    if default_calls != 1 { abort }
    if invoke#(with_default)(.args = produce().result).result != 42 { abort }
    if producer_calls != 1 { abort }
    if default_calls != 2 { abort }

    token ::= Token(42)
    assume token_ref := &token
    token_args: inputs_of#(read_token) = (.token = token_ref)
    if invoke#(read_token)(.args = ~token_args).result != 42 { abort }

    no_args: inputs_of#(nothing) = ()
    invoke#(nothing)(.args = ~no_args)
    pair_args: inputs_of#(pair) = (.value = 41)
    output: result_of#(pair) = invoke#(pair)(.args = ~pair_args)
    if output.first != 41 { abort }
    if output.second != 42 { abort }
    fixed_args: inputs_of#(fixed) = (.value = 42)
    if invoke#(fixed)(.args = ~fixed_args).result != 42 { abort }
}
