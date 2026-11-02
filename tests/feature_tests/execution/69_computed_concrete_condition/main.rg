positive := (.value: Int32) -> (.ok: Bool) { ok = value > 0 }

Counter := (.value: Int32)

read := (.source: &Counter) -> (.value: Int32) { value = source&.value }

staged := (.source: &Counter) -> (.value: Int32 = 0) {
    #if true { value = read(.source = source) }
}

main := () -> (.status_code: Int32 = 0) {
    #if positive(.value = 42) {
        #if 3 < 4 {
            status_code = 42
        } #else {
            unavailable_nested_branch()
        }
    } #else {
        unavailable_outer_branch()
    }
    #if false { unavailable_empty_branch() }
    counter := Counter(.value = 42)
    if staged(.source = &counter) != 42 { abort }
}
