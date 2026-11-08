ap := import("command_line_interface/argument_parsing")
Args := (.input: ap.Positional#(StringView))

escape := (.allocator: Virtual#(Allocator)) -> (.result: Errable#(ap.Parsed#(Args), ap.TypedReasons)) {
    values: [1]StringView = ("main.rg")
    source ::= ap.ArgumentViews(view(&values))
    result = ap.parse_as#(Args)(.source = &source, .allocator = allocator)
}

main := (.system: System) -> () { escape(.allocator = system.page_allocator) }
