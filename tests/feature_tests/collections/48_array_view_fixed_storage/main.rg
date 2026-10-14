main() -> (.status_code: Int32) := {
    values :: [3]Int32 = (4, 5, 6)
    borrowed_view ::= view(.array = $&values)
    ro ::= view(.array = &values)

    if length(.self = &borrowed_view).count != 3 or length(.self = &ro).count != 3 {
        status_code = 1
        return
    }
    changed ::= set#(.t: Int32)(.self = $&borrowed_view, .index = 1, .value = 9).result
    if is(.value = changed, .variant = ..error) {
        status_code = 2
        return
    }
    observed ::= get_ro_ref(.self = &ro, .index = 1).result
    if is(.value = observed, .variant = ..error) {
        status_code = 3
        return
    }
    if observed..ok& != 9 {
        status_code = 4
        return
    }
    status_code = 0
}
