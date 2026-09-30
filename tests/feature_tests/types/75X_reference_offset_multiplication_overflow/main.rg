main() -> (.status_code: Int32) := {
    value :: UIntNative = 7
    elements :: UIntNative = 0
    elements = elements - 1
    elements = elements / 2 + 1
    reference ::= trusted_reference_offset#(.t: UIntNative)(.base = &value, .elements = elements).reference
    -- Do not dereference: failure must come from the arithmetic guard itself.
    status_code = 0
}
