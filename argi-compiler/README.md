# Self-hosted compiler CLI prototype

`source/argi-compiler/commands.rg` contains the complete typed command schema,
and shared metadata aliases. `main.rg` parses arguments, renders help and
dispatches commands directly.
All files in the folder share a namespace.

From the repository root, enter this project with `cd argi-compiler`.
Build here with `argi build`, or run with `argi run -- --help`. The CLI models the Zig compiler's
build, check, run, repl, test, init, format, lsp, version and help commands.
Each subcommand has its own typed payload and generated help:

```sh
./build/debug/argi-compiler --help
./build/debug/argi-compiler build --help
./build/debug/argi-compiler help run
./build/debug/argi-compiler build src -o app --emit-llvm app.ll --release
./build/debug/argi-compiler run . --exec demo --vm --vm-instructions 100000
./build/debug/argi-compiler test tests --filter parser
./build/debug/argi-compiler init example --lib
./build/debug/argi-compiler format source --check
```

Only parsing, help and prototype version output are implemented. Backend commands
report that they are not implemented and return status 1. Invalid arguments return
2; help returns 0. No backend command silently claims success. This is a CLI
schema for the self-hosting work, not a wrapper invoking the Zig compiler.

Differences from the Zig CLI:

- Options belong after the subcommand; each command has its own help.
- `run` takes a module path, with `--exec NAME` selecting an executable.
- Native library inputs and C driver arguments accept one comma-separated string
  per option instead of repeated occurrences. Splitting them belongs to the
  future backend adapter; commas within values are currently unsupported.
- `format` takes one file or directory, defaulting to the current directory.
- `check` exposes analysis options, excluding linker and emission options.
- The help alternative uses `ap.Help` and declares the default command with
  `ap.Subcommand`; the version alternative declares `--version`/`-V`.
  No argument-count checks or version-token checks are needed in main.
- `help COMMAND` and `COMMAND --help` show the same command usage.
- `version`, `--version` and `-V` identify this prototype, without claiming the
  release version of the Zig implementation.

TODO: Replace the backend placeholders with implementations, validate worker and
native-target policies, and support repeated link inputs and multiple format
paths when the typed parsing library gains repeated/variadic fields.

Argument failures use Argi's error tracer and ordinary `!!!` handling, with
status 2. The CLI supplies a local bounded tracer; argument details are recorded
by `ap.parse`, without a separate Diagnostic output parameter. Help and version
remain successful parsed commands, and tracing does not print until reporting.

Optional text options use `ap.Option#(?StringView)` directly. Missing options
remain `..none`; an explicitly supplied empty string remains `..some(.value = "")`.
The backend chooses its defaults only when the option is absent.
