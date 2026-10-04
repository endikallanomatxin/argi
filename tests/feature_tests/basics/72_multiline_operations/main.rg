Counter : Type = (.calls: Int32 = 0)
next(.self: $&Counter) -> (.value: Bool) := {
    self&.calls = self&.calls + 1
    value = true
}
identity#(.t: Type)(.value: t) -> (.result: t) := { result = value }
sum(.values: [2]Int32) -> (.result: Int32) := { result = values[0] + values[1] }
main() -> (.status_code: Int32 = 0) := {
    arithmetic ::= [
        20
        + 3 * 4
        - 6 / 2
        + 7 % 4
    ]
    if arithmetic != 32 { abort }
    nested ::= [
        [2
            + 3]
        * [4
            - 1]
    ]
    if nested != 15 { abort }
    continued ::= 2 +
        3 *
        4
    if continued != 14 { abort }
    signed ::= 10 +
        -
        2
    if signed != 8 { abort }
    compared ::= [
        arithmetic
        == 32
        and nested
        >= 15
        or false
    ]
    if compared == false { abort }
    counter :: Counter = Counter()
    skipped_and ::= [false
        and next(.self = $&counter)]
    skipped_or ::= [true
        or next(.self = $&counter)]
    if skipped_and or skipped_or == false or counter.calls != 0 { abort }
    piped ::= [3
        | identity(.value = _)
        | identity(.value = _ + 1)]
    if piped != 4 { abort }
    -- Parenthesized fields remain separated by newlines inside an outer group.
    fields ::= [sum(.values = (1
        -2))]
    if fields != -1 { abort }
    commented ::= [2
        -- A leading operator can follow a preserved comment.
        + 3]
    if commented != 5 { abort }
}
