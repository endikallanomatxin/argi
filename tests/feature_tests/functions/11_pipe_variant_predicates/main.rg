Result: Type = (..ok(.value: Int32), ..error(.code: UnicodeScalar))

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    failed: Result = ..error(.code = 'x')
    named ::= failed | is(.value = _, .variant = ..error)
    positional ::= failed | is(_, ..error)
    direct ::= is(failed, ..error)
    if named != true or positional != true or direct != true { abort }
    succeeded: Result = ..ok(.value = 42)
    wrong_named ::= succeeded | is(.value = _, .variant = ..error)
    wrong_positional ::= succeeded | is(_, ..error)
    if wrong_named or wrong_positional { abort }
}
