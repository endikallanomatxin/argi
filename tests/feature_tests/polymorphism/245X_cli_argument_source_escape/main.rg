ap := import("command_line_interface/argument_parsing")

escaped := () -> (.result: Errable#(StringView, (..out_of_bounds, ..invalid_utf8))) {

    args: [1]StringView = ("alpha")
    source ::= ap.ArgumentViews(view(&args))
    erased ::= Virtual#(ap.ArgumentSource)(&source)
    result = ap.ArgumentSource#().get(&erased, 0)
}

main := () -> () {

    escaped()
}
