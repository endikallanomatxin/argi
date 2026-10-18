positive(.value: Int32) -> (.ok: Bool) := { ok = value > 0 }

choose#(.n: Int32)() -> (.value: Int32 = 0) := {
    #if positive(.value = n) {
        value = 42
    } #else {
        unavailable_in_selected_specialization()
    }
}

negative#(.n: Int32)() -> (.value: Int32 = 0) := {
    #if positive(.value = n) {
        unavailable_in_discarded_branch()
    } #else {
        value = 42
    }
}

both#(.n: Int32)() -> (.value: Int32 = 0) := {
    #if n > 0 { value = 42 } #else { value = 41 }
}

locals#(.n: Int32)() -> (.value: Int32 = 0) := {
    previous := 0
    #if n > 0 {
        previous := 40
        selected := 2
    } #else {
        previous := 39
        selected := 3
    }
    value = previous + selected
}

Selected#(.T: Type): Contract = (
    .selected_value : (.input: T) -> (.value: Int32)
)

implement Selected#(Int32) (
    .selected_value = (.input: Int32) -> (.value: Int32 = 0) {
        #if 1 < 2 { value = input } #else { unavailable_operation_branch() }
    }
)

main() -> (.status_code: Int32 = 0) := {
    if locals#(.n = 1)() != 42 { abort }
    if locals#(.n = -1)() != 42 { abort }
    if selected_value(.input = 42) != 42 { abort }
    if both#(.n = 1)() != 42 { abort }
    if both#(.n = -1)() != 41 { abort }
    if negative#(.n = -1)() != 42 { abort }
    status_code = choose#(.n = 1)()
}
