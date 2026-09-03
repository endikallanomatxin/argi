..first
..shared
..second

Left : Type = (..first, ..shared)
Right : Type = (..shared, ..second)
make(.select_second: Bool) -> (.result: choice_union#(.a: Left, .b: Right)) := {
    if select_second {
        result = ..second
    } else {
        result = ..shared
    }
}

make_reversed() -> (.result: choice_union#(.a: Right, .b: Left)) := {
    result = ..first
}

main(.system: System = System()) -> (.status_code: Int32 = 0) := {
    combined ::= make(.select_second = false)
    match combined {
        ..first { status_code = 1 }
        ..shared { status_code = 0 }
        ..second { status_code = 2 }
    }
    reversed ::= make_reversed()
    match reversed {
        ..first {}
        ..shared { status_code = 3 }
        ..second { status_code = 4 }
    }
}
