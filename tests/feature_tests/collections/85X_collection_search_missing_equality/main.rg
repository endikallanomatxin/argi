Record: Type = (.value: Int32)

implement ImplicitlyCopyable#(Record) ()

main() -> () := {
    values: [1]Record = ((.value = 1))
    borrowed_view ::= view(.self = &values)
    target :: Record = (.value = 1)
    observed ::= contains(.self = &borrowed_view, .value = target).ok
}
