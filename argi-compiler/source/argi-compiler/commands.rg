ap := import ("command_line_interface/argument_parsing")

ModulePath := ap.Positional#(
    StringView,
    .help          = "Module directory (default: current directory)",
    .default_value = ..some(.value = ".")
)
FrontendJobs := ap.Option#(
    StringView,
    .long_name     = "frontend-jobs",
    .help          = "Frontend workers: auto or a positive count",
    .value_name    = "auto|N",
    .default_value = ..some(.value = "auto")
)
TargetOption := ap.Option#(
    StringView,
    .help          = "Target triple or native",
    .value_name    = "TRIPLE",
    .default_value = ..some(.value = "native")
)
InstructionLimit := ap.Option#(
    UIntNative,
    .long_name     = "vm-instructions",
    .help          = "VM instruction budget (default: 1000000)",
    .value_name    = "N",
    .default_value = ..some(.value = 1000000)
)
CallDepthLimit := ap.Option#(
    UIntNative,
    .long_name     = "vm-call-depth",
    .help          = "VM call depth budget (default: 128)",
    .value_name    = "N",
    .default_value = ..some(.value = 128)
)
ValueCellsLimit := ap.Option#(
    UIntNative,
    .long_name     = "vm-value-cells",
    .help          = "VM value cell budget (default: 1000000)",
    .value_name    = "N",
    .default_value = ..some(.value = 1000000)
)

-- Command payloads keep each command's inputs distinct. No ambient options.
BuildArgs := (
    .path   : ModulePath,
    .output : ap.Option#(
        ?StringView, .help = "Output binary path", .value_name = "PATH", .short_name = "o"
    ),
    .frontend_jobs : FrontendJobs,
    .emit_llvm     : ap.Option#(
        ?StringView, .long_name = "emit-llvm", .help = "Write LLVM IR", .value_name = "PATH"
    ),
    .emit_obj : ap.Option#(
        ?StringView,
        .long_name  = "emit-obj",
        .help       = "Also write an object file",
        .value_name = "PATH"
    ),
    .just_emit_obj : ap.Option#(
        ?StringView,
        .long_name  = "just-emit-obj",
        .help       = "Write an object file without linking",
        .value_name = "PATH"
    ),
    .sysroot : ap.Option#(
        ?StringView, .help = "Argi installation prefix", .value_name = "PATH"
    ),
    .exec : ap.Option#(
        ?StringView, .help = "Named executable from argi.toml", .value_name = "NAME"
    ),
    .link_library : ap.Option#(
        ?StringView,
        .long_name  = "link-library",
        .help       = "Comma-separated native libraries",
        .value_name = "NAMES"
    ),
    .link_static_library : ap.Option#(
        ?StringView,
        .long_name  = "link-static-library",
        .help       = "Comma-separated static libraries",
        .value_name = "NAMES"
    ),
    .link_shared_library : ap.Option#(
        ?StringView,
        .long_name  = "link-shared-library",
        .help       = "Comma-separated shared libraries",
        .value_name = "NAMES"
    ),
    .library_path : ap.Option#(
        ?StringView,
        .long_name  = "library-path",
        .help       = "Comma-separated library search directories",
        .value_name = "PATHS"
    ),
    .link_file : ap.Option#(
        ?StringView,
        .long_name  = "link-file",
        .help       = "Comma-separated object or archive files",
        .value_name = "FILES"
    ),
    .cc : ap.Option#(
        ?StringView, .help = "C linking driver", .value_name = "DRIVER"
    ),
    .cc_arg : ap.Option#(
        ?StringView,
        .long_name  = "cc-arg",
        .help       = "Comma-separated C driver arguments",
        .value_name = "ARGS"
    ),
    .c_sysroot : ap.Option#(
        ?StringView,
        .long_name  = "c-sysroot",
        .help       = "C toolchain sysroot",
        .value_name = "PATH"
    ),
    .target   : TargetOption,
    .release  : ap.Flag#(.help = "Optimize generated code"),
    .no_cache : ap.Flag#(
        .long_name = "no-cache", .help = "Rebuild without the frontend cache"
    ),
    .stats                       : ap.Flag#(.help = "Show compilation timings and statistics"),
    .on_build_error_show_cascade : ap.Flag#(
        .long_name = "on-build-error-show-cascade", .help = "Show cascading diagnostics"
    ),
    .on_build_error_show_syntax_tree : ap.Flag#(
        .long_name = "on-build-error-show-syntax-tree",
        .help      = "Show the syntax tree on failure"
    ),
    .on_build_error_show_semantic_graph : ap.Flag#(
        .long_name = "on-build-error-show-semantic-graph",
        .help      = "Show the semantic graph on failure"
    )
)

