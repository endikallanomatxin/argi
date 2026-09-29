inherit(.raw: RawPointer#(.t: Int32), .root: &Any) -> (.reference: $&Int32) := {
    reference = establish_inherited_reference#(.t: Int32)(.raw = raw, .root = root).reference
}

escape() -> (.reference: $&Int32) := {
    value :: Int32 = 7
    raw ::= raw_pointer#(.t: Int32)(.address = UIntNative(.value = $&value)).raw
    reference = inherit(
        .raw = raw,
        .root = erase_mutable_reference#(.t: Int32)(.base = $&value).reference,
    ).reference
}

main() -> (.status_code: Int32 = 0) := {
    escaped ::= escape()
    status_code = escaped&
}
