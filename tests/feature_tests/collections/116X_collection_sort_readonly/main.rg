main() -> () := {
    values : [2]Int32 = (2, 1)
    borrowed_view ::= view(.array = &values)
    order ::= Int32OrderPolicy()
    sort(.self = $&borrowed_view, .order = &order)
}
