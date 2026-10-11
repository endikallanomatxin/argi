first(.source: &Virtual#(ArgumentSource)) -> (.result: Errable#(StringView, (..out_of_bounds))) := {
    result = get(source, 0)
}

main(.system: System) -> (.status_code: Int32 = 0) := {
    args: [2]StringView = ("alpha", "beta")
    source ::= CliArgumentViews(view(&args))
    erased ::= to_virtual#(ArgumentSource)(&source)

    if length(&erased) != 2 { abort }
    if unwrap_or_abort(first(&erased)) != "alpha" { abort }
    if unwrap_or_abort(get(&erased, 1)) != "beta" { abort }

    match get(&erased, 2) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_bounds { abort } }
    }

    native ::= to_virtual#(ArgumentSource)(system.args)
    if length(&native) == 0 { abort }
    if unwrap_or_abort(get(&native, 0)).length == 0 { abort }
}
