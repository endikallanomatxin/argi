Value : Type = (
    .number: UInt8
)

Holder : Type = (
    .reference: &UInt8
)

deinit(.self: $&Value) -> () := {
}

deinit(.self: $&Holder) -> () := {
}

main() -> (.status_code: Int32) := {
    source :: Value = (.number = 0)
    lifetime :: Value = (.number = 1)
    held :: Holder = (.reference = restrict_reference#(.t: &UInt8)(.input = &source.number, .lifetime = &lifetime).reference)
    destination :: Holder = (.reference = &source.number)
    deinit(.self = $&destination)
    relocate(.source = $&held, .destination = $&destination)
    deinit(.self = $&lifetime)
    if destination.reference& == 0 {
        status_code = 0
    } else {
        status_code = 1
    }
    deinit(.self = $&source)
}
