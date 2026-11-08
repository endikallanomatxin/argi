ap := import ("command_line_interface/argument_parsing")

Args := (.jobs: ap.Option#(UInt8))

Command: Type = (..run Args, ..help ap.Help)

Owner := (.writer: $&File)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () { write(self&.writer, "cleanup\n") handle ignored {} }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stderr
    assume error_tracer ::= $&Virtual#(ErrorTracer)(
        $&FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [4096]UInt8)()))
    )
    owner ::= Owner(.writer = $&system.terminal&.stdout)
    parsed ::= ap.parse#(Command)(system.args, .start = 1)!!! { status_code = 2 }
    match parsed {
        ..help info {
            ap.write_typed_help#(Command)(
                $&system.terminal&.stdout, &info, .program = "example"
            )!!! {
                status_code = 1
            }
        }
        ..run args { if args.jobs.value != 8 { abort } }
    }
}
