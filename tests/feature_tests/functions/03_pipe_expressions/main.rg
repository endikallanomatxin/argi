Point := (.x: Int32, .y: Int32)

add_one := (.i: Int32) -> (.o: Int32) { o = i + 1 }

double := (.i: Int32) -> (.o: Int32) { o = i * 2 }

sum_point := (.a: Int32, .b: Int32) -> (.r: Int32) { r = a + b }

inferred_identity := #(.t: Type) (.x: t) -> (.y: t) { y = x }

explicit_identity := #(.t: Type) (.x: t) -> (.y: t) { y = x }

main := () -> (.status_code: Int32 = 42) {
    point: Point = (.x = 20, .y = 21)
    total: Int32 = point | sum_point(.a = _.x, .b = _.y)
    if total != 41 { abort }
    incremented ::= total | add_one(.i = _)
    if incremented != 42 { abort }
    expression ::= 40 | add_one(_ + 1)
    if expression != 42 { abort }
    chained ::= 20 | add_one(.i = _) | double(.i = _)
    if chained != 42 { abort }
    inferred ::= 42 | inferred_identity(.x = _)
    if inferred != 42 { abort }
    explicit ::= 42 | explicit_identity#(.t: Int32)(.x = _)
    if explicit != 42 { abort }
}
