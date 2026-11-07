ap := import("command_line_interface/argument_parsing")

first := (.source: &Virtual#(ap.ArgumentSource)) -> (
    .result : Errable#(StringView, (..out_of_bounds, ..invalid_utf8))
) {

    result = ap.ArgumentSource#().get(source, 0)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr

    args: [2]StringView = ("alpha", "beta")
    source ::= ap.ArgumentViews(view(&args))
    erased ::= Virtual#(ap.ArgumentSource)(&source)

    if ap.ArgumentSource#().length(&erased) != 2 { abort }
    if first(&erased)!!! != "alpha" { abort }
    if ap.ArgumentSource#().get(&erased, 1)!!! != "beta" { abort }

    match ap.ArgumentSource#().get(&erased, 2) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_bounds { abort } }
    }

    native ::= Virtual#(ap.ArgumentSource)(system.args)
    if ap.ArgumentSource#().length(&native) == 0 { abort }
    if byte_length(&ap.ArgumentSource#().get(&native, 0)!!!).count == 0 { abort }
}
