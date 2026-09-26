value(.number: Int32 = 3) -> (.result: Int32) := {
    result = number
}

nested(.number: Int32) -> (.result: Int32) := {
    result = value().result
}

main() -> (.status_code: Int32 = 0) := {
    number :: Int32 = 42
    assume number
    if value().result != 42 { status_code = 1 }
    if value(.number = 7).result != 7 { status_code = 2 }
    if nested().result != 3 { status_code = 3 }
    if generic().result != 42 { status_code = 4 }
    if forward().result != 42 { status_code = 5 }
    number = 43
    if value().result != 43 { status_code = 6 }
    if true {
        number :: Int32 = 9
        if value().result != 3 { status_code = 7 }
        assume number
        if value().result != 9 { status_code = 8 }
    }
    if value().result != 43 { status_code = 9 }
    unused :: Int32 = 10
    assume unused
    if value().result != 43 { status_code = 10 }
    if true {
        assume number := value().result + 1
        if value().result != 44 { status_code = 11 }
        if forward().result != 44 { status_code = 12 }
    }
    if value().result != 43 { status_code = 13 }
    if compact_generic(.number = 17).result != 18 { status_code = 14 }
    if true {
        assume number :: Int32 = 20
        number = 21
        if value().result != 21 { status_code = 15 }
    }
}

generic #(.t: Type) (.number: t) -> (.result: t) := {
    result = number
}

forward #(.t: Type) (.number: t) -> (.result: t) := {
    assume number
    result = generic().result
}

compact_generic #(.t: Type) (.number: t) -> (.result: t) := {
    assume number ::= number + 1
    result = generic().result
}
