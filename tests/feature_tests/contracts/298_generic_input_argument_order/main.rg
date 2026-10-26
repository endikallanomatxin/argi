Packet := <.T: Type, .N: UIntNative> (.items: Array<.n = N, .t: T>)

first_named := <.T: Type: ImplicitlyCopyable, .N: UIntNative> (.packet: &Packet<.N = N, .T: T>) -> (
    .value: T, .count: UIntNative
) {
    value = packet&.items[0]
    count = N
}

first_ordered := <.T: Type: ImplicitlyCopyable, .N: UIntNative> (
    .packet: &Packet<.T: T, .N = N>
) -> (.value: T, .count: UIntNative) {
    value = packet&.items[0]
    count = N
}

Pair := <.Left: Type, .Right: Type> (.left: Left, .right: Right)

left_positional := <.Left: Type: ImplicitlyCopyable, .Right: Type> (.pair: &Pair<Left, Right>) -> (
    .value : Left
) { value = pair&.left }

left_named := <.Left: Type: ImplicitlyCopyable, .Right: Type> (
    .pair: &Pair<.Right: Right, .Left: Left>
) -> (.value: Left) { value = pair&.left }

main := () -> (.status_code: Int32 = 0) {
    normal ::= Packet<.T: UInt8, .N = 2>(.items = (250, 9))
    named ::= Packet<.N = 3, .T: Int32>(.items = (-7, 4, 2))
    a ::= first_named(.packet = &normal)
    b ::= first_ordered(.packet = &named)
    if a.value != 250 or a.count != 2 { status_code = 1 }
    if b.value != -7 or b.count != 3 { status_code = 2 }
    c ::= first_named(.packet = &named)
    d ::= first_ordered(.packet = &normal)
    if c.value != -7 or c.count != 3 { status_code = 3 }
    if d.value != 250 or d.count != 2 { status_code = 4 }
    pair_positional ::= Pair<Int32, UInt8>(.left = -9, .right = 250)
    pair_named ::= Pair<.Right: UInt8, .Left: Int32>(.left = 7, .right = 251)
    if left_named(.pair = &pair_positional).value != -9 { status_code = 5 }
    if left_positional(.pair = &pair_named).value != 7 { status_code = 6 }
}
