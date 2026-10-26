Box := <.Value: Type, .Tag: Type = Int32> (.value: Value)

implement<.Value: Type, .Tag: Type> Init<Box<Value, Tag>, (.value: Value)> (
    .Result : Type = Box<Value, Tag>
    .init   = (.args: (.value: Value)) -> (.result: Result) { result = (.value = args.value) }
)

main := () -> () {
    value ::= Box<.Missing: Int32>(.value = 7)
}
