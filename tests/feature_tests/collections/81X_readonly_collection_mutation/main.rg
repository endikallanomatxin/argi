mutate(.items: $&IndexableMutable#(.t: Int32)) -> () := {}
main() -> () := {
    values : [1]Int32 = (1)
    view ::= array_view_ro(.array = &values)
    mutate(.items = $&view)
}
