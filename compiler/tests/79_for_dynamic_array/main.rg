main () -> (.status_code: Int32) := {
    dyn :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $&dyn)
    push(.self = $&dyn, .value = 7)
    push(.self = $&dyn, .value = 8)

    dynamic_sum :: Int32 = 0
    for value in dyn {
        dynamic_sum = dynamic_sum + value
    }

    if dynamic_sum != 15 {
        status_code = 1
        return
    }

    status_code = 0
}
