mutate#(.Collection: Type: MutableIndexable#(.Item: Int32))(.items: $&Collection) -> () := {}

main() -> () := {
    values: [1]Int32 = (1)
    borrowed_view ::= view(.array = &values)
    mutate(.items = $&borrowed_view)
}
