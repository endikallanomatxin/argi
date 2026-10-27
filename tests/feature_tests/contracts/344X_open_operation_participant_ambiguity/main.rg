First: Type = ()
Second: Type = ()
Build#(.Target: Type): Contract = (.build: _)

implement Build#(First) (
    .build = (.value: Int32) -> (.result: First) { result = () }
)
implement Build#(Second) (
    .build = (.value: Int32) -> (.result: Second) { result = () }
)

main := () -> () { result: First = build(42) }
