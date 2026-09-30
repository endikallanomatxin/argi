main() -> (.status_code: Int32) := {
    value :: UInt8 = 7
    elements :: UIntNative = 0
    elements = elements - 1
    reference ::= reference_offset#(.t: UInt8)(.base = &value, .elements = elements).reference
    -- Do not dereference: failure must come from the arithmetic guard itself.
    status_code = 0
}
