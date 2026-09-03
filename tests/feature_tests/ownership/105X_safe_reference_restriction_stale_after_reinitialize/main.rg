Value : Type = (
    .number: UInt8
)

deinit(.self: $&Value) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 0)
    lifetime :: Value = (.number = 1)
    stale ::= restrict_reference#(.t: &UInt8)(.input = &source.number, .lifetime = &lifetime).reference
    deinit(.self = $&source)
    source = (.number = 0)
    if stale& == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&source)
    deinit(.self = $&lifetime)
}