CheckArgs := (
    .path          : ModulePath,
    .frontend_jobs : FrontendJobs,
    .sysroot       : ap.Option#(
        ?StringView, .help = "Argi installation prefix", .value_name = "PATH"
    ),
    .exec : ap.Option#(
        ?StringView, .help = "Named executable from argi.toml", .value_name = "NAME"
    ),
    .target   : TargetOption,
    .no_cache : ap.Flag#(
        .long_name = "no-cache", .help = "Rebuild without the frontend cache"
    ),
    .stats                       : ap.Flag#(.help = "Show compilation timings and statistics"),
    .on_build_error_show_cascade : ap.Flag#(
        .long_name = "on-build-error-show-cascade", .help = "Show cascading diagnostics"
    ),
    .on_build_error_show_syntax_tree : ap.Flag#(
        .long_name = "on-build-error-show-syntax-tree",
        .help      = "Show the syntax tree on failure"
    ),
    .on_build_error_show_semantic_graph : ap.Flag#(
        .long_name = "on-build-error-show-semantic-graph",
        .help      = "Show the semantic graph on failure"
    )
)

RunArgs := (
    .path : ModulePath,
    .exec : ap.Option#(
        ?StringView, .help = "Named executable from argi.toml", .value_name = "NAME"
    ),
    .frontend_jobs : FrontendJobs,
    .sysroot       : ap.Option#(
        ?StringView, .help = "Argi installation prefix", .value_name = "PATH"
    ),
    .link_library : ap.Option#(
        ?StringView,
        .long_name  = "link-library",
        .help       = "Comma-separated native libraries",
        .value_name = "NAMES"
    ),
    .link_static_library : ap.Option#(
        ?StringView,
        .long_name  = "link-static-library",
        .help       = "Comma-separated static libraries",
        .value_name = "NAMES"
    ),
    .link_shared_library : ap.Option#(
        ?StringView,
        .long_name  = "link-shared-library",
        .help       = "Comma-separated shared libraries",
        .value_name = "NAMES"
    ),
    .library_path : ap.Option#(
        ?StringView,
        .long_name  = "library-path",
        .help       = "Comma-separated library search directories",
        .value_name = "PATHS"
    ),
    .link_file : ap.Option#(
        ?StringView,
        .long_name  = "link-file",
        .help       = "Comma-separated object or archive files",
        .value_name = "FILES"
    ),
    .cc : ap.Option#(
        ?StringView, .help = "C linking driver", .value_name = "DRIVER"
    ),
    .cc_arg : ap.Option#(
        ?StringView,
        .long_name  = "cc-arg",
        .help       = "Comma-separated C driver arguments",
        .value_name = "ARGS"
    ),
    .c_sysroot : ap.Option#(
        ?StringView,
        .long_name  = "c-sysroot",
        .help       = "C toolchain sysroot",
        .value_name = "PATH"
    ),
    .target   : TargetOption,
    .release  : ap.Flag#(.help = "Optimize generated code"),
    .no_cache : ap.Flag#(
        .long_name = "no-cache", .help = "Rebuild without the frontend cache"
    ),
    .stats           : ap.Flag#(.help = "Show compilation timings and statistics"),
    .vm              : ap.Flag#(.help = "Execute using the bytecode VM"),
    .vm_instructions : InstructionLimit,
    .vm_call_depth   : CallDepthLimit,
    .vm_value_cells  : ValueCellsLimit,
    .on_build_error_show_cascade : ap.Flag#(
        .long_name = "on-build-error-show-cascade", .help = "Show cascading diagnostics"
    ),
    .on_build_error_show_syntax_tree : ap.Flag#(
        .long_name = "on-build-error-show-syntax-tree",
        .help      = "Show the syntax tree on failure"
    ),
    .on_build_error_show_semantic_graph : ap.Flag#(
        .long_name = "on-build-error-show-semantic-graph",
        .help      = "Show the semantic graph on failure"
    )
)

ReplArgs := (
    .sysroot : ap.Option#(
        ?StringView, .help = "Argi installation prefix", .value_name = "PATH"
    ),
    .vm_instructions : InstructionLimit,
    .vm_call_depth   : CallDepthLimit,
    .vm_value_cells  : ValueCellsLimit
)

TestArgs := (
    .path   : ModulePath,
    .filter : ap.Option#(
        ?StringView, .help = "Run tests whose names contain this text", .value_name = "TEXT"
    ),
    .sysroot : ap.Option#(?StringView, .help = "Argi installation prefix", .value_name = "PATH")
)

InitArgs := (
    .name : ap.Positional#(
        StringView,
        .help          = "Project name or directory (default: current directory)",
        .default_value = ..some(.value = ".")
    ),
    .lib : ap.Flag#(.help = "Create a library module")
)

FormatArgs := (
    .path : ap.Positional#(
        StringView,
        .help          = "File or directory to format recursively (default: current directory)",
        .default_value = ..some(.value = ".")
    ),
    .check  : ap.Flag#(.help = "Check formatting without writing files"),
    .stdout : ap.Flag#(.help = "Print one formatted file without writing it")
)

EmptyArgs: Type = ()

CompilerCommand: Type = (
    ..build BuildArgs,
    ..check CheckArgs,
    ..run RunArgs,
    ..repl ReplArgs,
    ..test TestArgs,
    ..init InitArgs,
    ..format FormatArgs,
    ..lsp EmptyArgs,
    ..version ap.Subcommand#(EmptyArgs, .long_alias = "version", .short_alias = "V"),
    ..help ap.Subcommand#(ap.Help, .is_default = true)
)
