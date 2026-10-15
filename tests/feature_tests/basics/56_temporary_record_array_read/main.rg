Packet : Type = (.bytes: [3]Int32, .nested: [2][2]Int32)

packet(.calls: $&Int32) -> (.result: Packet) := {
    calls& = calls& + 1
    result = (.bytes = (10, 20, 30), .nested = ((1, 2), (3, 4)))
}

index(.calls: &Int32) -> (.result: UIntNative) := {
    if calls& == 1 { result = 2 } else { result = 0 }
}

read_generic#(.t: Type)(.value: t, .calls: $&Int32) -> (.result: Int32) := {
    result = packet(.calls = calls).nested[1][0]
}

main() -> (.status_code: Int32 = 0) := {
    calls :: Int32 = 0
    value ::= packet(.calls = $&calls).bytes[index(.calls = &calls)]
    if value != 30 or calls != 1 { status_code = 1 return }
    nested ::= packet(.calls = $&calls).nested[1][1]
    if nested != 4 or calls != 2 { status_code = 2 return }
    generic ::= read_generic(.value = 0, .calls = $&calls)
    if generic != 3 or calls != 3 { status_code = 3 }
}
