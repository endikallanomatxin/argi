main() -> (.status_code: Int32) := {
    values :: [3]Int32 = (4, 5, 6)
    view ::= array_view#(.n = 3, .t: Int32)(.array = $&values)
    ro ::= array_view_ro#(.n = 3, .t: Int32)(.array = &values)

    if length#(.t: Int32)(.self = &view).count != 3 or length#(.t: Int32)(.self = &ro).count != 3 {
        status_code = 1
        return
    }
    changed ::= set#(.t: Int32)(.self = $&view, .index = 1, .value = 9).result
    if is(.value = changed, .variant = ..error) {
        status_code = 2
        return
    }
    observed ::= get_ro_ref#(.t: Int32)(.self = &ro, .index = 1).result
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
