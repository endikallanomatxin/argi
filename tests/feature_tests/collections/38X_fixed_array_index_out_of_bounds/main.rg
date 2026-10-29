main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    values :: [2]Int32 = (10, 20)
    index ::= length(.self = system.args).count + 1
    value ::= values[index]
    status_code = value
}
