Box#(.t: Type) : Type = (.value: t, .tag: Int32)
Box init#(.t: Type)(.value: t) -> (.result: Box#(.t: t)) := {
    result = (.value = value, .tag = 1)
}
Box init#(.t: Type)(.value: t, .tag: Int32) -> (.result: Box#(.t: t)) := {
    result = (.value = value, .tag = tag)
}
Other#(.t: Type) : Type = (.value: t)
Other init#(.t: Type)(.value: t) -> (.result: Other#(.t: t)) := {
    result = (.value = value)
}
Record : Type = (.tag: Int32)
Record init#(.sample: Type)(.value: sample) -> (.result: Record) := {
    _ ::= value
    result = (.tag = 42)
}
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
