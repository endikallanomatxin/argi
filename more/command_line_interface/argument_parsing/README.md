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
    matches ::= ap.parse_specs(
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
- `parse_specs` validates the schema, matches options and returns `Matches`. Short aliases
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

## Typed records and choices

`parse#(T)` returns `Errable#(Parsed#(T), TypedReasons)`. The successful payload
is a choice between `..arguments T` and `..help Help`. `Option`, `Positional`
and `Flag` store only their `.value`.

Help is a successful parse outcome, not an error. `parse` never prints, changes
an exit status, aborts or exits the process. The caller handles help and execution
explicitly; invalid arguments use the ordinary Errable error branch. There is no
separate `try_parse` entry point. Return normally from the caller to preserve its
lexical cleanup.

A record declares the arguments; a choice declares subcommands whose payloads
are argument records. The field/alternative names become long option/command
names. Option and Flag accept `.long_name = "output-file"` to override the
field name while preserving an ordinary field such as `.output_file`. Positional
fields are consumed in declaration order; help shows required positionals in
angle brackets and defaulted positionals in square brackets.

```rg
ap := import("command_line_interface/argument_parsing")

BuildArgs := (
    .input: ap.Positional#(StringView),
    .output: ap.Option#(
        StringView, .short_name = "o", .help = "Output file",
        .value_name = "FILE", .default_value = ..some(.value = "output")
    ),
    .verbose: ap.Flag#()
)
RunArgs := (.input: ap.Positional#(StringView), .release: ap.Flag#())
Command: Type = (..build BuildArgs, ..run RunArgs)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stderr
    parsed ::= ap.parse#(Command)(system.args, .start = 1)!!! { status_code = 1 }
    match parsed {
        ..help info {
            ap.write_typed_help#(Command)(writer, &info, .program = "example")!!! {
                status_code = 1
            }
        }
        ..arguments command { match command {
            ..build args {
                if args.verbose.value { print(args.output.value)!!! { status_code = 1 } }
            }
            ..run args { print(args.input.value)!!! { status_code = 1 } }
        } }
    }
}
```

For records without subcommands, pass `BuildArgs` instead of `Command`.
An `Option` or `Positional` is required unless its configuration supplies a
default. Flags default to false. Numeric options use the existing checked core
parsers; an invalid value, including overflow, returns `invalid_argument_value`.
Built-in value support covers StringView, Bool, signed/unsigned 8/16/32/64-bit
integers, UIntNative, Float32 and Float64. Implement `ArgumentValue#(T)` for
additional value types; its `empty` operation supplies an unpublished placeholder
for error cleanup, not an argument default. The current compile-time default
parameter requires an implicitly copyable value type; noncopyable owning custom
values are not supported by these wrappers.

Configuration is supplied directly as compile-time parameters of each field's
type. `Option` accepts `T`, `short_name`, `help`, `value_name`, `long_name`, and
`default_value: ?T`. `Positional` accepts `T`, `help`, `value_name`, and
`default_value`; `Flag` accepts `short_name`, `help`, and `long_name`. Parameter values are
immutable literals or forwarded compile-time value parameters. Strings and
compound defaults participate in type identity, without occupying instance
storage. Each wrapper contains only `.value`; the parser specializes for the
containing record or choice and discovers its fields through structural callbacks.
No configuration provider functions or comptime-only instance fields are needed.

The lower-level specification API remains available as `parse_specs`; its
`Spec`, `Matches`, and query helpers can be used for runtime-defined schemas.

The typed entry supports one occurrence per option, no repeated or variadic
fields, and a single level of subcommands. Positionals are consumed in declaration
order; place defaulted positionals last. Extra positionals are rejected.
`--help`/`-h` are reserved and return before reading required fields. Tokens after `--`, or consumed as
option values, remain ordinary text. Only the selected subcommand's argument
values are constructed. Help uses the type again when rendering, so the handle
contains just a borrowed command name; it does not own a fabricated argument
record. Config metadata is queried to describe the selected command.

Typed StringView values borrow the original argument source. Keep that source
alive while using the resulting record/choice. The optional Diagnostic follows
the same rules as `parse_specs`; command failures preserve their original reason.

## Default subcommands and command aliases

Command choices can attach optional metadata to a payload:

```rg
HelpArgs := (.command: ap.Positional#(StringView, .default_value = ..some(.value = "")))
EmptyArgs: Type = ()
Command: Type = (
    ..build BuildArgs,
    ..help ap.Subcommand#(
        HelpArgs, .is_default = true, .long_alias = "help", .short_alias = "h"
    ),
    ..version ap.Subcommand#(EmptyArgs, .long_alias = "version", .short_alias = "V")
)
```

With no arguments, `parse#(Command)` selects the default alternative and parses
its arguments normally. Required fields still apply. With no default, a missing
command remains an error. `--help`, `-h` and `help` select the declared help
command above; `--version`, `-V` and `version` select its version command.
The parser contains no reserved version result or version output policy.

Ordinary payloads remain unchanged. A Subcommand payload stores its parsed
record in `.arguments`, so the help target above is
`args.arguments.command.value` after matching `..help args`. Metadata is part of
the specialized type, not stored in each instance. The SubcommandPayload contract
supplies the record type, metadata and wrapping operation for these payloads.

Aliases are recognized only in command position. Text consumed as an option
value, or following `--` in a command's arguments, keeps its ordinary meaning.
`build --help` still returns `..help Help` without requiring or constructing
BuildArgs. If no command claims `--help`/`-h`, they retain the existing top-level
help behavior. Multiple defaults, duplicate aliases and invalid alias spellings
are schema errors. The library never prints or exits on these outcomes.
