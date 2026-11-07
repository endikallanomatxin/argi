# Command-line arguments

Import `command_line_interface/argument_parsing` as `ap` to parse options,
validate a schema and render help. Core supplies
`system.args` and indexed/iterable process argument access; it does not define
CLI policy or depend on this library.

```rg
ap := import("command_line_interface/argument_parsing")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator ::= Virtual#(Allocator)($&GeneralPurposeAllocator(system.page_allocator))
    specs ::= (
        ap.Spec(.name = "help", .short_name = "h", .help = "Show help"),
        ap.Spec(.name = "output", .short_name = "o", .value_name = "FILE"),
    )
    matches ::= ap.parse(
        .source = system.args, .specs = view(&specs), .start = 1
    )!!! { status_code = 1 }
    for option in matches.options {
        if option.name == "help" {
            ap.write_help(
                $&system.terminal&.stdout, .program = "example",
                .about = "Example program", .specs = view(&specs)
            )!!! { status_code = 1 }
        }
    }
}
```

Use `start = 1` for process arguments to skip the executable name. Parsing starts
at zero by default, useful for argument views and other sources. Help is an
ordinary option: callers decide when to display it and which status to return.
Errors carry reason variants; presenting detailed option diagnostics and typed
value conversion remain the caller's responsibility. The command API supports one level of subcommands.

## API and ownership

- `ArgumentSource` defines indexed `length` and fallible `get` operations.
  This module implements it for core `Arguments` and borrowed `ArgumentViews`.
- `Parser`, `next` and `take_value` provide incremental parsing without allocating.
  They recognize long options, attached values, short groups, positionals and `--`.
  `take_value` consumes the next token verbatim, including negative numbers.
- `Spec` describes option names, aliases, help, value labels, requirements,
  repetition and defaults. A nonempty `value_name` marks an option taking a value.
- `parse` validates the schema, matches options and returns `Matches`. Short aliases
  are normalized to long names. Flags carry no value; value options carry one.
- `write_help` writes usage and option descriptions to an ordinary Writer.

`Matches` owns its option and positional arrays, allocated through the supplied
allocator, but borrows their text from the argument source and schema. Keep both
alive until the results are no longer used. Destroying matches releases its
arrays; it does not destroy the source, schema or allocator. Virtual argument
sources retain the same borrowed-result lifetime rules as concrete sources.

## Organization and tests

`argument_source.rg` contains the source protocol and its adapters; `parser.rg`
handles token interpretation; `schema.rg` defines and matches option specifications;
`matches.rg` defines results and errors; `help.rg` renders help.

Behavior tests live beside the implementation as `*_test.rg`. Run them with
`argi test more/command_line_interface/argument_parsing` or `zig build test-cli -j16 -Dtest-jobs=16`. Compiler
integration, imported evidence and rejected lifetime escapes stay under `tests/`.


## Commands and diagnostics

```rg
ap := import("command_line_interface/argument_parsing")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stderr
    build_options ::= (ap.Spec(.name = "output", .short_name = "o", .value_name = "FILE"),)
    commands ::= (
        ap.Command(.name = "build", .about = "Compile a program", .specs = view(&build_options)),
        ap.Command(.name = "check", .about = "Check a program"),
    )
    diagnostic ::= ap.Diagnostic()
    invocation ::= ap.parse_command(
        .source = system.args, .commands = view(&commands), .start = 1,
        .diagnostic = ..some(.value = $&diagnostic)
    ) handle error, recovered {
        ap.write_diagnostic(writer, &diagnostic)!!! { status_code = 1 }
        status_code = 1
        return
    }
    if invocation.help {
        ap.write_command_help(
            writer, .program = "example", .about = "Example compiler",
            .commands = view(&commands), .command = invocation.command
        )!!! { status_code = 1 }
        return
    }
    if invocation.command == "build" {
        output ::= ap.value(&invocation.matches, "output")
    }
}
```

`parse_command` expects a command name followed by that command's options and
positionals. `--help` and `-h` return a successful `Invocation` with `help = true`,
without enforcing required options. Top-level help has an empty command name.
The help names are reserved by this API. A value consumed by another option,
or text after `--`, is never interpreted as help. Missing/unknown commands are
errors. Options before the command, nested subcommands and inherited global
options are deliberately unsupported; reuse option specifications explicitly.

`contains`, `occurrences` and `value` query canonical option names. `value` returns
the last value, including defaults; flags and absent options return `..none`.
Use `occurrences` for repeated flags and inspect `matches.options` for all values.

Both parsing APIs optionally accept a borrowed mutable `Diagnostic`. They reset
it on entry and fill option/command context for user input errors. Context borrows
the source/schema just like matches. Source, allocation and schema errors may
leave the message empty: callers must fall back to the returned reason. Rendering
is explicit through `write_diagnostic`; parsing never writes or exits the process.
