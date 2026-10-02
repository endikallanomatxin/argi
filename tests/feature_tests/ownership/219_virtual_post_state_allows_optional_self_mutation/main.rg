Mutator : Abstract = (
    mutate(.self: $&Self) -> ()
)

Keeping : Type = (.counter: Int32)
Mutating : Type = (.counter: Int32)
Keeping implements Mutator
Mutating implements Mutator

mutate(.self: $&Keeping) -> () := {}

mutate(.self: $&Mutating) -> () := {
    self&.counter = self&.counter + 1
}

register_keeping(.value: $&Keeping) -> () := {
    _ ::= to_virtual#(.abstract: Mutator)(.value = value)
}

main() -> (.status_code: Int32) := {
    keeping :: Keeping = (.counter = 0)
    register_keeping(.value = $&keeping)
    value :: Mutating = (.counter = 0)
    virtual ::= to_virtual#(.abstract: Mutator)(.value = $&value)
    mutate(.self = $&virtual)
    status_code = value.counter - 1
}
