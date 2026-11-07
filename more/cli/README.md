# Command-line arguments

Import `cli` to parse options, validate a schema and render help. Core supplies
`system.args` and indexed/iterable process argument access; it does not define
CLI policy or depend on this library.

```rg
cli := import("cli")

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator ::= Virtual#(Allocator)($&GeneralPurposeAllocator(system.page_allocator))
    specs ::= (
        cli.Spec(.name = "help", .short_name = "h", .help = "Show help"),
        cli.Spec(.name = "output", .short_name = "o", .value_name = "FILE"),
    )
    matches ::= cli.parse(
        .source = system.args, .specs = view(&specs), .start = 1
    )!!! { status_code = 1 }
    for option in matches.options {
        if option.name == "help" {
            cli.write_help(
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
value conversion remain the caller's responsibility. Subcommands are not yet
modeled.

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
`argi test more/cli` or `zig build test-cli -j16 -Dtest-jobs=16`. Compiler
integration, imported evidence and rejected lifetime escapes stay under `tests/`.
