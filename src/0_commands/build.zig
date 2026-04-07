const std = @import("std");

const llvm = @import("../5_codegen/llvm.zig");
const c = llvm.c;

const sf = @import("../1_base/source_files.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const link = @import("../5_codegen/link.zig");
const codegen = @import("../5_codegen/codegen.zig");
const tokp = @import("../2_tokens/token_print.zig");
const frontend = @import("frontend_pipeline.zig");
const semantizer_mod = @import("../4_semantics/semantizer.zig");

pub const BuildFlags = struct {
    show_cascade: bool = false,
    show_syntax_tree: bool = false,
    show_semantic_graph: bool = false,
    show_token_list: bool = false,
    time_phases: bool = false,
    output_path: ?[]const u8 = null,
    llvm_ir_path: ?[]const u8 = null,
    object_path: ?[]const u8 = null,
    just_object_path: ?[]const u8 = null,
};

pub const CompileOptions = struct {
    frontend_options: frontend.FrontendPipeline.Options = .{},
    codegen_options: codegen.CodeGenerator.Options = .{},
    success_message: ?[]const u8 = "✔ Build completed\n",
};

/// Argi keeps project-local transient artifacts under `.argi-cache/`.
/// This stays separate from explicit user outputs like `build/output` or
/// `--output <path>`, and gives `argi test` a stable place to put generated
/// binaries without polluting source fixtures.
pub fn localCacheRoot(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.resolve(allocator, &.{".argi-cache"});
}

const PhaseTimings = struct {
    collect_files_ns: u64 = 0,
    tokenize_ns: u64 = 0,
    syntax_ns: u64 = 0,
    semantizing_ns: u64 = 0,
    codegen_ns: u64 = 0,
    link_ns: u64 = 0,

    fn total(self: PhaseTimings) u64 {
        return self.collect_files_ns + self.tokenize_ns + self.syntax_ns + self.semantizing_ns + self.codegen_ns + self.link_ns;
    }
};

fn parseFlags(args: []const []const u8) !BuildFlags {
    var flags: BuildFlags = .{};
    var idx: usize = 0;
    while (idx < args.len) : (idx += 1) {
        const a = args[idx];
        if (std.mem.eql(u8, a, "--on-build-error-show-cascade")) {
            flags.show_cascade = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-syntax-tree")) {
            flags.show_syntax_tree = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-semantic-graph")) {
            flags.show_semantic_graph = true;
        } else if (std.mem.eql(u8, a, "--on-build-error-show-token-list")) {
            flags.show_token_list = true;
        } else if (std.mem.eql(u8, a, "--time-phases")) {
            flags.time_phases = true;
        } else if (std.mem.eql(u8, a, "--output")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.output_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-llvm")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.llvm_ir_path = args[idx];
        } else if (std.mem.eql(u8, a, "--emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.object_path = args[idx];
        } else if (std.mem.eql(u8, a, "--just-emit-obj")) {
            idx += 1;
            if (idx >= args.len) return error.MissingFlagValue;
            flags.just_object_path = args[idx];
        }
    }
    if (flags.object_path != null and flags.just_object_path != null) return error.ConflictingObjectEmissionModes;
    return flags;
}

fn printTokenList(all: []const token.Token) void {
    std.debug.print("\nTOKENS\n", .{});
    for (all, 0..) |t, i| {
        std.debug.print("{d}: ", .{i});
        tokp.printTokenWithLocation(t, t.location);
    }
}

fn elapsedSince(start_ns: i128) u64 {
    return @intCast(std.time.nanoTimestamp() - start_ns);
}

fn printPhaseTimings(timings: PhaseTimings) void {
    std.debug.print("phase timings:\n", .{});
    std.debug.print("  collect files: {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.collect_files_ns)) / 1_000_000.0});
    std.debug.print("  tokenize:      {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.tokenize_ns)) / 1_000_000.0});
    std.debug.print("  syntax:        {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.syntax_ns)) / 1_000_000.0});
    std.debug.print("  semantizing:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.semantizing_ns)) / 1_000_000.0});
    std.debug.print("  codegen:       {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.codegen_ns)) / 1_000_000.0});
    std.debug.print("  link:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.link_ns)) / 1_000_000.0});
    std.debug.print("  total:         {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.total())) / 1_000_000.0});
}

fn printSemantizingTimings(timings: semantizer_mod.Semantizer.SemantizeTimings) void {
    std.debug.print("semantizing breakdown:\n", .{});
    std.debug.print("  initial pass:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.initial_pass_ns)) / 1_000_000.0});
    std.debug.print("    support top-level:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.support_top_level_ns)) / 1_000_000.0});
    std.debug.print("    function interface:  {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_interface_ns)) / 1_000_000.0});
    std.debug.print("    function in defaults:{d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_input_defaults_ns)) / 1_000_000.0});
    std.debug.print("    function out defs:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_output_defaults_ns)) / 1_000_000.0});
    std.debug.print("    function bodies:     {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.function_body_ns)) / 1_000_000.0});
    std.debug.print("  retry passes:          {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.retry_passes_ns)) / 1_000_000.0});
    std.debug.print("  initial retry nodes:   {d}\n", .{timings.initial_retry_count});
    std.debug.print("  retry rounds:          {d}\n", .{timings.retry_round_count});
    std.debug.print("  retry enqueue dedupe:  {d}/{d}\n", .{ timings.retry_enqueue_unique, timings.retry_enqueue_attempts });
    std.debug.print("  retry node kinds:      fn={d} type={d} symbol={d} other={d}\n", .{
        timings.retry_function_nodes,
        timings.retry_type_nodes,
        timings.retry_symbol_nodes,
        timings.retry_other_nodes,
    });
    std.debug.print("  final retry resolve:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.final_retry_resolution_ns)) / 1_000_000.0});
    std.debug.print("  verify abstracts:      {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.abstract_verify_ns)) / 1_000_000.0});
    std.debug.print("  verify once:           {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.once_verify_ns)) / 1_000_000.0});
    std.debug.print("  infer error reasons:   {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.error_reason_inference_ns)) / 1_000_000.0});
    std.debug.print("  semantizing total:     {d:.3} ms\n", .{@as(f64, @floatFromInt(timings.total())) / 1_000_000.0});
}

fn dumpDiagnosticsOrWarn(
    diagnostics: *diag.Diagnostics,
    limit: usize,
) void {
    diagnostics.dumpWithLimit(limit) catch |err| {
        std.debug.print("failed to print diagnostics: {s}\n", .{@errorName(err)});
    };
}

pub fn resolveBuildModuleDir(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (std.fs.cwd().openDir(path, .{})) |opened_dir| {
        var dir = opened_dir;
        dir.close();
        return std.fs.path.resolve(allocator, &.{path});
    } else |dir_err| switch (dir_err) {
        error.NotDir, error.FileNotFound => {},
        else => return dir_err,
    }

    _ = try std.fs.cwd().statFile(path);
    const dir = std.fs.path.dirname(path) orelse ".";
    return std.fs.path.resolve(allocator, &.{dir});
}

fn ensureParentDir(path: []const u8) !void {
    const parent = std.fs.path.dirname(path) orelse return;
    if (parent.len == 0 or std.mem.eql(u8, parent, ".")) return;
    try std.fs.cwd().makePath(parent);
}

pub fn defaultOutputPathForModuleDir(allocator: std.mem.Allocator, module_dir: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        allocator,
        "{s}/build/output",
        .{module_dir},
    );
}

fn replaceFile(src: []const u8, dst: []const u8) !void {
    std.fs.cwd().rename(src, dst) catch |err| switch (err) {
        error.PathAlreadyExists => {
            try std.fs.cwd().deleteFile(dst);
            try std.fs.cwd().rename(src, dst);
        },
        else => return err,
    };
}

pub fn compileTarget(target_path: []const u8, flags: BuildFlags, options: CompileOptions) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const module_dir = try resolveBuildModuleDir(allocator, target_path);
    var timings: PhaseTimings = .{};

    // Salidas finales por defecto dentro del módulo compilado.
    const final_output_path = if (flags.output_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        try defaultOutputPathForModuleDir(allocator, module_dir);
    const final_ir_path = if (flags.llvm_ir_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        null;
    const final_obj_path = if (flags.just_object_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else if (flags.object_path) |path|
        try std.fs.path.resolve(allocator, &.{path})
    else
        null;
    const emit_object_only = flags.just_object_path != null;

    if (!emit_object_only) try ensureParentDir(final_output_path);
    if (final_ir_path) |path| try ensureParentDir(path);
    if (final_obj_path) |path| try ensureParentDir(path);

    // 1. Reunir ficheros ──────────────────────────────────────────────────
    const collect_start = std.time.nanoTimestamp();
    const files = try sf.collectModule(&allocator, "core", module_dir);
    timings.collect_files_ns = elapsedSince(collect_start);

    // 2. Diagnósticos globales ────────────────────────────────────────────
    var diagnostics = diag.Diagnostics.init(&allocator, files.items);

    var pipeline = frontend.FrontendPipeline.init(&allocator, &diagnostics, options.frontend_options);
    defer pipeline.deinit();

    // 3. Tokenizar todos (fusionando EOF) ─────────────────────────────────
    const tokenize_start = std.time.nanoTimestamp();
    pipeline.tokenizeFiles(files.items) catch {
        timings.tokenize_ns = elapsedSince(tokenize_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.tokenize_ns = elapsedSince(tokenize_start);

    // 4. Sintaxis ──────────────────────────────────────────────────────────
    const syntax_start = std.time.nanoTimestamp();
    _ = pipeline.syntax() catch {
        timings.syntax_ns = elapsedSince(syntax_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.syntax_ns = elapsedSince(syntax_start);

    // 5. Semántica ────────────────────────────────────────────────────────
    const semantizing_start = std.time.nanoTimestamp();
    const sg = pipeline.semantize() catch {
        timings.semantizing_ns = elapsedSince(semantizing_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.semantizing_ns = elapsedSince(semantizing_start);

    // 6. Si hubo errores semánticos, parar antes de codegen ───────────────
    if (diagnostics.hasErrors()) {
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.syntax_ctx) |*syntax_ctx| {
            if (flags.show_syntax_tree) syntax_ctx.printST();
        }
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    }

    // 7. Generación de código ──────────────────────────────────────────────
    const codegen_start = std.time.nanoTimestamp();
    var gen = codegen.CodeGenerator.init(&allocator, sg, &diagnostics, options.codegen_options) catch |err| {
        std.debug.print("failed to initialize codegen: {s}\n", .{@errorName(err)});
        return err;
    };
    const module = gen.generate() catch {
        timings.codegen_ns = elapsedSince(codegen_start);
        if (flags.show_token_list) printTokenList(pipeline.tokens.items);
        if (pipeline.sem_ctx) |*semantizer_ctx| {
            if (flags.show_semantic_graph) semantizer_ctx.printSG();
        }
        dumpDiagnosticsOrWarn(&diagnostics, if (flags.show_cascade) std.math.maxInt(usize) else 1);
        return error.CompilationFailed;
    };
    timings.codegen_ns = elapsedSince(codegen_start);

    // Temporales en el mismo directorio final.
    const temp_stem_base = if (emit_object_only) final_obj_path.? else final_output_path;
    const temp_stem = try std.fmt.allocPrint(
        allocator,
        "{s}.tmp.{d}",
        .{ temp_stem_base, std.time.nanoTimestamp() },
    );
    const temp_ir_path = if (final_ir_path != null)
        try std.fmt.allocPrint(
            allocator,
            "{s}.ll",
            .{temp_stem},
        )
    else
        null;
    const temp_obj_path = try std.fmt.allocPrint(
        allocator,
        "{s}.o",
        .{temp_stem},
    );

    try ensureParentDir(temp_stem);
    if (temp_ir_path) |path| try ensureParentDir(path);
    try ensureParentDir(temp_obj_path);

    if (temp_ir_path) |path| {
        std.fs.cwd().deleteFile(path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }
    std.fs.cwd().deleteFile(temp_stem) catch |err| {
        if (err != error.FileNotFound) return err;
    };
    std.fs.cwd().deleteFile(temp_obj_path) catch |err| {
        if (err != error.FileNotFound) return err;
    };

    // 8. Escribir el módulo LLVM a un fichero .ll ─────────────────────────
    if (temp_ir_path) |path| {
        var err_msg: [*c]u8 = null;
        const temp_ir_path_c = try allocator.dupeZ(u8, path);
        if (c.LLVMPrintModuleToFile(module, temp_ir_path_c.ptr, &err_msg) != 0) {
            std.debug.print("Failed to write LLVM module: {s}\n", .{err_msg});
            return error.WriteFailed;
        }
    }

    // 9. Emitir objeto y, si hace falta, enlazar con libc ─────────────────
    const triple_cstr = c.LLVMGetDefaultTargetTriple();
    defer c.LLVMDisposeMessage(triple_cstr);
    const triple = std.mem.span(triple_cstr);

    const link_start = std.time.nanoTimestamp();
    if (emit_object_only)
        try link.emitObjectFile(module, triple, temp_obj_path)
    else
        try link.linkWithLibc(module, triple, temp_stem, &allocator);
    timings.link_ns = elapsedSince(link_start);

    // 10. Mover a nombres finales ─────────────────────────────────────────
    if (temp_ir_path) |src| {
        const dst = final_ir_path.?;
        if (std.fs.cwd().statFile(src)) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp ir before rename: {s}\n", .{src});
                return err;
            },
            else => return err,
        }
        try replaceFile(src, dst);
    }

    if (!emit_object_only) {
        if (std.fs.cwd().statFile(temp_stem)) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp output before rename: {s}\n", .{temp_stem});
                return err;
            },
            else => return err,
        }
        try replaceFile(temp_stem, final_output_path);
    }

    if (final_obj_path) |obj_dst| {
        if (std.fs.cwd().statFile(temp_obj_path)) |_| {} else |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("missing temp obj before rename: {s}\n", .{temp_obj_path});
                return err;
            },
            else => return err,
        }
        try replaceFile(temp_obj_path, obj_dst);
    } else {
        std.fs.cwd().deleteFile(temp_obj_path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    if (flags.time_phases) {
        printPhaseTimings(timings);
        printSemantizingTimings(pipeline.semantize_timings);
    }

    if (options.success_message) |message| {
        std.debug.print("{s}", .{message});
    }
}

pub fn compile(args: []const []const u8) !void {
    if (args.len == 0) return error.MissingBuildTarget;
    const flags = try parseFlags(args[1..]);
    try compileTarget(args[0], flags, .{});
}

test "parse build flags keeps diagnostics toggles and output paths" {
    const flags = try parseFlags(&.{
        "--on-build-error-show-cascade",
        "--on-build-error-show-token-list",
        "--time-phases",
        "--output",
        "bin/app",
        "--emit-llvm",
        "ir/app.ll",
        "--emit-obj",
        "obj/app.o",
    });

    try std.testing.expect(flags.show_cascade);
    try std.testing.expect(flags.show_token_list);
    try std.testing.expect(flags.time_phases);
    try std.testing.expectEqualStrings("bin/app", flags.output_path.?);
    try std.testing.expectEqualStrings("ir/app.ll", flags.llvm_ir_path.?);
    try std.testing.expectEqualStrings("obj/app.o", flags.object_path.?);
    try std.testing.expect(flags.just_object_path == null);
}

test "parse build flags rejects missing path value" {
    try std.testing.expectError(error.MissingFlagValue, parseFlags(&.{"--output"}));
}

test "parse build flags keeps just emit obj path" {
    const flags = try parseFlags(&.{
        "--just-emit-obj",
        "obj-only/app.o",
    });

    try std.testing.expectEqualStrings("obj-only/app.o", flags.just_object_path.?);
    try std.testing.expect(flags.object_path == null);
}

test "parse build flags rejects conflicting object emission modes" {
    try std.testing.expectError(error.ConflictingObjectEmissionModes, parseFlags(&.{
        "--emit-obj",
        "obj/app.o",
        "--just-emit-obj",
        "obj-only/app.o",
    }));
}

test "local cache root resolves to dot argi cache" {
    const cache_root = try localCacheRoot(std.testing.allocator);
    defer std.testing.allocator.free(cache_root);

    try std.testing.expect(std.mem.endsWith(u8, cache_root, "/.argi-cache") or std.mem.eql(u8, cache_root, ".argi-cache"));
}
