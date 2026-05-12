main() -> (.status_code: Int32) := {
    point := Point(20, 22)

    if is_origin(.self = point) {
        status_code = 1
        return
    }

    if uses_sum(.self = point) {
        status_code = 0
        return
    }

    status_code = 2
}
