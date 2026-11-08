ap := import("command_line_interface/argument_parsing")

output_config := () -> (.config: ap.OptionConfig#(StringView)) {
    config = (.short_name = "o", .help = "Output file", .default_value = ..some(.value = "output"))
}
BuildArgs := (
    .input: ap.Positional#(StringView),
    .output: ap.Option#(StringView, output_config),
    .jobs: ap.Option#(UInt8)
)
Command: Type = (..build BuildArgs)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stderr
    values: [4]StringView = ("build", "main.rg", "--jobs", "8")
    source ::= ap.ArgumentViews(view(&values))
    parsed ::= ap.parse_as#(Command)(.source = &source)!!! { status_code = 1 }
    match parsed {
        ..help _ { status_code = 2 }
        ..arguments command { match command {
            ..build args {
                if args.input.value != "main.rg" or args.output.value != "output" or args.jobs.value != 8 { abort }
            }
        } }
    }
}
