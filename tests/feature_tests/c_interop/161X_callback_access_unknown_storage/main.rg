Pure(.address: UIntNative) -> (.result: CInt): CFunctionPointer where { no_access() }
helper := (.address: UIntNative) -> (.result: CInt) {
    anchor: UInt8 = 0
    reference ::= trusted_establish_inherited_reference#(CInt)(
        .raw = raw_pointer#(CInt)(.address = address),
        .root = erase_reference#(UInt8)(.base = &anchor)
    )
    result = reference&
}
read := (.address: UIntNative) -> (.result: CInt): CFunction { result = helper(address) }
main := () -> () { callback ::= Pure(.function = read) _ = callback }
