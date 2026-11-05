Invalid(.value: CInt) -> (.result: CInt): CFunctionPointer where { reads(value) }
body := (.value: CInt) -> (.result: CInt): CFunction { result = value }
main := () -> () { callback ::= Invalid(.function = body) _ = callback }
