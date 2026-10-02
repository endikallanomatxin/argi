main() -> () := {
    values : [2]Int32 = (2, 1)
    view ::= array_view_ro(.array = &values).view
    order ::= Int32OrderPolicy()
    sort(.self = $&view, .order = &order)
}
