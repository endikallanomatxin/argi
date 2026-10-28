Cell := #(.T: Type) (.value: T)

Args := (.cell: Cell#(Int32))

read := Args -> (.value: Int32) { value = cell.value }

make := #(.T: Type) (.value: T) -> (.result: Cell#(T)) {
    local: Cell#(T) = (.value = value)
    result = (.value = local.value)
}

known ::= #run () -> (.result: Int32) {
    cell ::= make(42)
    result = cell.value
}

DefaultBox := #(.T: Type, .n: UIntNative = 4) (.items: [n]T)

DefaultBoxArgs := #(.T: Type) (.value: T)

implement#(.T: Type) Init#(DefaultBox#(T), DefaultBoxArgs#(T)) (
    .Result : Type = DefaultBox#(T)
    .init   = DefaultBoxArgs#(T) -> (.result: Result) {
        result = (.items = (value, value, value, value))
    }
)

read_default := #(.T: Type) (.box: &DefaultBox#(T)) -> (.result: T) {
    result = box&.items[3]
}

DefaultPair := #(.T: Type, .Other: Type = T) (.first: T, .second: Other)

read_pair := #(.T: Type) (.pair: DefaultPair#(T)) -> (.result: T) {
    result = pair.second
}

known_default ::= #run () -> (.result: Int32) {
    box ::= DefaultBox#(Int32)(.value = 42)
    result = read_default(&box)
}

main := () -> (.status_code: Int32 = 0) {
    cell ::= make(42)
    if cell.value != 42 or known != 42 { status_code = 1 }
    if read(.cell = (.value = 42)) != 42 { status_code = 2 }
    box ::= DefaultBox#(Int32)(.value = 42)
    inferred ::= DefaultBox(.value = 42)
    if read_default(&box) != 42 or read_default(&inferred) != 42 { status_code = 3 }
    if known_default != 42 { status_code = 4 }
    pair: DefaultPair#(Int32) = (.first = 1, .second = 42)
    if read_pair(pair) != 42 { status_code = 5 }
}
