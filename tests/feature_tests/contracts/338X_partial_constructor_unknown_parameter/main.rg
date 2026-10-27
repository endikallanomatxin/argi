Box := #(.Value: Type, .Tag: Type = Int32) (.value: Value)

BoxInitArgs: Type = #(.Value: Type, .Tag: Type) (.value: Value)

implement#(.Value: Type, .Tag: Type) Init#(Box#(Value, Tag), BoxInitArgs#(Value, Tag)) (
    .Result : Type = Box#(Value, Tag)

    .init = BoxInitArgs#(Value, Tag) -> (.result: Result) { result = (.value = value) }
)

main := () -> () {
    value ::= Box#(.Missing: Int32)(.value = 7)
}
