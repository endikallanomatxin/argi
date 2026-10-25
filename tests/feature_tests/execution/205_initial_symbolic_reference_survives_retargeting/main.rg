Resource: Type = (.value: Int32)

Holder: Type = (.reference: $&Resource)

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () {})

check(.holder: $&Holder, .other: $&Resource) -> (.result: Int32) := {
    saved ::= holder&.reference
    holder&.reference = other
    deinit(.self = other)
    result = saved&.value
}

main() -> (.status_code: Int32) := {
    owner :: Resource = (.value = 1)
    other :: Resource = (.value = 2)
    holder :: Holder = (.reference = $&owner)
    if check(.holder = $&holder, .other = $&other) != 1 { abort }
    status_code = 42
}
