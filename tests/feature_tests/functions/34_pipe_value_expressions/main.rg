ops := import ("./operations")
Counter: Type = (.calls: Int32)
next(.self: $&Counter) -> (.value: Int32) := {
    self&.calls = self&.calls + 1
    value = self&.calls
}
next_index(.self: $&Counter) -> (.value: UIntNative) := {
    self&.calls = self&.calls + 1
    value = 0
}
bump(.self: $&Int32) -> () := { self&= self&+ 1 }
generic_sum#(.t: Type)(.left: t, .right: t) -> (.value: t) := {
    value = left | ops.identity#(.t: t)(.value = _ + right)
}
generic_twice#(.t: Type)(.self: $&Counter, .token: t) -> (.value: Int32) := {
    value = next(.self = self) | ops.add(.left = _, .right = _)
}
generic_bump#(.t: Type)(.pointer: $&t) -> () := {
    pointer | bump(.self = $&_)
}
main() -> (.status_code: Int32 = 0) := {
    counter :: Counter = (.calls = 0)
    value ::= next(.self = $&counter) | ops.add(.left = _ + 1, .right = _ * 2)
    if value != 4 or counter.calls != 1 { abort }
    counter.calls = 0
    ordered ::= next(.self = $&counter) | ops.add(.left = _ + next(.self = $&counter),
        .right = _ + next(.self = $&counter))
    if ordered != 7 or counter.calls != 3 { abort }
    inferred ::= 7 | ops.identity(.value = [_ + 2])
    explicit ::= inferred | ops.identity#(.t: Int32)(.value = _ + 1)
    if explicit != 10 { abort }
    nested ::= 5 | ops.add(.left = 2 | ops.identity(.value = _), .right = _)
    outer_nested ::= 5 | ops.add(.left = _ | ops.identity(.value = _), .right = _)
    if nested != 7 or outer_nested != 10 { abort }
    grouped ::= 5 | [_ * 2 + 1]
    if grouped != 11 { abort }
    values :: [2]Int32 = (20, 21)
    indexed ::= values | ops.add(.left = _[0], .right = _[1])
    if indexed != 41 { abort }
    selected ::= values[next_index(.self = $&counter)] | ops.add(.left = _, .right = _)
    if selected != 40 or counter.calls != 4 { abort }
    values[0] | bump(.self = $&_)
    if values[0] != 21 { abort }
    before ::= counter.calls
    skipped ::= false and [next(.self = $&counter) | [_ > 0]]
    if skipped or counter.calls != before { abort }
    pointer ::= &values[1]
    pointed ::= pointer | ops.identity(.value = _&)
    if pointed != 21 { abort }
    if generic_sum(.left = 20, .right = 22) != 42 { abort }
    counter.calls = 0
    if generic_twice(.self = $&counter, .token = true) != 2 or counter.calls != 1 { abort }
    generic_bump(.pointer = $&values[0])
    if values[0] != 22 { abort }

}
