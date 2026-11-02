Comparator(.left: CInt, .right: CInt) -> (.result: CInt): CFunctionPointer

compare := once (.left: CInt, .right: CInt) -> (.result: CInt): CFunction { result = left }

main := () -> () { callback := Comparator(.function = compare) }
