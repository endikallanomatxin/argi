Pure() -> (.result: CInt): CFunctionPointer where { no_access() }
stored :: CInt = 42
read := () -> (.result: CInt): CFunction { result = stored }
main := () -> () { callback ::= Pure(.function = read) _ = callback }
