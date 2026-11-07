ap := import("command_line_interface/argument_parsing")

read_first := #(.T: Type: ap.ArgumentSource#(T)) (.source: &T) -> (.text: StringView) {

    if ap.ArgumentSource#().length(source).count != 2 { abort }
    text = ap.ArgumentSource#().get(source, .index = 0) handle ignored, value { abort }
}

main := () -> (.status_code: Int32 = 0) {

    values: [2]StringView = ("first", "second")
    source ::= ap.ArgumentViews(view(&values))
    if read_first(&source).text != "first" { abort }
    erased ::= Virtual#(.contract: ap.ArgumentSource)(.value = &source)
    if read_first(&erased).text != "first" { abort }
}
