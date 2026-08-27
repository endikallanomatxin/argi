Value : Type = (
    .number: UInt8
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 0)
    lifetime :: Value = (.number = 1)
    original ::= &source.number
    restricted ::= restrict_reference#(.t: &UInt8)(.input = original, .lifetime = &lifetime).reference
    deinit(.self = $&source)
    if restricted& == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
}
