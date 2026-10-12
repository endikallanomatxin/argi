Record : Type = (.value: Int32)
implement ImplicitlyCopyable#(Record) ()
main() -> () := {
    values : [1]Record = ((.value = 1))
    view ::= array_view_ro(.array = &values).view
    target :: Record = (.value = 1)
    observed ::= contains(.self = &view, .value = target).ok
}
