Copy#(.T: Type): Contract = (.copy: (.value: T) -> (.result: T))

implement Copy#(Int32) (.copy = (.value: Int32) -> (.result: Int32) { result = value })

copy := (.value: UInt8) -> (.result: UInt8) { result = value }

main := () -> (.status_code: Int32 = 0) {
    integer: Int32 = 42
    byte: UInt8 = 7
    if copy(integer).result != 42 { abort }
    if copy(byte).result != 7 { abort }
}
