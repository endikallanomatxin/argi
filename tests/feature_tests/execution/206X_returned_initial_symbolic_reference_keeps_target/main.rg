Resource: Type = (.value: Int32)

Holder: Type = (.reference: $&Resource)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

load_reference(.holder: &Holder) -> (.result: $&Resource) := { result = holder&.reference }

check(.holder: $&Holder) -> () := {
    saved ::= load_reference(.holder = holder)
    deinit(.self = holder&.reference)
    value ::= saved&.value
    if value == 1 { abort }
}

main() -> (.status_code: Int32) := {
    owner :: Resource = (.value = 1)
    holder :: Holder = (.reference = $&owner)
    check(.holder = $&holder)
    status_code = 42
}
