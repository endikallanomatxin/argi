main() -> (.status_code: Int32) := {
    element :: Int32 = 0
    view ::= array_view(.data = $&element)
    set_result ::= set(.self = $&view, .index = 1, .value = 42).result
    if is(.value = set_result, .variant = ..error) {
        if is(.value = set_result..error.reason, .variant = ..out_of_bounds) {
            status_code = 0
        } else {
            status_code = 2
        }
    } else {
        status_code = 3
    }
}
