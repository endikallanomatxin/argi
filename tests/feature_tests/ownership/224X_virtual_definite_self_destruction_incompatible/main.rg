Closable : Abstract = (
    close(.self: $&Self) -> ()
)

drops :: Int32 = 0

First : Type = (.value: Int32)
Second : Type = (.value: Int32)
First implements Closable
Second implements Closable

deinit(.self: $&First) -> () := {
    drops = drops + 1
}

deinit(.self: $&Second) -> () := {
    drops = drops + 1
}

close(.self: $&First) -> () := {
    deinit(.self = self)
}

close(.self: $&Second) -> () := {
    deinit(.self = self)
}

register_second(.value: $&Second) -> () := {
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
    second :: Second = (.value = 0)
    register_second(.value = $&second)
    value :: First = (.value = 0)
    virtual ::= to_virtual#(.abstract: Closable)(.value = $&value)
    close(.self = $&virtual)
}
