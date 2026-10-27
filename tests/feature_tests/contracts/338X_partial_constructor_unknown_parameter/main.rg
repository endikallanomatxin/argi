Box := #(.Value: Type, .Tag: Type = Int32) (.value: Value)

implement#(.Value: Type, .Tag: Type) Init#(Box#(Value, Tag)) (
    .init = (.value: Value) -> (.result: Box#(Value, Tag)) { result = (.value = value) }
)

main := () -> () {
    value ::= Box#(.Missing: Int32)(.value = 7)
}
