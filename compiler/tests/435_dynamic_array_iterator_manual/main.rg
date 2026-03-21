main () -> (.status_code: Int32) := {
    dyn :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $&dyn)

    push(.self = $&dyn, .value = 10)
    push(.self = $&dyn, .value = 20)
    push(.self = $&dyn, .value = 30)

    it ::= to_iterator(.value = &dyn)
    sum :: Int32 = 0

    while has_next(.self = &it) {
        value :: Int32 = next(.self = $&it)
        sum = sum + value
    }

    if sum != 60 {
        status_code = 1
        return
    }

    status_code = 0
}
