Closable#(.Participant: Type): Contract = (
    .close: (.self: $&Participant) -> () where {}
)

drops :: Int32 = 0

Closing: Type = (.value: Int32)

Keeping: Type = (.value: Int32)

implement Closable#(Closing) (.close = _impl_close_Closing)
implement Closable#(Keeping) (.close = _impl_close_Keeping)

implement Deinit#(Closing) (
    .deinit = (.self: $&Closing) -> () {
        drops = drops + 1
    }
)

_impl_close_Closing := (.self: $&Closing) -> ()  {
    deinit(.self = self)
}

_impl_close_Keeping := (.self: $&Keeping) -> ()  {}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.contract: Closable)(.value = value)
}

verify(.status: $&Int32) -> () := {
    if drops == 1 {
        status&= 0
    } else {
        status&= 7
    }
}

main() -> (.status_code: Int32) := {
    status_code = 9
    #defer verify(.status = $&status_code)
    keeping :: Keeping = (.value = 0)
    register_keeping(.value = $&keeping)
    value :: Closing = (.value = 0)
    virtual ::= to_virtual#(.contract: Closable)(.value = $&value)
    close(.self = $&virtual)
}
