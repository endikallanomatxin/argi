Closable : Abstract = (
    close(.self: $&Self) -> ()
)

Closing : Type = (.value: Int32)
Keeping : Type = (.value: Int32)
Closing implements Closable
Keeping implements Closable

deinit(.self: $&Closing) -> () := {
}

close(.self: $&Closing) -> () := {
    deinit(.self = self)
}

close(.self: $&Keeping) -> () := {
}

register_keeping(.value: $&Keeping) -> () := {
    unused ::= to_virtual#(.abstract: Closable)(.value = value)
}

main() -> (.status_code: Int32) := {
    keeping :: Keeping = (.value = 0)
    register_keeping(.value = $&keeping)
    value :: Closing = (.value = 0)
    virtual ::= to_virtual#(.abstract: Closable)(.value = $&value)
    close(.self = $&virtual)
    status_code = value.value
}
