Closable : Abstract = (
    close(.self: $&Self) -> ()
)

drops :: Int32 = 0

Closing : Type = (.value: Int32)
Keeping : Type = (.value: Int32)
Closing implements Closable
Keeping implements Closable

deinit(.self: $&Closing) -> () := {
    drops = drops + 1
}

close(.self: $&Closing) -> () := {
    deinit(.self = self)
}

close(.self: $&Keeping) -> () := {}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.abstract: Closable)(.value = value)
}

verify(.status: $&Int32) -> () := {
    if drops == 1 {
        status& = 0
    } else {
        status& = 7
    }
}

main() -> (.status_code: Int32) := {
    status_code = 9
    #defer verify(.status = $&status_code)
    keeping :: Keeping = (.value = 0)
    register_keeping(.value = $&keeping)
    value :: Closing = (.value = 0)
    virtual ::= to_virtual#(.abstract: Closable)(.value = $&value)
    close(.self = $&virtual)
}
