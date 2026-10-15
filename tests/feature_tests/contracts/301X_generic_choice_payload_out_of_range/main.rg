optional_byte := (.value: ?UInt8) -> (.byte: UInt8) {
    match value {
        ..none { byte = 0 }
        ..some payload { byte = payload.value }
    }
}

bad_payload#(.Marker: Type) := (.marker: Marker) -> (.byte: UInt8) {
    byte = optional_byte(.value = ..some(.value = 256))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    value ::= bad_payload(.marker = 1)
}
