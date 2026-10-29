Closable#(.Participant: Type): Contract = (
    .close : (.self: $&Participant) -> () where {}
)

drops :: Int32 = 0

First := (.value: Int32)

Second := (.value: Int32)

implement Closable#(First) (.close = _impl_close_First)

implement Closable#(Second) (.close = _impl_close_Second)

implement Deinit#(First) (
    .deinit = (.self: $&First) -> () {
        drops = drops + 1
    }
)

implement Deinit#(Second) (
    .deinit = (.self: $&Second) -> () {
        drops = drops + 1
    }
)

_impl_close_First := (.self: $&First) -> () {
    deinit(.self = self)
}

_impl_close_Second := (.self: $&Second) -> () {
    deinit(.self = self)
}

register_second := (.value: $&Second) -> () {
    _ ::= to_virtual#(.contract: Closable)(.value = value)
}

verify := (.status: $&Int32) -> () {
    if drops == 1 {
        status&= 0
    } else {
        status&= 7
    }
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    status_code = 9
    defer verify(.status = $&status_code)
    second :: Second = (.value = 0)
    register_second(.value = $&second)
    value :: First = (.value = 0)
    virtual ::= to_virtual#(.contract: Closable)(.value = $&value)
    close(.self = $&virtual)
}
