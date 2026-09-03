main(.system: System = System()) -> (.status_code: Int32) := {
    source ::= DynamicArray#(.t: UIntNative)(.capacity = 1)
    destination ::= DynamicArray#(.t: UIntNative)(.capacity = 1)

    push#(.t: UIntNative)(.self = $&source, .value = 7)
    value ::= source[0]
    push#(.t: UIntNative)(.self = $&destination, .value = value)

    deinit#(.t: UIntNative)(.self = $&source)
    if destination[0] != 7 {
        deinit#(.t: UIntNative)(.self = $&destination)
        status_code = 1
        return
    }

    deinit#(.t: UIntNative)(.self = $&destination)
    status_code = 0
}
