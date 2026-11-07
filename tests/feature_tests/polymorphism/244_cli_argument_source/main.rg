cli := import ("cli")

first := (.source: &Virtual#(cli.ArgumentSource)) -> (
    .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
) {

    result = cli.ArgumentSource#().get(source, 0)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr

    args: [2]StringView = ("alpha", "beta")
    source ::= cli.ArgumentViews(view(&args))
    erased ::= Virtual#(cli.ArgumentSource)(&source)

    if cli.ArgumentSource#().length(&erased) != 2 { abort }
    if first(&erased)!!! != "alpha" { abort }
    if cli.ArgumentSource#().get(&erased, 1)!!! != "beta" { abort }

    match cli.ArgumentSource#().get(&erased, 2) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_bounds { abort } }
    }

    native ::= Virtual#(cli.ArgumentSource)(system.args)
    if cli.ArgumentSource#().length(&native) == 0 { abort }
    if byte_length(&cli.ArgumentSource#().get(&native, 0)!!!).count == 0 { abort }
}
