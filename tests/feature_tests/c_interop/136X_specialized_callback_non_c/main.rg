Callback(.value: CInt) -> (.result: CInt): CFunctionPointer
identity := #(.T: Type) (.value: T) -> (.result: T) { result = value }
main := () -> () { callback ::= Callback(.function = identity#(CInt)) _ = callback }
