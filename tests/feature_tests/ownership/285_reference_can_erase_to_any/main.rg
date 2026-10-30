main := (.system: System) -> (.status_code: Int32) {

    value :: Int32 = 7
    erased ::= trusted_reinterpret_reference#(.from: Int32, .to: Any)(.base = &value).reference
    if erased | convert#(.to: UIntNative)(_) != &value | convert#(.to: UIntNative)(_) {
        status_code = 1
        return
    }
    status_code = 0
}
