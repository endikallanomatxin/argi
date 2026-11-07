cli := import ("cli")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    specs ::= (cli.Spec(.name = "help", .short_name = "h"),)
    matches ::= cli.parse(
        .source    = system.args
        .specs     = view(&specs)
        .start     = 1
        .allocator = system.page_allocator
    )!!! { status_code = 1 }
    if length(&matches.options) != 0 { abort }
    if length(&matches.positionals) != 0 { abort }
}
