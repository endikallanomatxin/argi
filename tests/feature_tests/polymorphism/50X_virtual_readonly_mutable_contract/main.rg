Counter: Abstract = (bump(.self: $&Self) -> () where {})

Box: Type = (.value: Int32)

Box implements Counter

bump(.self: $&Box) -> () := { self&.value = self&.value + 1 }

main() -> (.status_code: Int32 = 0) := {
    box :: Box = (.value = 7)
    readonly ::= &box
    handle ::= to_virtual#(.abstract: Counter)(.value = readonly)
    bump(.self = $&handle)
}
