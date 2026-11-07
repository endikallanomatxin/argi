cli := import("cli")

escaped := () -> (.result: Errable#(StringView, (..out_of_bounds, ..invalid_utf8))) {

    args: [1]StringView = ("alpha")
    source ::= cli.ArgumentViews(view(&args))
    erased ::= Virtual#(cli.ArgumentSource)(&source)
    result = cli.ArgumentSource#().get(&erased, 0)
}

main := () -> () {

    escaped()
}
