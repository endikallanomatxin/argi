Box#(.t: Type) : Type = (.tag: Int32)
Box init#(.sample: Type)(.value: sample) -> (.result: Box#(.t: Int32)) := {
    _ ::= value
    result = (.tag = 1)
}
Box init#(.sample: Type)(.value: sample) -> (.result: Box#(.t: Char)) := {
    _ ::= value
    result = (.tag = 2)
}
main() -> (.status_code: Int32 = 0) := {
    value ::= Box#(.t: Int32)(.value = 5)
    status_code = value.tag
}
