main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    left :: Int16 = 1
    right :: UInt16 = 2
    value ::= checked_add(.left = left, .right = right)
}
