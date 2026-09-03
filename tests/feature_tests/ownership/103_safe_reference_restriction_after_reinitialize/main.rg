Value : Type = (
    .number: UInt8
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 0)
    lifetime :: Value = (.number = 1)
    deinit(.self = $&source)
    source = (.number = 0)
    fresh ::= restrict_reference#(.t: &UInt8)(.input = &source.number, .lifetime = &lifetime).reference
    if fresh& == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&source)
    deinit(.self = $&lifetime)
}
