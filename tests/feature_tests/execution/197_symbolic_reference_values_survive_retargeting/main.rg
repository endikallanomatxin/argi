drops :: Int32 = 0

Resource: Type = (.value: Int32)

Holder: Type = (.reference: $&Resource)

implement ImplicitlyCopyable#(Holder) ()

implement Deinit#(Resource) (.deinit = (.self: $&Resource) -> () { drops = drops + 1 })

check(.holder: $&Holder, .first: $&Resource, .second: $&Resource) -> (.result: Int32) := {
    holder&.reference = first
    saved ::= holder&.reference
    copied ::= holder&
    holder&.reference = second
    deinit(.self = second)
    result = saved&.value + copied.reference&.value
}

main() -> (.status_code: Int32) := {
    {
        owner :: Resource = Resource(.value = 1)
        first :: Resource = Resource(.value = 2)
        second :: Resource = Resource(.value = 3)
        holder :: Holder = Holder(.reference = $&owner)
        if check(.holder = $&holder, .first = $&first, .second = $&second) != 4 { abort }
    }
    if drops != 3 { abort }
    status_code = 42
}
