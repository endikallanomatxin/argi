escaped() -> (.result: Errable#(StringView, (..out_of_bounds))) := {
    args: [1]StringView = ("alpha",)
    source ::= CliArgumentViews(view(&args))
    erased ::= to_virtual#(ArgumentSource)(&source)
    result = get(&erased, 0)
}

main() -> () := { escaped() }
