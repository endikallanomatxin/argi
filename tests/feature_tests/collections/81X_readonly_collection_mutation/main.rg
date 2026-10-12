mutate#(.Collection: Type: IndexableMutable#(.Item: Int32))(.items: $&Collection) -> () := {}
main() -> () := {
    values : [1]Int32 = (1)
    view ::= array_view_ro(.array = &values)
    mutate(.items = $&view)
}
