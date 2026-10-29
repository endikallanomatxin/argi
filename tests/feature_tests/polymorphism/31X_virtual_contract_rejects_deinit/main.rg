Closable#(.Participant: Type): Contract = (
    .close : (.self: $&Participant) -> () where {}
)

Closing := (.value: Int32)

Keeping := (.value: Int32)

implement Closable#(Closing) (.close = _impl_close_Closing)

implement Closable#(Keeping) (.close = _impl_close_Keeping)

implement Deinit#(Closing) (
    .deinit = (.self: $&Closing) -> () {

    }
)

_impl_close_Closing := (.self: $&Closing) -> () {
    deinit(.self = self)
}

_impl_close_Keeping := (.self: $&Keeping) -> () {
}

register_keeping := (.value: $&Keeping) -> () {
    unused ::= to_virtual#(.contract: Closable)(.value = value)
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    keeping :: Keeping = (.value = 0)
    register_keeping(.value = $&keeping)
    value :: Closing = (.value = 0)
    virtual ::= to_virtual#(.contract: Closable)(.value = $&value)
    close(.self = $&virtual)
    status_code = value.value
}
