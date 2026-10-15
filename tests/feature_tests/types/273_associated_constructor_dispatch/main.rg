Box#(.t: Type) : Type = (.value: t, .tag: Int32)
implement#(.t: Type) Init#(Box#(.t: t), (.value: t)) (
    .Result: Type = Box#(.t: t)
    .init = (.args: (.value: t)) -> (.result: Result) {
        value ::= ~args.value

        result = (.value = value, .tag = 1)
    }
)
implement#(.t: Type) Init#(Box#(.t: t), (.value: t, .tag: Int32)) (
    .Result: Type = Box#(.t: t)
    .init = (.args: (.value: t, .tag: Int32)) -> (.result: Result) {
        value ::= ~args.value
        tag ::= ~args.tag

        result = (.value = value, .tag = tag)
    }
)
Other#(.t: Type) : Type = (.value: t)
implement#(.t: Type) Init#(Other#(.t: t), (.value: t)) (
    .Result: Type = Other#(.t: t)
    .init = (.args: (.value: t)) -> (.result: Result) {
        value ::= ~args.value

        result = (.value = value)
    }
)
Record : Type = (.tag: Int32)
implement#(.sample: Type) Init#(Record, (.value: sample)) (
    .Result: Type = Record
    .init = (.args: (.value: sample)) -> (.result: Result) {
        value ::= ~args.value

        _ ::= value
        result = (.tag = 42)
    }
)
main() -> (.status_code: Int32) := {
    first ::= Box#(.t: Int32)(.value = 4)
    second ::= Box(.value = 'a', .tag = 7)
    other ::= Other(.value = 9)
    record ::= Record(.value = 'b')
    if first.value != 4 or first.tag != 1 or second.value != 'a' or second.tag != 7 or other.value != 9 or record.tag != 42 {
        status_code = 1
        return
    }
    status_code = 0
}
