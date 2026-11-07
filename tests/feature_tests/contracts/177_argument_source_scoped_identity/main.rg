cli := import("cli")

read_first := #(.T: Type: cli.ArgumentSource#(T)) (.source: &T) -> (.text: StringView) {

    if cli.ArgumentSource#().length(source).count != 2 { abort }
    text = cli.ArgumentSource#().get(source, .index = 0) handle ignored, value { abort }
}

main := () -> (.status_code: Int32 = 0) {

    values: [2]StringView = ("first", "second")
    source ::= cli.ArgumentViews(view(&values))
    if read_first(&source).text != "first" { abort }
    erased ::= Virtual#(.contract: cli.ArgumentSource)(.value = &source)
    if read_first(&erased).text != "first" { abort }
}
