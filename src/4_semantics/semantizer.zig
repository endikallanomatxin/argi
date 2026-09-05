const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const log = std.log.scoped(.semantizer);

const typ = @import("types.zig");
const abs = @import("abstracts.zig");
const gen = @import("generics.zig");
const Scope = @import("scope.zig").Scope;
const SemErr = @import("errors.zig").SemErr;

fn safetyPrimitiveForBundledDeclaration(name: []const u8, file: []const u8) sg.SafetyPrimitive {
    const Entry = struct { name: []const u8, primitive: sg.SafetyPrimitive };
    const raw_pointer_entries = [_]Entry{
        .{ .name = "establish_fresh_reference", .primitive = .establish_fresh_reference },
        .{ .name = "establish_inherited_reference", .primitive = .establish_inherited_reference },
        .{ .name = "establish_inherited_storage", .primitive = .establish_inherited_storage },
        .{ .name = "reference_offset", .primitive = .reference_offset },
        .{ .name = "mutable_reference_offset", .primitive = .mutable_reference_offset },
        .{ .name = "reinterpret_reference", .primitive = .reinterpret_reference },
        .{ .name = "mutable_reinterpret_reference", .primitive = .mutable_reinterpret_reference },
        .{ .name = "read_reference", .primitive = .read_reference },
    };
    if (std.mem.endsWith(u8, file, "core/memory/heap_allocation/RawPointer.rg"))
        for (raw_pointer_entries) |entry| if (std.mem.eql(u8, name, entry.name)) return entry.primitive;
    if (std.mem.endsWith(u8, file, "core/memory/heap_allocation/Allocator.rg") and
        std.mem.eql(u8, name, "establish_allocation")) return .establish_allocation;
    if (std.mem.endsWith(u8, file, "core/memory/relocation.rg") and
        std.mem.eql(u8, name, "relocate")) return .relocate;
    if (std.mem.endsWith(u8, file, "core/memory/reference_lifetime.rg") and
        std.mem.eql(u8, name, "restrict_reference")) return .restrict_reference;
    // SourceFile.origin establishes trust before this function is reached.
    // The canonical path only identifies the trusted declaration, so another
    // bundled-core helper with the same name cannot become a primitive.
    if (std.mem.endsWith(u8, file, "core/memory/opaque_ownership.rg")) {
        if (std.mem.eql(u8, name, "trusted_opaque_move")) return .trusted_opaque_move;
        if (std.mem.eql(u8, name, "trusted_opaque_move_in")) return .trusted_opaque_move_in;
        if (std.mem.eql(u8, name, "trusted_opaque_move_out")) return .trusted_opaque_move_out;
        if (std.mem.eql(u8, name, "trusted_opaque_relocate")) return .trusted_opaque_relocate;
        if (std.mem.eql(u8, name, "trusted_opaque_drop")) return .trusted_opaque_drop;
        if (std.mem.eql(u8, name, "trusted_opaque_mark_empty")) return .trusted_opaque_mark_empty;
    }
    if (std.mem.endsWith(u8, file, "core/libc/libc.rg") and std.mem.eql(u8, name, "malloc"))
        return .raw_allocated_storage;
    return .none;
}

fn nowNs(io: std.Io) i96 {
    return std.Io.Timestamp.now(io, .boot).nanoseconds;
}

const OwnedText = struct {
    allocator: *const std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: OwnedText) void {
        self.allocator.free(self.bytes);
    }
};

const TypePairText = struct {
    expected: OwnedText,
    actual: OwnedText,

    fn deinit(self: TypePairText) void {
        self.expected.deinit();
        self.actual.deinit();
    }
};

const SignatureText = struct {
    actual: OwnedText,
    available: OwnedText,

    fn deinit(self: SignatureText) void {
        self.actual.deinit();
        self.available.deinit();
    }
};

const ReachFunctionContext = struct {
    function_name: []const u8,
    location: tok.Location,
    input_struct: *sg.StructType,
    body_scope: *Scope,
};

const PendingFunctionBody = struct {
    const State = enum { unseen, queued, done };

    top_node: syn.SyntaxRef,
    decl: syn.FunctionDeclaration,
    location: tok.Location,
    function: *sg.FunctionDeclaration,
    is_test: bool = false,
    prepared_scope: ?*Scope = null,
    prepared_input_struct: ?*sg.StructType = null,
    state: State = .unseen,
};

pub const SemantizerOptions = struct {
    include_tests: bool = false,
    selected_test_name: ?[]const u8 = null,
    implicit_testing_module_dir: ?[]const u8 = null,
    exhaustive_function_bodies: bool = false,
};

const OnceConsumption = struct {
    first_location: tok.Location,
    first_consumer: *const sg.FunctionDeclaration,
};

const OnceTraversalState = struct {
    seen_once: std.AutoHashMap(*const sg.FunctionDeclaration, OnceConsumption),
    active_functions: std.array_list.Managed(*const sg.FunctionDeclaration),

    fn init(allocator: *const std.mem.Allocator) OnceTraversalState {
        return .{
            .seen_once = std.AutoHashMap(*const sg.FunctionDeclaration, OnceConsumption).init(allocator.*),
            .active_functions = std.array_list.Managed(*const sg.FunctionDeclaration).init(allocator.*),
        };
    }

    fn deinit(self: *OnceTraversalState) void {
        self.seen_once.deinit();
        self.active_functions.deinit();
    }
};

const AutoDeinitResolution = struct {
    function: *sg.FunctionDeclaration,
    input: typ.TypedExpr,
    self_field_index: u32,
};

const GenericSubst = struct {
    allocator: *const std.mem.Allocator,
    types: std.StringHashMap(sg.Type),
    ints: std.StringHashMap(i64),

    fn init(allocator: *const std.mem.Allocator) GenericSubst {
        return .{
            .allocator = allocator,
            .types = std.StringHashMap(sg.Type).init(allocator.*),
            .ints = std.StringHashMap(i64).init(allocator.*),
        };
    }

    fn deinit(self: *GenericSubst) void {
        self.types.deinit();
        self.ints.deinit();
    }

    fn cloneFrom(self: *GenericSubst, other: *const GenericSubst) !void {
        var it_types = other.types.iterator();
        while (it_types.next()) |entry| {
            try self.types.put(entry.key_ptr.*, entry.value_ptr.*);
        }

        var it_ints = other.ints.iterator();
        while (it_ints.next()) |entry| {
            try self.ints.put(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
};

const GenericSpecialization = struct {
    template_name: []const u8,
    template_location: tok.Location,
    dispatch_kind: gen.GenericDispatchKind,
    input: *const sg.StructType,
    output: *const sg.StructType,
    subst: GenericSubst,
    function: *sg.FunctionDeclaration,

    fn deinit(self: *GenericSpecialization) void {
        self.subst.deinit();
    }
};

//──────────────────────────────────────────────────────────────────────────────
//  SEMANTIZER
//──────────────────────────────────────────────────────────────────────────────
pub const Semantizer = struct {
    // Semantizing is staged explicitly instead of relying on retries as the
    // normal path:
    // 1. predeclare top-level symbols
    // 2. stabilize support top-level declarations
    // 3. semantize callable function interfaces
    // 4. verify abstracts over that declaration-only world
    // 5. semantize deferred function defaults and bodies
    //
    // The split keeps top-level nominal work separated from executable body
    // work and makes the remaining retries residual rather than fundamental.
    allocator: *const std.mem.Allocator,
    io: std.Io,
    syntax_files: []const syn.SyntaxFile,
    syntax_roots: []const syn.SyntaxRef,
    root_list: std.array_list.Managed(*sg.SGNode), // buffer mut
    root_nodes: []const *sg.SGNode = &.{}, // slice final
    diags: *diagnostic.Diagnostics,
    options: SemantizerOptions,

    // ── Reintentos top-level
    pending_now: std.array_list.Managed(syn.SyntaxRef),
    pending_next: std.array_list.Managed(syn.SyntaxRef),
    defer_unknown_top_level: bool = false,
    current_top_node: ?syn.SyntaxRef = null,
    max_retry_rounds: u32 = 8,
    retry_enqueue_attempts: u32 = 0,
    retry_enqueue_unique: u32 = 0,
    retry_function_nodes: u32 = 0,
    retry_type_nodes: u32 = 0,
    retry_symbol_nodes: u32 = 0,
    retry_other_nodes: u32 = 0,
    function_semantize_mode: FunctionSemantizeMode = .full,
    pending_function_bodies: std.array_list.Managed(PendingFunctionBody),
    function_body_worklist: std.array_list.Managed(usize),
    discover_function_references: bool = false,
    generic_specializations: std.array_list.Managed(GenericSpecialization),
    generic_specializations_created: u32 = 0,
    generic_specialization_cache_hits: u32 = 0,
    synthetic_name_counter: u32 = 0,
    next_function_id: u32 = 1,
    next_choice_option_id: u32 = 1,
    next_inferred_choice_identity_id: u32 = 1,
    function_reach_stack: std.array_list.Managed(ReachFunctionContext),

    fn safetyPrimitiveForDeclaration(self: *const Semantizer, name: []const u8, file: []const u8) sg.SafetyPrimitive {
        for (self.diags.source_files) |source| {
            if (!std.mem.eql(u8, source.path, file)) continue;
            if (source.origin != .bundled_core) return .none;
            return safetyPrimitiveForBundledDeclaration(name, file);
        }
        return .none;
    }

    pub fn init(
        alloc: *const std.mem.Allocator,
        io: std.Io,
        syntax_files: []const syn.SyntaxFile,
        st: []const syn.SyntaxRef,
        diags: *diagnostic.Diagnostics,
        options: SemantizerOptions,
    ) Semantizer {
        return .{
            .allocator = alloc,
            .io = io,
            .syntax_files = syntax_files,
            .syntax_roots = st,
            .root_list = std.array_list.Managed(*sg.SGNode).init(alloc.*),
            .diags = diags,
            .options = options,
            .pending_now = std.array_list.Managed(syn.SyntaxRef).init(alloc.*),
            .pending_next = std.array_list.Managed(syn.SyntaxRef).init(alloc.*),
            .pending_function_bodies = std.array_list.Managed(PendingFunctionBody).init(alloc.*),
            .function_body_worklist = std.array_list.Managed(usize).init(alloc.*),
            .generic_specializations = std.array_list.Managed(GenericSpecialization).init(alloc.*),
            .function_reach_stack = std.array_list.Managed(ReachFunctionContext).init(alloc.*),
        };
    }

    fn freshFunctionId(self: *Semantizer) u32 {
        const id = self.next_function_id;
        self.next_function_id += 1;
        return id;
    }

    fn syntaxFile(self: *const Semantizer, node: syn.SyntaxRef) *const syn.SyntaxFile {
        return syn.fileForRef(self.syntax_files, node);
    }

    fn nodeTag(self: *const Semantizer, node: syn.SyntaxRef) syn.Node.Tag {
        return self.syntaxFile(node).tag(node.node);
    }

    fn nodeLocation(self: *const Semantizer, node: syn.SyntaxRef) tok.Location {
        return self.syntaxFile(node).location(node.node);
    }

    fn childRef(self: *const Semantizer, parent: syn.SyntaxRef, child: syn.NodeIndex) syn.SyntaxRef {
        _ = self;
        return .{ .file_id = parent.file_id, .node = child };
    }

    fn tokenText(self: *const Semantizer, owner: syn.SyntaxRef, token_index: syn.TokenIndex) []const u8 {
        return self.syntaxFile(owner).tokenText(&self.diags.source_db, token_index);
    }

    fn tokenLocation(self: *const Semantizer, owner: syn.SyntaxRef, token_index: syn.TokenIndex) tok.Location {
        return self.syntaxFile(owner).tokenLocation(token_index);
    }

    fn topLevelNodeIsCallable(self: *Semantizer, n: syn.SyntaxRef) bool {
        return switch (self.nodeTag(n)) {
            .function_declaration, .function_declaration_once => true,
            .test_declaration => self.options.include_tests,
            else => false,
        };
    }

    pub const SemantizeTimings = struct {
        initial_pass_ns: u64 = 0,
        support_top_level_ns: u64 = 0,
        function_interface_ns: u64 = 0,
        function_input_defaults_ns: u64 = 0,
        function_output_defaults_ns: u64 = 0,
        function_body_ns: u64 = 0,
        retry_passes_ns: u64 = 0,
        final_retry_resolution_ns: u64 = 0,
        abstract_verify_ns: u64 = 0,
        once_verify_ns: u64 = 0,
        error_reason_inference_ns: u64 = 0,
        initial_retry_count: u32 = 0,
        retry_round_count: u32 = 0,
        retry_enqueue_attempts: u32 = 0,
        retry_enqueue_unique: u32 = 0,
        retry_function_nodes: u32 = 0,
        retry_type_nodes: u32 = 0,
        retry_symbol_nodes: u32 = 0,
        retry_other_nodes: u32 = 0,
        generic_specializations_created: u32 = 0,
        generic_specialization_cache_hits: u32 = 0,
        declared_function_bodies_semantized: u32 = 0,

        pub fn total(self: SemantizeTimings) u64 {
            return self.initial_pass_ns +
                self.retry_passes_ns +
                self.final_retry_resolution_ns +
                self.abstract_verify_ns +
                self.once_verify_ns +
                self.error_reason_inference_ns;
        }
    };

    pub fn semantize(self: *Semantizer) SemErr![]const *sg.SGNode {
        return (try self.semantizeWithTimings()).nodes;
    }

    pub const SemantizeResult = struct {
        nodes: []const *sg.SGNode,
        timings: SemantizeTimings,
    };

    fn locationPath(self: *const Semantizer, loc: tok.Location) []const u8 {
        return self.diags.path(loc);
    }

    fn locationLineColumn(self: *const Semantizer, loc: tok.Location) source_db.LineColumn {
        return self.diags.lineColumn(loc);
    }

    fn ignoreOrLogStagedTopLevelError(self: *Semantizer, n: syn.SyntaxRef, err: anyerror) void {
        switch (err) {
            error.Reported, error.UnknownType, error.SymbolNotFound => return,
            else => {},
        }

        log.warn(
            "staged top-level semantizing of '{s}' failed at {s}:{d}:{d} with {s}",
            .{
                @tagName(self.nodeTag(n)),
                self.locationPath(self.nodeLocation(n)),
                self.locationLineColumn(self.nodeLocation(n)).line,
                self.locationLineColumn(self.nodeLocation(n)).column,
                @errorName(err),
            },
        );
    }

    const FunctionSemantizeMode = enum {
        full,
        interface_only,
        body_only,
    };

    const PendingFunctionBodyTimings = struct {
        input_defaults_ns: u64 = 0,
        output_defaults_ns: u64 = 0,
        body_ns: u64 = 0,
    };

    pub fn semantizeWithTimings(self: *Semantizer) SemErr!SemantizeResult {
        self.clearGenericSpecializationCache();
        defer self.clearGenericSpecializationCache();
        var global = try Scope.init(self.allocator, null, null);
        if (self.options.implicit_testing_module_dir) |testing_module_dir| {
            try global.module_aliases.put("testing", testing_module_dir);
        }
        try self.predeclareTopLevelSymbols(&global);
        var timings: SemantizeTimings = .{};
        self.retry_enqueue_attempts = 0;
        self.retry_enqueue_unique = 0;
        self.retry_function_nodes = 0;
        self.retry_type_nodes = 0;
        self.retry_symbol_nodes = 0;
        self.retry_other_nodes = 0;
        self.generic_specializations_created = 0;
        self.generic_specialization_cache_hits = 0;
        self.function_semantize_mode = .full;
        self.pending_function_bodies.items.len = 0;
        self.function_body_worklist.items.len = 0;
        self.discover_function_references = false;

        // 1) Pasada inicial: estabiliza primero top-level de soporte y sólo
        // después entra en funciones. Esto evita que los cuerpos se conviertan
        // en la fuente principal de dependencias top-level pendientes.
        const initial_start = nowNs(self.io);
        self.defer_unknown_top_level = true;
        const support_top_level_start = nowNs(self.io);
        for (self.syntax_roots) |n| {
            if (self.topLevelNodeIsCallable(n)) continue;
            if (self.nodeTag(n) == .test_declaration and !self.options.include_tests) continue;
            self.current_top_node = n;
            _ = self.visitNode(n, &global) catch |err| {
                self.ignoreOrLogStagedTopLevelError(n, err);
            };
        }

        var support_round: u32 = 0;
        while (self.hasPendingNonFunctionNodes() and support_round < self.max_retry_rounds) {
            const tmp = self.pending_now;
            self.pending_now = self.pending_next;
            self.pending_next = tmp;
            self.pending_next.items.len = 0;

            var progressed = false;
            for (self.pending_now.items) |pn| {
                if (self.topLevelNodeIsCallable(pn)) {
                    try self.pending_next.append(pn);
                    continue;
                }

                self.current_top_node = pn;
                if (self.visitNode(pn, &global)) |_| {
                    progressed = true;
                } else |_| {}
            }

            self.current_top_node = null;
            self.pending_now.items.len = 0;
            if (!progressed) break;
            support_round += 1;
        }
        timings.support_top_level_ns = @intCast(nowNs(self.io) - support_top_level_start);

        // Functions are semantized in two late stages: first their callable
        // interface, so overloads and abstract checks can stabilize on a
        // declaration-only world, and only afterwards their defaults and
        // bodies. Requiring explicit signature types is what keeps this split
        // practical without depending on body-semantic inference.
        const function_interface_start = nowNs(self.io);
        self.function_semantize_mode = .interface_only;
        for (self.syntax_roots) |n| {
            if (!self.topLevelNodeIsCallable(n)) continue;
            self.current_top_node = n;
            _ = self.visitNode(n, &global) catch |err| {
                self.ignoreOrLogStagedTopLevelError(n, err);
            };
        }
        self.current_top_node = null;

        var interface_round: u32 = 0;
        while (self.hasPendingFunctionNodes() and interface_round < self.max_retry_rounds) {
            const tmp = self.pending_now;
            self.pending_now = self.pending_next;
            self.pending_next = tmp;
            self.pending_next.items.len = 0;

            var progressed = false;
            for (self.pending_now.items) |pn| {
                if (!self.topLevelNodeIsCallable(pn)) {
                    try self.pending_next.append(pn);
                    continue;
                }

                self.current_top_node = pn;
                if (self.visitNode(pn, &global)) |_| {
                    progressed = true;
                } else |_| {}
            }

            self.current_top_node = null;
            self.pending_now.items.len = 0;
            if (!progressed) break;
            interface_round += 1;
        }
        timings.function_interface_ns = @intCast(nowNs(self.io) - function_interface_start);

        const abstract_verify_start = nowNs(self.io);
        try abs.verifyAbstracts(&global, self.allocator, self.diags);
        timings.abstract_verify_ns = @intCast(nowNs(self.io) - abstract_verify_start);

        self.function_semantize_mode = .body_only;
        const pending_fn_timings = try self.semantizePendingFunctionBodies(&global);
        self.function_semantize_mode = .full;
        timings.function_input_defaults_ns = pending_fn_timings.input_defaults_ns;
        timings.function_output_defaults_ns = pending_fn_timings.output_defaults_ns;
        timings.function_body_ns = pending_fn_timings.body_ns;
        timings.initial_pass_ns = @intCast(nowNs(self.io) - initial_start);
        timings.initial_retry_count = @intCast(self.pending_next.items.len);
        // 2) Rondas de reintento: solo lo pendiente
        const retry_start = nowNs(self.io);
        var round: u32 = 0;
        while (self.pending_next.items.len > 0 and round < self.max_retry_rounds) {
            // swap pending_next -> pending_now
            const tmp = self.pending_now;
            self.pending_now = self.pending_next;
            self.pending_next = tmp;
            self.pending_next.items.len = 0;

            var progressed = false;
            for (self.pending_now.items) |pn| {
                if (self.nodeTag(pn) == .function_declaration or self.nodeTag(pn) == .function_declaration_once) continue;
                self.current_top_node = pn;
                if (self.visitNode(pn, &global)) |_| {
                    progressed = true;
                } else |_| {
                    // Las causas distintas de UnknownType ya se reportan dentro.
                    // UnknownType vuelve a entrar en pending_next si procede.
                }
            }
            for (self.pending_now.items) |pn| {
                if (self.nodeTag(pn) != .function_declaration and self.nodeTag(pn) != .function_declaration_once) continue;
                self.current_top_node = pn;
                if (self.visitNode(pn, &global)) |_| {
                    progressed = true;
                } else |_| {
                    // Las causas distintas de UnknownType ya se reportan dentro.
                    // UnknownType vuelve a entrar en pending_next si procede.
                }
            }
            self.current_top_node = null;
            self.pending_now.items.len = 0; // vaciar
            if (!progressed) break;
            round += 1;
        }
        timings.retry_passes_ns = @intCast(nowNs(self.io) - retry_start);
        timings.retry_round_count = round;

        // 3) Último pase: ya NO diferir => emitir diags de lo que quede
        const final_retry_start = nowNs(self.io);
        self.defer_unknown_top_level = false;
        if (self.pending_next.items.len > 0) {
            for (self.pending_next.items) |pn| {
                self.current_top_node = pn;
                _ = self.visitNode(pn, &global) catch |err| {
                    self.ignoreOrLogStagedTopLevelError(pn, err);
                };
            }
            self.current_top_node = null;
            self.pending_next.items.len = 0;
        }
        timings.final_retry_resolution_ns = @intCast(nowNs(self.io) - final_retry_start);

        const once_verify_start = nowNs(self.io);
        try self.verifyOnceFunctions(&global);
        timings.once_verify_ns = @intCast(nowNs(self.io) - once_verify_start);

        const reason_inference_start = nowNs(self.io);
        try self.inferFunctionErrorReasons(&global);
        timings.error_reason_inference_ns = @intCast(nowNs(self.io) - reason_inference_start);
        timings.retry_enqueue_attempts = self.retry_enqueue_attempts;
        timings.retry_enqueue_unique = self.retry_enqueue_unique;
        timings.retry_function_nodes = self.retry_function_nodes;
        timings.retry_type_nodes = self.retry_type_nodes;
        timings.retry_symbol_nodes = self.retry_symbol_nodes;
        timings.retry_other_nodes = self.retry_other_nodes;
        timings.generic_specializations_created = self.generic_specializations_created;
        timings.generic_specialization_cache_hits = self.generic_specialization_cache_hits;
        timings.declared_function_bodies_semantized = 0;
        for (self.pending_function_bodies.items) |pending| {
            if (pending.state == .done) timings.declared_function_bodies_semantized += 1;
        }

        self.root_nodes = try self.root_list.toOwnedSlice();
        self.root_list.deinit();
        self.clearDeferred(&global);
        return .{
            .nodes = self.root_nodes,
            .timings = timings,
        };
    }

    fn hasPendingNonFunctionNodes(self: *Semantizer) bool {
        for (self.pending_next.items) |pending| {
            if (!self.topLevelNodeIsCallable(pending)) return true;
        }
        return false;
    }

    fn hasPendingFunctionNodes(self: *Semantizer) bool {
        for (self.pending_next.items) |pending| {
            if (self.topLevelNodeIsCallable(pending)) return true;
        }
        return false;
    }

    fn enqueuePendingFunctionBody(
        self: *Semantizer,
        top_node: syn.SyntaxRef,
        decl: syn.FunctionDeclaration,
        loc: tok.Location,
        function: *sg.FunctionDeclaration,
        is_test: bool,
    ) !void {
        for (self.pending_function_bodies.items) |pending| {
            if (pending.location.file == loc.file and pending.location.offset == loc.offset) return;
        }

        try self.pending_function_bodies.append(.{
            .top_node = top_node,
            .decl = decl,
            .location = loc,
            .function = function,
            .is_test = is_test,
        });
    }

    fn semantizePendingFunctionBodies(self: *Semantizer, global: *Scope) SemErr!PendingFunctionBodyTimings {
        const deferred = try self.allocator.alloc(bool, self.pending_function_bodies.items.len);
        @memset(deferred, false);
        var timings: PendingFunctionBodyTimings = .{};

        // Input defaults are part of the callable interface because omitted
        // call arguments need them before any function body is semantized.
        const input_defaults_start = nowNs(self.io);
        for (self.pending_function_bodies.items, 0..) |*pending, idx| {
            self.current_top_node = pending.top_node;
            self.prepareFunctionInputDefaults(pending, global) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => {
                    try self.pushTopLevelForRetry();
                    deferred[idx] = true;
                },
                else => return err,
            };
        }
        timings.input_defaults_ns = @intCast(nowNs(self.io) - input_defaults_start);

        if (self.options.exhaustive_function_bodies) {
            for (self.pending_function_bodies.items) |pending| try self.enqueueFunctionBody(pending.function);
            // The worklist is normally a dependency-first stack. Exhaustive
            // checking deliberately retains declaration order so that it
            // continues to provide the established whole-program diagnostic
            // behavior.
            std.mem.reverse(usize, self.function_body_worklist.items);
        } else {
            for (self.pending_function_bodies.items) |pending| {
                const is_selected_test = self.options.selected_test_name != null and pending.is_test and
                    std.mem.eql(u8, pending.function.name, self.options.selected_test_name.?);
                const is_main = self.options.selected_test_name == null and !pending.is_test and
                    std.mem.eql(u8, pending.function.name, "main");
                if (is_selected_test or is_main) {
                    try self.enqueueFunctionBody(pending.function);
                    try self.enqueueEntrypointRuntimeFunctions(pending.function);
                }
            }
        }

        // Output defaults and bodies are discovered together. Calls resolved
        // while processing either part extend the worklist.
        var output_defaults_ns: u64 = 0;
        var body_ns: u64 = 0;
        const previous_defer_unknown = self.defer_unknown_top_level;
        self.defer_unknown_top_level = false;
        defer self.defer_unknown_top_level = previous_defer_unknown;
        self.discover_function_references = true;
        defer self.discover_function_references = false;
        // Process as a stack, so a just-discovered dependency is semantized
        // before an unrelated pending root. This matters for `#reach` and
        // virtual dispatch: constructing a runtime value can materialize the
        // concrete generic implementations needed by a later reachable call.
        while (self.function_body_worklist.items.len > 0) {
            const idx = self.function_body_worklist.pop().?;
            if (deferred[idx]) continue;
            const pending = &self.pending_function_bodies.items[idx];
            self.current_top_node = pending.top_node;
            const defaults_start = nowNs(self.io);
            self.prepareRegularFunctionBodyScope(pending, global) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => {
                    try self.pushTopLevelForRetry();
                    deferred[idx] = true;
                    continue;
                },
                else => return err,
            };
            output_defaults_ns += @intCast(nowNs(self.io) - defaults_start);

            const body_start = nowNs(self.io);
            self.semantizePreparedFunctionBody(pending) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => {
                    try self.pushTopLevelForRetry();
                    deferred[idx] = true;
                },
                else => return err,
            };
            body_ns += @intCast(nowNs(self.io) - body_start);
            pending.state = .done;
        }
        timings.output_defaults_ns = output_defaults_ns;
        timings.body_ns = body_ns;
        self.current_top_node = null;
        return timings;
    }

    fn enqueueFunctionBody(self: *Semantizer, function: *const sg.FunctionDeclaration) !void {
        for (self.pending_function_bodies.items, 0..) |*pending, idx| {
            if (pending.function != function) continue;
            if (pending.state != .unseen) return;
            pending.state = .queued;
            try self.function_body_worklist.append(idx);
            return;
        }
    }

    fn discoverFunctionReference(self: *Semantizer, function: *const sg.FunctionDeclaration) !void {
        if (!self.discover_function_references) return;
        try self.enqueueFunctionBody(function);
    }

    fn enqueueEntrypointRuntimeFunctions(self: *Semantizer, entry: *const sg.FunctionDeclaration) !void {
        for (entry.input.fields) |entry_field| {
            for (self.pending_function_bodies.items) |pending| {
                const candidate = pending.function;
                if (!std.mem.eql(u8, candidate.name, "init") and
                    !std.mem.eql(u8, candidate.name, "deinit")) continue;
                if (candidate.input.fields.len == 0) continue;
                const receiver = candidate.input.fields[0].ty;
                if (receiver != .pointer_type) continue;
                if (!typ.typesExactlyEqual(receiver.pointer_type.child.*, entry_field.ty)) continue;

                var callable_by_runtime = true;
                for (candidate.input.fields[1..]) |field| {
                    if (field.default_value == null) {
                        callable_by_runtime = false;
                        break;
                    }
                }
                if (callable_by_runtime) try self.enqueueFunctionBody(candidate);
            }
        }
    }

    fn predeclareTopLevelSymbols(self: *Semantizer, global: *Scope) SemErr!void {
        for (self.syntax_roots) |node| {
            switch (self.nodeTag(node)) {
                .symbol_declaration_constant, .symbol_declaration_variable => {
                    try self.predeclareTopLevelImportAliasRef(node, global);
                    try self.predeclareTopLevelBindingRef(node, global);
                },
                .abstract_declaration => try self.predeclareTopLevelAbstractRef(node, global),
                .type_declaration, .c_enum_declaration, .c_union_declaration => try self.predeclareTopLevelTypeRef(node, global),
                .choice_option_declaration => try self.predeclareTopLevelChoiceOptionRef(node, global),
                .function_declaration, .function_declaration_once => try self.predeclareTopLevelFunctionRef(node, global, false),
                .test_declaration => if (self.options.include_tests) try self.predeclareTopLevelFunctionRef(node, global, true),
                else => {},
            }
        }
    }

    fn predeclareTopLevelChoiceOptionRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope) SemErr!void {
        const decl = self.syntaxFile(node).choiceOptionDeclaration(node.node).?;
        const name = self.tokenText(node, decl.name_token);
        if (global.choice_options.contains(name)) return;
        const option_decl = try self.allocator.create(sg.ChoiceOptionDeclaration);
        option_decl.* = .{ .name = name, .origin_file = self.locationPath(self.nodeLocation(node)), .id = self.next_choice_option_id };
        self.next_choice_option_id += 1;
        try global.choice_options.put(name, option_decl);
    }

    fn predeclareTopLevelImportAliasRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope) SemErr!void {
        const file = self.syntaxFile(node);
        const decl = file.symbolDeclaration(node.node).?;
        const value = decl.value orelse return;
        const import = file.importStatement(value) orelse return;
        const name = self.tokenText(node, decl.name_token);
        if (global.module_aliases.contains(name)) return;
        const resolved = source_files.resolveImportDir(
            self.allocator,
            self.io,
            self.locationPath(self.nodeLocation(node)),
            self.tokenText(node, import.path_token),
        ) catch return;
        try global.module_aliases.put(name, resolved);
    }

    fn predeclareTopLevelBindingRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope) SemErr!void {
        const file = self.syntaxFile(node);
        const decl = file.symbolDeclaration(node.node).?;
        if (decl.value) |value| if (file.tag(value) == .import_statement) return;
        const type_node = decl.type_node orelse return;
        const name = self.tokenText(node, decl.name_token);
        if (global.bindings.contains(name) or global.module_aliases.contains(name)) return;
        const ty = self.resolveTypeExpression(self.childRef(node, type_node), global) catch |err| switch (err) {
            error.UnknownType, error.SymbolNotFound => return,
            else => return err,
        };
        if (ty == .abstract_type) return;
        const binding = try self.allocator.create(sg.BindingDeclaration);
        binding.* = .{
            .name = name,
            .location = self.nodeLocation(node),
            .origin_file = self.locationPath(self.nodeLocation(node)),
            .mutability = @enumFromInt(@intFromEnum(decl.mutability)),
            .ty = ty,
            .initialization = null,
        };
        try global.bindings.put(name, binding);
    }

    fn predeclareTopLevelAbstractRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope) SemErr!void {
        const abstract_file = self.syntaxFile(node);
        const decl = abstract_file.abstractDeclaration(node.node).?;
        const name = self.tokenText(node, decl.name_token);
        if (global.abstracts.contains(name) or global.types.contains(name)) return;
        const param_names = try self.compactAbstractParamNames(node, decl.generic_params, decl.generic_params_struct);
        const params = try self.allocator.alloc(gen.GenericParam, param_names.len);
        for (param_names, 0..) |param_name, index| params[index] = .{ .name = param_name, .kind = .type };
        if (decl.generic_params_struct) |params_node| {
            for (abstract_file.structTypeLiteral(params_node).?.fields, 0..) |field_node, index| {
                const field = abstract_file.structTypeField(field_node).?;
                if (field.type_node) |type_node| {
                    const field_type = abstract_file.syntaxType(type_node);
                    const is_type = if (field_type) |ty| ty == .name and ty.name.qualifier_token == null and
                        std.mem.eql(u8, abstract_file.tokenText(&self.diags.source_db, ty.name.name_token), "Type") else false;
                    params[index].kind = if (is_type) .type else .comptime_int;
                }
            }
        }
        const info = try self.allocator.create(abs.AbstractInfo);
        info.* = .{ .name = name, .requirements = &.{}, .param_names = param_names, .params = params };
        const abstract_type = try self.allocator.create(sg.AbstractType);
        abstract_type.* = .{ .name = name };
        const type_decl = try self.allocator.create(sg.TypeDeclaration);
        type_decl.* = .{ .name = name, .origin_file = self.locationPath(self.nodeLocation(node)), .ty = .{ .abstract_type = abstract_type } };
        try global.abstracts.put(name, info);
        try global.types.put(name, type_decl);
    }

    fn predeclareTopLevelTypeRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope) SemErr!void {
        const file = self.syntaxFile(node);
        const name_token, const generic_params, const generic_params_struct, const value = switch (self.nodeTag(node)) {
            .type_declaration => blk: {
                const decl = file.typeDeclaration(node.node).?;
                break :blk .{ decl.name_token, decl.generic_params, decl.generic_params_struct, decl.value };
            },
            .c_enum_declaration => blk: {
                const decl = file.cEnumDeclaration(node.node).?;
                break :blk .{ decl.name_token, decl.generic_params, decl.generic_params_struct, decl.value };
            },
            .c_union_declaration => blk: {
                const decl = file.cUnionDeclaration(node.node).?;
                break :blk .{ decl.name_token, decl.generic_params, decl.generic_params_struct, decl.value };
            },
            else => unreachable,
        };
        const name = self.tokenText(node, name_token);
        if (generic_params.len > 0 or generic_params_struct != null) {
            const generic_info = self.compactGenericParamDefs(node, generic_params, generic_params_struct, global) catch return;
            try global.appendGenericTypeTemplate(name, .{
                .name = name,
                .location = file.location(value),
                .params = generic_info.params,
                .param_abstract_constraints = generic_info.abstract_constraints,
                .body = file.ref(value),
            });
            return;
        }
        if (global.types.contains(name)) return;
        const ty: sg.Type = switch (file.tag(value)) {
            .struct_type_literal => blk: {
                const struct_type = try self.allocator.create(sg.StructType);
                struct_type.* = .{ .fields = &.{} };
                break :blk .{ .struct_type = struct_type };
            },
            .choice_type_literal => blk: {
                const choice_type = try self.allocator.create(sg.ChoiceType);
                choice_type.* = .{ .variants = &.{} };
                break :blk .{ .choice_type = choice_type };
            },
            else => self.resolveTypeExpression(file.ref(value), global) catch return,
        };
        const type_decl = try self.allocator.create(sg.TypeDeclaration);
        type_decl.* = .{ .name = name, .origin_file = self.locationPath(file.location(value)), .ty = ty };
        try global.types.put(name, type_decl);
    }

    fn predeclareTopLevelFunctionRef(self: *Semantizer, node: syn.SyntaxRef, global: *Scope, is_test: bool) SemErr!void {
        const file = self.syntaxFile(node);
        const declaration = if (is_test)
            (file.testDeclaration(node.node) orelse return).function
        else
            file.functionDeclaration(node.node) orelse return;
        if (declaration.generic_params.len != 0 or declaration.generic_params_struct != null) return;
        for (file.structTypeLiteral(declaration.input).?.fields) |field_node| {
            const field = file.structTypeField(field_node).?;
            if (field.type_node) |type_node| {
                if (self.compactAbstractConstraintForType(node, type_node, global) != null) return;
            }
        }
        const name = self.functionNameText(node) orelse return;
        const location = self.nodeLocation(node);
        var function_scope = try Scope.init(self.allocator, global, null);
        const input = self.structTypeSignatureFromNode(file.ref(declaration.input), &function_scope, false) catch |err| switch (err) {
            error.UnknownType, error.SymbolNotFound, error.InvalidType => return,
            else => return err,
        };
        const output = self.structTypeSignatureFromNode(file.ref(declaration.output), &function_scope, true) catch |err| switch (err) {
            error.UnknownType, error.SymbolNotFound, error.InvalidType => return,
            else => return err,
        };
        if (global.functions.getPtr(name)) |functions| {
            for (functions.items) |candidate| {
                if (candidate.location.file == location.file and candidate.location.offset == location.offset) {
                    // Interfaces are refreshed after support declarations settle.
                    // Bodies and their bindings keep the same function identity.
                    if (candidate.input_bindings.len == 0 and candidate.output_bindings.len == 0) {
                        candidate.input = input.*;
                        candidate.output = output.*;
                    }
                    return;
                }
                if (typ.typesExactlyEqual(.{ .struct_type = &candidate.input }, .{ .struct_type = input })) return;
            }
        }
        const function = try self.allocator.create(sg.FunctionDeclaration);
        function.* = .{
            .id = self.freshFunctionId(),
            .name = name,
            .location = location,
            .safety_primitive = self.safetyPrimitiveForDeclaration(name, self.locationPath(location)),
            .is_deinit = std.mem.eql(u8, name, "deinit"),
            .is_once = declaration.is_once,
            .is_test = is_test,
            .input = input.*,
            .output = output.*,
            .body = null,
            .has_declared_body = declaration.body != null,
            .uses_inferred_error_reasons = self.compactSignatureUsesInferredErrable(file.ref(declaration.output)),
            .input_bindings = &.{},
            .output_bindings = &.{},
        };
        try global.appendFunction(name, function);
    }

    fn functionNameText(self: *Semantizer, node: syn.SyntaxRef) ?[]const u8 {
        const file = self.syntaxFile(node);
        return switch (file.functionName(&self.diags.source_db, node.node) orelse return null) {
            .identifier => |name_token| file.tokenText(&self.diags.source_db, name_token),
            .operator => |operator| switch (operator) {
                .add => "operator +",
                .equal => "operator ==",
                .not_equal => "operator !=",
                .get => "operator get[]",
                .set => "operator set[]",
                .get_ro_pointer => "operator get_ro_pointer[]",
                .get_rw_pointer => "operator get_rw_pointer[]",
            },
        };
    }

    fn requireExplicitFunctionFieldTypes(self: *Semantizer, node_ref: syn.SyntaxRef, declaration: syn.FunctionDeclaration) SemErr!void {
        const file = self.syntaxFile(node_ref);
        for ([_]syn.NodeIndex{ declaration.input, declaration.output }, [_][]const u8{ "input", "output" }) |signature, direction| {
            const literal = file.structTypeLiteral(signature) orelse return error.InvalidType;
            for (literal.fields) |field_node| {
                const field = file.structTypeField(field_node) orelse return error.InvalidType;
                if (field.type_node != null) continue;
                try self.diags.add(file.tokenLocation(field.name_token), .semantic, "function {s} field '.{s}' requires an explicit type", .{ direction, file.tokenText(&self.diags.source_db, field.name_token) });
                return error.Reported;
            }
        }
    }

    fn validateTestSignature(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        loc: tok.Location,
        node_ref: syn.SyntaxRef,
    ) SemErr!void {
        const file = self.syntaxFile(node_ref);
        const input = file.structTypeLiteral(f.input) orelse return error.InvalidType;
        const output = file.structTypeLiteral(f.output) orelse return error.InvalidType;
        if (f.is_once) {
            try self.diags.add(loc, .semantic, "tests cannot be marked once", .{});
            return error.Reported;
        }
        if (f.generic_params.len > 0 or f.generic_params_struct != null) {
            try self.diags.add(loc, .semantic, "tests do not support generic parameters in v1", .{});
            return error.Reported;
        }
        if (f.body == null) {
            try self.diags.add(loc, .semantic, "tests must define a body", .{});
            return error.Reported;
        }
        if (input.fields.len != 1) {
            try self.diags.add(loc, .semantic, "tests must declare exactly one input: '.system: System = System()'", .{});
            return error.Reported;
        }
        const system_field = file.structTypeField(input.fields[0]).?;
        if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, system_field.name_token), "system")) {
            try self.diags.add(file.tokenLocation(system_field.name_token), .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        const system_type = system_field.type_node orelse {
            try self.diags.add(file.tokenLocation(system_field.name_token), .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        };
        if (file.syntaxType(system_type) == null or file.syntaxType(system_type).? != .name or !std.mem.eql(u8, file.tokenText(&self.diags.source_db, file.syntaxType(system_type).?.name.name_token), "System")) {
            try self.diags.add(file.tokenLocation(system_field.name_token), .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        const system_default = system_field.default_value orelse {
            try self.diags.add(file.tokenLocation(system_field.name_token), .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        };
        if (file.functionCall(system_default) == null or !std.mem.eql(u8, file.tokenText(&self.diags.source_db, file.functionCall(system_default).?.callee_token), "System")) {
            try self.diags.add(file.location(system_default), .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        if (output.fields.len != 1) {
            try self.diags.add(loc, .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        }
        const result_field = file.structTypeField(output.fields[0]).?;
        if (!result_field.inferred_result and !std.mem.eql(u8, file.tokenText(&self.diags.source_db, result_field.name_token), "result")) {
            try self.diags.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        }
        const result_type = result_field.type_node orelse {
            try self.diags.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        };
        switch (file.syntaxType(result_type) orelse return error.InvalidType) {
            .inferred_errable => |inner| switch (file.syntaxType(inner) orelse return error.InvalidType) {
                .struct_literal => |st| {
                    if (st.fields.len != 0) {
                        try self.diags.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
                        return error.Reported;
                    }
                },
                else => {
                    try self.diags.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
                    return error.Reported;
                },
            },
            else => {
                try self.diags.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
                return error.Reported;
            },
        }
    }

    pub fn printSG(self: *Semantizer) void {
        std.debug.print("\nSEMANTIC GRAPH:\n", .{});
        for (self.root_nodes) |n| sgp.printNode(n, 0);
    }

    fn formatOwnedText(self: *Semantizer, bytes: []u8) OwnedText {
        return .{ .allocator = self.allocator, .bytes = bytes };
    }

    fn formatTypeText(self: *Semantizer, ty: sg.Type, s: *Scope) !OwnedText {
        return self.formatOwnedText(try typ.formatType(ty, s, self.allocator));
    }

    fn sourceLineText(self: *Semantizer, loc: tok.Location) []const u8 {
        const position = self.locationLineColumn(loc);
        for (self.diags.source_files) |f| {
            if (!std.mem.eql(u8, f.path, self.locationPath(loc))) continue;

            var lines = std.mem.splitScalar(u8, f.code, '\n');
            var line_index: u32 = 1;
            while (lines.next()) |line| : (line_index += 1) {
                if (line_index != position.line) continue;
                return std.mem.trim(u8, line, "\r");
            }
        }
        return "";
    }

    fn nextInferredChoiceIdentity(
        self: *Semantizer,
        kind: sg.InferredChoiceKind,
    ) !*const sg.InferredChoiceIdentity {
        const identity = try self.allocator.create(sg.InferredChoiceIdentity);
        identity.* = .{
            .id = self.next_inferred_choice_identity_id,
            .kind = kind,
        };
        self.next_inferred_choice_identity_id += 1;
        return identity;
    }

    fn inferFunctionErrorReasons(self: *Semantizer, global: *Scope) SemErr!void {
        var total_functions: usize = 0;
        var it_count = global.functions.iterator();
        while (it_count.next()) |entry| {
            total_functions += entry.value_ptr.items.len;
        }

        var round: usize = 0;
        while (round <= total_functions) : (round += 1) {
            var changed = false;
            var it = global.functions.iterator();
            while (it.next()) |entry| {
                for (entry.value_ptr.items) |fn_decl| {
                    if (try self.inferSingleFunctionErrorReasons(fn_decl)) {
                        changed = true;
                    }
                }
            }
            if (!changed) break;
        }
    }

    fn inferSingleFunctionErrorReasons(self: *Semantizer, fn_decl: *sg.FunctionDeclaration) SemErr!bool {
        const declared_reasons = self.functionDeclaredErrorReasons(fn_decl) orelse {
            fn_decl.inferred_error_reasons = null;
            return false;
        };

        if (fn_decl.body == null) {
            fn_decl.inferred_error_reasons = declared_reasons;
            return false;
        }

        var collected = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
        defer collected.deinit();

        const body = fn_decl.body.?;
        try self.collectFunctionReasonsFromBlock(fn_decl, body, &collected);

        if (fn_decl.uses_inferred_error_reasons) {
            const previous = declared_reasons.*;
            const inferred = try self.makeCollectedReasonChoice(collected.items);
            const changed = !self.reasonChoiceTypesEqual(&previous, inferred);
            @constCast(declared_reasons).variants = inferred.variants;
            fn_decl.inferred_error_reasons = declared_reasons;
            return changed;
        }

        const inferred = try self.makeReasonSubsetChoice(declared_reasons, collected.items);
        const changed = if (fn_decl.inferred_error_reasons) |existing|
            !self.reasonChoiceTypesEqual(existing, inferred)
        else
            true;
        fn_decl.inferred_error_reasons = inferred;
        return changed;
    }

    fn functionDeclaredErrorReasons(self: *Semantizer, fn_decl: *const sg.FunctionDeclaration) ?*const sg.ChoiceType {
        _ = self;
        const ret_ty = typ.functionReturnType(@constCast(fn_decl));
        return typ.errableReasonChoiceFromType(ret_ty);
    }

    fn collectFunctionReasonsFromNode(
        self: *Semantizer,
        fn_decl: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        switch (node.content) {
            .test_declaration => {},
            .testing_expect_error => |expect_err| {
                try self.collectFunctionReasonsFromNode(fn_decl, expect_err.actual_result, collected);
            },
            .binding_assignment => |assignment| {
                if (self.bindingIsFunctionOutput(fn_decl, assignment.sym_id)) {
                    try self.markReasonsFromReturnedExpr(assignment.value, collected);
                }
                try self.collectFunctionReasonsFromNode(fn_decl, assignment.value, collected);
            },
            .error_propagation => |prop| {
                try self.markReasonsFromErrableNode(prop.errable_value, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, prop.errable_value, collected);
            },
            .error_context => |ctx| {
                try self.markReasonsFromErrableNode(ctx.errable_value, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, ctx.errable_value, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, ctx.context, collected);
            },
            .return_statement => |ret| {
                if (ret.expression) |value| {
                    try self.markReasonsFromReturnedExpr(value, collected);
                    try self.collectFunctionReasonsFromNode(fn_decl, value, collected);
                }
            },
            .function_call => |call| {
                try self.collectFunctionReasonsFromNode(fn_decl, call.input, collected);
            },
            .virtualize => |virtualize| try self.collectFunctionReasonsFromNode(fn_decl, virtualize.value, collected),
            .virtual_call => |virtual_call| try self.collectFunctionReasonsFromNode(fn_decl, virtual_call.input, collected),
            .nullable_unwrap_or => |unwrap| {
                try self.collectFunctionReasonsFromNode(fn_decl, unwrap.nullable_value, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, unwrap.fallback_value, collected);
            },
            .code_block => |block| {
                for (block.nodes) |child| {
                    try self.collectFunctionReasonsFromNode(fn_decl, child, collected);
                }
                if (block.ret_val) |ret_node| {
                    try self.collectFunctionReasonsFromNode(fn_decl, ret_node, collected);
                }
            },
            .struct_value_literal => |lit| {
                for (lit.fields) |field| {
                    try self.collectFunctionReasonsFromNode(fn_decl, field.value, collected);
                }
            },
            .choice_literal => |lit| {
                if (lit.payload) |payload| {
                    try self.collectFunctionReasonsFromNode(fn_decl, payload, collected);
                }
            },
            .list_literal => |lit| {
                for (lit.elements) |elem| {
                    try self.collectFunctionReasonsFromNode(fn_decl, elem, collected);
                }
            },
            .array_literal => |arr| {
                for (arr.elements) |elem| {
                    try self.collectFunctionReasonsFromNode(fn_decl, elem, collected);
                }
            },
            .array_index => |idx| {
                try self.collectFunctionReasonsFromNode(fn_decl, idx.array_ptr, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, idx.index, collected);
            },
            .array_store => |store| {
                try self.collectFunctionReasonsFromNode(fn_decl, store.array_ptr, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, store.index, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, store.value, collected);
            },
            .struct_field_store => |store| {
                try self.collectFunctionReasonsFromNode(fn_decl, store.struct_ptr, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, store.value, collected);
            },
            .struct_field_access => |access| {
                try self.collectFunctionReasonsFromNode(fn_decl, access.struct_value, collected);
            },
            .choice_payload_access => |access| {
                try self.collectFunctionReasonsFromNode(fn_decl, access.choice_value, collected);
            },
            .binary_operation => |op| {
                try self.collectFunctionReasonsFromNode(fn_decl, op.left, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, op.right, collected);
            },
            .comparison => |cmp| {
                try self.collectFunctionReasonsFromNode(fn_decl, cmp.left, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, cmp.right, collected);
            },
            .logical_operation => |op| {
                try self.collectFunctionReasonsFromNode(fn_decl, op.left, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, op.right, collected);
            },
            .if_statement => |if_stmt| {
                try self.collectFunctionReasonsFromNode(fn_decl, if_stmt.condition, collected);
                try self.collectFunctionReasonsFromBlock(fn_decl, if_stmt.then_block, collected);
                if (if_stmt.else_block) |else_block| {
                    try self.collectFunctionReasonsFromBlock(fn_decl, else_block, collected);
                }
            },
            .while_statement => |while_stmt| {
                try self.collectFunctionReasonsFromNode(fn_decl, while_stmt.condition, collected);
                try self.collectFunctionReasonsFromBlock(fn_decl, while_stmt.body, collected);
            },
            .for_statement => |for_stmt| {
                if (for_stmt.init) |for_init| {
                    try self.collectFunctionReasonsFromNode(fn_decl, for_init, collected);
                }
                try self.collectFunctionReasonsFromNode(fn_decl, for_stmt.condition, collected);
                if (for_stmt.increment) |increment| {
                    try self.collectFunctionReasonsFromNode(fn_decl, increment, collected);
                }
                try self.collectFunctionReasonsFromBlock(fn_decl, for_stmt.body, collected);
            },
            .switch_statement => |switch_stmt| {
                try self.collectFunctionReasonsFromNode(fn_decl, switch_stmt.expression, collected);
                for (switch_stmt.cases) |case| {
                    try self.collectFunctionReasonsFromNode(fn_decl, case.value, collected);
                    try self.collectFunctionReasonsFromBlock(fn_decl, case.body, collected);
                }
                if (switch_stmt.default_case) |default_case| {
                    try self.collectFunctionReasonsFromBlock(fn_decl, default_case, collected);
                }
            },
            .move_value => |inner| try self.collectFunctionReasonsFromNode(fn_decl, inner, collected),
            .address_of => |inner| try self.collectFunctionReasonsFromNode(fn_decl, inner, collected),
            .dereference => |deref| try self.collectFunctionReasonsFromNode(fn_decl, deref.pointer, collected),
            .pointer_assignment => |assignment| {
                try self.collectFunctionReasonsFromNode(fn_decl, assignment.pointer, collected);
                try self.collectFunctionReasonsFromNode(fn_decl, assignment.value, collected);
            },
            .type_initializer => |type_init| {
                try self.collectFunctionReasonsFromNode(fn_decl, type_init.args, collected);
            },
            .explicit_cast => |cast_expr| try self.collectFunctionReasonsFromNode(fn_decl, cast_expr.value, collected),
            .choice_option_declaration,
            .type_declaration,
            .function_declaration,
            .auto_deinit_binding,
            .binding_declaration,
            .binding_use,
            .reach_directive,
            .value_literal,
            .type_literal,
            .break_statement,
            .continue_statement,
            => {},
        }
    }

    fn collectFunctionReasonsFromBlock(
        self: *Semantizer,
        fn_decl: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        for (block.nodes) |child| {
            try self.collectFunctionReasonsFromNode(fn_decl, child, collected);
        }
        if (block.ret_val) |ret_node| {
            try self.collectFunctionReasonsFromNode(fn_decl, ret_node, collected);
        }
    }

    fn bindingIsFunctionOutput(self: *Semantizer, fn_decl: *const sg.FunctionDeclaration, binding: *const sg.BindingDeclaration) bool {
        _ = self;
        for (fn_decl.output_bindings) |candidate| {
            if (candidate == binding) return true;
        }
        return false;
    }

    fn markReasonsFromReturnedExpr(
        self: *Semantizer,
        node: *const sg.SGNode,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        switch (node.content) {
            .choice_literal => |lit| {
                if (std.mem.eql(u8, lit.variant_name, "error")) {
                    if (lit.payload) |payload| {
                        try self.markReasonsFromErrorPayloadExpr(payload, collected);
                        return;
                    }
                }
            },
            else => {},
        }

        try self.markReasonsFromErrableNode(node, collected);
    }

    fn markReasonsFromErrorPayloadExpr(
        self: *Semantizer,
        payload: *const sg.SGNode,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        switch (payload.content) {
            .struct_value_literal => |lit| {
                for (lit.fields) |field| {
                    if (!std.mem.eql(u8, field.name, "reason")) continue;
                    try self.markReasonsFromReasonExpr(field.value, collected);
                    return;
                }
            },
            else => {},
        }

        const payload_ty = payload.sem_type orelse return;
        const payload_struct = switch (payload_ty) {
            .struct_type => |st| st,
            else => return,
        };
        const reason_field = typ.findFieldByName(payload_struct, "reason") orelse return;
        const reason_choice = switch (reason_field.ty) {
            .choice_type => |choice_ty| choice_ty,
            else => return,
        };
        try self.markReasonsFromChoice(reason_choice, collected);
    }

    fn markReasonsFromReasonExpr(
        self: *Semantizer,
        node: *const sg.SGNode,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        switch (node.content) {
            .choice_literal => |lit| {
                const variant = lit.choice_type.variants[lit.variant_index];
                try self.markReasonVariant(variant, collected);
                return;
            },
            else => {},
        }

        const reason_ty = node.sem_type orelse return;
        const reason_choice = switch (reason_ty) {
            .choice_type => |choice_ty| choice_ty,
            else => return,
        };
        try self.markReasonsFromChoice(reason_choice, collected);
    }

    fn markReasonsFromErrableNode(
        self: *Semantizer,
        node: *const sg.SGNode,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        switch (node.content) {
            .function_call => |call| {
                if (call.callee.inferred_error_reasons) |inferred| {
                    try self.markReasonsFromChoice(inferred, collected);
                    return;
                }
                if (self.functionDeclaredErrorReasons(call.callee)) |declared| {
                    try self.markReasonsFromChoice(declared, collected);
                }
                return;
            },
            .error_propagation => |prop| {
                const reason_choice = typ.errableReasonChoiceFromType(prop.errable_value.sem_type orelse return) orelse return;
                try self.markReasonsFromChoice(reason_choice, collected);
                return;
            },
            .error_context => |ctx| {
                const reason_choice = typ.errableReasonChoiceFromType(ctx.errable_value.sem_type orelse return) orelse return;
                try self.markReasonsFromChoice(reason_choice, collected);
                return;
            },
            else => {},
        }

        const node_ty = node.sem_type orelse return;
        const reason_choice = typ.errableReasonChoiceFromType(node_ty) orelse return;
        try self.markReasonsFromChoice(reason_choice, collected);
    }

    fn markReasonsFromChoice(
        self: *Semantizer,
        source_reasons: *const sg.ChoiceType,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        for (source_reasons.variants) |variant| {
            try self.markReasonVariant(variant, collected);
        }
    }

    fn markReasonVariant(
        self: *Semantizer,
        variant: sg.ChoiceVariant,
        collected: *std.array_list.Managed(sg.ChoiceVariant),
    ) SemErr!void {
        _ = self;
        for (collected.items) |existing| {
            if (reasonVariantsEqual(existing, variant)) return;
        }
        try collected.append(variant);
    }

    fn makeReasonSubsetChoice(
        self: *Semantizer,
        declared_reasons: *const sg.ChoiceType,
        collected: []const sg.ChoiceVariant,
    ) SemErr!*const sg.ChoiceType {
        var count: usize = 0;
        for (declared_reasons.variants) |variant| {
            if (collectedContainsVariant(collected, variant)) count += 1;
        }

        const variants = try self.allocator.alloc(sg.ChoiceVariant, count);
        var out_idx: usize = 0;
        for (declared_reasons.variants) |variant| {
            if (!collectedContainsVariant(collected, variant)) continue;
            variants[out_idx] = variant;
            out_idx += 1;
        }

        const choice = try self.allocator.create(sg.ChoiceType);
        choice.* = .{
            .variants = variants,
            .identity = null,
        };
        return choice;
    }

    fn collectedContainsVariant(collected: []const sg.ChoiceVariant, variant: sg.ChoiceVariant) bool {
        for (collected) |existing| {
            if (reasonVariantsEqual(existing, variant)) return true;
        }
        return false;
    }

    fn reasonVariantsEqual(left: sg.ChoiceVariant, right: sg.ChoiceVariant) bool {
        if (left.option_decl != right.option_decl) return false;
        if (left.option_decl == null and !std.mem.eql(u8, left.name, right.name)) return false;
        if (left.payload_type == null and right.payload_type == null) return true;
        if (left.payload_type == null or right.payload_type == null) return false;
        return typ.typesExactlyEqual(left.payload_type.?, right.payload_type.?);
    }

    fn makeCollectedReasonChoice(
        self: *Semantizer,
        collected: []const sg.ChoiceVariant,
    ) SemErr!*const sg.ChoiceType {
        const variants = try self.allocator.alloc(sg.ChoiceVariant, collected.len);
        @memcpy(variants, collected);

        const choice = try self.allocator.create(sg.ChoiceType);
        choice.* = .{
            .variants = variants,
            .identity = null,
        };
        return choice;
    }

    fn reasonChoiceTypesEqual(self: *Semantizer, left: *const sg.ChoiceType, right: *const sg.ChoiceType) bool {
        _ = self;
        if (left.variants.len != right.variants.len) return false;
        for (left.variants, right.variants) |lhs, rhs| {
            if (lhs.option_decl != rhs.option_decl) return false;
            if (lhs.option_decl == null and !std.mem.eql(u8, lhs.name, rhs.name)) return false;
        }
        return true;
    }

    fn collectActiveEarlyCleanupNodes(self: *Semantizer, s: *Scope) ![]const *sg.SGNode {
        var collected = std.array_list.Managed(*sg.SGNode).init(self.allocator.*);
        errdefer collected.deinit();

        var cur: ?*Scope = s;
        const current_fn = s.current_fn;
        while (cur) |scope_ptr| : (cur = scope_ptr.parent) {
            if (scope_ptr.current_fn != current_fn) break;

            var d_idx: usize = scope_ptr.deferred.items.len;
            while (d_idx > 0) : (d_idx -= 1) {
                const group = scope_ptr.deferred.items[d_idx - 1];
                for (group.nodes) |node| {
                    if (node.content == .auto_deinit_binding and node.content.auto_deinit_binding.deinit_fn == null) continue;
                    try collected.append(node);
                }
            }
        }

        return try collected.toOwnedSlice();
    }

    fn tryResolveAutoDeinitWithInput(
        self: *Semantizer,
        binding: *sg.BindingDeclaration,
        input_te: typ.TypedExpr,
        loc: tok.Location,
        s: *Scope,
    ) ?AutoDeinitResolution {
        const chosen = self.tryResolveImplicitCall("deinit", input_te, s, loc) catch return null;
        const coerced_input = self.coerceCallInputToExpected(&chosen.input, input_te, loc, s) catch return null;

        if (coerced_input.node.content != .struct_value_literal) return null;
        const input_value = coerced_input.node.content.struct_value_literal;
        const positional_prefix = @min(input_value.dispatch_prefix_positional_count, input_value.fields.len);

        for (chosen.input.fields[0..positional_prefix], 0..) |expected_field, idx| {
            if (expected_field.ty != .pointer_type) continue;
            const arg_node = input_value.fields[idx].value;
            if (arg_node.content != .address_of) continue;
            const inner = arg_node.content.address_of;
            if (inner.content != .binding_use) continue;
            if (inner.content.binding_use != binding) continue;
            return .{
                .function = chosen,
                .input = coerced_input,
                .self_field_index = @intCast(idx),
            };
        }

        for (chosen.input.fields[positional_prefix..], positional_prefix..) |expected_field, idx| {
            if (expected_field.ty != .pointer_type) continue;
            const actual_field = findStructValueFieldByNameFrom(input_value.fields, positional_prefix, expected_field.name) orelse continue;
            if (actual_field.value.content != .address_of) continue;
            const inner = actual_field.value.content.address_of;
            if (inner.content != .binding_use) continue;
            if (inner.content.binding_use != binding) continue;
            return .{
                .function = chosen,
                .input = coerced_input,
                .self_field_index = @intCast(idx),
            };
        }

        return null;
    }

    fn findVisibleAutoDeinitForType(
        self: *Semantizer,
        ty: sg.Type,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!?AutoDeinitResolution {
        if (!typeCanHaveVisibleAutoDeinit(ty)) return null;
        const fake_binding = try self.allocator.create(sg.BindingDeclaration);
        fake_binding.* = .{
            .name = "__auto_deinit_target",
            .location = loc,
            .origin_file = self.locationPath(loc),
            .mutability = .variable,
            .ty = ty,
            .initialization = null,
        };
        return self.findVisibleAutoDeinit(fake_binding, loc, s);
    }

    fn findVisibleAutoDeinit(
        self: *Semantizer,
        binding: *sg.BindingDeclaration,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!?AutoDeinitResolution {
        const binding_use = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
        binding_use.sem_type = binding.ty;

        var candidate_names = std.StringHashMap(void).init(self.allocator.*);
        defer candidate_names.deinit();
        try candidate_names.put("self", {});

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr("deinit")) |list_ptr| {
                for (list_ptr.items) |cand| {
                    for (cand.input.fields) |field| {
                        if (field.ty != .pointer_type) continue;
                        if (field.ty.pointer_type.mutability != .read_write) continue;
                        try candidate_names.put(field.name, {});
                    }
                }
            }
            if (sc.generic_functions.getPtr("deinit")) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    const template_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
                    const input = template_file.structTypeLiteral(tmpl.input) orelse continue;
                    for (input.fields) |field_node| {
                        const field = template_file.structTypeField(field_node) orelse continue;
                        const type_node = field.type_node orelse continue;
                        const field_type = template_file.syntaxType(type_node) orelse continue;
                        if (field_type != .pointer or field_type.pointer.mutability != .read_write) continue;
                        try candidate_names.put(template_file.tokenText(tmpl.source_db, field.name_token), {});
                    }
                }
            }
        }

        var it = candidate_names.iterator();
        while (it.next()) |entry| {
            const field_name = entry.key_ptr.*;
            const child_ty = try self.allocator.create(sg.Type);
            child_ty.* = binding.ty;

            const ptr_info = try self.allocator.create(sg.PointerType);
            ptr_info.* = .{
                .mutability = .read_write,
                .child = child_ty,
            };

            const raw_input = try self.buildNamedCallInput(&[_]CallArg{
                .{
                    .name = field_name,
                    .expr = .{
                        .node = try sg.makeSGNode(.{ .address_of = binding_use }, loc, self.allocator),
                        .ty = .{ .pointer_type = ptr_info },
                    },
                },
            });
            if (self.tryResolveAutoDeinitWithInput(binding, raw_input, loc, s)) |resolved| {
                return resolved;
            }
        }

        const child_ty = try self.allocator.create(sg.Type);
        child_ty.* = binding.ty;

        const ptr_info = try self.allocator.create(sg.PointerType);
        ptr_info.* = .{
            .mutability = .read_write,
            .child = child_ty,
        };

        const positional_input = try self.buildCallInputWithPositionalPrefix(&[_]CallArg{
            .{
                .name = "__arg0",
                .expr = .{
                    .node = try sg.makeSGNode(.{ .address_of = binding_use }, loc, self.allocator),
                    .ty = .{ .pointer_type = ptr_info },
                },
            },
        }, 1);

        return self.tryResolveAutoDeinitWithInput(binding, positional_input, loc, s);
    }

    fn tryResolveCopyCallWithInput(
        self: *Semantizer,
        input_te: typ.TypedExpr,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!?typ.TypedExpr {
        const chosen = self.tryResolveImplicitCall("copy", input_te, s, loc) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };
        const coerced_input = self.coerceCallInputToExpected(&chosen.input, input_te, loc, s) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };

        try self.discoverFunctionReference(chosen);
        const fc_ptr = self.allocator.create(sg.FunctionCall) catch return null;
        fc_ptr.* = .{ .callee = chosen, .input = coerced_input.node };
        const call_node = sg.makeSGNode(.{ .function_call = fc_ptr }, loc, self.allocator) catch return null;
        return .{ .node = call_node, .ty = typ.functionReturnType(chosen) };
    }

    fn ensureValuePositionAllowed(
        self: *Semantizer,
        expr: typ.TypedExpr,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (!typ.expressionNeedsCopyForValuePosition(expr.node)) return expr;
        // The canonical opaque-take primitive is the trusted boundary that
        // turns a representation load into an ownership transfer. Its body is
        // type-checked like ordinary core code, but this one read is not a
        // language-level copy even when `t` is non-copyable.
        if (s.current_fn != null and s.current_fn.?.safety_primitive == .trusted_opaque_move_out) return expr;
        const implicitly_copyable = try self.isImplicitlyCopyableType(expr.ty, s);
        if (implicitly_copyable and typ.isTypeTriviallyCopyable(expr.ty, s)) return expr;

        if (!implicitly_copyable) {
            const ty_text = try self.formatTypeText(expr.ty, s);
            defer ty_text.deinit();
            const has_explicit_copy = try self.typeImplementsAbstract(expr.ty, "InfalliblyCopyable", s) or
                try self.typeImplementsAbstract(expr.ty, "FalliblyCopyable", s);
            if (has_explicit_copy) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "type '{s}' cannot be copied implicitly; use 'copy(&value)' to duplicate it or '~value' to transfer ownership",
                    .{ty_text.bytes},
                );
            } else {
                try self.diags.add(
                    loc,
                    .semantic,
                    "type '{s}' cannot be copied implicitly; use '~value' to transfer ownership",
                    .{ty_text.bytes},
                );
            }
            return error.Reported;
        }

        const self_reference = try typ.makeAddressablePointer(
            expr.node,
            expr.ty,
            .read_only,
            loc,
            self.allocator,
            self.diags,
        );

        const named_input = try self.buildNamedCallInput(&[_]CallArg{
            .{ .name = "self", .expr = self_reference },
        });
        if (self.tryResolveCopyCallWithInput(named_input, loc, s)) |copy_expr_opt| {
            if (copy_expr_opt) |copy_expr| return copy_expr;
        } else |err| switch (err) {
            error.AmbiguousOverload => {
                try self.addAmbiguousFunctionDiagnostic("copy", named_input.ty, s, loc);
                return error.Reported;
            },
            error.Reported => return err,
            else => return err,
        }

        const positional_input = try self.buildCallInputWithPositionalPrefix(&[_]CallArg{
            .{ .name = "__arg0", .expr = self_reference },
        }, 1);
        if (self.tryResolveCopyCallWithInput(positional_input, loc, s)) |copy_expr_opt| {
            if (copy_expr_opt) |copy_expr| return copy_expr;
        } else |err| switch (err) {
            error.AmbiguousOverload => {
                try self.addAmbiguousFunctionDiagnostic("copy", positional_input.ty, s, loc);
                return error.Reported;
            },
            error.Reported => return err,
            else => return err,
        }

        const ty_text = try self.formatTypeText(expr.ty, s);
        defer ty_text.deinit();
        try self.diags.add(
            loc,
            .semantic,
            "type '{s}' is not copyable, so it cannot be used by value here; pass it by '&' or '$&', or implement 'copy()'",
            .{ty_text.bytes},
        );
        return error.Reported;
    }

    fn isImplicitlyCopyableType(self: *Semantizer, ty: sg.Type, s: *Scope) SemErr!bool {
        if (ty == .pointer_type) return true;
        if (typ.genericIdentityOf(ty)) |identity| {
            if (std.mem.eql(u8, identity.base_name, "Virtual")) return true;
        }
        if (try self.typeImplementsAbstract(ty, "ImplicitlyCopyable", s)) return true;
        return switch (ty) {
            .builtin => |builtin| switch (builtin) {
                .Int8, .Int16, .Int32, .Int64, .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64, .Float16, .Float32, .Float64, .Char, .Bool, .Void => true,
                else => false,
            },
            .array_type => |array| try self.isImplicitlyCopyableType(array.element_type.*, s),
            .choice_type => |choice| blk: {
                for (choice.variants) |variant| {
                    if (variant.payload_type) |payload| {
                        if (!try self.isImplicitlyCopyableType(payload, s)) break :blk false;
                    }
                }
                break :blk true;
            },
            .struct_type => |struct_type| blk: {
                if (self.lookupTypeDeclarationForType(ty, s) != null) break :blk false;
                for (struct_type.fields) |field| {
                    if (!try self.isImplicitlyCopyableType(field.ty, s)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        };
    }

    fn formatTypePairText(self: *Semantizer, expected: sg.Type, actual: sg.Type, s: *Scope) !TypePairText {
        return .{
            .expected = try self.formatTypeText(expected, s),
            .actual = try self.formatTypeText(actual, s),
        };
    }

    fn collectVisibleSignatureText(
        self: *Semantizer,
        fn_name: []const u8,
        input: *const sg.StructType,
        s: *Scope,
        loc: tok.Location,
    ) !SignatureText {
        return .{
            .actual = self.formatOwnedText(try typ.formatCallInput(input, s, self.allocator)),
            .available = self.formatOwnedText(try self.collectVisibleFunctionSignatures(fn_name, s, loc)),
        };
    }

    fn collectModuleSignatureText(
        self: *Semantizer,
        module_dir: []const u8,
        fn_name: []const u8,
        input: *const sg.StructType,
        s: *Scope,
        loc: tok.Location,
    ) !SignatureText {
        return .{
            .actual = self.formatOwnedText(try typ.formatCallInput(input, s, self.allocator)),
            .available = self.formatOwnedText(try self.collectModuleFunctionSignatures(module_dir, fn_name, s, loc)),
        };
    }

    fn isWrappableMainCandidate(self: *Semantizer, f: *const sg.FunctionDeclaration) bool {
        _ = self;
        if (!std.mem.eql(u8, f.name, "main")) return false;
        if (f.output.fields.len != 1) return false;
        const fld = f.output.fields[0];
        if (!std.mem.eql(u8, fld.name, "status_code")) return false;
        return switch (fld.ty) {
            .builtin => |bt| bt == .Int32,
            else => false,
        };
    }

    fn verifyOnceFunctions(self: *Semantizer, global: *Scope) SemErr!void {
        if (self.options.selected_test_name) |test_name| {
            if (global.functions.getPtr(test_name)) |test_list| {
                for (test_list.items) |test_fn| {
                    if (!test_fn.is_test) continue;
                    var state = OnceTraversalState.init(self.allocator);
                    defer state.deinit();
                    try self.walkFunctionOnceReachability(test_fn, test_fn.location, &state);
                }
            }
            return;
        }

        if (global.functions.getPtr("main")) |main_list| {
            for (main_list.items) |main_fn| {
                if (!self.isWrappableMainCandidate(main_fn)) continue;
                var state = OnceTraversalState.init(self.allocator);
                defer state.deinit();
                try self.walkFunctionOnceReachability(main_fn, main_fn.location, &state);
            }
        }
    }

    fn walkFunctionOnceReachability(
        self: *Semantizer,
        func: *const sg.FunctionDeclaration,
        call_loc: tok.Location,
        state: *OnceTraversalState,
    ) SemErr!void {
        if (func.body == null) return;

        for (state.active_functions.items) |active| {
            if (active == func) {
                try self.diags.add(
                    call_loc,
                    .semantic,
                    "once analysis does not support recursive call cycles; cycle detected while expanding '{s}'",
                    .{func.name},
                );
                return error.Reported;
            }
        }

        try state.active_functions.append(func);
        defer _ = state.active_functions.pop();

        for (func.input.fields) |field| {
            if (field.default_value) |default_node| {
                try self.walkNodeOnceReachability(func, default_node, state);
            }
        }
        for (func.output.fields) |field| {
            if (field.default_value) |default_node| {
                try self.walkNodeOnceReachability(func, default_node, state);
            }
        }

        try self.walkCodeBlockOnceReachability(func, func.body.?, state);
    }

    fn recordOnceConsumption(
        self: *Semantizer,
        once_fn: *const sg.FunctionDeclaration,
        consumer: *const sg.FunctionDeclaration,
        loc: tok.Location,
        state: *OnceTraversalState,
    ) SemErr!void {
        const result = try state.seen_once.getOrPut(once_fn);
        if (!result.found_existing) {
            result.value_ptr.* = .{
                .first_location = loc,
                .first_consumer = consumer,
            };
            return;
        }

        const first = result.value_ptr.*;
        try self.diags.add(
            loc,
            .semantic,
            "once function '{s}' is consumed more than once from the reachable entrypoint graph (first use at {s}:{d}:{d} via '{s}')",
            .{
                once_fn.name,
                self.locationPath(first.first_location),
                self.locationLineColumn(first.first_location).line,
                self.locationLineColumn(first.first_location).column,
                first.first_consumer.name,
            },
        );
        return error.Reported;
    }

    fn walkCodeBlockOnceReachability(
        self: *Semantizer,
        current_fn: *const sg.FunctionDeclaration,
        block: *const sg.CodeBlock,
        state: *OnceTraversalState,
    ) SemErr!void {
        for (block.nodes) |node| {
            try self.walkNodeOnceReachability(current_fn, node, state);
        }
        if (block.ret_val) |ret_node| {
            try self.walkNodeOnceReachability(current_fn, ret_node, state);
        }
    }

    fn walkNodeOnceReachability(
        self: *Semantizer,
        current_fn: *const sg.FunctionDeclaration,
        node: *const sg.SGNode,
        state: *OnceTraversalState,
    ) SemErr!void {
        switch (node.content) {
            .choice_option_declaration => {},
            .test_declaration => {},
            .testing_expect_error => |expect_err| {
                try self.walkNodeOnceReachability(current_fn, expect_err.expected_reason, state);
                try self.walkNodeOnceReachability(current_fn, expect_err.actual_result, state);
            },
            .binding_declaration => |binding| {
                if (binding.initialization) |init_node| {
                    try self.walkNodeOnceReachability(current_fn, init_node, state);
                }
            },
            .binding_assignment => |assign| {
                try self.walkNodeOnceReachability(current_fn, assign.value, state);
            },
            .auto_deinit_binding => |auto| {
                try self.walkAutoDeinitOnceReachability(auto, current_fn, node.location, state);
            },
            .reach_directive,
            .binding_use,
            .value_literal,
            .type_literal,
            .break_statement,
            .continue_statement,
            => {},
            .move_value => |inner| {
                try self.walkNodeOnceReachability(current_fn, inner, state);
            },
            .nullable_unwrap_or => |unwrap| {
                try self.walkNodeOnceReachability(current_fn, unwrap.nullable_value, state);
                try self.walkNodeOnceReachability(current_fn, unwrap.fallback_value, state);
            },
            .function_call => |call| {
                try self.walkNodeOnceReachability(current_fn, call.input, state);
                if (call.callee.is_once) {
                    try self.recordOnceConsumption(call.callee, current_fn, node.location, state);
                }
                try self.walkFunctionOnceReachability(call.callee, node.location, state);
            },
            .virtualize => |virtualize| try self.walkNodeOnceReachability(current_fn, virtualize.value, state),
            .virtual_call => |virtual_call| try self.walkNodeOnceReachability(current_fn, virtual_call.input, state),
            .code_block => |block| {
                try self.walkCodeBlockOnceReachability(current_fn, block, state);
            },
            .choice_literal => |choice| {
                if (choice.payload) |payload| {
                    try self.walkNodeOnceReachability(current_fn, payload, state);
                }
            },
            .list_literal => |list| {
                for (list.elements) |elem| {
                    try self.walkNodeOnceReachability(current_fn, elem, state);
                }
            },
            .struct_value_literal => |st| {
                for (st.fields) |field| {
                    try self.walkNodeOnceReachability(current_fn, field.value, state);
                }
            },
            .struct_field_access => |access| {
                try self.walkNodeOnceReachability(current_fn, access.struct_value, state);
            },
            .choice_payload_access => |access| {
                try self.walkNodeOnceReachability(current_fn, access.choice_value, state);
            },
            .error_propagation => |prop| {
                try self.walkNodeOnceReachability(current_fn, prop.errable_value, state);
            },
            .error_context => |ctx| {
                try self.walkNodeOnceReachability(current_fn, ctx.errable_value, state);
                try self.walkNodeOnceReachability(current_fn, ctx.context, state);
            },
            .array_literal => |arr| {
                for (arr.elements) |elem| {
                    try self.walkNodeOnceReachability(current_fn, elem, state);
                }
            },
            .array_index => |index| {
                try self.walkNodeOnceReachability(current_fn, index.array_ptr, state);
                try self.walkNodeOnceReachability(current_fn, index.index, state);
            },
            .array_store => |store| {
                try self.walkNodeOnceReachability(current_fn, store.array_ptr, state);
                try self.walkNodeOnceReachability(current_fn, store.index, state);
                try self.walkNodeOnceReachability(current_fn, store.value, state);
            },
            .struct_field_store => |store| {
                try self.walkNodeOnceReachability(current_fn, store.struct_ptr, state);
                try self.walkNodeOnceReachability(current_fn, store.value, state);
            },
            .binary_operation => |op| {
                try self.walkNodeOnceReachability(current_fn, op.left, state);
                try self.walkNodeOnceReachability(current_fn, op.right, state);
            },
            .comparison => |cmp| {
                try self.walkNodeOnceReachability(current_fn, cmp.left, state);
                try self.walkNodeOnceReachability(current_fn, cmp.right, state);
            },
            .logical_operation => |lo| {
                try self.walkNodeOnceReachability(current_fn, lo.left, state);
                try self.walkNodeOnceReachability(current_fn, lo.right, state);
            },
            .return_statement => |ret| {
                if (ret.expression) |expr| {
                    try self.walkNodeOnceReachability(current_fn, expr, state);
                }
            },
            .if_statement => |if_stmt| {
                try self.walkNodeOnceReachability(current_fn, if_stmt.condition, state);
                try self.walkCodeBlockOnceReachability(current_fn, if_stmt.then_block, state);
                if (if_stmt.else_block) |else_block| {
                    try self.walkCodeBlockOnceReachability(current_fn, else_block, state);
                }
            },
            .while_statement => |while_stmt| {
                try self.walkNodeOnceReachability(current_fn, while_stmt.condition, state);
                try self.walkCodeBlockOnceReachability(current_fn, while_stmt.body, state);
            },
            .for_statement => |for_stmt| {
                if (for_stmt.init) |init_node| {
                    try self.walkNodeOnceReachability(current_fn, init_node, state);
                }
                try self.walkNodeOnceReachability(current_fn, for_stmt.condition, state);
                if (for_stmt.increment) |inc_node| {
                    try self.walkNodeOnceReachability(current_fn, inc_node, state);
                }
                try self.walkCodeBlockOnceReachability(current_fn, for_stmt.body, state);
            },
            .switch_statement => |switch_stmt| {
                try self.walkNodeOnceReachability(current_fn, switch_stmt.expression, state);
                for (switch_stmt.cases) |case| {
                    try self.walkNodeOnceReachability(current_fn, case.value, state);
                    try self.walkCodeBlockOnceReachability(current_fn, case.body, state);
                }
                if (switch_stmt.default_case) |default_block| {
                    try self.walkCodeBlockOnceReachability(current_fn, default_block, state);
                }
            },
            .address_of => |inner| {
                try self.walkNodeOnceReachability(current_fn, inner, state);
            },
            .dereference => |deref| {
                try self.walkNodeOnceReachability(current_fn, deref.pointer, state);
            },
            .pointer_assignment => |assign| {
                try self.walkNodeOnceReachability(current_fn, assign.pointer, state);
                try self.walkNodeOnceReachability(current_fn, assign.value, state);
            },
            .type_initializer => |type_init| {
                try self.walkNodeOnceReachability(current_fn, type_init.args, state);
                if (type_init.init_fn.is_once) {
                    try self.recordOnceConsumption(type_init.init_fn, current_fn, node.location, state);
                }
                try self.walkFunctionOnceReachability(type_init.init_fn, node.location, state);
            },
            .explicit_cast => |cast_expr| {
                try self.walkNodeOnceReachability(current_fn, cast_expr.value, state);
            },
            .function_declaration,
            .type_declaration,
            => {},
        }
    }

    fn buildOverloadCandidatesText(
        self: *Semantizer,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
    ) !OwnedText {
        return self.formatOwnedText(try abs.buildOverloadCandidatesString(
            fn_name,
            input_ty,
            s,
            self.allocator,
            self.diags,
        ));
    }

    fn makeEmptyCodeBlock(self: *Semantizer) !*sg.CodeBlock {
        const empty = try self.allocator.create(sg.CodeBlock);
        empty.* = .{ .nodes = &.{}, .ret_val = null };
        return empty;
    }

    fn makeNoopNode(self: *Semantizer, loc: tok.Location) !*sg.SGNode {
        return sg.makeSGNode(.{ .code_block = try self.makeEmptyCodeBlock() }, loc, self.allocator);
    }

    fn makeSyntheticName(self: *Semantizer, prefix: []const u8) ![]u8 {
        const name = try std.fmt.allocPrint(self.allocator.*, "__for_{s}_{d}", .{ prefix, self.synthetic_name_counter });
        self.synthetic_name_counter += 1;
        return name;
    }

    fn functionMatchesVisibilityFilter(
        self: *Semantizer,
        cand: *sg.FunctionDeclaration,
        requester_file: []const u8,
        module_dir: ?[]const u8,
    ) !bool {
        if (module_dir) |dir| {
            if (!std.mem.startsWith(u8, self.locationPath(cand.location), dir)) return false;
        }
        return self.functionIsVisible(cand, requester_file);
    }

    //────────────────────────────────────────────────────────────────── visitors
    pub fn visitNode(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        return self.visitNodeInner(node, s) catch |err| {
            if (err == error.AbstractNeedsDefault) {
                const file = self.syntaxFile(node);
                if (file.symbolDeclaration(node.node)) |declaration| {
                    if (declaration.type_node) |type_node| {
                        if (file.syntaxType(type_node)) |ty| {
                            if (ty == .name) {
                                const name = file.tokenText(&self.diags.source_db, ty.name.name_token);
                                try self.diags.add(file.location(node.node), .semantic, "cannot use abstract '{s}' as a type for a symbol. Use a concrete type or add a default concrete type to the abstract type ('{s} defaultsto <Type>')", .{ name, name });
                                return error.Reported;
                            }
                        }
                    }
                    try self.diags.add(file.location(node.node), .semantic, "cannot use abstract type without a default (add 'defaultsto' or use a concrete type)", .{});
                    return error.Reported;
                }
            }
            if (err == error.UnknownType or err == error.SymbolNotFound) try self.pushTopLevelForRetry();
            return err;
        };
    }

    fn visitNodeInner(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const location = self.nodeLocation(node);
        // Runtime/expression syntax includes declarations allowed in local
        // scopes. Type-only, child-only and context-only tags are listed
        // explicitly below so a new tag cannot silently fall through.
        return switch (self.nodeTag(node)) {
            .function_declaration, .function_declaration_once => self.handleCompactFunctionDeclaration(node, s, false),
            // Top-level-only syntax has an explicit context check.
            .test_declaration => blk: {
                if (s.parent != null) {
                    try self.diags.add(location, .semantic, "tests are only supported at top level", .{});
                    break :blk error.Reported;
                }
                break :blk self.handleCompactFunctionDeclaration(node, s, true);
            },
            .assignment => self.handleCompactAssignment(node, s),
            .symbol_declaration_constant, .symbol_declaration_variable => self.handleCompactSymbolDeclaration(node, s),
            .struct_value_literal => self.handleCompactStructValueLiteral(node, s),
            .function_call => self.handleCompactFunctionCall(node, s),
            .struct_field_access => self.handleCompactStructFieldAccess(node, s),
            .choice_payload_access => self.handleChoicePayloadAccess(node, s),
            .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => self.handleCompactBinaryOperation(node, s),
            .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal => self.handleCompactComparison(node, s),
            .logical_and, .logical_or => self.handleCompactLogicalOperation(node, s),
            .if_statement => self.handleCompactIf(node, s),
            .match_statement => self.handleCompactMatch(node, s),
            .for_value, .for_borrow, .for_mut_borrow => self.handleCompactFor(node, s),
            .pipe_expression => self.handleCompactPipe(node, s),
            .unwrap_or, .unwrap_or_do => self.handleCompactNullableUnwrap(node, s),
            .error_propagation => self.handleCompactErrorPropagation(node, s),
            .error_context => self.handleCompactErrorContext(node, s),
            .nullable_test => self.handleCompactNullableTest(node, s),
            .type_declaration, .c_enum_declaration, .c_union_declaration => self.handleCompactTypeDeclaration(node, s),
            .choice_option_declaration => self.handleCompactChoiceOptionDeclaration(node, s),
            .abstract_declaration => self.handleCompactAbstractDeclaration(node, s),
            .abstract_implements => self.handleCompactAbstractImplements(node, s),
            .abstract_defaultsto => self.handleCompactAbstractDefault(node, s),
            .identifier => self.handleIdentifier(self.tokenText(node, self.syntaxFile(node).mainToken(node.node)), s, location),
            .literal => self.handleCompactLiteral(node, s),
            .code_block => self.handleCompactCodeBlock(node, s),
            .expression_statement => blk: {
                const value = try self.visitNode(self.childRef(node, self.syntaxFile(node).unaryOperand(node.node).?), s);
                try s.nodes.append(value.node);
                break :blk value;
            },
            .return_statement => self.handleCompactReturn(node, s),
            .while_statement => self.handleWhile(node, s),
            .dereference => self.handleDereference(self.childRef(node, self.syntaxFile(node).unaryOperand(node.node).?), s),
            .defer_statement => self.handleDefer(self.childRef(node, self.syntaxFile(node).unaryOperand(node.node).?), s),
            .move_expression => self.handleMove(self.childRef(node, self.syntaxFile(node).unaryOperand(node.node).?), s, location),
            .list_literal => self.handleListLiteral(node, s),
            .keep_statement => self.handleKeep(node, s),
            .choice_literal, .choice_some_literal => self.handleChoiceLiteral(node, s),
            .index_access => self.handleIndexAccess(node, s),
            .address_of, .address_of_mut => self.handleAddressOf(node, s),
            .pointer_assignment => self.handlePointerAssignment(node, s),
            .index_assignment => self.handleIndexAssignment(node, s),
            .import_statement => self.handleImportStatement(location),
            // Context-only: defaults and symbol declarations resolve #reach.
            .reach_directive => self.handleReachDirective(node, location),
            .break_statement => self.handleBreak(location, s),
            .continue_statement => self.handleContinue(location, s),
            // Type syntax is resolved through syntaxType(), except a struct
            // with defaults, which can also materialize a runtime value.
            .struct_type_literal => self.handleCompactStructTypeValue(node, s),
            .choice_type_literal => blk: {
                try self.diags.add(location, .semantic, "choice type literals are only valid inside type declarations or type annotations", .{});
                break :blk error.Reported;
            },
            .type_name, .pointer_type, .pointer_type_mut, .nullable_type, .inferred_errable_type, .array_type, .generic_type_instantiation => error.InvalidType,
            // Child-only nodes are consumed by their owner's typed view.
            .abstract_function_requirement, .reach_alternative, .struct_type_field, .inferred_result_field, .choice_type_variant, .choice_type_variant_default, .struct_value_field, .positional_value_field, .match_case_value, .match_case_borrow, .match_case_mut_borrow, .match_case_move => error.InvalidType,
            // Context-only syntax: evalCompactPipeArg supplies the piped value.
            .pipe_placeholder => error.InvalidType,
        };
    }

    fn handleCompactStructTypeValue(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const literal = file.structTypeLiteral(node.node).?;
        var arguments = std.array_list.Managed(CallArg).init(self.allocator.*);
        defer arguments.deinit();
        for (literal.fields) |field_node| {
            const field = file.structTypeField(field_node).?;
            const value = field.default_value orelse {
                try self.diags.add(file.location(node.node), .semantic, "error in struct type literal: NotYetImplemented", .{});
                return error.Reported;
            };
            try arguments.append(.{ .name = file.tokenText(&self.diags.source_db, field.name_token), .expr = try self.visitNode(file.ref(value), scope) });
        }
        return self.buildCallInput(arguments.items);
    }

    fn handleCompactNullableTest(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const operand = file.unaryOperand(node.node).?;
        const value = try self.visitNode(file.ref(operand), scope);
        const location = file.location(node.node);
        if (value.ty != .choice_type) {
            const desc = try self.formatTypeText(value.ty, scope);
            defer desc.deinit();
            try self.diags.add(file.location(operand), .semantic, "is expects '.value' to be a choice, found '{s}'", .{desc.bytes});
            return error.Reported;
        }
        for (value.ty.choice_type.variants, 0..) |variant, index| {
            if (!std.mem.eql(u8, variant.name, "some")) continue;
            const literal = try self.allocator.create(sg.ChoiceLiteral);
            literal.* = .{ .variant_name = "some", .choice_type = value.ty.choice_type, .variant_index = @intCast(index), .payload = null };
            const variant_node = try sg.makeSGNode(.{ .choice_literal = literal }, location, self.allocator);
            variant_node.sem_type = value.ty;
            const result = try sg.makeSGNode(.{ .comparison = .{ .operator = .equal, .left = value.node, .right = variant_node } }, location, self.allocator);
            try scope.nodes.append(result);
            return .{ .node = result, .ty = .{ .builtin = .Bool } };
        }
        const desc = try self.formatTypeText(value.ty, scope);
        defer desc.deinit();
        try self.diags.add(location, .semantic, "choice type '{s}' has no variant '..some'", .{desc.bytes});
        return error.Reported;
    }

    fn handleCompactFunctionDeclaration(
        self: *Semantizer,
        node: syn.SyntaxRef,
        scope: *Scope,
        is_test: bool,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const declaration = if (is_test)
            (file.testDeclaration(node.node) orelse return error.InvalidType).function
        else
            file.functionDeclaration(node.node) orelse return error.InvalidType;
        try self.requireExplicitFunctionFieldTypes(node, declaration);
        const name = self.functionNameText(node) orelse return error.InvalidType;
        const location = self.nodeLocation(node);
        if (is_test) try self.validateTestSignature(declaration, location, node);
        if (declaration.is_once and declaration.body == null) {
            try self.diags.add(location, .semantic, "once is not supported on extern functions", .{});
            return error.Reported;
        }
        if (declaration.generic_params.len != 0 or declaration.generic_params_struct != null) {
            if (declaration.is_once) {
                try self.diags.add(location, .semantic, "once is not supported on generic functions yet", .{});
                return error.Reported;
            }
            const info = try self.compactGenericParamDefs(node, declaration.generic_params, declaration.generic_params_struct, scope);
            try scope.appendGenericFunctionTemplate(name, .{
                .syntax_files = self.syntax_files,
                .source_db = &self.diags.source_db,
                .syntax_file_id = node.file_id,
                .name = name,
                .location = location,
                .params = info.params,
                .param_abstract_constraints = info.abstract_constraints,
                .input = declaration.input,
                .output = declaration.output,
                .body = if (declaration.body) |body| file.ref(body) else null,
            });
            const noop = try self.makeNoopNode(location);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }
        if (!is_test and try self.registerAbstractContractTemplateIfNeeded(node, scope, location)) {
            const noop = try self.makeNoopNode(location);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }
        try self.predeclareTopLevelFunctionRef(node, scope, is_test);
        var function: ?*sg.FunctionDeclaration = null;
        if (scope.functions.getPtr(name)) |functions| {
            for (functions.items) |candidate| {
                if (candidate.location.file == location.file and candidate.location.offset == location.offset) {
                    function = candidate;
                    break;
                }
            }
        }
        const resolved = function orelse return error.UnknownType;
        if (resolved.output_bindings.len == 0 and resolved.output.fields.len != 0) {
            const output_nodes = file.structTypeLiteral(declaration.output) orelse return error.InvalidType;
            const bindings = try self.allocator.alloc(*const sg.BindingDeclaration, resolved.output.fields.len);
            for (output_nodes.fields, 0..) |field_node, index| {
                const field = file.structTypeField(field_node) orelse return error.InvalidType;
                const binding = try self.allocator.create(sg.BindingDeclaration);
                binding.* = .{
                    .name = if (field.inferred_result) "result" else file.tokenText(&self.diags.source_db, field.name_token),
                    .location = file.tokenLocation(field.name_token),
                    .origin_file = self.locationPath(location),
                    .mutability = .variable,
                    .ty = resolved.output.fields[index].ty,
                    .initialization = null,
                };
                bindings[index] = binding;
            }
            resolved.output_bindings = bindings;
        }
        if (is_test)
            _ = try self.appendTestDeclarationNodeIfMissing(scope, resolved, location)
        else
            _ = try self.appendFunctionDeclarationNodeIfMissing(scope, resolved, location);
        try self.enqueuePendingFunctionBody(node, declaration, location, resolved, is_test);
        const noop = try self.makeNoopNode(location);
        return .{ .node = noop, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactLiteral(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const literal = file.literal(node.node).?;
        const content = file.tokenContent(literal.token).literal;
        var value: sg.ValueLiteral = undefined;
        var ty: sg.Type = .{ .builtin = .Int32 };
        switch (content) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => {
                var parsed = std.fmt.parseInt(i64, file.tokenText(&self.diags.source_db, literal.token), 0) catch 0;
                if (literal.negative) parsed = -parsed;
                value = .{ .int_literal = parsed };
            },
            .regular_float_literal, .scientific_float_literal => {
                var parsed = std.fmt.parseFloat(f64, file.tokenText(&self.diags.source_db, literal.token)) catch 0.0;
                if (literal.negative) parsed = -parsed;
                ty = .{ .builtin = .Float32 };
                value = .{ .float_literal = parsed };
            },
            .char_literal => |character| {
                ty = .{ .builtin = .Char };
                value = .{ .char_literal = character };
            },
            .string_literal => {
                const declaration = s.lookupType("StringView") orelse return error.UnknownType;
                if (!typeDeclIsReady(declaration)) return error.UnknownType;
                ty = declaration.ty;
                value = .{ .string_literal = try tok.decodeStringLiteral(self.allocator.*, file.tokenText(&self.diags.source_db, literal.token)) };
            },
            .bool_literal => |boolean| {
                ty = .{ .builtin = .Bool };
                value = .{ .bool_literal = boolean };
            },
        }
        const result = try sg.makeSGNode(.{ .value_literal = value }, self.nodeLocation(node), self.allocator);
        result.sem_type = ty;
        return .{ .node = result, .ty = ty };
    }

    fn handleCompactAssignment(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const assignment = file.assignment(node.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, assignment.name_token);
        const location = file.tokenLocation(assignment.name_token);
        const binding = scope.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(binding, self.locationPath(location)))) {
            try self.addPrivateMemberDiag(location, "value", name);
            return error.Reported;
        }
        if (scope.bindingMoveLocation(name)) |move_location| {
            try self.diags.add(location, .semantic, "binding '{s}' was moved and cannot be reassigned (moved at {s}:{d}:{d})", .{
                name,
                self.locationPath(move_location),
                self.locationLineColumn(move_location).line,
                self.locationLineColumn(move_location).column,
            });
            return error.Reported;
        }
        if (binding.mutability == .constant and binding.initialization != null) {
            try self.diags.add(location, .semantic, "binding '{s}' is constant and cannot be reassigned after initialization", .{name});
            return error.Reported;
        }
        const value_ref = file.ref(assignment.value);
        var value = try self.visitNode(value_ref, scope);
        value = try typ.coerceExprToType(binding.ty, value, file.location(assignment.value), scope, self.allocator, self.diags);
        value = try self.ensureValuePositionAllowed(value, file.location(assignment.value), scope);
        if (!typ.typesExactlyEqual(binding.ty, value.ty)) return error.InvalidType;
        const semantic_assignment = try self.allocator.create(sg.Assignment);
        semantic_assignment.* = .{ .sym_id = binding, .value = value.node };
        const result = try sg.makeSGNode(.{ .binding_assignment = semantic_assignment }, location, self.allocator);
        try scope.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactSymbolDeclaration(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const declaration = file.symbolDeclaration(node.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, declaration.name_token);
        const location = file.tokenLocation(declaration.name_token);
        if (declaration.value) |value_node| if (file.importStatement(value_node)) |import| {
            const resolved = source_files.resolveImportDir(
                self.allocator,
                self.io,
                self.locationPath(location),
                file.tokenText(&self.diags.source_db, import.path_token),
            ) catch return error.Reported;
            if (!scope.module_aliases.contains(name)) try scope.module_aliases.put(name, resolved);
            return typ.makeTypeLiteral(self.allocator, location, .{ .builtin = .Any });
        };
        const predeclared = if (scope.parent == null) scope.bindings.get(name) else null;
        const reuses_predeclared = if (predeclared) |binding|
            binding.location.file == location.file and binding.location.offset == location.offset
        else
            false;
        if (scope.bindings.contains(name) and !reuses_predeclared) return error.SymbolAlreadyDefined;
        var value: ?typ.TypedExpr = if (declaration.value) |value_node| blk: {
            if (file.tag(value_node) != .reach_directive) break :blk try self.visitNode(file.ref(value_node), scope);
            const reach_ref = file.ref(value_node);
            const reach = try self.semanticReachDirectiveFromSyntax(reach_ref);
            const expected = if (declaration.type_node) |type_node|
                try self.resolveTypeExpression(file.ref(type_node), scope)
            else inferred: {
                const inferred = try self.resolveReachedArgumentForInference(name, reach, scope, file.location(value_node)) orelse {
                    const reach_text = try self.formatReachDirective(reach);
                    defer self.allocator.free(reach_text);
                    try self.diags.add(file.location(value_node), .semantic, "cannot infer type for '.{s}' from #reach [{s}]", .{ name, reach_text });
                    return error.Reported;
                };
                break :inferred inferred.ty;
            };
            break :blk try self.resolveReachedArgument(name, expected, reach, scope, file.location(value_node));
        } else null;
        var value_type: sg.Type = if (value) |typed| typed.ty else .{ .builtin = .Int32 };
        if (declaration.type_node) |type_node| {
            value_type = try self.resolveTypeExpression(file.ref(type_node), scope);
            if (value) |typed| value = try typ.coerceExprToType(value_type, typed, file.location(declaration.value.?), scope, self.allocator, self.diags);
        } else if (value) |typed| if (typed.node.content == .list_literal) {
            const array = try self.inferArrayTypeFromList(typed.node.content.list_literal, file.location(declaration.value.?), scope);
            value_type = .{ .array_type = array };
            value = try typ.convertListLiteralToArray(typed, array, file.location(declaration.value.?), scope, self.allocator, self.diags);
        };
        if (value) |typed| value = try self.ensureValuePositionAllowed(typed, file.location(declaration.value.?), scope);
        const binding = if (reuses_predeclared) predeclared.? else blk: {
            const created = try self.allocator.create(sg.BindingDeclaration);
            try scope.bindings.put(name, created);
            break :blk created;
        };
        binding.* = .{
            .name = name,
            .location = location,
            .origin_file = self.locationPath(location),
            .mutability = @enumFromInt(@intFromEnum(declaration.mutability)),
            .ty = value_type,
            .initialization = if (value) |typed| typed.node else null,
        };
        scope.clearBindingMoved(name);
        const result = try self.appendBindingDeclarationNodeIfMissing(scope, binding, location);
        try self.maybeScheduleAutoDeinit(binding, location, scope);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactStructValueLiteral(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const literal = file.structValueLiteral(node.node) orelse return error.InvalidType;
        const values = try self.allocator.alloc(sg.StructValueLiteralField, literal.fields.len);
        const fields = try self.allocator.alloc(sg.StructTypeField, literal.fields.len);
        for (literal.fields, 0..) |field_node, index| {
            const field = file.valueField(field_node) orelse return error.InvalidType;
            const value_ref = file.ref(field.value);
            var typed = try self.visitNode(value_ref, scope);
            typed = try self.ensureValuePositionAllowed(typed, file.location(field.value), scope);
            const name = if (field.name_token) |name_token|
                file.tokenText(&self.diags.source_db, name_token)
            else
                try std.fmt.allocPrint(self.allocator.*, "__positional_{d}", .{field.position.?});
            values[index] = .{ .name = name, .value = typed.node };
            fields[index] = .{ .name = name, .ty = typed.ty, .default_value = null };
        }
        const struct_type = try self.allocator.create(sg.StructType);
        struct_type.* = .{ .fields = fields };
        const semantic_literal = try self.allocator.create(sg.StructValueLiteral);
        semantic_literal.* = .{
            .fields = values,
            .ty = .{ .struct_type = struct_type },
            .dispatch_prefix_positional_count = literal.positional_prefix_count,
        };
        const result = try sg.makeSGNode(.{ .struct_value_literal = semantic_literal }, self.nodeLocation(node), self.allocator);
        return .{ .node = result, .ty = .{ .struct_type = struct_type } };
    }

    fn handleCompactFunctionCall(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const call = file.functionCall(node.node) orelse return error.InvalidType;
        const callee = file.tokenText(&self.diags.source_db, call.callee_token);
        const location = file.tokenLocation(call.callee_token);
        if (std.mem.eql(u8, callee, "size_of")) return self.handleBuiltinTypeInfo(.size, node, scope);
        if (std.mem.eql(u8, callee, "alignment_of")) return self.handleBuiltinTypeInfo(.alignment, node, scope);
        if (std.mem.eql(u8, callee, "to_virtual")) return self.handleToVirtual(node, scope);
        if (std.mem.eql(u8, callee, "type_of")) return self.handleTypeOf(node, scope);
        if (std.mem.eql(u8, callee, "cast")) return self.handleCastBuiltin(node, scope);
        if (std.mem.eql(u8, callee, "is")) return self.handleIsBuiltin(node, scope);
        if (std.mem.eql(u8, callee, "length")) length: {
            return self.handleLengthBuiltin(node, scope) catch |err| switch (err) {
                error.SymbolNotFound => break :length,
                else => return err,
            };
        }
        var input = try self.visitNode(file.ref(call.input), scope);
        if (call.module_qualifier) |qualifier| {
            if (std.mem.eql(u8, file.tokenText(&self.diags.source_db, qualifier), "testing") and std.mem.eql(u8, callee, "expect_error")) return self.handleTestingExpectErrorBuiltin(node, input, scope);
        }

        if (input.ty != .struct_type) return error.InvalidType;

        if (typ.builtinFromName(callee)) |builtin| if (builtin == .Void) {
            if (input.ty.struct_type.fields.len != 0) return error.InvalidType;
            const literal = try self.allocator.create(sg.StructValueLiteral);
            literal.* = .{ .fields = &.{}, .ty = .{ .builtin = .Void }, .dispatch_prefix_positional_count = 0 };
            const result = try sg.makeSGNode(.{ .struct_value_literal = literal }, location, self.allocator);
            result.sem_type = .{ .builtin = .Void };
            return .{ .node = result, .ty = .{ .builtin = .Void } };
        };

        if (scope.lookupType(callee)) |type_declaration| {
            if (!(try self.typeIsVisible(type_declaration, self.locationPath(location)))) {
                try self.addPrivateMemberDiag(location, "type", callee);
                return error.Reported;
            }
            return self.handleTypeInitializer(node, input, type_declaration, scope);
        }

        if (call.type_arguments_struct) |arguments| {
            const instantiated = self.resolveCompactGenericTypeWithMode(callee, location, file.ref(arguments), scope, false, null) catch |err| switch (err) {
                error.UnknownType, error.AbstractNeedsDefault => null,
                else => return err,
            };
            if (instantiated) |ty| {
                const declaration = try self.allocator.create(sg.TypeDeclaration);
                declaration.* = .{ .name = callee, .origin_file = self.locationPath(location), .ty = ty };
                return self.handleTypeInitializer(node, input, declaration, scope);
            }
        }
        const inferred_type = self.instantiateGenericTypeFromInitializer(callee, input.ty, scope) catch |err| switch (err) {
            error.SymbolNotFound => null,
            error.AmbiguousOverload => {
                try self.diags.add(file.location(call.input), .semantic, "generic type initializer for '{s}' is ambiguous", .{callee});
                return error.Reported;
            },
            else => return err,
        };
        if (inferred_type) |ty| {
            const declaration = try self.allocator.create(sg.TypeDeclaration);
            declaration.* = .{ .name = callee, .origin_file = self.locationPath(location), .ty = ty };
            return self.handleTypeInitializer(node, input, declaration, scope);
        }
        if (try self.tryHandleVirtualCall(node, input, scope)) |virtual_call| return virtual_call;

        const trusted_drop_without_destructor = scope.current_fn != null and
            scope.current_fn.?.safety_primitive == .trusted_opaque_drop and std.mem.eql(u8, callee, "deinit");
        const chosen = (if (trusted_drop_without_destructor)
            self.tryResolveRegularCallCallee(node, input, scope, file.location(call.input), null)
        else
            self.resolveRegularCallCallee(node, input, scope, file.location(call.input))) catch |err| switch (err) {
            error.SymbolNotFound => if (trusted_drop_without_destructor) {
                // Trusted drops of trivially destructible values have no runtime work.
                const literal = try self.allocator.create(sg.StructValueLiteral);
                literal.* = .{ .fields = &.{}, .ty = .{ .builtin = .Void } };
                const result = try sg.makeSGNode(.{ .struct_value_literal = literal }, location, self.allocator);
                result.sem_type = .{ .builtin = .Void };
                return .{ .node = result, .ty = .{ .builtin = .Void } };
            } else return err,
            error.AmbiguousOverload => {
                if (call.module_qualifier) |qualifier| {
                    const module_name = file.tokenText(&self.diags.source_db, qualifier);
                    const module_dir = scope.lookupModuleAlias(module_name) orelse return error.SymbolNotFound;
                    try self.addAmbiguousModuleFunctionDiagnostic(module_name, module_dir, callee, input.ty, scope, file.location(call.input));
                } else try self.addAmbiguousFunctionDiagnostic(callee, input.ty, scope, location);
                return error.Reported;
            },
            else => return err,
        };

        input = try self.coerceCallInputToExpected(&chosen.input, input, file.location(call.input), scope);
        try self.discoverFunctionReference(chosen);
        const semantic_call = try self.allocator.create(sg.FunctionCall);
        semantic_call.* = .{
            .callee = chosen,
            .input = input.node,
            .consumes_auto_deinit = self.explicitDeinitAutoCleanupTarget(chosen, input, scope),
        };
        const result = try sg.makeSGNode(.{ .function_call = semantic_call }, location, self.allocator);
        return .{ .node = result, .ty = typ.functionReturnType(chosen) };
    }

    fn handleCompactStructFieldAccess(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const access = file.structFieldAccess(node.node) orelse return error.InvalidType;
        const field_name = file.tokenText(&self.diags.source_db, access.field_token);
        const field_location = file.tokenLocation(access.field_token);
        if (file.tag(access.value) == .identifier) {
            const module_name = file.tokenText(&self.diags.source_db, file.mainToken(access.value));
            if (scope.lookupModuleAlias(module_name)) |module_dir| {
                return self.handleModuleFieldAccess(module_dir, field_name, scope, file.location(access.value));
            }
        }
        const base = try self.visitNode(file.ref(access.value), scope);
        if (base.ty != .struct_type) {
            if (base.node.content == .function_call) {
                const call = base.node.content.function_call;
                if (call.callee.output.fields.len == 1 and std.mem.eql(u8, call.callee.output.fields[0].name, field_name)) return base;
            }
            return error.InvalidType;
        }
        return self.buildStructFieldAccessFromTypedExpr(base, field_name, field_location, scope);
    }

    fn handleCompactBinaryOperation(self: *Semantizer, node_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const operation = file.binaryOperation(node_ref.node) orelse return error.InvalidType;
        const loc = file.location(node_ref.node);
        const operator: tok.BinaryOperator = switch (file.tag(node_ref.node)) {
            .binary_add => .addition,
            .binary_subtract => .subtraction,
            .binary_multiply => .multiplication,
            .binary_divide => .division,
            .binary_modulo => .modulo,
            else => unreachable,
        };
        var lhs = try self.visitNode(file.ref(operation.lhs), s);
        var rhs = try self.visitNode(file.ref(operation.rhs), s);

        const operator_name = switch (operator) {
            .addition => "operator +",
            else => null,
        };

        if (operator_name) |name| {
            var input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "left", .expr = lhs },
                .{ .name = "right", .expr = rhs },
            });
            const empty_args: ?syn.SyntaxRef = null;

            var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, file.location(operation.lhs)) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, file.location(operation.lhs));
                        return error.Reported;
                    },
                    else => return err,
                };
            }

            if (chosen == null) {
                chosen = self.instantiateGenericNamed(name, empty_args, input_te, s, .abstract_contract) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    else => return err,
                };
            }

            if (chosen) |chosen_fn| {
                try self.discoverFunctionReference(chosen_fn);
                input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, file.location(operation.lhs), s);

                const result_ty = typ.functionReturnType(chosen_fn);
                const fc_ptr = try self.allocator.create(sg.FunctionCall);
                fc_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

                const node = try sg.makeSGNode(.{ .function_call = fc_ptr }, loc, self.allocator);
                try s.nodes.append(node);
                return .{ .node = node, .ty = result_ty };
            }
        }

        const lhs_is_ptr = lhs.ty == .pointer_type;
        const rhs_is_ptr = rhs.ty == .pointer_type;
        if ((operator == .addition or operator == .subtraction) and lhs_is_ptr != rhs_is_ptr) {
            try self.diags.add(
                file.location(operation.lhs),
                .semantic,
                "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
                .{},
            );
            return error.Reported;
        }

        rhs = try typ.coerceExprToType(lhs.ty, rhs, file.location(operation.rhs), s, self.allocator, self.diags);
        lhs = try typ.coerceExprToType(rhs.ty, lhs, file.location(operation.lhs), s, self.allocator, self.diags);

        if (!typ.typesExactlyEqual(lhs.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(lhs.ty, rhs.ty, s);
            defer pair.deinit();
            const verb = binaryOpVerb(operator);
            try self.diags.add(
                file.location(operation.lhs),
                .semantic,
                "cannot {s} '{s}' and '{s}'",
                .{ verb, pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const bin = try self.allocator.create(sg.BinaryOperation);
        bin.* = .{ .operator = operator, .left = lhs.node, .right = rhs.node };

        const n = try sg.makeSGNode(.{ .binary_operation = bin.* }, loc, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = lhs.ty };
    }

    //──────────────────────────────────────────────────── COMPARISON
    fn handleCompactComparison(self: *Semantizer, node_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const operation = file.binaryOperation(node_ref.node) orelse return error.InvalidType;
        const loc = file.location(node_ref.node);
        const operator: tok.ComparisonOperator = switch (file.tag(node_ref.node)) {
            .compare_equal => .equal,
            .compare_not_equal => .not_equal,
            .compare_less => .less_than,
            .compare_greater => .greater_than,
            .compare_less_equal => .less_than_or_equal,
            .compare_greater_equal => .greater_than_or_equal,
            else => unreachable,
        };
        var lhs = try self.visitNode(file.ref(operation.lhs), s);
        var rhs = try self.visitNode(file.ref(operation.rhs), s);

        const operator_name = switch (operator) {
            .equal => "operator ==",
            .not_equal => "operator !=",
            else => null,
        };

        if (operator_name) |name| {
            var input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "left", .expr = lhs },
                .{ .name = "right", .expr = rhs },
            });
            const empty_args: ?syn.SyntaxRef = null;

            var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, file.location(operation.lhs)) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, file.location(operation.lhs));
                        return error.Reported;
                    },
                    else => return err,
                };
            }

            if (chosen) |chosen_fn| {
                try self.discoverFunctionReference(chosen_fn);
                input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, file.location(operation.lhs), s);

                const result_ty = typ.functionReturnType(chosen_fn);
                if (!typ.typesExactlyEqual(result_ty, .{ .builtin = .Bool })) {
                    const actual = try self.formatTypeText(result_ty, s);
                    defer actual.deinit();
                    try self.diags.add(
                        file.location(operation.lhs),
                        .semantic,
                        "comparison operator '{s}' must return 'Bool', got '{s}'",
                        .{ name, actual.bytes },
                    );
                    return error.Reported;
                }

                const fc_ptr = try self.allocator.create(sg.FunctionCall);
                fc_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

                const node = try sg.makeSGNode(.{ .function_call = fc_ptr }, loc, self.allocator);
                try s.nodes.append(node);
                return .{ .node = node, .ty = result_ty };
            }
        }

        if (operator == .equal or operator == .not_equal) {
            if (try self.coercePayloadlessChoiceComparisonSide(lhs.ty, rhs, file.location(operation.rhs), s)) |coerced_rhs| {
                rhs = coerced_rhs;
            }
            if (try self.coercePayloadlessChoiceComparisonSide(rhs.ty, lhs, file.location(operation.lhs), s)) |coerced_lhs| {
                lhs = coerced_lhs;
            }
        }

        rhs = try typ.coerceExprToType(lhs.ty, rhs, file.location(operation.rhs), s, self.allocator, self.diags);
        lhs = try typ.coerceExprToType(rhs.ty, lhs, file.location(operation.lhs), s, self.allocator, self.diags);

        if (!typ.typesExactlyEqual(lhs.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(lhs.ty, rhs.ty, s);
            defer pair.deinit();
            try self.diags.add(
                file.location(operation.lhs),
                .semantic,
                "cannot compare '{s}' and '{s}'",
                .{ pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const cmp_ptr = try self.allocator.create(sg.Comparison);
        cmp_ptr.* = .{
            .operator = operator,
            .left = lhs.node,
            .right = rhs.node,
        };

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, loc, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Bool } };
    }

    fn handleCompactLogicalOperation(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const operation = file.binaryOperation(node.node) orelse return error.InvalidType;
        const bool_type: sg.Type = .{ .builtin = .Bool };
        var left = try self.visitNode(file.ref(operation.lhs), scope);
        var right = try self.visitNode(file.ref(operation.rhs), scope);
        left = try typ.coerceExprToType(bool_type, left, file.location(operation.lhs), scope, self.allocator, self.diags);
        right = try typ.coerceExprToType(bool_type, right, file.location(operation.rhs), scope, self.allocator, self.diags);
        if (!typ.typesExactlyEqual(left.ty, bool_type) or !typ.typesExactlyEqual(right.ty, bool_type)) return error.InvalidType;
        const operator: sg.LogicalOperator = if (file.tag(node.node) == .logical_and) .and_ else .or_;
        const result = try sg.makeSGNode(.{ .logical_operation = .{ .operator = operator, .left = left.node, .right = right.node } }, self.nodeLocation(node), self.allocator);
        try scope.nodes.append(result);
        return .{ .node = result, .ty = bool_type };
    }

    fn handleCompactIf(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const statement = file.ifStatement(node.node) orelse return error.InvalidType;
        const start_len = scope.nodes.items.len;
        const condition = try self.visitNode(file.ref(statement.condition), scope);
        const refinement = try self.extractCompactNullableIfRefinement(file.ref(statement.condition), scope);
        const then_value = if (file.codeBlock(statement.then_block)) |block|
            try self.handleCompactCodeBlockWithNullableRefinement(file.ref(statement.then_block), block, scope, refinement, file.location(statement.condition))
        else
            try self.visitNode(file.ref(statement.then_block), scope);
        const else_block = if (statement.else_block) |else_node| blk: {
            const else_value = try self.visitNode(file.ref(else_node), scope);
            break :blk else_value.node.content.code_block;
        } else null;
        scope.nodes.items.len = start_len;
        const semantic_if = try self.allocator.create(sg.IfStatement);
        semantic_if.* = .{
            .condition = condition.node,
            .choice_test = self.choiceTagTestForCondition(condition.node),
            .then_block = then_value.node.content.code_block,
            .else_block = else_block,
        };
        const result = try sg.makeSGNode(.{ .if_statement = semantic_if }, self.nodeLocation(node), self.allocator);
        try scope.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn extractCompactNullableIfRefinement(
        self: *Semantizer,
        condition: syn.SyntaxRef,
        scope: *Scope,
    ) SemErr!?NullableIfRefinement {
        const file = self.syntaxFile(condition);
        if (file.tag(condition.node) == .nullable_test) {
            const value = file.unaryOperand(condition.node).?;
            if (file.tag(value) != .identifier) return null;
            const name = file.tokenText(&self.diags.source_db, file.mainToken(value));
            const binding = scope.lookupBinding(name) orelse return null;
            const nullable = self.tryNullableInfoOfType(binding.ty) orelse return null;
            return .{
                .source_binding = binding,
                .some_variant_index = nullable.some_variant_index,
                .some_payload_type = nullable.some_payload_type,
                .some_value_type = nullable.some_value_type,
            };
        }
        const call = file.functionCall(condition.node) orelse return null;
        if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, call.callee_token), "is") or
            call.module_qualifier != null or call.type_arguments.len != 0 or call.type_arguments_struct != null) return null;
        const input = file.structValueLiteral(call.input) orelse return null;
        var value_node: ?syn.NodeIndex = null;
        var variant_node: ?syn.NodeIndex = null;
        for (input.fields) |field_node| {
            const field = file.valueField(field_node) orelse return error.InvalidType;
            const name_token = field.name_token orelse continue;
            const name = file.tokenText(&self.diags.source_db, name_token);
            if (std.mem.eql(u8, name, "value")) value_node = field.value else if (std.mem.eql(u8, name, "variant")) variant_node = field.value;
        }
        const value = value_node orelse return null;
        const variant = variant_node orelse return null;
        if (file.tag(value) != .identifier) return null;
        const literal = file.choiceLiteral(variant) orelse return null;
        if (literal.payload != null) return null;
        const binding_name = file.tokenText(&self.diags.source_db, file.mainToken(value));
        const binding = scope.lookupBinding(binding_name) orelse return null;
        const nullable = self.tryNullableInfoOfType(binding.ty) orelse return null;
        const variant_name = file.tokenText(&self.diags.source_db, literal.name_token);
        if (!std.mem.eql(u8, variant_name, "some") or
            !std.mem.eql(u8, binding.ty.choice_type.variants[nullable.some_variant_index].name, variant_name)) return null;
        return .{
            .source_binding = binding,
            .some_variant_index = nullable.some_variant_index,
            .some_payload_type = nullable.some_payload_type,
            .some_value_type = nullable.some_value_type,
        };
    }

    fn handleCompactCodeBlockWithNullableRefinement(
        self: *Semantizer,
        node: syn.SyntaxRef,
        block: syn.CodeBlock,
        parent: *Scope,
        refinement: ?NullableIfRefinement,
        refinement_loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        if (refinement) |value| try self.applyNullableThenRefinement(value, &child, refinement_loc);
        var return_value: ?*sg.SGNode = null;
        var return_type: sg.Type = .{ .builtin = .Any };
        const file = self.syntaxFile(node);
        for (block.statements, 0..) |statement, index| {
            const typed = try self.visitNode(self.childRef(node, statement), &child);
            if (index + 1 == block.statements.len and file.tag(statement) == .expression_statement) {
                return_value = typed.node;
                return_type = typed.ty;
            } else if (file.tag(statement) == .function_call) try child.nodes.append(typed.node);
        }
        var deferred_index = child.deferred.items.len;
        while (deferred_index > 0) : (deferred_index -= 1) {
            for (child.deferred.items[deferred_index - 1].nodes) |deferred_node| try child.nodes.append(deferred_node);
        }
        const nodes = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);
        const block_value = try self.allocator.create(sg.CodeBlock);
        block_value.* = .{ .nodes = nodes, .ret_val = return_value };
        const result = try sg.makeSGNode(.{ .code_block = block_value }, self.nodeLocation(node), self.allocator);
        try parent.nodes.append(result);
        return .{ .node = result, .ty = return_type };
    }

    fn handleCompactMatch(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const statement = file.matchStatement(node.node) orelse return error.InvalidType;
        const requires_move = for (statement.cases) |case_node| {
            const match_case = file.matchCase(case_node) orelse return error.InvalidType;
            if (match_case.payload_name) |payload_name| {
                const name = file.tokenText(&self.diags.source_db, payload_name);
                if (!std.mem.eql(u8, name, "_") and match_case.mode == .move) break true;
            }
        } else false;
        const value_ref = self.childRef(node, statement.value);
        const value = if (requires_move) blk: {
            if (file.tag(statement.value) == .identifier) break :blk try self.handleMove(value_ref, scope, file.location(statement.value));
            const typed = try self.visitNode(value_ref, scope);
            if (typ.expressionNeedsCopyForValuePosition(typed.node)) {
                try self.diags.add(file.location(statement.value), .semantic, "match payload move bindings currently only support named bindings or temporary expressions", .{});
                return error.Reported;
            }
            break :blk typed;
        } else try self.visitNode(value_ref, scope);
        const choice = switch (value.ty) {
            .choice_type => |choice_type| choice_type,
            else => {
                const desc = try self.formatTypeText(value.ty, scope);
                defer desc.deinit();
                try self.diags.add(file.location(statement.value), .semantic, "match expects a choice value, found '{s}'", .{desc.bytes});
                return error.Reported;
            },
        };
        const start_len = scope.nodes.items.len;
        var cases = std.array_list.Managed(sg.SwitchCase).init(self.allocator.*);
        for (statement.cases) |case_node| {
            const match_case = file.matchCase(case_node) orelse return error.InvalidType;
            const variant_name = file.tokenText(&self.diags.source_db, match_case.variant_token);
            const variant_loc = file.tokenLocation(match_case.variant_token);
            var variant_index: ?u32 = null;
            var payload_type: ?sg.Type = null;
            for (choice.variants, 0..) |variant, index| if (std.mem.eql(u8, variant.name, variant_name)) {
                variant_index = @intCast(index);
                payload_type = variant.payload_type;
                break;
            };
            const index = variant_index orelse {
                const desc = try self.formatTypeText(value.ty, scope);
                defer desc.deinit();
                try self.diags.add(variant_loc, .semantic, "choice type '{s}' has no variant '..{s}'", .{ desc.bytes, variant_name });
                return error.Reported;
            };
            const body = try self.handleCompactMatchCaseBody(value, index, payload_type, match_case, node, scope);
            const literal = try self.allocator.create(sg.ChoiceLiteral);
            literal.* = .{ .variant_name = variant_name, .choice_type = choice, .variant_index = index, .payload = null };
            const literal_node = try sg.makeSGNode(.{ .choice_literal = literal }, variant_loc, self.allocator);
            literal_node.sem_type = value.ty;
            try cases.append(.{ .value = literal_node, .variant_index = index, .body = body });
        }
        scope.nodes.items.len = start_len;
        var exhaustive = cases.items.len == choice.variants.len;
        if (exhaustive) for (choice.variants, 0..) |_, variant_index| {
            const found = for (cases.items) |case| {
                if (case.variant_index == variant_index) break true;
            } else false;
            if (!found) {
                exhaustive = false;
                break;
            }
        };
        const semantic = try self.allocator.create(sg.SwitchStatement);
        semantic.* = .{ .expression = value.node, .cases = try cases.toOwnedSlice(), .default_case = null, .exhaustive = exhaustive };
        const result = try sg.makeSGNode(.{ .switch_statement = semantic }, file.location(statement.value), self.allocator);
        try scope.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactMatchCaseBody(
        self: *Semantizer,
        choice_value: typ.TypedExpr,
        variant_index: u32,
        payload_type: ?sg.Type,
        match_case: syn.MatchCase,
        parent_node: syn.SyntaxRef,
        parent: *Scope,
    ) SemErr!*const sg.CodeBlock {
        const file = self.syntaxFile(parent_node);
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        const variant_name = file.tokenText(&self.diags.source_db, match_case.variant_token);
        if (match_case.payload_name) |payload_name_token| {
            const binding_name = file.tokenText(&self.diags.source_db, payload_name_token);
            const binding_loc = file.tokenLocation(payload_name_token);
            const resolved_payload = payload_type orelse {
                try self.diags.add(binding_loc, .semantic, "choice variant '..{s}' has no payload to bind", .{variant_name});
                return error.Reported;
            };
            if (!std.mem.eql(u8, binding_name, "_")) {
                const access = try self.allocator.create(sg.ChoicePayloadAccess);
                access.* = .{ .choice_value = choice_value.node, .variant_index = variant_index, .payload_type = resolved_payload };
                const access_node = try sg.makeSGNode(.{ .choice_payload_access = access }, binding_loc, self.allocator);
                access_node.sem_type = resolved_payload;
                const initialization: typ.TypedExpr = switch (match_case.mode) {
                    .value => try self.ensureValuePositionAllowed(.{ .node = access_node, .ty = resolved_payload }, binding_loc, parent),
                    .move => .{ .node = access_node, .ty = resolved_payload },
                    .borrow => try typ.makeAddressablePointer(access_node, resolved_payload, .read_only, binding_loc, self.allocator, self.diags),
                    .mut_borrow => try typ.makeAddressablePointer(access_node, resolved_payload, .read_write, binding_loc, self.allocator, self.diags),
                };
                const binding = try self.allocator.create(sg.BindingDeclaration);
                binding.* = .{ .name = binding_name, .location = binding_loc, .origin_file = self.locationPath(binding_loc), .mutability = .constant, .ty = initialization.ty, .initialization = initialization.node };
                try child.bindings.put(binding_name, binding);
                try child.nodes.append(try sg.makeSGNode(.{ .binding_declaration = binding }, binding_loc, self.allocator));
                try self.maybeScheduleAutoDeinit(binding, binding_loc, &child);
            }
        } else if (payload_type != null) {
            const loc = file.tokenLocation(match_case.variant_token);
            try self.diags.add(loc, .semantic, "choice variant '..{s}' carries a payload and match must bind it explicitly; use '..{s} _' to ignore it", .{ variant_name, variant_name });
            return error.Reported;
        }
        const body = file.codeBlock(match_case.body) orelse return error.InvalidType;
        for (body.statements) |statement| {
            const typed = try self.visitNode(self.childRef(parent_node, statement), &child);
            if (file.tag(statement) == .function_call) try child.nodes.append(typed.node);
        }
        var deferred_index = child.deferred.items.len;
        while (deferred_index > 0) : (deferred_index -= 1) for (child.deferred.items[deferred_index - 1].nodes) |deferred_node| try child.nodes.append(deferred_node);
        const nodes = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);
        const result = try self.allocator.create(sg.CodeBlock);
        result.* = .{ .nodes = nodes, .ret_val = null };
        return result;
    }

    fn handleCompactErrorPropagation(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const value = file.unaryOperand(node.node) orelse return error.InvalidType;
        return self.lowerErrorPropagation(try self.visitNode(self.childRef(node, value), scope), null, scope, self.nodeLocation(node));
    }

    fn handleCompactErrorContext(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const operation = file.binaryOperation(node.node) orelse return error.InvalidType;
        const value = try self.visitNode(self.childRef(node, operation.lhs), scope);
        var context = try self.visitNode(self.childRef(node, operation.rhs), scope);
        context = try self.ensureValuePositionAllowed(context, file.location(operation.rhs), scope);
        return self.lowerErrorPropagation(value, context, scope, self.nodeLocation(node));
    }

    fn handleCompactNullableUnwrap(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const operation = file.binaryOperation(node.node) orelse return error.InvalidType;
        const value_ref = self.childRef(node, operation.lhs);
        const fallback_ref = self.childRef(node, operation.rhs);
        const value = try self.visitNode(value_ref, scope);
        const nullable = try self.nullableInfoOf(value.ty, file.location(operation.lhs), "unwrap_or left operand", scope);
        var fallback = try self.visitNode(fallback_ref, scope);
        fallback = try typ.coerceExprToType(nullable.some_value_type, fallback, file.location(operation.rhs), scope, self.allocator, self.diags);
        const semantic = try self.allocator.create(sg.NullableUnwrapOr);
        semantic.* = .{
            .nullable_value = value.node,
            .fallback_value = fallback.node,
            .some_variant_index = nullable.some_variant_index,
            .some_value_field_index = nullable.some_value_field_index,
            .result_type = nullable.some_value_type,
        };
        const result = try sg.makeSGNode(.{ .nullable_unwrap_or = semantic }, self.nodeLocation(node), self.allocator);
        result.sem_type = nullable.some_value_type;
        return .{ .node = result, .ty = nullable.some_value_type };
    }

    fn makeCompactBindingUse(self: *Semantizer, binding: *sg.BindingDeclaration, loc: tok.Location) !typ.TypedExpr {
        const node = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
        node.sem_type = binding.ty;
        return .{ .node = node, .ty = binding.ty };
    }

    fn makeCompactImplicitCall(
        self: *Semantizer,
        name: []const u8,
        args: []const CallArg,
        positional_prefix_count: u32,
        loc: tok.Location,
        scope: *Scope,
    ) SemErr!typ.TypedExpr {
        var input = try self.buildCallInputWithPositionalPrefix(args, positional_prefix_count);
        const callee = try self.tryResolveImplicitCall(name, input, scope, loc);
        input = try self.coerceCallInputToExpected(&callee.input, input, loc, scope);
        try self.discoverFunctionReference(callee);
        const semantic = try self.allocator.create(sg.FunctionCall);
        semantic.* = .{ .callee = callee, .input = input.node };
        const result = try sg.makeSGNode(.{ .function_call = semantic }, loc, self.allocator);
        result.sem_type = typ.functionReturnType(callee);
        return .{ .node = result, .ty = typ.functionReturnType(callee) };
    }

    fn handleCompactFor(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const statement = file.forStatement(node.node) orelse return error.InvalidType;
        const loc = self.nodeLocation(node);
        const iterable_ref = self.childRef(node, statement.iterable);
        const iterable = try self.visitNode(iterable_ref, scope);
        const abstract_name = switch (statement.mode) {
            .value => "Iterable",
            .borrow => "ROPointerIterable",
            .mut_borrow => "RWPointerIterable",
        };
        const constructor_name = switch (statement.mode) {
            .value => "to_iterator",
            .borrow => "to_ro_pointer_iterator",
            .mut_borrow => "to_rw_pointer_iterator",
        };
        const needs_mutability = statement.mode == .mut_borrow;
        const direct_pointer = iterable.ty == .pointer_type and
            (!needs_mutability or iterable.ty.pointer_type.mutability == .read_write) and
            try self.typeImplementsAbstract(iterable.ty.pointer_type.child.*, abstract_name, scope);
        if (!try self.typeImplementsAbstract(iterable.ty, abstract_name, scope) and !direct_pointer) {
            const desc = try self.formatTypeText(iterable.ty, scope);
            defer desc.deinit();
            try self.diags.add(loc, .semantic, "for expects a type implementing abstract '{s}', got '{s}'", .{ abstract_name, desc.bytes });
            return error.Reported;
        }
        const copyable = typ.isTypeCopyable(iterable.ty, scope);
        if (!copyable and file.tag(statement.iterable) != .identifier) {
            try self.diags.add(file.location(statement.iterable), .semantic, "for cannot iterate a non-copyable expression directly; bind it to a name first", .{});
            return error.Reported;
        }
        var lowered_scope = try Scope.init(self.allocator, scope, scope.current_fn);
        var iterable_value = iterable;
        if (copyable and file.tag(statement.iterable) != .identifier) {
            const name = try self.makeSyntheticName("iterable");
            const binding = try self.allocator.create(sg.BindingDeclaration);
            binding.* = .{ .name = name, .location = loc, .origin_file = self.locationPath(loc), .mutability = if (needs_mutability) .variable else .constant, .ty = iterable.ty, .initialization = iterable.node };
            try lowered_scope.bindings.put(name, binding);
            try lowered_scope.nodes.append(try sg.makeSGNode(.{ .binding_declaration = binding }, loc, self.allocator));
            iterable_value = try self.makeCompactBindingUse(binding, loc);
        }
        const constructor_value = if (direct_pointer) iterable_value else switch (needs_mutability) {
            false => try typ.ensureReadOnlyPointer(loc, iterable_value, self.allocator, self.diags),
            true => try typ.ensureMutablePointer(loc, iterable_value, &lowered_scope, self.allocator, self.diags),
        };
        const iterator_value = try self.makeCompactImplicitCall(constructor_name, &.{.{ .name = "value", .expr = constructor_value }}, 0, loc, &lowered_scope);
        if (!try self.typeImplementsAbstract(iterator_value.ty, "Iterator", &lowered_scope)) {
            const desc = try self.formatTypeText(iterator_value.ty, &lowered_scope);
            defer desc.deinit();
            try self.diags.add(loc, .semantic, "for expects '{s}(.value = ...)' to return a type implementing abstract 'Iterator', got '{s}'", .{ constructor_name, desc.bytes });
            return error.Reported;
        }
        const iterator_name = try self.makeSyntheticName("iterator");
        const iterator_binding = try self.allocator.create(sg.BindingDeclaration);
        iterator_binding.* = .{ .name = iterator_name, .location = loc, .origin_file = self.locationPath(loc), .mutability = .variable, .ty = iterator_value.ty, .initialization = iterator_value.node };
        try lowered_scope.bindings.put(iterator_name, iterator_binding);
        try lowered_scope.nodes.append(try sg.makeSGNode(.{ .binding_declaration = iterator_binding }, loc, self.allocator));
        try self.maybeScheduleAutoDeinit(iterator_binding, loc, &lowered_scope);
        const iterator_use = try self.makeCompactBindingUse(iterator_binding, loc);
        const has_next_self = try typ.ensureReadOnlyPointer(loc, iterator_use, self.allocator, self.diags);
        const has_next = try self.makeCompactImplicitCall("has_next", &.{.{ .name = "self", .expr = has_next_self }}, 0, loc, &lowered_scope);
        const next_self = try typ.ensureMutablePointer(loc, iterator_use, &lowered_scope, self.allocator, self.diags);
        const next = try self.makeCompactImplicitCall("next", &.{.{ .name = "self", .expr = next_self }}, 0, loc, &lowered_scope);
        const item_name = file.tokenText(&self.diags.source_db, statement.name_token);
        const item_loc = file.tokenLocation(statement.name_token);
        const body = try self.handleCompactForBody(node, statement.body, item_name, item_loc, next, &lowered_scope);
        const semantic = try self.allocator.create(sg.WhileStatement);
        semantic.* = .{ .condition = has_next.node, .body = body };
        const result = try sg.makeSGNode(.{ .while_statement = semantic }, loc, self.allocator);
        try lowered_scope.nodes.append(result);
        var deferred_index = lowered_scope.deferred.items.len;
        while (deferred_index > 0) : (deferred_index -= 1) for (lowered_scope.deferred.items[deferred_index - 1].nodes) |deferred_node| try lowered_scope.nodes.append(deferred_node);
        const lowered_nodes = try lowered_scope.nodes.toOwnedSlice();
        lowered_scope.nodes.deinit();
        self.clearDeferred(&lowered_scope);
        const block = try self.allocator.create(sg.CodeBlock);
        block.* = .{ .nodes = lowered_nodes, .ret_val = null };
        const block_node = try sg.makeSGNode(.{ .code_block = block }, loc, self.allocator);
        try scope.nodes.append(block_node);
        return .{ .node = block_node, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactForBody(self: *Semantizer, parent_node: syn.SyntaxRef, body_node: syn.NodeIndex, item_name: []const u8, item_loc: tok.Location, next: typ.TypedExpr, parent: *Scope) SemErr!*const sg.CodeBlock {
        const file = self.syntaxFile(parent_node);
        const body = file.codeBlock(body_node) orelse return error.InvalidType;
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        const binding = try self.allocator.create(sg.BindingDeclaration);
        binding.* = .{ .name = item_name, .location = item_loc, .origin_file = self.locationPath(item_loc), .mutability = .constant, .ty = next.ty, .initialization = next.node };
        try child.bindings.put(item_name, binding);
        try child.nodes.append(try sg.makeSGNode(.{ .binding_declaration = binding }, item_loc, self.allocator));
        try self.maybeScheduleAutoDeinit(binding, item_loc, &child);
        for (body.statements) |statement| {
            const typed = try self.visitNode(self.childRef(parent_node, statement), &child);
            if (file.tag(statement) == .function_call) try child.nodes.append(typed.node);
        }
        var deferred_index = child.deferred.items.len;
        while (deferred_index > 0) : (deferred_index -= 1) for (child.deferred.items[deferred_index - 1].nodes) |deferred_node| try child.nodes.append(deferred_node);
        const nodes = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);
        const result = try self.allocator.create(sg.CodeBlock);
        result.* = .{ .nodes = nodes, .ret_val = null };
        return result;
    }

    fn compactPipeContainsPlaceholder(self: *Semantizer, node: syn.SyntaxRef) bool {
        const file = self.syntaxFile(node);
        return switch (file.tag(node.node)) {
            .pipe_placeholder => true,
            .struct_field_access => blk: {
                const access = file.structFieldAccess(node.node).?;
                break :blk self.compactPipeContainsPlaceholder(self.childRef(node, access.value));
            },
            .choice_payload_access => blk: {
                const access = file.choicePayloadAccess(node.node).?;
                break :blk self.compactPipeContainsPlaceholder(self.childRef(node, access.value));
            },
            .address_of, .address_of_mut, .error_propagation => self.compactPipeContainsPlaceholder(self.childRef(node, file.unaryOperand(node.node).?)),
            .error_context, .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo, .compare_equal, .compare_not_equal, .compare_less, .compare_greater, .compare_less_equal, .compare_greater_equal, .logical_and, .logical_or, .index_access => blk: {
                const operation = file.binaryOperation(node.node).?;
                break :blk self.compactPipeContainsPlaceholder(self.childRef(node, operation.lhs)) or self.compactPipeContainsPlaceholder(self.childRef(node, operation.rhs));
            },
            .function_call => self.compactPipeContainsPlaceholder(self.childRef(node, file.functionCall(node.node).?.input)),
            .struct_value_literal => blk: {
                for (file.structValueLiteral(node.node).?.fields) |field_node| {
                    const field = file.valueField(field_node).?;
                    if (self.compactPipeContainsPlaceholder(self.childRef(node, field.value))) break :blk true;
                }
                break :blk false;
            },
            .list_literal => blk: {
                for (file.listLiteral(node.node).?.elements) |element| if (self.compactPipeContainsPlaceholder(self.childRef(node, element))) break :blk true;
                break :blk false;
            },
            .choice_literal, .choice_some_literal => if (file.choiceLiteral(node.node).?.payload) |payload| self.compactPipeContainsPlaceholder(self.childRef(node, payload)) else false,
            else => false,
        };
    }

    fn handleCompactPipeChoicePayloadAccess(self: *Semantizer, base: typ.TypedExpr, variant_name: []const u8, loc: tok.Location, scope: *Scope) SemErr!typ.TypedExpr {
        const choice = switch (base.ty) {
            .choice_type => |value| value,
            else => {
                const desc = try self.formatTypeText(base.ty, scope);
                defer desc.deinit();
                try self.diags.add(loc, .semantic, "cannot access choice payload '..{s}' on value of type '{s}'", .{ variant_name, desc.bytes });
                return error.Reported;
            },
        };
        for (choice.variants, 0..) |variant, index| if (std.mem.eql(u8, variant.name, variant_name)) {
            const payload = variant.payload_type orelse {
                try self.diags.add(loc, .semantic, "choice variant '..{s}' has no payload", .{variant_name});
                return error.Reported;
            };
            const access = try self.allocator.create(sg.ChoicePayloadAccess);
            access.* = .{ .choice_value = base.node, .variant_index = @intCast(index), .payload_type = payload };
            const result = try sg.makeSGNode(.{ .choice_payload_access = access }, loc, self.allocator);
            result.sem_type = payload;
            return .{ .node = result, .ty = payload };
        };
        const desc = try self.formatTypeText(base.ty, scope);
        defer desc.deinit();
        try self.diags.add(loc, .semantic, "choice type '{s}' has no variant '..{s}'", .{ desc.bytes, variant_name });
        return error.Reported;
    }

    fn evalCompactPipeArg(self: *Semantizer, node: syn.SyntaxRef, left: typ.TypedExpr, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        if (!self.compactPipeContainsPlaceholder(node)) return self.visitNode(node, scope);
        return switch (file.tag(node.node)) {
            .pipe_placeholder => left,
            .struct_field_access => blk: {
                const access = file.structFieldAccess(node.node).?;
                const base = try self.evalCompactPipeArg(self.childRef(node, access.value), left, scope);
                const field_name = file.tokenText(&self.diags.source_db, access.field_token);
                if (base.ty != .struct_type and base.node.content == .function_call) {
                    const output = base.node.content.function_call.callee.output.fields;
                    if (output.len == 1 and std.mem.eql(u8, output[0].name, field_name)) break :blk base;
                }
                break :blk self.buildStructFieldAccessFromTypedExpr(base, field_name, file.tokenLocation(access.field_token), scope);
            },
            .choice_payload_access => blk: {
                const access = file.choicePayloadAccess(node.node).?;
                break :blk self.handleCompactPipeChoicePayloadAccess(try self.evalCompactPipeArg(self.childRef(node, access.value), left, scope), file.tokenText(&self.diags.source_db, access.variant_token), file.tokenLocation(access.variant_token), scope);
            },
            .address_of, .address_of_mut => blk: {
                const address = file.addressOf(node.node).?;
                const inner = try self.evalCompactPipeArg(self.childRef(node, address.value), left, scope);
                break :blk switch (address.mutability) {
                    .read_only => typ.ensureReadOnlyPointer(self.nodeLocation(node), inner, self.allocator, self.diags),
                    .read_write => typ.ensureMutablePointer(self.nodeLocation(node), inner, scope, self.allocator, self.diags),
                };
            },
            else => {
                try self.diags.add(self.nodeLocation(node), .semantic, "pipe placeholders are only supported as '_', '&_', '$&_', '_.field', or '..variant' payload access for now", .{});
                return error.Reported;
            },
        };
    }

    fn handleCompactPipe(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const operation = file.binaryOperation(node.node) orelse return error.InvalidType;
        const left = try self.visitNode(self.childRef(node, operation.lhs), scope);
        const right = self.childRef(node, operation.rhs);
        if (file.functionCall(operation.rhs)) |call| {
            const input = file.structValueLiteral(call.input) orelse {
                try self.diags.add(self.nodeLocation(node), .semantic, "pipe right-hand side must be a call with explicit arguments", .{});
                return error.Reported;
            };
            var args = std.array_list.Managed(CallArg).init(self.allocator.*);
            defer args.deinit();
            var found_placeholder = false;
            for (input.fields) |field_node| {
                const field = file.valueField(field_node) orelse return error.InvalidType;
                found_placeholder = found_placeholder or self.compactPipeContainsPlaceholder(self.childRef(right, field.value));
                const name = if (field.name_token) |token_index| file.tokenText(&self.diags.source_db, token_index) else try std.fmt.allocPrint(self.allocator.*, "__positional_{d}", .{field.position.?});
                try args.append(.{ .name = name, .expr = try self.evalCompactPipeArg(self.childRef(right, field.value), left, scope) });
            }
            if (!found_placeholder) {
                try self.diags.add(self.nodeLocation(node), .semantic, "pipe right-hand side must use at least one argument placeholder", .{});
                return error.Reported;
            }
            var typed_input = try self.buildCallInputWithPositionalPrefix(args.items, input.positional_prefix_count);
            const name = file.tokenText(&self.diags.source_db, call.callee_token);
            if (std.mem.eql(u8, name, "is") and call.module_qualifier == null) return self.handleIsBuiltinFromInput(typed_input, self.nodeLocation(node), scope);
            const callee = try self.resolveRegularCallCallee(right, typed_input, scope, self.nodeLocation(node));
            typed_input = try self.coerceCallInputToExpected(&callee.input, typed_input, self.nodeLocation(node), scope);
            try self.discoverFunctionReference(callee);
            const semantic = try self.allocator.create(sg.FunctionCall);
            semantic.* = .{ .callee = callee, .input = typed_input.node };
            const result = try sg.makeSGNode(.{ .function_call = semantic }, self.nodeLocation(node), self.allocator);
            result.sem_type = typ.functionReturnType(callee);
            return .{ .node = result, .ty = typ.functionReturnType(callee) };
        }
        if (!self.compactPipeContainsPlaceholder(right)) {
            try self.diags.add(self.nodeLocation(node), .semantic, "pipe right-hand side must use at least one argument placeholder", .{});
            return error.Reported;
        }
        return self.evalCompactPipeArg(right, left, scope);
    }

    fn handleCompactChoiceOptionDeclaration(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const declaration = file.choiceOptionDeclaration(node.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, declaration.name_token);
        const option = scope.lookupChoiceOption(name) orelse return error.SymbolNotFound;
        const result = try sg.makeSGNode(.{ .choice_option_declaration = option }, self.nodeLocation(node), self.allocator);
        try scope.nodes.append(result);
        if (scope.parent == null) try self.root_list.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn compactAbstractTargetName(self: *Semantizer, target: syn.SyntaxRef) ?[]const u8 {
        const file = self.syntaxFile(target);
        return switch (file.syntaxType(target.node) orelse return null) {
            .name => |name| if (name.qualifier_token == null) file.tokenText(&self.diags.source_db, name.name_token) else null,
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse break :blk null;
                break :blk if (base == .name and base.name.qualifier_token == null)
                    file.tokenText(&self.diags.source_db, base.name.name_token)
                else
                    null;
            },
            else => null,
        };
    }

    fn compactResolvedAbstractArgs(self: *Semantizer, target: syn.SyntaxRef, scope: *Scope) SemErr![]const ?gen.GenericArgValue {
        const file = self.syntaxFile(target);
        const generic = switch (file.syntaxType(target.node) orelse return error.UnknownType) {
            .generic => |value| value,
            else => return &.{},
        };
        const name = self.compactAbstractTargetName(target) orelse return error.UnknownType;
        const info = scope.lookupAbstractInfo(name) orelse return error.UnknownType;
        const result = try self.allocator.alloc(?gen.GenericArgValue, info.params.len);
        for (result) |*argument| argument.* = null;
        const arguments = file.structTypeLiteral(generic.arguments) orelse return error.InvalidType;
        for (arguments.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const field_name = file.tokenText(&self.diags.source_db, field.name_token);
            var parameter_index: ?usize = null;
            for (info.params, 0..) |parameter, index| if (std.mem.eql(u8, parameter.name, field_name)) {
                parameter_index = index;
                break;
            };
            const index = parameter_index orelse return error.UnknownType;
            result[index] = switch (info.params[index].kind) {
                .type => .{ .type = try self.resolveSyntaxTypeWithMode(file.ref(field.type_node orelse return error.UnknownType), scope, true, null) },
                .comptime_int => .{ .comptime_int = try self.resolveComptimeIntExpr(file.ref(field.default_value orelse return error.UnknownType), scope, null) },
            };
        }
        return result;
    }

    const CompactAbstractRequirementFields = struct {
        fields: sg.StructType,
        generic_param_indices: []const ?u32,
        abstract_requirements: []const ?[]const u8,
        nested_patterns: []const ?syn.SyntaxRef,
        self_indices: []const u32,
        pointer_self_indices: []const u32,
    };

    fn compactAbstractRequirementTypeContainsParam(
        self: *Semantizer,
        node: syn.SyntaxRef,
        generic_params: []const []const u8,
    ) bool {
        const file = self.syntaxFile(node);
        return switch (file.syntaxType(node.node) orelse return false) {
            .name => |name| blk: {
                const text = file.tokenText(&self.diags.source_db, name.name_token);
                if (std.mem.eql(u8, text, "Self")) break :blk true;
                for (generic_params) |param| if (std.mem.eql(u8, text, param)) break :blk true;
                break :blk false;
            },
            .pointer => |pointer| self.compactAbstractRequirementTypeContainsParam(file.ref(pointer.child), generic_params),
            .array => |array| self.compactAbstractRequirementTypeContainsParam(file.ref(array.element), generic_params),
            .inferred_errable => |inner| self.compactAbstractRequirementTypeContainsParam(file.ref(inner), generic_params),
            .generic => |generic| blk: {
                const arguments = file.structTypeLiteral(generic.arguments) orelse break :blk false;
                for (arguments.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse break :blk false;
                    if (field.type_node) |field_type| {
                        if (self.compactAbstractRequirementTypeContainsParam(file.ref(field_type), generic_params)) break :blk true;
                    }
                }
                break :blk false;
            },
            .struct_literal => |literal| blk: {
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse break :blk false;
                    if (field.type_node) |field_type| {
                        if (self.compactAbstractRequirementTypeContainsParam(file.ref(field_type), generic_params)) break :blk true;
                    }
                }
                break :blk false;
            },
            .choice_literal => |literal| blk: {
                for (literal.variants) |variant_node| {
                    const variant = file.choiceTypeVariant(variant_node) orelse break :blk false;
                    if (variant.payload_type) |payload| {
                        if (self.compactAbstractRequirementTypeContainsParam(file.ref(payload), generic_params)) break :blk true;
                    }
                }
                break :blk false;
            },
            .nullable => |inner| self.compactAbstractRequirementTypeContainsParam(file.ref(inner), generic_params),
        };
    }

    fn compactAbstractRequirementFields(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        literal_node: syn.NodeIndex,
        generic_params: []const []const u8,
        scope: *Scope,
    ) SemErr!CompactAbstractRequirementFields {
        const file = self.syntaxFile(owner);
        const literal = file.structTypeLiteral(literal_node) orelse return error.InvalidType;
        var fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        var generic_indices = std.array_list.Managed(?u32).init(self.allocator.*);
        var abstract_requirements = std.array_list.Managed(?[]const u8).init(self.allocator.*);
        var nested_patterns = std.array_list.Managed(?syn.SyntaxRef).init(self.allocator.*);
        var self_indices = std.array_list.Managed(u32).init(self.allocator.*);
        var pointer_self_indices = std.array_list.Managed(u32).init(self.allocator.*);

        for (literal.fields, 0..) |field_node, index| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            var ty: sg.Type = .{ .builtin = .Any };
            var generic_index: ?u32 = null;
            var abstract_requirement: ?[]const u8 = null;
            var nested_pattern: ?syn.SyntaxRef = null;

            if (field.type_node) |type_node| {
                const type_ref = file.ref(type_node);
                switch (file.syntaxType(type_node) orelse return error.InvalidType) {
                    .name => |name| {
                        const text = file.tokenText(&self.diags.source_db, name.name_token);
                        if (std.mem.eql(u8, text, "Self")) {
                            try self_indices.append(@intCast(index));
                        } else {
                            for (generic_params, 0..) |param, param_index| {
                                if (std.mem.eql(u8, text, param)) {
                                    generic_index = @intCast(param_index);
                                    break;
                                }
                            }
                            if (generic_index == null) {
                                if (scope.lookupAbstractInfo(text) != null)
                                    abstract_requirement = text
                                else
                                    ty = try self.resolveSyntaxType(type_ref, scope);
                            }
                        }
                    },
                    .generic => |generic| {
                        const base = file.syntaxType(generic.base) orelse return error.InvalidType;
                        const base_name = if (base == .name and base.name.qualifier_token == null)
                            file.tokenText(&self.diags.source_db, base.name.name_token)
                        else
                            null;
                        if (base_name) |text| {
                            if (scope.lookupAbstractInfo(text) != null) {
                                abstract_requirement = text;
                            } else if (self.compactAbstractRequirementTypeContainsParam(type_ref, generic_params)) {
                                nested_pattern = type_ref;
                            } else {
                                ty = try self.resolveSyntaxType(type_ref, scope);
                            }
                        } else {
                            ty = try self.resolveSyntaxType(type_ref, scope);
                        }
                    },
                    .pointer => |pointer| {
                        const child = file.syntaxType(pointer.child) orelse return error.InvalidType;
                        const child_name: ?[]const u8 = switch (child) {
                            .name => |name| if (name.qualifier_token == null) file.tokenText(&self.diags.source_db, name.name_token) else null,
                            .generic => |generic| blk: {
                                const base = file.syntaxType(generic.base) orelse break :blk null;
                                break :blk if (base == .name and base.name.qualifier_token == null)
                                    file.tokenText(&self.diags.source_db, base.name.name_token)
                                else
                                    null;
                            },
                            else => null,
                        };
                        if (child_name) |text| {
                            if (std.mem.eql(u8, text, "Self")) {
                                ty = try typ.pointerToAny(@enumFromInt(@intFromEnum(pointer.mutability)), self.allocator);
                                try pointer_self_indices.append(@intCast(index));
                            } else if (scope.lookupAbstractInfo(text) != null) {
                                ty = try typ.pointerToAny(@enumFromInt(@intFromEnum(pointer.mutability)), self.allocator);
                                abstract_requirement = text;
                            } else {
                                ty = try self.resolveSyntaxType(type_ref, scope);
                            }
                        } else {
                            ty = try self.resolveSyntaxType(type_ref, scope);
                        }
                    },
                    else => ty = try self.resolveSyntaxType(type_ref, scope),
                }
            }

            try fields.append(.{
                .name = file.tokenText(&self.diags.source_db, field.name_token),
                .ty = ty,
                .default_value = null,
            });
            try generic_indices.append(generic_index);
            try abstract_requirements.append(abstract_requirement);
            try nested_patterns.append(nested_pattern);
        }

        return .{
            .fields = .{ .fields = try fields.toOwnedSlice() },
            .generic_param_indices = try generic_indices.toOwnedSlice(),
            .abstract_requirements = try abstract_requirements.toOwnedSlice(),
            .nested_patterns = try nested_patterns.toOwnedSlice(),
            .self_indices = try self_indices.toOwnedSlice(),
            .pointer_self_indices = try pointer_self_indices.toOwnedSlice(),
        };
    }

    fn compactAbstractParamNames(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        parameter_nodes: []const syn.NodeIndex,
        parameter_struct: ?syn.NodeIndex,
    ) SemErr![]const []const u8 {
        const file = self.syntaxFile(owner);
        const nodes = if (parameter_struct) |struct_node|
            (file.structTypeLiteral(struct_node) orelse return error.InvalidType).fields
        else
            parameter_nodes;
        const names = try self.allocator.alloc([]const u8, nodes.len);
        for (nodes, 0..) |parameter_node, index| {
            names[index] = if (parameter_struct != null) blk: {
                const field = file.structTypeField(parameter_node) orelse return error.InvalidType;
                break :blk file.tokenText(&self.diags.source_db, field.name_token);
            } else file.tokenText(&self.diags.source_db, file.mainToken(parameter_node));
        }
        return names;
    }

    fn compactCollectHiddenComptimeImplementsParams(
        self: *Semantizer,
        node: syn.SyntaxRef,
        params: *std.array_list.Managed(gen.GenericParam),
        scope: *Scope,
    ) SemErr!void {
        const file = self.syntaxFile(node);
        switch (file.tag(node.node)) {
            .identifier => {
                const name = file.tokenText(&self.diags.source_db, file.mainToken(node.node));
                if (hasGenericParamNamed(params.items, name) or typ.builtinFromName(name) != null) return;
                if (scope.lookupType(name) != null or scope.lookupBinding(name) != null) return;
                try params.append(.{ .name = name, .kind = .comptime_int, .value_type = .{ .builtin = .UIntNative } });
            },
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            => {
                const operation = file.binaryOperation(node.node) orelse return;
                try self.compactCollectHiddenComptimeImplementsParams(file.ref(operation.lhs), params, scope);
                try self.compactCollectHiddenComptimeImplementsParams(file.ref(operation.rhs), params, scope);
            },
            else => {},
        }
    }

    fn compactCollectHiddenImplementsParams(
        self: *Semantizer,
        node: syn.SyntaxRef,
        params: *std.array_list.Managed(gen.GenericParam),
        scope: *Scope,
    ) SemErr!void {
        const file = self.syntaxFile(node);
        switch (file.syntaxType(node.node) orelse return) {
            .name => |name| {
                if (name.qualifier_token != null) return;
                const text = file.tokenText(&self.diags.source_db, name.name_token);
                if (hasGenericParamNamed(params.items, text) or typ.builtinFromName(text) != null or scope.lookupType(text) != null) return;
                try params.append(.{ .name = text, .kind = .type, .value_type = null });
            },
            .pointer => |pointer| try self.compactCollectHiddenImplementsParams(file.ref(pointer.child), params, scope),
            .array => |array| try self.compactCollectHiddenImplementsParams(file.ref(array.element), params, scope),
            .inferred_errable => |inner| try self.compactCollectHiddenImplementsParams(file.ref(inner), params, scope),
            .nullable => |inner| try self.compactCollectHiddenImplementsParams(file.ref(inner), params, scope),
            .struct_literal => |literal| try self.compactCollectHiddenImplementsParamsFromFields(file, literal.fields, params, scope),
            .generic => |generic| {
                const arguments = file.structTypeLiteral(generic.arguments) orelse return error.InvalidType;
                try self.compactCollectHiddenImplementsParamsFromFields(file, arguments.fields, params, scope);
            },
            .choice_literal => |literal| {
                for (literal.variants) |variant_node| {
                    const variant = file.choiceTypeVariant(variant_node) orelse return error.InvalidType;
                    if (variant.payload_type) |payload| try self.compactCollectHiddenImplementsParams(file.ref(payload), params, scope);
                }
            },
        }
    }

    fn compactCollectHiddenImplementsParamsFromFields(
        self: *Semantizer,
        file: *const syn.SyntaxFile,
        fields: []const syn.NodeIndex,
        params: *std.array_list.Managed(gen.GenericParam),
        scope: *Scope,
    ) SemErr!void {
        for (fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            if (field.type_node) |field_type| try self.compactCollectHiddenImplementsParams(file.ref(field_type), params, scope);
            if (field.default_value) |value| try self.compactCollectHiddenComptimeImplementsParams(file.ref(value), params, scope);
        }
    }

    fn handleCompactAbstractDeclaration(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const declaration = file.abstractDeclaration(node.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, declaration.name_token);
        const generic_info = try self.compactGenericParamDefs(node, declaration.generic_params, declaration.generic_params_struct, scope);
        const param_names = try self.compactAbstractParamNames(node, declaration.generic_params, declaration.generic_params_struct);
        var requirements = std.array_list.Managed(abs.AbstractFunctionReqSem).init(self.allocator.*);
        defer requirements.deinit();
        for (declaration.requires_functions) |requirement_node| {
            const requirement = file.abstractFunctionRequirement(requirement_node) orelse return error.InvalidType;
            const input = try self.compactAbstractRequirementFields(node, requirement.input, param_names, scope);
            const output = try self.compactAbstractRequirementFields(node, requirement.output, param_names, scope);
            try requirements.append(.{
                .syntax_files = self.syntax_files,
                .source_db = &self.diags.source_db,
                .name = file.tokenText(&self.diags.source_db, requirement.name_token),
                .input = input.fields,
                .output = output.fields,
                .input_self_indices = input.self_indices,
                .output_self_indices = output.self_indices,
                .input_pointer_self_indices = input.pointer_self_indices,
                .output_pointer_self_indices = output.pointer_self_indices,
                .input_generic_param_indices = input.generic_param_indices,
                .output_generic_param_indices = output.generic_param_indices,
                .input_abstract_requirements = input.abstract_requirements,
                .output_abstract_requirements = output.abstract_requirements,
                .input_nested_patterns = input.nested_patterns,
                .output_nested_patterns = output.nested_patterns,
                .abstract_param_names = param_names,
            });
        }
        const info = scope.lookupAbstractInfo(name) orelse return error.SymbolNotFound;
        info.requirements = try requirements.toOwnedSlice();
        info.param_names = param_names;
        info.params = generic_info.params;
        const virtual_methods = try self.allocator.alloc(*sg.VirtualMethodRegistry, info.requirements.len);
        for (virtual_methods) |*registry| {
            registry.* = try self.allocator.create(sg.VirtualMethodRegistry);
            registry.*.* = .{ .implementations = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*) };
        }
        info.virtual_methods = virtual_methods;
        // Function contracts are populated as their compact views are semantized.
        // Keeping the predeclared entry makes mutually-referential abstracts resolvable.
        const type_declaration = scope.lookupType(name) orelse return error.SymbolNotFound;
        const result = try self.appendTypeDeclarationNodeIfMissing(scope, type_declaration, self.nodeLocation(node));
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactAbstractImplements(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const relation = file.abstractImplements(node.node) orelse return error.InvalidType;
        const abstract_ref = file.ref(relation.abstract_type);
        const abstract_name = self.compactAbstractTargetName(abstract_ref) orelse return error.UnknownType;
        const concrete_name = file.tokenText(&self.diags.source_db, relation.concrete_name_token);
        if (relation.generic_params.len != 0 or relation.generic_params_struct != null) {
            const generic_info = try self.compactGenericParamDefs(node, relation.generic_params, relation.generic_params_struct, scope);
            var params = std.array_list.Managed(gen.GenericParam).init(self.allocator.*);
            defer params.deinit();
            var constraints = std.array_list.Managed(?gen.AbstractConstraint).init(self.allocator.*);
            defer constraints.deinit();
            for (generic_info.params, 0..) |param, index| {
                try params.append(param);
                try constraints.append(generic_info.abstract_constraints[index]);
            }
            for (constraints.items) |constraint| {
                if (constraint) |value| if (value.args) |arguments|
                    try self.compactCollectHiddenImplementsParams(arguments, &params, scope);
            }
            const target_type = file.syntaxType(relation.abstract_type) orelse return error.InvalidType;
            if (target_type == .generic) {
                try self.compactCollectHiddenImplementsParams(file.ref(target_type.generic.arguments), &params, scope);
            }
            while (constraints.items.len < params.items.len) try constraints.append(null);
            try scope.appendAbstractImplTemplate(abstract_name, .{
                .syntax_files = self.syntax_files,
                .source_db = &self.diags.source_db,
                .params = try params.toOwnedSlice(),
                .param_abstract_constraints = try constraints.toOwnedSlice(),
                .concrete_name = concrete_name,
                .concrete_param_count = generic_info.params.len,
                .args = switch (target_type) {
                    .generic => |generic| file.ref(generic.arguments),
                    else => null,
                },
                .location = self.nodeLocation(node),
            });
        } else {
            const concrete = try self.resolveSyntaxTypeName(node, relation.concrete_name_token, null, scope, true);
            const args = try self.compactResolvedAbstractArgs(abstract_ref, scope);
            try self.ensureConcreteAbstractImplCoherent(abstract_name, concrete, args, scope, self.nodeLocation(node));
            try scope.appendAbstractImpl(abstract_name, .{ .ty = concrete, .args = args, .location = self.nodeLocation(node) });
        }
        const result = try self.makeNoopNode(self.nodeLocation(node));
        try scope.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactAbstractDefault(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const relation = file.abstractDefaultsTo(node.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, relation.name_token);
        const concrete = try self.resolveTypeExpression(file.ref(relation.type_node), scope);
        try scope.abstract_defaults.put(name, .{ .ty = concrete, .location = self.nodeLocation(node) });
        const result = try self.makeNoopNode(self.nodeLocation(node));
        try scope.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactTypeDeclaration(self: *Semantizer, node: syn.SyntaxRef, scope: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const name_token, const generic_params, const generic_params_struct, const value = switch (file.tag(node.node)) {
            .type_declaration => blk: {
                const declaration = file.typeDeclaration(node.node).?;
                break :blk .{ declaration.name_token, declaration.generic_params, declaration.generic_params_struct, declaration.value };
            },
            .c_enum_declaration => blk: {
                const declaration = file.cEnumDeclaration(node.node).?;
                break :blk .{ declaration.name_token, declaration.generic_params, declaration.generic_params_struct, declaration.value };
            },
            .c_union_declaration => blk: {
                const declaration = file.cUnionDeclaration(node.node).?;
                break :blk .{ declaration.name_token, declaration.generic_params, declaration.generic_params_struct, declaration.value };
            },
            else => unreachable,
        };
        const name = file.tokenText(&self.diags.source_db, name_token);
        if (generic_params.len != 0 or generic_params_struct != null) {
            if (scope.generic_types.getPtr(name)) |templates| {
                for (templates.items) |template| {
                    if (template.location.file != file.location(value).file or template.location.offset != file.location(value).offset) continue;
                    const noop = try self.makeNoopNode(file.location(value));
                    try scope.nodes.append(noop);
                    return .{ .node = noop, .ty = .{ .builtin = .Any } };
                }
            }
            const generic_info = try self.compactGenericParamDefs(
                node,
                generic_params,
                generic_params_struct,
                scope,
            );
            try scope.appendGenericTypeTemplate(name, .{
                .name = name,
                .location = file.location(value),
                .params = generic_info.params,
                .param_abstract_constraints = generic_info.abstract_constraints,
                .body = file.ref(value),
            });
            const noop = try self.makeNoopNode(file.location(value));
            try scope.nodes.append(noop);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }
        const declaration = scope.lookupType(name) orelse blk: {
            const alias_type = try self.resolveTypeExpression(file.ref(value), scope);
            const created = try self.allocator.create(sg.TypeDeclaration);
            created.* = .{ .name = name, .origin_file = self.locationPath(file.location(value)), .ty = alias_type };
            try scope.types.put(name, created);
            break :blk created;
        };
        switch (file.tag(value)) {
            .struct_type_literal => {
                var subst = GenericSubst.init(self.allocator);
                defer subst.deinit();
                const resolved = try self.structTypeFromNodeWithSubst(file.ref(value), scope, &subst);
                const target = @constCast(declaration.ty.struct_type);
                target.fields = resolved.fields;
                target.layout = if (file.tag(node.node) == .c_union_declaration) .c_union else .regular;
                if (target.identity == null) {
                    const identity = try self.allocator.create(sg.GenericTypeIdentity);
                    identity.* = .{ .base_name = name, .arg_names = &.{}, .arg_values = &.{} };
                    target.identity = .{ .generic = identity };
                }
            },
            .choice_type_literal => {
                const literal = file.choiceTypeLiteral(value) orelse return error.InvalidType;
                if (file.tag(node.node) == .c_enum_declaration) {
                    for (literal.variants) |variant_node| {
                        const variant = file.choiceTypeVariant(variant_node).?;
                        if (variant.payload_type != null) {
                            try self.diags.add(file.tokenLocation(variant.name_token), .semantic, "CEnum variant '..{s}' cannot carry a payload", .{file.tokenText(&self.diags.source_db, variant.name_token)});
                            return error.Reported;
                        }
                    }
                }
                const resolved = try self.choiceTypeFromNode(file.ref(value), scope);
                const target = @constCast(declaration.ty.choice_type);
                target.variants = resolved.variants;
                target.layout = if (file.tag(node.node) == .c_enum_declaration) .c_enum else .regular;
                if (target.identity == null) {
                    const identity = try self.allocator.create(sg.GenericTypeIdentity);
                    identity.* = .{ .base_name = name, .arg_names = &.{}, .arg_values = &.{} };
                    target.identity = .{ .generic = identity };
                }
            },
            else => declaration.ty = try self.resolveTypeExpression(file.ref(value), scope),
        }
        const result = try self.appendTypeDeclarationNodeIfMissing(scope, declaration, file.location(value));
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleCompactCodeBlock(self: *Semantizer, node: syn.SyntaxRef, parent: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const block = file.codeBlock(node.node).?;
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        var return_value: ?*sg.SGNode = null;
        var return_type: sg.Type = .{ .builtin = .Any };
        for (block.statements, 0..) |statement, index| {
            const statement_ref = self.childRef(node, statement);
            const typed = try self.visitNode(statement_ref, &child);
            if (index + 1 == block.statements.len and file.tag(statement) == .expression_statement) {
                return_value = typed.node;
                return_type = typed.ty;
            } else if (file.tag(statement) == .function_call) {
                try child.nodes.append(typed.node);
            }
        }
        var deferred_index = child.deferred.items.len;
        while (deferred_index > 0) : (deferred_index -= 1) {
            for (child.deferred.items[deferred_index - 1].nodes) |deferred_node| try child.nodes.append(deferred_node);
        }
        const nodes = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);
        const block_value = try self.allocator.create(sg.CodeBlock);
        block_value.* = .{ .nodes = nodes, .ret_val = return_value };
        const result = try sg.makeSGNode(.{ .code_block = block_value }, self.nodeLocation(node), self.allocator);
        try parent.nodes.append(result);
        return .{ .node = result, .ty = return_type };
    }

    fn handleCompactReturn(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const statement = self.syntaxFile(node).returnStatement(node.node).?;
        var expression: ?typ.TypedExpr = null;
        if (statement.value) |value| {
            const value_ref = self.childRef(node, value);
            expression = try self.visitNode(value_ref, s);
            expression = try self.ensureValuePositionAllowed(expression.?, self.nodeLocation(value_ref), s);
        }
        const semantic = try self.allocator.create(sg.ReturnStatement);
        semantic.* = .{
            .expression = if (expression) |value| value.node else null,
            .cleanup_nodes = try self.collectActiveEarlyCleanupNodes(s),
        };
        const result = try sg.makeSGNode(.{ .return_statement = semantic }, self.nodeLocation(node), self.allocator);
        try s.nodes.append(result);
        return .{ .node = result, .ty = .{ .builtin = .Any } };
    }

    fn handleImportStatement(self: *Semantizer, loc: tok.Location) SemErr!typ.TypedExpr {
        return try typ.makeTypeLiteral(self.allocator, loc, .{ .builtin = .Any });
    }

    fn isPrivateName(name: []const u8) bool {
        return name.len > 0 and name[0] == '_';
    }

    fn moduleDirForFile(self: *Semantizer, file_path: []const u8) []const u8 {
        _ = self;
        return std.fs.path.dirname(file_path) orelse ".";
    }

    fn isSameModule(self: *Semantizer, lhs_file: []const u8, rhs_file: []const u8) !bool {
        const lhs_dir = self.moduleDirForFile(lhs_file);
        const rhs_dir = self.moduleDirForFile(rhs_file);
        return std.mem.eql(u8, lhs_dir, rhs_dir);
    }

    fn bindingIsVisible(self: *Semantizer, binding: *const sg.BindingDeclaration, requester_file: []const u8) !bool {
        if (!isPrivateName(binding.name)) return true;
        return try self.isSameModule(requester_file, binding.origin_file);
    }

    fn lookupTypeDeclarationForType(self: *Semantizer, ty: sg.Type, s: *Scope) ?*const sg.TypeDeclaration {
        _ = self;
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            var it = sc.types.iterator();
            while (it.next()) |entry| {
                const td = entry.value_ptr.*;
                if (typ.declaredTypeMatches(td.ty, ty)) return td;
            }
        }
        return null;
    }

    fn typeIsVisible(self: *Semantizer, td: *const sg.TypeDeclaration, requester_file: []const u8) !bool {
        if (!isPrivateName(td.name)) return true;
        return try self.isSameModule(requester_file, td.origin_file);
    }

    fn functionIsVisible(self: *Semantizer, fd: *const sg.FunctionDeclaration, requester_file: []const u8) !bool {
        if (!isPrivateName(fd.name)) return true;
        return try self.isSameModule(requester_file, self.locationPath(fd.location));
    }

    fn typeDeclIsReady(td: *const sg.TypeDeclaration) bool {
        return switch (td.ty) {
            .struct_type => |st| !(st.fields.len == 0 and st.identity == null),
            else => true,
        };
    }

    fn addPrivateMemberDiag(
        self: *Semantizer,
        loc: tok.Location,
        kind: []const u8,
        name: []const u8,
    ) !void {
        try self.diags.add(
            loc,
            .semantic,
            "{s} '{s}' is private to its module",
            .{ kind, name },
        );
    }

    //──────────────────────────────────────────────────── ABSTRACT DECLARATION

    // For now, relations are recorded as no-ops to accept syntax without enforcing.

    fn ensureConcreteAbstractImplCoherent(
        self: *Semantizer,
        abstract_name: []const u8,
        concrete: sg.Type,
        args: []const ?gen.GenericArgValue,
        s: *Scope,
        location: tok.Location,
    ) SemErr!void {
        var cur: ?*Scope = s;
        while (cur) |scope| : (cur = scope.parent) {
            const entries = scope.abstract_impls.getPtr(abstract_name) orelse continue;
            for (entries.items) |entry| {
                if (!typ.typesExactlyEqual(entry.ty, concrete)) continue;
                if (associatedArgsEqual(entry.args, args)) continue;
                const concrete_text = try self.formatTypeText(concrete, s);
                defer concrete_text.deinit();
                try self.diags.add(
                    location,
                    .semantic,
                    "conflicting implementations of abstract '{s}' for type '{s}' produce different associated arguments",
                    .{ abstract_name, concrete_text.bytes },
                );
                return error.Reported;
            }
        }
    }

    //─────────────────────────────────────────────────────────  LITERALS

    fn handleChoiceLiteral(self: *Semantizer, syntax_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const lit = file.choiceLiteral(syntax_ref.node) orelse return error.InvalidType;
        var payload: ?*const sg.SGNode = null;
        if (lit.payload) |payload_node| {
            var payload_te = try self.visitNode(file.ref(payload_node), s);
            payload_te = try self.ensureValuePositionAllowed(payload_te, file.location(payload_node), s);
            payload_te.node.sem_type = payload_te.ty;
            payload = payload_te.node;
        }

        const node = try self.allocator.create(sg.ChoiceLiteral);
        node.* = .{
            .variant_name = file.tokenText(&self.diags.source_db, lit.name_token),
            .module_qualifier = null,
            .choice_type = undefined,
            .variant_index = 0,
            .payload = payload,
        };
        const n = try sg.makeSGNode(.{ .choice_literal = node }, file.tokenLocation(lit.name_token), self.allocator);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn resolveChoiceOptionReference(
        self: *Semantizer,
        module_qualifier: ?[]const u8,
        name: []const u8,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!*const sg.ChoiceOptionDeclaration {
        if (module_qualifier) |module_name| {
            const module_dir = s.lookupModuleAlias(module_name) orelse return error.SymbolNotFound;
            if (s.lookupChoiceOptionInModule(module_dir, name)) |decl| {
                if (isPrivateName(name)) {
                    const requester_dir = self.moduleDirForFile(self.locationPath(loc));
                    if (!std.mem.eql(u8, requester_dir, module_dir)) {
                        try self.addPrivateMemberDiag(loc, "choice option", name);
                        return error.Reported;
                    }
                }
                return decl;
            }
            return error.SymbolNotFound;
        }
        return s.lookupChoiceOption(name) orelse error.SymbolNotFound;
    }

    //─────────────────────────────────────────────────────────  IDENTIFIER
    fn handleIdentifier(
        self: *Semantizer,
        name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (s.bindingMoveLocation(name)) |move_loc| {
            if (move_loc.file == loc.file and move_loc.offset == loc.offset) {
                const b = s.lookupBinding(name) orelse return error.SymbolNotFound;
                if (!(try self.bindingIsVisible(b, self.locationPath(loc)))) {
                    try self.addPrivateMemberDiag(loc, "value", name);
                    return error.Reported;
                }
                const n = try sg.makeSGNode(.{ .binding_use = b }, loc, self.allocator);
                n.sem_type = b.ty;
                return .{ .node = n, .ty = b.ty };
            }
            try self.diags.add(
                loc,
                .semantic,
                "binding '{s}' was moved and cannot be used again (moved at {s}:{d}:{d})",
                .{ name, self.locationPath(move_loc), self.locationLineColumn(move_loc).line, self.locationLineColumn(move_loc).column },
            );
            return error.Reported;
        }

        if (s.lookupGenericValue(name)) |generic_value| {
            const literal: sg.ValueLiteral = switch (generic_value.value) {
                .comptime_int => |value| .{ .int_literal = value },
                .type => return error.SymbolNotFound,
            };
            const n = try sg.makeSGNode(.{ .value_literal = literal }, undefined, self.allocator);
            n.sem_type = generic_value.ty;
            return .{ .node = n, .ty = generic_value.ty };
        }

        if (s.lookupRefinedBinding(name)) |b| {
            const n = try sg.makeSGNode(.{ .binding_use = b }, loc, self.allocator);
            n.sem_type = b.ty;
            return .{ .node = n, .ty = b.ty };
        }

        const b = s.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(b, self.locationPath(loc)))) {
            try self.addPrivateMemberDiag(loc, "value", name);
            return error.Reported;
        }
        const n = try sg.makeSGNode(.{ .binding_use = b }, loc, self.allocator);
        n.sem_type = b.ty;
        return .{ .node = n, .ty = b.ty };
    }

    fn handleReachDirective(
        self: *Semantizer,
        reach: syn.SyntaxRef,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const reach_ptr = try self.semanticReachDirectiveFromSyntax(reach);
        const node = try sg.makeSGNode(.{ .reach_directive = reach_ptr }, loc, self.allocator);
        node.sem_type = .{ .builtin = .Any };
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    fn semanticReachDirectiveFromSyntax(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
    ) !*sg.ReachDirective {
        const file = self.syntaxFile(syntax_ref);
        const reach = file.reachDirective(syntax_ref.node) orelse return error.InvalidType;
        var alternatives = try self.allocator.alloc(sg.ReachAlternative, reach.alternatives.len);
        for (reach.alternatives, 0..) |alt_node, idx| {
            const alt = file.reachAlternative(alt_node).?;
            var segments = try self.allocator.alloc([]const u8, alt.segments.len);
            for (alt.segments, 0..) |segment, seg_idx| {
                segments[seg_idx] = file.tokenText(&self.diags.source_db, file.mainToken(segment));
            }
            alternatives[idx] = .{ .segments = segments };
        }

        const reach_ptr = try self.allocator.create(sg.ReachDirective);
        reach_ptr.* = .{ .alternatives = alternatives };
        return reach_ptr;
    }

    fn buildStructFieldAccessFromTypedExpr(
        self: *Semantizer,
        base: typ.TypedExpr,
        field_name: []const u8,
        field_loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (base.ty == .array_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                field_loc,
                .semantic,
                "type '{s}' has no field '.{s}'",
                .{ desc.bytes, field_name },
            );
            return error.Reported;
        }

        if (base.ty != .struct_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                field_loc,
                .semantic,
                "cannot access field '.{s}' on value of type '{s}'",
                .{ field_name, desc.bytes },
            );
            return error.Reported;
        }

        const st = base.ty.struct_type;
        var idx: ?u32 = null;
        var fty: sg.Type = undefined;
        for (st.fields, 0..) |f, i| {
            if (std.mem.eql(u8, f.name, field_name)) {
                idx = @intCast(i);
                fty = typ.effectiveStructFieldType(f);
                break;
            }
        }
        if (idx == null) return error.FieldsNotFound;

        if (isPrivateName(field_name)) {
            if (self.lookupTypeDeclarationForType(base.ty, s)) |td| {
                if (!(try self.isSameModule(self.locationPath(field_loc), td.origin_file))) {
                    try self.addPrivateMemberDiag(field_loc, "field", field_name);
                    return error.Reported;
                }
            }
        }

        const fa = try self.allocator.create(sg.StructFieldAccess);
        fa.* = .{
            .struct_value = base.node,
            .field_name = field_name,
            .field_index = idx.?,
        };

        const n = try sg.makeSGNode(.{ .struct_field_access = fa }, field_loc, self.allocator);
        n.sem_type = fty;
        return .{ .node = n, .ty = fty };
    }

    fn resolveReachAlternativeInScope(
        self: *Semantizer,
        alt: sg.ReachAlternative,
        expected_ty: sg.Type,
        field_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?typ.TypedExpr {
        if (alt.segments.len == 0) return null;

        var current = self.handleIdentifier(alt.segments[0], s, loc) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };

        for (alt.segments[1..]) |segment| {
            current = try self.dereferenceReachPathValue(current);
            current = self.buildStructFieldAccessFromTypedExpr(current, segment, loc, s) catch |err| switch (err) {
                error.FieldsNotFound => return null,
                else => return err,
            };
        }

        if (abs.typesCompatibleForDispatch(expected_ty, current.ty, s)) return current;
        if (self.tryImplicitPointerLiftForDispatch(expected_ty, current)) |lifted| {
            if (abs.typesCompatibleForDispatch(expected_ty, lifted.ty, s)) return lifted;
        }
        if (self.fieldExprMatchesDispatch(expected_ty, current, s)) return current;

        _ = field_name;
        return null;
    }

    fn resolveReachAlternativeInScopeLoose(
        self: *Semantizer,
        alt: sg.ReachAlternative,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?typ.TypedExpr {
        if (alt.segments.len == 0) return null;

        var current = self.handleIdentifier(alt.segments[0], s, loc) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };

        for (alt.segments[1..]) |segment| {
            current = try self.dereferenceReachPathValue(current);
            current = self.buildStructFieldAccessFromTypedExpr(current, segment, loc, s) catch |err| switch (err) {
                error.FieldsNotFound => return null,
                else => return err,
            };
        }

        return current;
    }

    fn currentReachFunctionContext(self: *Semantizer) ?*ReachFunctionContext {
        if (self.function_reach_stack.items.len == 0) return null;
        return &self.function_reach_stack.items[self.function_reach_stack.items.len - 1];
    }

    fn ensurePropagatedReachedField(
        self: *Semantizer,
        field_name: []const u8,
        expected_ty: sg.Type,
        reach: *const sg.ReachDirective,
        loc: tok.Location,
        ctx: *ReachFunctionContext,
    ) SemErr!typ.TypedExpr {
        for (ctx.input_struct.fields) |existing| {
            if (!std.mem.eql(u8, existing.name, field_name)) continue;
            if (!abs.typesCompatibleForDispatch(existing.ty, expected_ty, ctx.body_scope) and
                !abs.typesCompatibleForDispatch(expected_ty, existing.ty, ctx.body_scope))
            {
                const pair = try self.formatTypePairText(expected_ty, existing.ty, ctx.body_scope);
                defer pair.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "cannot propagate reached argument '.{s}': function already has incompatible argument type '{s}' (expected '{s}')",
                    .{ field_name, pair.actual.bytes, pair.expected.bytes },
                );
                return error.Reported;
            }

            const binding = ctx.body_scope.bindings.get(field_name) orelse {
                try self.diags.add(
                    loc,
                    .semantic,
                    "internal error: missing propagated binding for reached argument '.{s}'",
                    .{field_name},
                );
                return error.Reported;
            };
            const use_node = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
            return .{ .node = use_node, .ty = binding.ty };
        }

        const new_len = ctx.input_struct.fields.len + 1;
        const new_fields = try self.allocator.alloc(sg.StructTypeField, new_len);
        std.mem.copyForwards(sg.StructTypeField, new_fields[0..ctx.input_struct.fields.len], ctx.input_struct.fields);
        new_fields[new_len - 1] = .{
            .name = field_name,
            .ty = expected_ty,
            .default_value = try sg.makeSGNode(.{ .reach_directive = reach }, loc, self.allocator),
        };
        ctx.input_struct.fields = new_fields;

        const binding = try self.allocator.create(sg.BindingDeclaration);
        binding.* = .{
            .name = field_name,
            .location = loc,
            .origin_file = self.locationPath(ctx.location),
            .mutability = .constant,
            .ty = expected_ty,
            .initialization = new_fields[new_len - 1].default_value,
        };
        try ctx.body_scope.bindings.put(field_name, binding);

        const use_node = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
        return .{ .node = use_node, .ty = expected_ty };
    }

    fn formatReachDirective(self: *Semantizer, reach: *const sg.ReachDirective) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        for (reach.alternatives, 0..) |alt, alt_idx| {
            if (alt_idx != 0) try buf.appendSlice(", ");
            for (alt.segments, 0..) |segment, seg_idx| {
                if (seg_idx != 0) try buf.append('.');
                try buf.appendSlice(segment);
            }
        }
        return buf.toOwnedSlice();
    }

    fn resolveReachedArgument(
        self: *Semantizer,
        field_name: []const u8,
        expected_ty: sg.Type,
        reach: *const sg.ReachDirective,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        for (reach.alternatives) |alt| {
            if (try self.resolveReachAlternativeInScope(alt, expected_ty, field_name, s, loc)) |resolved| {
                return resolved;
            }
        }

        if (self.currentReachFunctionContext()) |ctx| {
            if (!std.mem.eql(u8, ctx.function_name, "main")) {
                return self.ensurePropagatedReachedField(field_name, expected_ty, reach, loc, ctx);
            }
        }

        const reach_text = try self.formatReachDirective(reach);
        defer self.allocator.free(reach_text);
        const expected_text = try self.formatTypeText(expected_ty, s);
        defer expected_text.deinit();
        try self.diags.add(
            loc,
            .semantic,
            "cannot resolve reached argument '.{s}' with alternatives [{s}] expected as '{s}'",
            .{ field_name, reach_text, expected_text.bytes },
        );
        return error.Reported;
    }

    fn tryResolveReachedArgumentInLocalScope(
        self: *Semantizer,
        field_name: []const u8,
        expected_ty: sg.Type,
        reach: *const sg.ReachDirective,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?typ.TypedExpr {
        for (reach.alternatives) |alt| {
            if (try self.resolveReachAlternativeInScope(alt, expected_ty, field_name, s, loc)) |resolved| {
                return resolved;
            }
        }
        return null;
    }

    fn resolveReachedArgumentForInference(
        self: *Semantizer,
        field_name: []const u8,
        reach: *const sg.ReachDirective,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?typ.TypedExpr {
        for (reach.alternatives) |alt| {
            if (try self.resolveReachAlternativeInScopeLoose(alt, s, loc)) |resolved| {
                return resolved;
            }
        }

        if (self.currentReachFunctionContext()) |ctx| {
            for (ctx.input_struct.fields) |existing| {
                if (!std.mem.eql(u8, existing.name, field_name)) continue;
                const binding = ctx.body_scope.bindings.get(field_name) orelse return null;
                const use_node = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
                return .{ .node = use_node, .ty = binding.ty };
            }
        }

        return null;
    }

    fn handleMove(
        self: *Semantizer,
        inner: syn.SyntaxRef,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (self.nodeTag(inner) != .identifier) {
            const value = try self.visitNode(inner, s);
            if (value.node.content != .struct_field_access and value.node.content != .choice_payload_access and
                value.node.content != .array_index and value.node.content != .dereference)
            {
                try self.diags.add(loc, .semantic, "move requires a stable place", .{});
                return error.Reported;
            }
            const node = try sg.makeSGNode(.{ .move_value = value.node }, loc, self.allocator);
            node.sem_type = value.ty;
            return .{ .node = node, .ty = value.ty };
        }

        const name = self.tokenText(inner, self.syntaxFile(inner).mainToken(inner.node));
        const binding = s.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(binding, self.locationPath(loc)))) {
            try self.addPrivateMemberDiag(loc, "value", name);
            return error.Reported;
        }
        if (self.isSystemType(binding.ty, s)) {
            try self.diags.add(
                loc,
                .semantic,
                "System cannot be moved by value; pass it by '&' or '$&' instead",
                .{},
            );
            return error.Reported;
        }
        if (s.bindingMoveLocation(binding.name)) |move_loc| {
            if (!(move_loc.file == loc.file and move_loc.offset == loc.offset)) {
                try self.diags.add(
                    self.nodeLocation(inner),
                    .semantic,
                    "binding '{s}' was moved and cannot be used again (moved at {s}:{d}:{d})",
                    .{ binding.name, self.locationPath(move_loc), self.locationLineColumn(move_loc).line, self.locationLineColumn(move_loc).column },
                );
                return error.Reported;
            }
        }
        try s.markBindingMoved(binding.name, loc);

        const binding_use = try sg.makeSGNode(.{ .binding_use = binding }, self.nodeLocation(inner), self.allocator);
        const node = try sg.makeSGNode(.{ .move_value = binding_use }, loc, self.allocator);
        node.sem_type = binding.ty;
        return .{ .node = node, .ty = binding.ty };
    }

    fn isSystemType(self: *Semantizer, ty: sg.Type, s: *Scope) bool {
        _ = self;
        const type_name = typ.typeNameFor(s, ty) orelse return false;
        return std.mem.eql(u8, type_name, "System");
    }

    //─────────────────────────────────────────────────────────  CODE BLOCK

    //──────────────────────────────────────────────────── SYMBOL DECLARATION

    //──────────────────────────────────────────────────── TYPE DECLARATION

    //──────────────────────────────────────────────────── FUNCTION DECLARATION

    fn prepareFunctionInputDefaults(
        self: *Semantizer,
        pending: *PendingFunctionBody,
        p: *Scope,
    ) SemErr!void {
        const f = pending.decl;
        const loc = pending.location;
        const fn_ptr = pending.function;
        const syntax_file = self.syntaxFile(pending.top_node);
        const syntax_input_fields = syntax_file.structTypeLiteral(f.input).?.fields;

        const child = try self.allocator.create(Scope);
        child.* = try Scope.init(self.allocator, p, null);
        child.current_fn = fn_ptr;

        const input_struct_ptr = try self.allocator.create(sg.StructType);
        var prepared_input_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        if (!functionHasAnyDefaults(syntax_file, syntax_input_fields)) {
            input_struct_ptr.* = .{ .fields = fn_ptr.input.fields };
            for (syntax_input_fields, 0..) |field_node, idx| {
                const fld = syntax_file.structTypeField(field_node).?;
                const field_name = if (fld.inferred_result) "result" else syntax_file.tokenText(&self.diags.source_db, fld.name_token);
                const bd = try self.allocator.create(sg.BindingDeclaration);
                bd.* = .{
                    .name = field_name,
                    .location = syntax_file.tokenLocation(fld.name_token),
                    .origin_file = self.locationPath(loc),
                    .mutability = .constant,
                    .ty = fn_ptr.input.fields[idx].ty,
                    .initialization = null,
                };
                try child.bindings.put(field_name, bd);
                try prepared_input_bindings.append(bd);
            }
            fn_ptr.input_bindings = try prepared_input_bindings.toOwnedSlice();
            prepared_input_bindings.deinit();
            fn_ptr.input = input_struct_ptr.*;
            pending.prepared_scope = child;
            pending.prepared_input_struct = input_struct_ptr;
            return;
        }

        const input_fields = try self.allocator.alloc(sg.StructTypeField, fn_ptr.input.fields.len);
        @memcpy(input_fields, fn_ptr.input.fields);
        input_struct_ptr.* = .{ .fields = input_fields };

        for (syntax_input_fields, 0..) |field_node, idx| {
            const fld = syntax_file.structTypeField(field_node).?;
            const field_name = if (fld.inferred_result) "result" else syntax_file.tokenText(&self.diags.source_db, fld.name_token);
            const ty = input_struct_ptr.fields[idx].ty;
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(syntax_file.ref(n), child)).node
            else
                null;

            input_fields[idx].default_value = dvp;

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = field_name,
                .location = syntax_file.tokenLocation(fld.name_token),
                .origin_file = self.locationPath(loc),
                .mutability = .constant,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(field_name, bd);
            try prepared_input_bindings.append(bd);
        }

        fn_ptr.input_bindings = try prepared_input_bindings.toOwnedSlice();
        prepared_input_bindings.deinit();
        fn_ptr.input = input_struct_ptr.*;
        pending.prepared_scope = child;
        pending.prepared_input_struct = input_struct_ptr;
    }

    fn prepareRegularFunctionBodyScope(
        self: *Semantizer,
        pending: *PendingFunctionBody,
        p: *Scope,
    ) SemErr!void {
        _ = p;
        const f = pending.decl;
        const fn_ptr = pending.function;
        const syntax_file = self.syntaxFile(pending.top_node);
        const output_fields_syntax = syntax_file.structTypeLiteral(f.output).?.fields;
        const child = pending.prepared_scope orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared input scope during staged semantizing", .{});
            return error.Reported;
        };
        const input_struct_ptr = pending.prepared_input_struct orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared function input during staged semantizing", .{});
            return error.Reported;
        };

        if (!functionHasAnyDefaults(syntax_file, output_fields_syntax)) {
            for (output_fields_syntax, 0..) |field_node, idx| {
                const fld = syntax_file.structTypeField(field_node).?;
                const field_name = if (fld.inferred_result) "result" else syntax_file.tokenText(&self.diags.source_db, fld.name_token);
                const bd = @constCast(fn_ptr.output_bindings[idx]);
                bd.initialization = null;
                try child.bindings.put(field_name, bd);
            }
            fn_ptr.input = input_struct_ptr.*;
            return;
        }

        const output_fields = try self.allocator.alloc(sg.StructTypeField, fn_ptr.output.fields.len);
        @memcpy(output_fields, fn_ptr.output.fields);

        for (output_fields_syntax, 0..) |field_node, idx| {
            const fld = syntax_file.structTypeField(field_node).?;
            const field_name = if (fld.inferred_result) "result" else syntax_file.tokenText(&self.diags.source_db, fld.name_token);
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(syntax_file.ref(n), child)).node
            else
                null;

            output_fields[idx].default_value = dvp;

            const bd = @constCast(fn_ptr.output_bindings[idx]);
            bd.initialization = dvp;
            try child.bindings.put(field_name, bd);
        }

        fn_ptr.output = .{ .fields = output_fields };
        fn_ptr.input = input_struct_ptr.*;
    }

    fn functionHasAnyDefaults(file: *const syn.SyntaxFile, fields: []const syn.NodeIndex) bool {
        for (fields) |field_node| {
            if (file.structTypeField(field_node).?.default_value != null) return true;
        }
        return false;
    }

    fn semantizePreparedFunctionBody(
        self: *Semantizer,
        pending: *PendingFunctionBody,
    ) SemErr!void {
        const child = pending.prepared_scope orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared function scope during staged semantizing", .{});
            return error.Reported;
        };
        const input_struct_ptr = pending.prepared_input_struct orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared function input during staged semantizing", .{});
            return error.Reported;
        };
        const f = pending.decl;
        const loc = pending.location;
        const fn_ptr = pending.function;
        const syntax_file = self.syntaxFile(pending.top_node);
        const function_name = syntax_file.tokenText(&self.diags.source_db, f.name_token);

        var body_cb: ?*sg.CodeBlock = null;
        if (f.body) |body_node| {
            try self.function_reach_stack.append(.{
                .function_name = function_name,
                .location = loc,
                .input_struct = input_struct_ptr,
                .body_scope = child,
            });
            defer _ = self.function_reach_stack.pop();
            const body_te = try self.visitNode(syntax_file.ref(body_node), child);
            body_cb = body_te.node.content.code_block;
        }

        fn_ptr.input = input_struct_ptr.*;
        fn_ptr.body = body_cb;
        self.clearDeferred(child);
    }

    fn appendTypeDeclarationNodeIfMissing(
        self: *Semantizer,
        s: *Scope,
        td: *sg.TypeDeclaration,
        loc: tok.Location,
    ) !*sg.SGNode {
        for (s.nodes.items) |node| {
            if (node.content != .type_declaration) continue;
            if (node.content.type_declaration == td) return node;
        }

        const node = try sg.makeSGNode(.{ .type_declaration = td }, loc, self.allocator);
        try s.nodes.append(node);
        if (s.parent == null) try self.root_list.append(node);
        return node;
    }

    fn appendFunctionDeclarationNodeIfMissing(
        self: *Semantizer,
        s: *Scope,
        fd: *sg.FunctionDeclaration,
        loc: tok.Location,
    ) !void {
        for (s.nodes.items) |node| {
            if (node.content != .function_declaration) continue;
            if (node.content.function_declaration == fd) return;
        }

        const node = try sg.makeSGNode(.{ .function_declaration = fd }, loc, self.allocator);
        try s.nodes.append(node);
        if (s.parent == null) try self.root_list.append(node);
    }

    fn appendBindingDeclarationNodeIfMissing(
        self: *Semantizer,
        s: *Scope,
        bd: *sg.BindingDeclaration,
        loc: tok.Location,
    ) !*sg.SGNode {
        for (s.nodes.items) |node| {
            if (node.content != .binding_declaration) continue;
            if (node.content.binding_declaration == bd) return node;
        }

        const node = try sg.makeSGNode(.{ .binding_declaration = bd }, loc, self.allocator);
        try s.nodes.append(node);
        if (s.parent == null) try self.root_list.append(node);
        return node;
    }

    fn appendTestDeclarationNodeIfMissing(
        self: *Semantizer,
        s: *Scope,
        fd: *sg.FunctionDeclaration,
        loc: tok.Location,
    ) !void {
        for (s.nodes.items) |node| {
            if (node.content != .test_declaration) continue;
            if (node.content.test_declaration.function == fd) return;
        }

        const test_decl = try self.allocator.create(sg.TestDeclaration);
        test_decl.* = .{
            .name = fd.name,
            .location = loc,
            .function = fd,
        };
        const node = try sg.makeSGNode(.{ .test_declaration = test_decl }, loc, self.allocator);
        try s.nodes.append(node);
        if (s.parent == null) try self.root_list.append(node);
    }

    fn compactGenericParamDefs(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        parameter_nodes: []const syn.NodeIndex,
        parameter_struct: ?syn.NodeIndex,
        scope: *Scope,
    ) SemErr!GenericParamSyntaxInfo {
        const file = self.syntaxFile(owner);
        const nodes = if (parameter_struct) |struct_node|
            (file.structTypeLiteral(struct_node) orelse return error.InvalidType).fields
        else
            parameter_nodes;
        const params = try self.allocator.alloc(gen.GenericParam, nodes.len);
        const constraints = try self.allocator.alloc(?gen.AbstractConstraint, nodes.len);
        for (nodes, 0..) |parameter_node, index| {
            constraints[index] = null;
            if (parameter_struct == null) {
                params[index] = .{
                    .name = file.tokenText(&self.diags.source_db, file.mainToken(parameter_node)),
                    .kind = .type,
                };
                continue;
            }
            const field = file.structTypeField(parameter_node) orelse return error.InvalidType;
            const name = file.tokenText(&self.diags.source_db, field.name_token);
            const type_node = field.type_node orelse {
                params[index] = .{ .name = name, .kind = .type };
                continue;
            };
            const syntax_type = file.syntaxType(type_node) orelse return error.InvalidType;
            if (syntax_type == .name) {
                const type_name = file.tokenText(&self.diags.source_db, syntax_type.name.name_token);
                if (std.mem.eql(u8, type_name, "Type")) {
                    params[index] = .{ .name = name, .kind = .type };
                    continue;
                }
                if (scope.lookupAbstractInfo(type_name) != null) {
                    params[index] = .{ .name = name, .kind = .type };
                    constraints[index] = .{ .name = type_name };
                    continue;
                }
            }
            if (syntax_type == .generic) {
                const base = file.syntaxType(syntax_type.generic.base) orelse return error.InvalidType;
                if (base == .name) {
                    const base_name = file.tokenText(&self.diags.source_db, base.name.name_token);
                    if (scope.lookupAbstractInfo(base_name) != null) {
                        params[index] = .{ .name = name, .kind = .type };
                        constraints[index] = .{ .name = base_name, .args = file.ref(syntax_type.generic.arguments) };
                        continue;
                    }
                }
            }
            params[index] = .{
                .name = name,
                .kind = .comptime_int,
                .value_type = try self.resolveTypeExpression(file.ref(type_node), scope),
            };
        }
        return .{ .params = params, .abstract_constraints = constraints };
    }

    fn hasGenericParamNamed(params: []const gen.GenericParam, name: []const u8) bool {
        for (params) |param| {
            if (std.mem.eql(u8, param.name, name)) return true;
        }
        return false;
    }

    fn intValueFitsType(self: *Semantizer, value: i64, ty: sg.Type) bool {
        _ = self;
        return switch (ty) {
            .builtin => |bt| switch (bt) {
                .UIntNative, .UInt8, .UInt16, .UInt32, .UInt64 => value >= 0,
                .Int8, .Int16, .Int32, .Int64 => true,
                else => false,
            },
            else => false,
        };
    }

    fn resolveComptimeIntExpr(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!i64 {
        const file = self.syntaxFile(node);
        const location = self.nodeLocation(node);
        return switch (file.tag(node.node)) {
            .literal => blk: {
                const literal = file.literal(node.node) orelse return error.InvalidType;
                const text = file.tokenText(&self.diags.source_db, literal.token);
                const magnitude = std.fmt.parseInt(i64, text, 0) catch {
                    try self.diags.add(location, .semantic, "expected comptime integer literal", .{});
                    return error.Reported;
                };
                break :blk if (literal.negative) -magnitude else magnitude;
            },
            .identifier => blk: {
                const name = file.tokenText(&self.diags.source_db, file.mainToken(node.node));
                if (subst) |subst_ptr| {
                    if (subst_ptr.ints.get(name)) |value| break :blk value;
                }
                if (s.lookupGenericValue(name)) |binding| {
                    break :blk switch (binding.value) {
                        .comptime_int => |value| value,
                        else => {
                            try self.diags.add(location, .semantic, "generic value '{s}' is not a comptime integer", .{name});
                            return error.Reported;
                        },
                    };
                }
                try self.diags.add(
                    location,
                    .semantic,
                    "unknown comptime integer '{s}'",
                    .{name},
                );
                return error.Reported;
            },
            .binary_add, .binary_subtract, .binary_multiply, .binary_divide, .binary_modulo => blk: {
                const operation = file.binaryOperation(node.node) orelse return error.InvalidType;
                const left = try self.resolveComptimeIntExpr(file.ref(operation.lhs), s, subst);
                const right = try self.resolveComptimeIntExpr(file.ref(operation.rhs), s, subst);
                const operator = file.tokenText(&self.diags.source_db, file.mainToken(node.node));
                if (std.mem.eql(u8, operator, "+")) break :blk left + right;
                if (std.mem.eql(u8, operator, "-")) break :blk left - right;
                if (std.mem.eql(u8, operator, "*")) break :blk left * right;
                if (std.mem.eql(u8, operator, "/")) {
                    if (right == 0) {
                        try self.diags.add(location, .semantic, "division by zero in comptime integer expression", .{});
                        return error.Reported;
                    }
                    break :blk @divTrunc(left, right);
                }
                if (std.mem.eql(u8, operator, "%")) {
                    if (right == 0) {
                        try self.diags.add(location, .semantic, "modulo by zero in comptime integer expression", .{});
                        return error.Reported;
                    }
                    break :blk @mod(left, right);
                }
                return error.InvalidType;
            },
            else => {
                try self.diags.add(
                    location,
                    .semantic,
                    "expected comptime integer expression",
                    .{},
                );
                return error.Reported;
            },
        };
    }

    fn resolveTypeExpressionWithSubst(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(node);
        if (file.syntaxType(node.node) != null) return self.resolveSyntaxTypeWithSubstPreservingAbstracts(node, s, subst);
        return switch (file.tag(node.node)) {
            .identifier => blk: {
                const name = file.tokenText(&self.diags.source_db, file.mainToken(node.node));
                if (subst.types.get(name)) |mapped| break :blk mapped;
                break :blk self.resolveSyntaxTypeName(node, file.mainToken(node.node), null, s, false) catch {
                    try self.diags.add(
                        self.nodeLocation(node),
                        .semantic,
                        "unknown type '{s}'",
                        .{name},
                    );
                    return error.Reported;
                };
            },
            .function_call => {
                try self.diags.add(
                    self.nodeLocation(node),
                    .semantic,
                    "unsupported expression in type generic argument",
                    .{},
                );
                return error.Reported;
            },
            else => {
                try self.diags.add(
                    self.nodeLocation(node),
                    .semantic,
                    "expected type expression",
                    .{},
                );
                return error.Reported;
            },
        };
    }

    fn makeArrayType(self: *Semantizer, length: usize, element_ty: sg.Type) !sg.Type {
        const elem_ptr = try self.allocator.create(sg.Type);
        elem_ptr.* = element_ty;

        const arg_names = try self.allocator.alloc([]const u8, 2);
        arg_names[0] = "n";
        arg_names[1] = "t";

        const arg_values = try self.allocator.alloc(sg.GenericIdentityArg, 2);
        arg_values[0] = .{ .comptime_int = @intCast(length) };
        arg_values[1] = .{ .type = element_ty };

        const identity = try self.allocator.create(sg.GenericTypeIdentity);
        identity.* = .{
            .base_name = "Array",
            .arg_names = arg_names,
            .arg_values = arg_values,
        };

        const sem_arr = try self.allocator.create(sg.ArrayType);
        sem_arr.* = .{
            .length = length,
            .element_type = elem_ptr,
            .identity = .{ .generic = identity },
        };
        return .{ .array_type = sem_arr };
    }

    fn resolveExplicitGenericArg(
        self: *Semantizer,
        field_node: syn.SyntaxRef,
        param: gen.GenericParam,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!gen.GenericArgValue {
        const file = self.syntaxFile(field_node);
        const field = file.structTypeField(field_node.node) orelse return error.InvalidType;
        const field_location = file.tokenLocation(field.name_token);
        return switch (param.kind) {
            .type => blk: {
                if (field.type_node) |type_node| {
                    break :blk .{ .type = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(type_node), s, subst) };
                }
                if (field.default_value) |type_expr| {
                    break :blk .{ .type = try self.resolveTypeExpressionWithSubst(file.ref(type_expr), s, subst) };
                }
                try self.diags.add(
                    field_location,
                    .semantic,
                    "generic parameter '.{s}' expects a type argument",
                    .{param.name},
                );
                return error.Reported;
            },
            .comptime_int => blk: {
                const value_node = field.default_value orelse {
                    try self.diags.add(
                        field_location,
                        .semantic,
                        "generic parameter '.{s}' expects a comptime integer expression",
                        .{param.name},
                    );
                    return error.Reported;
                };
                const value = try self.resolveComptimeIntExpr(file.ref(value_node), s, subst);
                if (param.value_type) |value_ty| {
                    if (!self.intValueFitsType(value, value_ty)) {
                        try self.diags.add(
                            file.location(value_node),
                            .semantic,
                            "generic integer argument '.{s}' does not fit expected type",
                            .{param.name},
                        );
                        return error.Reported;
                    }
                }
                break :blk .{ .comptime_int = value };
            },
        };
    }

    fn putGenericArg(self: *Semantizer, subst: *GenericSubst, param: gen.GenericParam, value: gen.GenericArgValue) !void {
        _ = self;
        switch (param.kind) {
            .type => try subst.types.put(param.name, value.type),
            .comptime_int => try subst.ints.put(param.name, value.comptime_int),
        }
    }

    fn compactAbstractConstraintForType(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        type_node: syn.NodeIndex,
        scope: *Scope,
    ) ?gen.AbstractConstraint {
        const file = self.syntaxFile(owner);
        const syntax_type = file.syntaxType(type_node) orelse return null;
        const abstract_type_node = switch (syntax_type) {
            .pointer => |pointer| pointer.child,
            else => type_node,
        };
        return switch (file.syntaxType(abstract_type_node) orelse return null) {
            .name => |name| blk: {
                if (name.qualifier_token != null) break :blk null;
                const text = file.tokenText(&self.diags.source_db, name.name_token);
                if (scope.lookupAbstractInfo(text) == null) break :blk null;
                break :blk .{ .name = text };
            },
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse break :blk null;
                if (base != .name or base.name.qualifier_token != null) break :blk null;
                const text = file.tokenText(&self.diags.source_db, base.name.name_token);
                if (scope.lookupAbstractInfo(text) == null) break :blk null;
                break :blk .{ .name = text, .args = file.ref(generic.arguments) };
            },
            else => null,
        };
    }

    fn compactOutputUsesUnboundAbstract(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        type_node: syn.NodeIndex,
        bound_abstracts: []const gen.GenericParam,
        scope: *Scope,
    ) bool {
        const file = self.syntaxFile(owner);
        return switch (file.syntaxType(type_node) orelse return false) {
            .name => |name| blk: {
                const text = file.tokenText(&self.diags.source_db, name.name_token);
                if (scope.lookupAbstractInfo(text) == null or scope.lookupAbstractDefault(text) != null) break :blk false;
                for (bound_abstracts) |bound| if (std.mem.eql(u8, bound.name, text)) break :blk false;
                break :blk true;
            },
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse break :blk false;
                if (base == .name) {
                    const text = file.tokenText(&self.diags.source_db, base.name.name_token);
                    if (scope.lookupAbstractInfo(text) != null and scope.lookupAbstractDefault(text) == null) {
                        for (bound_abstracts) |bound| if (std.mem.eql(u8, bound.name, text)) break :blk false;
                        break :blk true;
                    }
                }
                const arguments = file.structTypeLiteral(generic.arguments) orelse break :blk false;
                for (arguments.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse break :blk false;
                    if (field.type_node) |field_type| {
                        if (self.compactOutputUsesUnboundAbstract(owner, field_type, bound_abstracts, scope)) break :blk true;
                    }
                }
                break :blk false;
            },
            .pointer => |pointer| self.compactOutputUsesUnboundAbstract(owner, pointer.child, bound_abstracts, scope),
            .array => |array| self.compactOutputUsesUnboundAbstract(owner, array.element, bound_abstracts, scope),
            .inferred_errable => |inner| self.compactOutputUsesUnboundAbstract(owner, inner, bound_abstracts, scope),
            .struct_literal => |literal| blk: {
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse break :blk false;
                    if (field.type_node) |field_type| {
                        if (self.compactOutputUsesUnboundAbstract(owner, field_type, bound_abstracts, scope)) break :blk true;
                    }
                }
                break :blk false;
            },
            .choice_literal => |literal| blk: {
                for (literal.variants) |variant_node| {
                    const variant = file.choiceTypeVariant(variant_node) orelse break :blk false;
                    if (variant.payload_type) |payload| {
                        if (self.compactOutputUsesUnboundAbstract(owner, payload, bound_abstracts, scope)) break :blk true;
                    }
                }
                break :blk false;
            },
            .nullable => |inner| self.compactOutputUsesUnboundAbstract(owner, inner, bound_abstracts, scope),
        };
    }

    fn registerAbstractContractTemplateIfNeeded(
        self: *Semantizer,
        node: syn.SyntaxRef,
        scope: *Scope,
        loc: tok.Location,
    ) SemErr!bool {
        const file = self.syntaxFile(node);
        const function = file.functionDeclaration(node.node) orelse return error.InvalidType;
        if (function.generic_params.len != 0 or function.generic_params_struct != null) return false;

        const input = file.structTypeLiteral(function.input) orelse return error.InvalidType;
        var params = std.array_list.Managed(gen.GenericParam).init(self.allocator.*);
        defer params.deinit();
        var constraints = std.array_list.Managed(?gen.AbstractConstraint).init(self.allocator.*);
        defer constraints.deinit();

        for (input.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const type_node = field.type_node orelse continue;
            const constraint = self.compactAbstractConstraintForType(node, type_node, scope) orelse continue;
            // Keeping the abstract spelling as the parameter name lets the
            // compact type resolver substitute it without materializing a
            // rewritten AST. Repeated occurrences intentionally share the
            // same contract parameter, just as repeated generic names do.
            if (hasGenericParamNamed(params.items, constraint.name)) continue;
            try params.append(.{ .name = constraint.name, .kind = .type, .value_type = null });
            try constraints.append(constraint);
        }
        if (params.items.len == 0) return false;

        const output = file.structTypeLiteral(function.output) orelse return error.InvalidType;
        for (output.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const type_node = field.type_node orelse continue;
            if (self.compactOutputUsesUnboundAbstract(node, type_node, params.items, scope)) return error.AbstractNeedsDefault;
        }

        try scope.appendGenericFunctionTemplate(file.tokenText(&self.diags.source_db, function.name_token), .{
            .syntax_files = self.syntax_files,
            .source_db = &self.diags.source_db,
            .syntax_file_id = node.file_id,
            .name = file.tokenText(&self.diags.source_db, function.name_token),
            .location = loc,
            .params = try params.toOwnedSlice(),
            .param_abstract_constraints = try constraints.toOwnedSlice(),
            .dispatch_kind = .abstract_contract,
            .input = function.input,
            .output = function.output,
            .body = if (function.body) |body| file.ref(body) else null,
        });
        return true;
    }

    //──────────────────────────────────────────────────── ASSIGNMENT

    //──────────────────────────────────────────────────── STRUCT VALUE LITERAL

    //──────────────────────────────────────────────────── STRUCT FIELD ACCESS

    fn handleChoicePayloadAccess(self: *Semantizer, node_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const access_view = file.choicePayloadAccess(node_ref.node) orelse return error.InvalidType;
        const value_ref = file.ref(access_view.value);
        const variant_name = file.tokenText(&self.diags.source_db, access_view.variant_token);
        const variant_location = file.tokenLocation(access_view.variant_token);
        if (file.tag(access_view.value) == .identifier) {
            const base_name = file.tokenText(&self.diags.source_db, file.mainToken(access_view.value));
            if (s.lookupModuleAlias(base_name) != null) {
                const literal = try self.allocator.create(sg.ChoiceLiteral);
                literal.* = .{ .variant_name = variant_name, .module_qualifier = base_name, .choice_type = undefined, .variant_index = 0, .payload = null };
                const result = try sg.makeSGNode(.{ .choice_literal = literal }, variant_location, self.allocator);
                return .{ .node = result, .ty = .{ .builtin = .Any } };
            }
        }
        const base = if (file.tag(access_view.value) == .identifier) blk: {
            const binding_name = file.tokenText(&self.diags.source_db, file.mainToken(access_view.value));
            if (s.lookupBinding(binding_name)) |binding| {
                const node = try sg.makeSGNode(.{ .binding_use = binding }, file.location(access_view.value), self.allocator);
                node.sem_type = binding.ty;
                break :blk typ.TypedExpr{ .node = node, .ty = binding.ty };
            }
            break :blk try self.visitNode(value_ref, s);
        } else try self.visitNode(value_ref, s);
        if (base.ty != .choice_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                file.location(access_view.value),
                .semantic,
                "cannot access choice payload '..{s}' on value of type '{s}'",
                .{ variant_name, desc.bytes },
            );
            return error.Reported;
        }

        const choice_ty = base.ty.choice_type;
        for (choice_ty.variants, 0..) |variant, idx| {
            if (!std.mem.eql(u8, variant.name, variant_name)) continue;
            const payload_ty = variant.payload_type orelse {
                try self.diags.add(
                    variant_location,
                    .semantic,
                    "choice variant '..{s}' has no payload",
                    .{variant_name},
                );
                return error.Reported;
            };

            const access = try self.allocator.create(sg.ChoicePayloadAccess);
            access.* = .{
                .choice_value = base.node,
                .variant_index = @intCast(idx),
                .payload_type = payload_ty,
            };
            const node = try sg.makeSGNode(.{ .choice_payload_access = access }, variant_location, self.allocator);
            return .{ .node = node, .ty = payload_ty };
        }

        const choice_text = try self.formatTypeText(.{ .choice_type = choice_ty }, s);
        defer choice_text.deinit();
        try self.diags.add(
            variant_location,
            .semantic,
            "choice type '{s}' has no variant '..{s}'",
            .{ choice_text.bytes, variant_name },
        );
        return error.Reported;
    }

    fn handleModuleFieldAccess(
        self: *Semantizer,
        module_dir: []const u8,
        field_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const binding = s.lookupBindingInModule(module_dir, field_name) orelse {
            const module_name = if (std.mem.lastIndexOfScalar(u8, module_dir, '/')) |idx|
                module_dir[idx + 1 ..]
            else
                module_dir;
            try self.diags.add(
                loc,
                .semantic,
                "module '{s}' has no value '.{s}'",
                .{ module_name, field_name },
            );
            return error.Reported;
        };
        if (!(try self.bindingIsVisible(binding, self.locationPath(loc)))) {
            try self.addPrivateMemberDiag(loc, "value", field_name);
            return error.Reported;
        }

        const n = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
        return .{ .node = n, .ty = binding.ty };
    }

    //──────────────────────────────────────────────────── LIST LITERAL
    fn handleListLiteral(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const ll = file.listLiteral(syntax_ref.node) orelse return error.InvalidType;

        var elems = std.array_list.Managed(*sg.SGNode).init(self.allocator.*);
        var elem_types = std.array_list.Managed(sg.Type).init(self.allocator.*);
        defer {
            elems.deinit();
            elem_types.deinit();
        }

        for (ll.elements) |elem_node| {
            const elem_te = try self.visitNode(file.ref(elem_node), s);

            try elems.append(elem_te.node);
            try elem_types.append(elem_te.ty);
        }

        const elements_slice = try elems.toOwnedSlice();
        const elem_types_slice = try elem_types.toOwnedSlice();

        const lit_ptr = try self.allocator.create(sg.ListLiteral);
        lit_ptr.* = .{
            .elements = elements_slice,
            .element_types = elem_types_slice,
        };

        const node = try sg.makeSGNode(.{ .list_literal = lit_ptr }, self.nodeLocation(syntax_ref), self.allocator);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    fn handleIndexAccess(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const ia = file.indexAccess(syntax_ref.node) orelse return error.InvalidType;
        const base = try self.visitNode(file.ref(ia.value), s);
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };

        if (base.ty == .array_type) {
            var idx_te = try self.visitNode(file.ref(ia.index), s);
            idx_te = try typ.coerceExprToType(native_uint_ty, idx_te, file.location(ia.index), s, self.allocator, self.diags);
            if (!typ.typesExactlyEqual(idx_te.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(idx_te.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    file.location(ia.index),
                    .semantic,
                    "array index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            const arr_type_ptr = base.ty.array_type;
            const elem_ty = arr_type_ptr.*.element_type.*;
            const ro_self = try typ.ensureReadOnlyPointer(file.location(ia.value), base, self.allocator, self.diags);

            const node = try sg.makeSGNode(.{ .array_index = .{
                .array_ptr = ro_self.node,
                .index = idx_te.node,
                .element_type = elem_ty,
                .array_type = arr_type_ptr,
            } }, undefined, self.allocator);
            return .{ .node = node, .ty = elem_ty };
        }

        if (base.node.content == .list_literal) {
            const ll = base.node.content.list_literal;
            var idx_te = try self.visitNode(file.ref(ia.index), s);
            idx_te = try typ.coerceExprToType(native_uint_ty, idx_te, file.location(ia.index), s, self.allocator, self.diags);

            if (!typ.typesExactlyEqual(idx_te.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(idx_te.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    file.location(ia.index),
                    .semantic,
                    "list literal index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            if (idx_te.node.content != .value_literal) {
                try self.diags.add(
                    file.location(ia.index),
                    .semantic,
                    "index into a list literal must be a 'UIntNative' integer literal",
                    .{},
                );
                return error.Reported;
            }

            const lit = idx_te.node.content.value_literal;
            const raw_index: i64 = switch (lit) {
                .int_literal => |v| v,
                else => blk: {
                    try self.diags.add(
                        file.location(ia.index),
                        .semantic,
                        "index into a list literal must be a 'UIntNative' integer literal",
                        .{},
                    );
                    break :blk 0;
                },
            };

            if (raw_index < 0 or raw_index >= ll.elements.len) {
                try self.diags.add(
                    file.location(ia.index),
                    .semantic,
                    "list literal index {d} out of bounds (length {d})",
                    .{ raw_index, ll.elements.len },
                );
                return error.Reported;
            }

            const ui: usize = @intCast(raw_index);
            const elem_node = ll.elements[ui];
            const elem_ty = ll.element_types[ui];
            return .{ .node = @constCast(elem_node), .ty = elem_ty };
        }

        const ro_self = try typ.ensureReadOnlyPointer(file.location(ia.value), base, self.allocator, self.diags);
        return self.lowerIndexedOperatorCall(
            "operator get[]",
            ro_self,
            file.ref(ia.index),
            file.location(ia.value),
            s,
        );
    }

    fn lowerIndexedOperatorCall(
        self: *Semantizer,
        name: []const u8,
        self_expr: typ.TypedExpr,
        index_node: syn.SyntaxRef,
        call_loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const empty_args: ?syn.SyntaxRef = null;
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };
        var idx = try self.visitNode(index_node, s);
        var input_te = try self.buildCallInput(&[_]CallArg{
            .{ .name = "self", .expr = self_expr },
            .{ .name = "index", .expr = idx },
        });

        var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
            error.SymbolNotFound => null,
            else => return err,
        };

        if (chosen == null) {
            chosen = self.resolveVisibleOverload(name, input_te, s, call_loc) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.AmbiguousOverload => {
                    try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, call_loc);
                    return error.Reported;
                },
                else => return err,
            };
        }

        if (chosen == null and !typ.typesExactlyEqual(idx.ty, native_uint_ty)) {
            idx = try typ.coerceExprToType(native_uint_ty, idx, self.nodeLocation(index_node), s, self.allocator, self.diags);
            input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "self", .expr = self_expr },
                .{ .name = "index", .expr = idx },
            });

            chosen = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, call_loc) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, call_loc);
                        return error.Reported;
                    },
                    else => return err,
                };
            }
        }

        const chosen_fn = chosen orelse {
            try self.addMissingFunctionDiagnostic(name, input_te.ty, s, call_loc);
            return error.Reported;
        };
        try self.discoverFunctionReference(chosen_fn);
        input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, self.nodeLocation(index_node), s);

        const call_ptr = try self.allocator.create(sg.FunctionCall);
        call_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, call_loc, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = typ.functionReturnType(chosen_fn) };
    }

    fn handleBorrowedIndexAccess(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        mutability: syn.PointerMutability,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const ia = file.indexAccess(syntax_ref.node) orelse return error.InvalidType;
        const base = try self.visitNode(file.ref(ia.value), s);

        const operator_name = switch (mutability) {
            .read_only => "operator get_ro_pointer[]",
            .read_write => "operator get_rw_pointer[]",
        };

        const self_expr = switch (mutability) {
            .read_only => try typ.ensureReadOnlyPointer(file.location(ia.value), base, self.allocator, self.diags),
            .read_write => try typ.ensureMutablePointer(file.location(ia.value), base, s, self.allocator, self.diags),
        };

        return self.lowerIndexedOperatorCall(
            operator_name,
            self_expr,
            file.ref(ia.index),
            file.location(ia.value),
            s,
        );
    }

    fn handleIndexAssignment(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const ia = file.indexAssignment(syntax_ref.node) orelse return error.InvalidType;
        const idx = file.indexAccess(ia.target) orelse return error.InvalidType;
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };

        const base = try self.visitNode(file.ref(idx.value), s);

        if (base.ty == .array_type) {
            var index_expr = try self.visitNode(file.ref(idx.index), s);
            index_expr = try typ.coerceExprToType(native_uint_ty, index_expr, file.location(idx.index), s, self.allocator, self.diags);
            if (!typ.typesExactlyEqual(index_expr.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(index_expr.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    file.location(idx.index),
                    .semantic,
                    "array index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            const value_expr = try self.visitNode(file.ref(ia.value), s);
            const arr_type_ptr = base.ty.array_type;
            const elem_ty = arr_type_ptr.*.element_type.*;

            if (!typ.typesStructurallyEqual(elem_ty, value_expr.ty)) {
                const pair = try self.formatTypePairText(elem_ty, value_expr.ty, s);
                defer pair.deinit();
                try self.diags.add(
                    file.location(ia.value),
                    .semantic,
                    "cannot assign value of type '{s}' to array element of type '{s}'",
                    .{ pair.actual.bytes, pair.expected.bytes },
                );
                return error.Reported;
            }

            const ptr_self = try typ.ensureMutablePointer(file.location(idx.value), base, s, self.allocator, self.diags);

            const node = try sg.makeSGNode(.{ .array_store = .{
                .array_ptr = ptr_self.node,
                .index = index_expr.node,
                .value = value_expr.node,
                .element_type = elem_ty,
                .array_type = arr_type_ptr,
            } }, undefined, self.allocator);
            try s.nodes.append(node);
            return .{ .node = node, .ty = .{ .builtin = .Any } };
        }

        var index_expr = try self.visitNode(file.ref(idx.index), s);
        const value_expr = try self.visitNode(file.ref(ia.value), s);

        const ptr_self = try typ.ensureMutablePointer(file.location(idx.value), base, s, self.allocator, self.diags);

        const name = "operator set[]";
        const empty_args: ?syn.SyntaxRef = null;
        var input_te = try self.buildCallInput(&[_]CallArg{
            .{ .name = "self", .expr = ptr_self },
            .{ .name = "index", .expr = index_expr },
            .{ .name = "value", .expr = value_expr },
        });

        var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
            error.SymbolNotFound => null,
            else => return err,
        };

        if (chosen == null) {
            chosen = self.resolveVisibleOverload(name, input_te, s, file.location(ia.target)) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.AmbiguousOverload => {
                    try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, file.location(ia.target));
                    return error.Reported;
                },
                else => return err,
            };
        }

        if (chosen == null and !typ.typesExactlyEqual(index_expr.ty, native_uint_ty)) {
            index_expr = try typ.coerceExprToType(native_uint_ty, index_expr, file.location(idx.index), s, self.allocator, self.diags);
            input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "self", .expr = ptr_self },
                .{ .name = "index", .expr = index_expr },
                .{ .name = "value", .expr = value_expr },
            });

            chosen = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, file.location(ia.target)) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, file.location(ia.target));
                        return error.Reported;
                    },
                    else => return err,
                };
            }
        }

        const chosen_fn = chosen orelse {
            try self.addMissingFunctionDiagnostic(name, input_te.ty, s, file.location(ia.target));
            return error.Reported;
        };
        try self.discoverFunctionReference(chosen_fn);
        input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, file.location(ia.target), s);

        const call_ptr = try self.allocator.create(sg.FunctionCall);
        call_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, file.location(ia.target), self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    //────────────────────────────────────────────────────  AUX STRUCT TYPES

    fn structTypeFromNodeWithSubst(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!*sg.StructType {
        const file = self.syntaxFile(node);
        const literal = file.structTypeLiteral(node.node) orelse return error.InvalidType;
        var fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer fields.deinit();
        for (literal.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const type_node = field.type_node orelse continue;
            const field_type = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(type_node), s, subst);
            const default_value = if (field.default_value) |default_node|
                (try self.visitNode(file.ref(default_node), s)).node
            else
                null;
            try fields.append(.{
                .name = if (field.inferred_result) "result" else file.tokenText(&self.diags.source_db, field.name_token),
                .ty = field_type,
                .default_value = default_value,
            });
        }
        const result = try self.allocator.create(sg.StructType);
        result.* = .{ .fields = try fields.toOwnedSlice() };
        return result;
    }

    fn structTypeFromNode(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!*sg.StructType {
        var subst = GenericSubst.init(self.allocator);
        defer subst.deinit();
        return self.structTypeFromNodeWithSubst(node, s, &subst);
    }

    fn choiceTypeFromNode(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!*sg.ChoiceType {
        var subst = GenericSubst.init(self.allocator);
        defer subst.deinit();
        return self.choiceTypeFromNodeWithSubst(node, s, &subst);
    }

    fn choiceTypeFromNodeWithSubst(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!*sg.ChoiceType {
        const file = self.syntaxFile(node);
        const literal = file.choiceTypeLiteral(node.node) orelse return error.InvalidType;
        var variants = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
        defer variants.deinit();
        for (literal.variants, 0..) |variant_node, index| {
            const variant = file.choiceTypeVariant(variant_node) orelse return error.InvalidType;
            const name = file.tokenText(&self.diags.source_db, variant.name_token);
            const payload_type = if (variant.payload_type) |payload|
                try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(payload), s, subst)
            else
                null;
            const option_decl = if (payload_type == null)
                self.resolveChoiceOptionReference(
                    if (variant.module_qualifier) |qualifier| file.tokenText(&self.diags.source_db, qualifier) else null,
                    name,
                    file.tokenLocation(variant.name_token),
                    s,
                ) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    else => return err,
                }
            else
                null;
            try variants.append(.{
                .name = name,
                .value = if (option_decl) |declaration| @intCast(declaration.id) else @intCast(index),
                .payload_type = payload_type,
                .option_decl = option_decl,
            });
        }
        const result = try self.allocator.create(sg.ChoiceType);
        result.* = .{ .variants = try variants.toOwnedSlice() };
        return result;
    }

    fn structTypeSignatureFromNode(
        self: *Semantizer,
        node: syn.SyntaxRef,
        scope: *Scope,
        infer_errable_reasons: bool,
    ) SemErr!*sg.StructType {
        const file = self.syntaxFile(node);
        const literal = file.structTypeLiteral(node.node) orelse return error.InvalidType;
        var fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer fields.deinit();
        for (literal.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const type_node = field.type_node orelse return error.InvalidType;
            const field_type = if (infer_errable_reasons)
                if (self.compactInferableErrableInnerType(file.ref(type_node))) |inner|
                    try self.makeCompactInferredErrableType(inner, scope, null)
                else
                    try self.resolveSyntaxTypeWithMode(file.ref(type_node), scope, true, null)
            else
                try self.resolveSyntaxTypeWithMode(file.ref(type_node), scope, true, null);
            const field_name = if (field.inferred_result) "result" else file.tokenText(&self.diags.source_db, field.name_token);
            const field_location = file.tokenLocation(field.name_token);
            const default_value = if (field.default_value != null) try self.makeNoopNode(field_location) else null;
            try fields.append(.{ .name = field_name, .ty = field_type, .default_value = default_value });
            const binding = try self.allocator.create(sg.BindingDeclaration);
            binding.* = .{
                .name = field_name,
                .location = field_location,
                .origin_file = self.locationPath(field_location),
                .mutability = .constant,
                .ty = field_type,
                .initialization = null,
            };
            try scope.bindings.put(field_name, binding);
        }
        const result = try self.allocator.create(sg.StructType);
        result.* = .{ .fields = try fields.toOwnedSlice() };
        return result;
    }

    fn compactInferableErrableInnerType(self: *Semantizer, node: syn.SyntaxRef) ?syn.SyntaxRef {
        const file = self.syntaxFile(node);
        return switch (file.syntaxType(node.node) orelse return null) {
            .inferred_errable => |inner| file.ref(inner),
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse break :blk null;
                if (base != .name or base.name.qualifier_token != null) break :blk null;
                if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, base.name.name_token), "Errable")) break :blk null;
                const arguments = file.structTypeLiteral(generic.arguments) orelse break :blk null;
                var value: ?syn.SyntaxRef = null;
                for (arguments.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse break :blk null;
                    const name = file.tokenText(&self.diags.source_db, field.name_token);
                    if (std.mem.eql(u8, name, "reasons")) break :blk null;
                    if (std.mem.eql(u8, name, "t")) value = file.ref(field.type_node orelse break :blk null);
                }
                break :blk value;
            },
            else => null,
        };
    }

    fn compactSignatureUsesInferredErrable(self: *Semantizer, node: syn.SyntaxRef) bool {
        const file = self.syntaxFile(node);
        const literal = file.structTypeLiteral(node.node) orelse return false;
        for (literal.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse continue;
            const type_node = field.type_node orelse continue;
            if (self.compactInferableErrableInnerType(file.ref(type_node)) != null) return true;
        }
        return false;
    }

    //──────────────────────────────────────────────────── FUNCTION CALL
    fn handleToVirtual(self: *Semantizer, node_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const call = file.functionCall(node_ref.node) orelse return error.InvalidType;
        const location = file.tokenLocation(call.callee_token);
        const type_args = call.type_arguments_struct orelse {
            try self.diags.add(location, .semantic, "to_virtual requires '#(.abstract: <Abstract>)'", .{});
            return error.Reported;
        };
        const virtual_type = try self.resolveCompactVirtualTypeFromGenericArgs(location, file.ref(type_args), s);
        if (virtual_type != .struct_type) return error.InvalidType;
        const identity = virtual_type.struct_type.identity orelse return error.InvalidType;
        const abstract_type = switch (identity) {
            .generic => |generic| switch (generic.arg_values[0]) {
                .type => |abstract_sem_type| if (abstract_sem_type == .abstract_type)
                    abstract_sem_type.abstract_type
                else
                    return error.InvalidType,
                else => return error.InvalidType,
            },
            else => return error.InvalidType,
        };
        const input = file.structValueLiteral(call.input) orelse return error.InvalidType;
        if (input.fields.len != 1) return error.InvalidType;
        const field = file.valueField(input.fields[0]) orelse return error.InvalidType;
        if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token orelse return error.InvalidType), "value")) return error.InvalidType;
        const value = try self.visitNode(file.ref(field.value), s);
        if (value.ty != .pointer_type) {
            try self.diags.add(file.location(field.value), .semantic, "to_virtual '.value' must be a reference", .{});
            return error.Reported;
        }
        const concrete_type = value.ty.pointer_type.child.*;
        if (!try self.typeImplementsAbstract(concrete_type, abstract_type.name, s)) {
            const concrete_text = try self.formatTypeText(concrete_type, s);
            defer concrete_text.deinit();
            try self.diags.add(file.location(field.value), .semantic, "type '{s}' does not implement Abstract '{s}'", .{ concrete_text.bytes, abstract_type.name });
            return error.Reported;
        }
        const abstract_info = s.lookupAbstractInfo(abstract_type.name) orelse return error.SymbolNotFound;
        const methods = try self.allocator.alloc(*const sg.FunctionDeclaration, abstract_info.requirements.len);
        for (abstract_info.requirements, 0..) |*requirement, index| {
            const expected_input = try abs.buildExpectedInputWithConcrete(requirement, concrete_type, self.allocator);
            methods[index] = abs.resolveOverload(requirement.name, .{ .struct_type = expected_input }, s) catch |err| switch (err) {
                error.SymbolNotFound, error.AmbiguousOverload => {
                    try self.diags.add(location, .semantic, "cannot build Virtual vtable for '{s}': requirement '{s}' has no unique concrete implementation", .{ abstract_type.name, requirement.name });
                    return error.Reported;
                },
                else => return err,
            };
            var known = false;
            for (abstract_info.virtual_methods[index].implementations.items) |implementation| {
                if (implementation == methods[index]) {
                    known = true;
                    break;
                }
            }
            if (!known) try abstract_info.virtual_methods[index].implementations.append(methods[index]);
        }
        try self.registerKnownVirtualImplementations(abstract_info, s);
        for (abstract_info.virtual_methods) |registry| {
            for (registry.implementations.items) |implementation| {
                try self.discoverFunctionReference(implementation);
            }
        }
        const virtualize = try self.allocator.create(sg.Virtualize);
        virtualize.* = .{
            .value = value.node,
            .concrete_type = concrete_type,
            .abstract_type = abstract_type,
            .virtual_type = virtual_type.struct_type,
            .methods = methods,
            .safety_methods = abstract_info.virtual_methods,
            .location = location,
        };
        const node = try sg.makeSGNode(.{ .virtualize = virtualize }, location, self.allocator);
        node.sem_type = virtual_type;
        return .{ .node = node, .ty = virtual_type };
    }

    fn registerKnownVirtualImplementations(
        self: *Semantizer,
        abstract_info: *abs.AbstractInfo,
        s: *Scope,
    ) SemErr!void {
        var current: ?*Scope = s;
        while (current) |scope| : (current = scope.parent) {
            const entries = scope.abstract_impls.get(abstract_info.name) orelse continue;
            for (entries.items) |entry| {
                for (abstract_info.requirements, 0..) |*requirement, method_index| {
                    const expected_input = try abs.buildExpectedInputWithConcrete(requirement, entry.ty, self.allocator);
                    const implementation = abs.resolveOverload(requirement.name, .{ .struct_type = expected_input }, s) catch |err| switch (err) {
                        error.SymbolNotFound, error.AmbiguousOverload => continue,
                        else => return err,
                    };
                    var known = false;
                    for (abstract_info.virtual_methods[method_index].implementations.items) |candidate| {
                        if (candidate == implementation) {
                            known = true;
                            break;
                        }
                    }
                    if (!known) try abstract_info.virtual_methods[method_index].implementations.append(implementation);
                }
            }
        }
    }

    fn virtualAbstractType(ty: sg.Type) ?*const sg.AbstractType {
        const value_type = if (ty == .pointer_type) ty.pointer_type.child.* else ty;
        if (value_type != .struct_type) return null;
        const identity = value_type.struct_type.identity orelse return null;
        const generic = switch (identity) {
            .generic => |value| value,
            else => return null,
        };
        if (!std.mem.eql(u8, generic.base_name, "Virtual") or generic.arg_values.len != 1) return null;
        return switch (generic.arg_values[0]) {
            .type => |abstract_type| if (abstract_type == .abstract_type) abstract_type.abstract_type else null,
            else => null,
        };
    }

    fn containsU32Index(indices: []const u32, index: usize) bool {
        for (indices) |candidate| if (candidate == index) return true;
        return false;
    }

    fn tryHandleVirtualCall(self: *Semantizer, node_ref: syn.SyntaxRef, input: typ.TypedExpr, s: *Scope) SemErr!?typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const call = file.functionCall(node_ref.node) orelse return error.InvalidType;
        const callee = file.tokenText(&self.diags.source_db, call.callee_token);
        const location = file.tokenLocation(call.callee_token);
        if (call.module_qualifier != null or call.type_arguments.len != 0 or call.type_arguments_struct != null) return null;
        if (input.ty != .struct_type or input.node.content != .struct_value_literal) return null;
        const input_type = input.ty.struct_type;
        for (input_type.fields, 0..) |actual_field, self_index| {
            const abstract_type = virtualAbstractType(actual_field.ty) orelse continue;
            if (actual_field.ty != .pointer_type) continue;
            const info = s.lookupAbstractInfo(abstract_type.name) orelse return error.SymbolNotFound;
            for (info.requirements, 0..) |*requirement, method_index| {
                if (!std.mem.eql(u8, requirement.name, callee)) continue;
                if (!containsU32Index(requirement.input_pointer_self_indices, self_index)) continue;
                if (requirement.input_self_indices.len != 0 or requirement.output_self_indices.len != 0 or requirement.output_pointer_self_indices.len != 0) {
                    try self.diags.add(location, .semantic, "Abstract method '{s}' is not virtual-safe because Self escapes by value or output", .{callee});
                    return error.Reported;
                }
                if (requirement.input.fields.len != input_type.fields.len) continue;
                var compatible = true;
                for (requirement.input.fields, 0..) |expected_field, field_index| {
                    if (!std.mem.eql(u8, expected_field.name, input_type.fields[field_index].name)) {
                        compatible = false;
                        break;
                    }
                    if (field_index == self_index) {
                        if (expected_field.ty != .pointer_type or !typ.pointerMutabilityCompatible(expected_field.ty.pointer_type.mutability, actual_field.ty.pointer_type.mutability)) {
                            compatible = false;
                            break;
                        }
                    }
                }
                if (!compatible) continue;
                const coerced_input = try self.coerceCallInputToExpected(&requirement.input, input, file.location(call.input), s);
                for (info.virtual_methods[method_index].implementations.items) |implementation| {
                    try self.discoverFunctionReference(implementation);
                }
                if (coerced_input.node.content != .struct_value_literal) return error.InvalidType;
                const coerced_value = coerced_input.node.content.struct_value_literal;
                const virtual_call = try self.allocator.create(sg.VirtualCall);
                virtual_call.* = .{
                    .handle = coerced_value.fields[self_index].value,
                    .input = coerced_input.node,
                    .self_input_index = @intCast(self_index),
                    .method_index = @intCast(method_index),
                    .method_count = @intCast(info.requirements.len),
                    .method_name = requirement.name,
                    .input_type = &requirement.input,
                    .output_type = &requirement.output,
                    .self_permission = requirement.input.fields[self_index].ty.pointer_type.mutability,
                    .safety_methods = info.virtual_methods[method_index],
                };
                const node = try sg.makeSGNode(.{ .virtual_call = virtual_call }, location, self.allocator);
                const result_type: sg.Type = switch (requirement.output.fields.len) {
                    0 => .{ .builtin = .Any },
                    1 => requirement.output.fields[0].ty,
                    else => .{ .struct_type = &requirement.output },
                };
                node.sem_type = result_type;
                return .{ .node = node, .ty = result_type };
            }
        }
        return null;
    }

    fn explicitDeinitAutoCleanupTarget(
        self: *Semantizer,
        chosen: *sg.FunctionDeclaration,
        coerced_input: typ.TypedExpr,
        s: *Scope,
    ) ?*const sg.SGNode {
        if (!chosen.is_deinit) return null;
        if (coerced_input.node.content != .struct_value_literal) return null;

        const input_value = coerced_input.node.content.struct_value_literal;
        const positional_prefix = @min(input_value.dispatch_prefix_positional_count, input_value.fields.len);

        for (chosen.input.fields[0..positional_prefix], 0..) |expected_field, idx| {
            if (expected_field.ty != .pointer_type) continue;
            if (expected_field.ty.pointer_type.mutability != .read_write) continue;

            const arg_node = input_value.fields[idx].value;
            if (arg_node.content != .address_of) continue;
            const inner = arg_node.content.address_of;
            const binding = cleanupRootBinding(inner) orelse continue;
            if (self.hasAutoDeinitForBinding(binding, s)) return inner;
        }

        for (chosen.input.fields[positional_prefix..]) |expected_field| {
            if (expected_field.ty != .pointer_type) continue;
            if (expected_field.ty.pointer_type.mutability != .read_write) continue;

            const actual_field = findStructValueFieldByNameFrom(input_value.fields, positional_prefix, expected_field.name) orelse continue;
            if (actual_field.value.content != .address_of) continue;
            const inner = actual_field.value.content.address_of;
            const binding = cleanupRootBinding(inner) orelse continue;
            if (self.hasAutoDeinitForBinding(binding, s)) return inner;
        }
        return null;
    }

    fn hasAutoDeinitForBinding(self: *Semantizer, binding: *const sg.BindingDeclaration, s: *Scope) bool {
        _ = self;
        var cur: ?*Scope = s;
        while (cur) |scope_ptr| : (cur = scope_ptr.parent) {
            for (scope_ptr.deferred.items) |group| {
                if (group.nodes.len != 1 or group.nodes[0].content != .auto_deinit_binding) continue;
                if (group.nodes[0].content.auto_deinit_binding.binding == binding) return true;
            }
        }
        return false;
    }

    fn handleIsBuiltinFromInput(
        self: *Semantizer,
        input_te: typ.TypedExpr,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            try self.diags.add(
                loc,
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const input_struct = input_te.ty.struct_type;
        const input_value = input_te.node.content.struct_value_literal;

        var value_idx: ?usize = null;
        var variant_idx: ?usize = null;
        for (input_struct.fields, 0..) |field, idx| {
            if (idx < input_value.dispatch_prefix_positional_count) {
                if (idx == 0) {
                    if (value_idx != null) {
                        try self.addDuplicateIsBuiltinArgument(loc);
                        return error.Reported;
                    }
                    value_idx = idx;
                } else if (idx == 1) {
                    if (variant_idx != null) {
                        try self.addDuplicateIsBuiltinArgument(loc);
                        return error.Reported;
                    }
                    variant_idx = idx;
                } else {
                    try self.diags.add(
                        loc,
                        .semantic,
                        "is only accepts two positional arguments: value and variant",
                        .{},
                    );
                    return error.Reported;
                }
            } else if (std.mem.eql(u8, field.name, "value")) {
                if (value_idx != null) {
                    try self.addDuplicateIsBuiltinArgument(loc);
                    return error.Reported;
                }
                value_idx = idx;
            } else if (std.mem.eql(u8, field.name, "variant")) {
                if (variant_idx != null) {
                    try self.addDuplicateIsBuiltinArgument(loc);
                    return error.Reported;
                }
                variant_idx = idx;
            } else {
                try self.diags.add(
                    loc,
                    .semantic,
                    "is only accepts '.value' and '.variant' arguments",
                    .{},
                );
                return error.Reported;
            }
        }

        if (value_idx == null or variant_idx == null) {
            try self.diags.add(
                loc,
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const value_field = input_value.fields[value_idx.?];
        const variant_field = input_value.fields[variant_idx.?];
        const value_ty = input_struct.fields[value_idx.?].ty;

        if (value_ty != .choice_type) {
            const desc = try self.formatTypeText(value_ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "is expects '.value' to be a choice, found '{s}'",
                .{desc.bytes},
            );
            return error.Reported;
        }

        const variant_te = blk_variant: {
            const variant_node = variant_field.value.*;
            if (variant_node.content == .choice_literal) {
                const raw_variant = variant_node.content.choice_literal;
                if (raw_variant.payload == null) {
                    const choice_ty = value_ty.choice_type;
                    for (choice_ty.variants, 0..) |variant, idx| {
                        if (!std.mem.eql(u8, variant.name, raw_variant.variant_name)) continue;

                        const typed = try self.allocator.create(sg.ChoiceLiteral);
                        typed.* = .{
                            .variant_name = raw_variant.variant_name,
                            .choice_type = choice_ty,
                            .variant_index = @intCast(idx),
                            .payload = null,
                        };
                        const typed_node = try sg.makeSGNode(.{ .choice_literal = typed }, loc, self.allocator);
                        typed_node.sem_type = value_ty;
                        break :blk_variant typ.TypedExpr{ .node = typed_node, .ty = value_ty };
                    }

                    const choice_text = try self.formatTypeText(value_ty, s);
                    defer choice_text.deinit();
                    try self.diags.add(
                        loc,
                        .semantic,
                        "choice type '{s}' has no variant '..{s}'",
                        .{ choice_text.bytes, raw_variant.variant_name },
                    );
                    return error.Reported;
                }
            }

            break :blk_variant typ.TypedExpr{
                .node = @constCast(variant_field.value),
                .ty = input_struct.fields[variant_idx.?].ty,
            };
        };

        if (!typ.typesExactlyEqual(variant_te.ty, value_ty)) {
            try self.diags.add(
                loc,
                .semantic,
                "is expects '.variant' to belong to the same choice type as '.value'",
                .{},
            );
            return error.Reported;
        }

        const cmp_ptr = try self.allocator.create(sg.Comparison);
        cmp_ptr.* = .{
            .operator = .equal,
            .left = value_field.value,
            .right = variant_te.node,
        };

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, loc, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Bool } };
    }

    fn addDuplicateIsBuiltinArgument(self: *Semantizer, loc: tok.Location) !void {
        try self.diags.add(
            loc,
            .semantic,
            "is received the same argument more than once",
            .{},
        );
    }

    fn tryResolveImplicitCall(
        self: *Semantizer,
        name: []const u8,
        input: typ.TypedExpr,
        s: *Scope,
        location: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        const empty_args: ?syn.SyntaxRef = null;
        var has_unknown_candidate = false;
        const generic = self.instantiateGenericNamedVisible(
            name,
            empty_args,
            input,
            s,
            .regular,
            null,
            self.locationPath(location),
        ) catch |err| switch (err) {
            error.SymbolNotFound => null,
            error.UnknownType => blk: {
                has_unknown_candidate = true;
                break :blk null;
            },
            else => return err,
        };
        const declared = try self.resolveVisibleDeclaredOverloadMaybe(name, input, s, location);
        const abstract = self.instantiateGenericNamed(name, empty_args, input, s, .abstract_contract) catch |err| switch (err) {
            error.SymbolNotFound => null,
            error.UnknownType => blk: {
                has_unknown_candidate = true;
                break :blk null;
            },
            else => return err,
        };

        var best = declared;
        var best_kind: CallCandidateKind = .declared;
        if (abstract) |candidate| {
            if (best) |current| {
                const better = try self.chooseBetterCallCandidateWithKind(current, best_kind, candidate, .abstract_contract, input, s);
                best = better.function;
                best_kind = better.kind;
            } else {
                best = candidate;
                best_kind = .abstract_contract;
            }
        }
        if (generic) |candidate| {
            if (best) |current| {
                const better = try self.chooseBetterCallCandidateWithKind(current, best_kind, candidate, .generic_regular, input, s);
                best = better.function;
            } else best = candidate;
        }
        if (best) |chosen| return chosen;
        if (has_unknown_candidate) return error.UnknownType;
        return error.SymbolNotFound;
    }

    fn resolveRegularCallCallee(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        const file = self.syntaxFile(syntax_ref);
        const call = file.functionCall(syntax_ref.node) orelse return error.InvalidType;
        const callee = file.tokenText(&self.diags.source_db, call.callee_token);
        const qualifier = if (call.module_qualifier) |token_index| file.tokenText(&self.diags.source_db, token_index) else null;
        return self.tryResolveRegularCallCallee(syntax_ref, input_te, s, loc, null) catch |err| switch (err) {
            error.SymbolNotFound => {
                if (self.defer_unknown_top_level and self.current_top_node != null) {
                    return error.SymbolNotFound;
                }
                if (qualifier) |module_name| {
                    const module_dir = s.lookupModuleAlias(module_name) orelse {
                        try self.diags.add(loc, .semantic, "unknown module alias '{s}'", .{module_name});
                        return error.Reported;
                    };
                    if (try self.addMissingAbstractImplementationDiagnosticMaybeFiltered(callee, input_te.ty, s, loc, module_dir)) {
                        return error.Reported;
                    }
                    try self.addMissingModuleFunctionDiagnostic(module_name, module_dir, callee, input_te.ty, s, loc);
                    return error.Reported;
                }
                if (try self.addMissingAbstractImplementationDiagnostic(callee, input_te.ty, s, loc)) {
                    return error.Reported;
                }
                try self.addMissingFunctionDiagnostic(callee, input_te.ty, s, loc);
                return error.Reported;
            },
            else => return err,
        };
    }

    fn tryResolveRegularCallCallee(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
        callee_override: ?[]const u8,
    ) SemErr!*sg.FunctionDeclaration {
        const file = self.syntaxFile(syntax_ref);
        const call = file.functionCall(syntax_ref.node) orelse return error.InvalidType;
        const callee = callee_override orelse file.tokenText(&self.diags.source_db, call.callee_token);
        const qualifier = if (callee_override != null) null else if (call.module_qualifier) |token_index| file.tokenText(&self.diags.source_db, token_index) else null;
        const qualified_module_dir = if (qualifier) |module_name|
            s.lookupModuleAlias(module_name)
        else
            null;
        var chosen: *sg.FunctionDeclaration = undefined;
        if (call.type_arguments_struct) |stargs| {
            chosen = self.instantiateGenericNamedVisible(callee, file.ref(stargs), input_te, s, .regular, qualified_module_dir, self.locationPath(loc)) catch |err| switch (err) {
                error.SymbolNotFound => try self.instantiateGenericNamedVisible(callee, file.ref(stargs), input_te, s, .abstract_contract, qualified_module_dir, self.locationPath(loc)),
                else => return err,
            };
        } else if (call.type_arguments.len != 0) {
            const targs = call.type_arguments;
            chosen = self.instantiateGenericVisible(callee, syntax_ref, targs, input_te, s, .regular, qualified_module_dir, self.locationPath(loc)) catch |err| switch (err) {
                error.SymbolNotFound => try self.instantiateGenericVisible(callee, syntax_ref, targs, input_te, s, .abstract_contract, qualified_module_dir, self.locationPath(loc)),
                else => return err,
            };
        } else {
            const empty_args: ?syn.SyntaxRef = null;
            var has_unknown_candidate = false;
            const inferred = self.instantiateGenericNamedVisible(callee, empty_args, input_te, s, .regular, qualified_module_dir, self.locationPath(loc)) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.UnknownType => blk: {
                    has_unknown_candidate = true;
                    break :blk null;
                },
                else => return err,
            };

            const visible_declared = if (qualifier) |module_name|
                try self.resolveQualifiedDeclaredOverloadMaybe(module_name, callee, input_te, s, loc)
            else
                try self.resolveVisibleDeclaredOverloadMaybe(callee, input_te, s, loc);
            const abstract_inferred = if (qualifier != null)
                self.instantiateGenericNamedVisible(
                    callee,
                    empty_args,
                    input_te,
                    s,
                    .abstract_contract,
                    qualified_module_dir,
                    self.locationPath(loc),
                ) catch |inner_err| switch (inner_err) {
                    error.SymbolNotFound => null,
                    error.UnknownType => blk: {
                        has_unknown_candidate = true;
                        break :blk null;
                    },
                    else => return inner_err,
                }
            else
                self.instantiateGenericNamed(callee, empty_args, input_te, s, .abstract_contract) catch |inner_err| switch (inner_err) {
                    error.SymbolNotFound => null,
                    error.UnknownType => blk: {
                        has_unknown_candidate = true;
                        break :blk null;
                    },
                    else => return inner_err,
                };

            var best: ?*sg.FunctionDeclaration = null;
            var best_kind: CallCandidateKind = .declared;

            if (visible_declared) |resolved_visible| {
                best = resolved_visible;
                best_kind = .declared;
            }
            if (abstract_inferred) |instantiated_abstract| {
                if (best) |current_best| {
                    const better = try self.chooseBetterCallCandidateWithKind(
                        current_best,
                        best_kind,
                        instantiated_abstract,
                        .abstract_contract,
                        input_te,
                        s,
                    );
                    best = better.function;
                    best_kind = better.kind;
                } else {
                    best = instantiated_abstract;
                    best_kind = .abstract_contract;
                }
            }
            if (inferred) |instantiated| {
                if (best) |current_best| {
                    const better = try self.chooseBetterCallCandidateWithKind(
                        current_best,
                        best_kind,
                        instantiated,
                        .generic_regular,
                        input_te,
                        s,
                    );
                    best = better.function;
                    best_kind = better.kind;
                } else {
                    best = instantiated;
                    best_kind = .generic_regular;
                }
            }

            if (best) |resolved_best| {
                chosen = resolved_best;
            } else {
                if (has_unknown_candidate) return error.UnknownType;
                return error.SymbolNotFound;
            }
        }
        return chosen;
    }

    const CallCandidateKind = enum {
        declared,
        abstract_contract,
        generic_regular,
    };

    fn candidateKindPriority(kind: CallCandidateKind) u8 {
        return switch (kind) {
            .declared => 0,
            .abstract_contract => 1,
            .generic_regular => 2,
        };
    }

    fn preferCandidateOnEqualSpecificity(
        self: *Semantizer,
        current_kind: CallCandidateKind,
        candidate_kind: CallCandidateKind,
    ) bool {
        _ = self;
        return candidateKindPriority(candidate_kind) < candidateKindPriority(current_kind);
    }

    const RankedCallCandidate = struct {
        function: *sg.FunctionDeclaration,
        kind: CallCandidateKind,
    };

    const PreparedGenericTemplateCandidate = struct {
        tmpl: gen.GenericTemplate,
        subst: GenericSubst,
        dispatch_input: typ.TypedExpr,
        score: u32,

        fn deinit(self: *PreparedGenericTemplateCandidate) void {
            self.subst.deinit();
        }
    };

    fn kindForResolvedFunction(function: *sg.FunctionDeclaration) CallCandidateKind {
        return switch (function.origin_kind) {
            .declared => .declared,
            .generic_instantiation => switch (function.generic_dispatch_kind orelse .regular) {
                .regular => .generic_regular,
                .abstract_contract => .abstract_contract,
            },
        };
    }

    fn chooseBetterCallCandidateWithKind(
        self: *Semantizer,
        current: *sg.FunctionDeclaration,
        current_kind: CallCandidateKind,
        candidate: *sg.FunctionDeclaration,
        candidate_kind: CallCandidateKind,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) SemErr!RankedCallCandidate {
        const chosen = try self.chooseBetterCallCandidate(current, current_kind, candidate, candidate_kind, input_te, s);
        if (chosen == current) return .{ .function = current, .kind = current_kind };
        return .{ .function = candidate, .kind = candidate_kind };
    }

    fn chooseBetterCallCandidate(
        self: *Semantizer,
        current: *sg.FunctionDeclaration,
        current_kind: CallCandidateKind,
        candidate: *sg.FunctionDeclaration,
        candidate_kind: CallCandidateKind,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) SemErr!*sg.FunctionDeclaration {
        const current_score = self.callInputSpecificityScore(&current.input, input_te, s);
        const candidate_score = self.callInputSpecificityScore(&candidate.input, input_te, s);

        if (candidate_score < current_score) return candidate;
        if (candidate_score > current_score) return current;
        if (self.preferCandidateOnEqualSpecificity(current_kind, candidate_kind)) return candidate;
        if (self.preferCandidateOnEqualSpecificity(candidate_kind, current_kind)) return current;
        return error.AmbiguousOverload;
    }

    fn templateInstantiationDispatchScore(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        call_input: typ.TypedExpr,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!?u32 {
        const template_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        var in_struct_ptr = try self.structTypeFromNodeWithSubst(template_file.ref(tmpl.input), s, subst);

        if (try self.refinedStructTypeWithActual(in_struct_ptr, call_input.ty, s)) |refined| {
            in_struct_ptr = refined;
        }
        if (!self.callInputMatchesDispatch(in_struct_ptr, call_input, s)) return null;
        return self.callInputSpecificityScore(in_struct_ptr, call_input, s);
    }

    fn chooseBetterPreparedTemplateCandidate(
        self: *Semantizer,
        current: *const PreparedGenericTemplateCandidate,
        candidate_score: u32,
    ) bool {
        _ = self;
        return candidate_score < current.score;
    }

    fn resolveQualifiedDeclaredOverloadMaybe(
        self: *Semantizer,
        module_name: []const u8,
        fn_name: []const u8,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?*sg.FunctionDeclaration {
        const module_dir = s.lookupModuleAlias(module_name) orelse {
            try self.diags.add(loc, .semantic, "unknown module alias '{s}'", .{module_name});
            return error.Reported;
        };
        if (isPrivateName(fn_name)) {
            const requester_dir = self.moduleDirForFile(self.locationPath(loc));
            if (!std.mem.eql(u8, requester_dir, module_dir)) {
                try self.addPrivateMemberDiag(loc, "function", fn_name);
                return error.Reported;
            }
        }

        var best: ?*sg.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (cand.origin_kind != .declared) continue;
                    if (!std.mem.startsWith(u8, self.locationPath(cand.location), module_dir)) continue;
                    if (!(try self.functionIsVisible(cand, self.locationPath(loc)))) continue;
                    if (!self.callInputMatchesDispatch(&cand.input, input_te, s)) continue;

                    const score = self.callInputSpecificityScore(&cand.input, input_te, s);
                    if (best == null or score < best_score) {
                        best = cand;
                        best_score = score;
                        ambiguous = false;
                    } else if (score == best_score) {
                        ambiguous = true;
                    }
                }
            }
        }

        if (ambiguous) {
            try self.addAmbiguousModuleFunctionDiagnostic(module_name, module_dir, fn_name, input_te.ty, s, loc);
            return error.Reported;
        }
        return best;
    }

    fn resolveVisibleDeclaredOverloadMaybe(
        self: *Semantizer,
        fn_name: []const u8,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!?*sg.FunctionDeclaration {
        var best: ?*sg.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;
        var hidden_private_match = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (cand.origin_kind != .declared) continue;
                    if (!self.callInputMatchesDispatch(&cand.input, input_te, s)) continue;
                    if (!(try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), null))) {
                        hidden_private_match = true;
                        continue;
                    }

                    const score = self.callInputSpecificityScore(&cand.input, input_te, s);
                    if (best == null or score < best_score) {
                        best = cand;
                        best_score = score;
                        ambiguous = false;
                    } else if (score == best_score) {
                        ambiguous = true;
                    }
                }
            }
        }

        if (best == null and hidden_private_match and isPrivateName(fn_name)) {
            try self.addPrivateMemberDiag(loc, "function", fn_name);
            return error.Reported;
        }
        if (ambiguous) return error.AmbiguousOverload;
        return best;
    }

    fn fieldExprMatchesDispatch(
        self: *Semantizer,
        expected: sg.Type,
        actual: typ.TypedExpr,
        s: *Scope,
    ) bool {
        if (abs.typesCompatibleForDispatch(expected, actual.ty, s)) return true;
        if (self.tryImplicitPointerLiftForDispatch(expected, actual)) |lifted| {
            if (abs.typesCompatibleForDispatch(expected, lifted.ty, s)) return true;
        }

        return switch (expected) {
            .builtin => |bt| typ.canLiteralCoerceToBuiltin(bt, actual),
            .pointer_type => |pt| typ.canStringLiteralCoerceToPointer(pt, actual),
            .choice_type => |ct| blk: {
                if (actual.node.content != .choice_literal) break :blk false;
                const lit = actual.node.content.choice_literal;
                if (lit.payload != null) break :blk false;
                for (ct.variants) |variant| {
                    if (std.mem.eql(u8, variant.name, lit.variant_name)) break :blk true;
                }
                break :blk false;
            },
            .array_type => |arr_info| blk: {
                if (actual.node.content != .list_literal) break :blk false;
                const ll = actual.node.content.list_literal;
                if (ll.elements.len != arr_info.length) break :blk false;
                for (ll.elements, 0..) |elem_node, idx| {
                    const elem_expr = typ.TypedExpr{
                        .node = @constCast(elem_node),
                        .ty = ll.element_types[idx],
                    };
                    if (!self.fieldExprMatchesDispatch(arr_info.element_type.*, elem_expr, s)) break :blk false;
                }
                break :blk true;
            },
            .struct_type => |st| blk: {
                if (actual.node.content != .struct_value_literal or actual.ty != .struct_type) break :blk false;
                const actual_value = actual.node.content.struct_value_literal;
                if (st.layout == .c_union) {
                    if (actual_value.fields.len != 1 or actual_value.dispatch_prefix_positional_count != 0) break :blk false;
                    const actual_field_value = actual_value.fields[0];
                    const expected_field = typ.findFieldByName(st, actual_field_value.name) orelse break :blk false;
                    const actual_field_ty = typ.findFieldByName(actual.ty.struct_type, actual_field_value.name) orelse break :blk false;
                    const actual_field_expr = typ.TypedExpr{
                        .node = @constCast(actual_field_value.value),
                        .ty = actual_field_ty.ty,
                    };
                    break :blk self.fieldExprMatchesDispatch(expected_field.ty, actual_field_expr, s);
                }
                for (st.fields) |exp_field| {
                    const actual_field_ty = typ.findFieldByName(actual.ty.struct_type, exp_field.name) orelse break :blk false;
                    const actual_field_value = typ.findStructValueFieldByName(actual_value, exp_field.name) orelse break :blk false;
                    const actual_field_expr = typ.TypedExpr{
                        .node = @constCast(actual_field_value.value),
                        .ty = actual_field_ty.ty,
                    };
                    if (!self.fieldExprMatchesDispatch(exp_field.ty, actual_field_expr, s)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        };
    }

    fn tryImplicitPointerLiftForDispatch(
        self: *Semantizer,
        expected: sg.Type,
        actual: typ.TypedExpr,
    ) ?typ.TypedExpr {
        if (expected != .pointer_type) return null;
        if (actual.ty == .pointer_type) return null;
        const binding_use_node: *const sg.SGNode = switch (actual.node.content) {
            .binding_use => actual.node,
            .move_value => |inner| if (inner.content == .binding_use) inner else return null,
            else => return null,
        };
        const binding = binding_use_node.content.binding_use;
        if (expected.pointer_type.mutability == .read_write and binding.mutability != .variable) {
            return null;
        }

        const child_ty = self.allocator.create(sg.Type) catch return null;
        child_ty.* = actual.ty;

        const ptr_info = self.allocator.create(sg.PointerType) catch return null;
        ptr_info.* = .{
            .mutability = expected.pointer_type.mutability,
            .child = child_ty,
        };

        const addr_node = self.allocator.create(sg.SGNode) catch return null;
        sg.recordNodeAllocation();
        addr_node.* = .{
            .location = actual.node.location,
            .sem_type = .{ .pointer_type = ptr_info },
            .content = .{ .address_of = binding_use_node },
        };
        return .{ .node = addr_node, .ty = .{ .pointer_type = ptr_info } };
    }

    fn findStructTypeFieldByNameFrom(fields: []const sg.StructTypeField, start: usize, name: []const u8) ?*const sg.StructTypeField {
        for (fields[start..]) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    fn findStructValueFieldByNameFrom(fields: []const sg.StructValueLiteralField, start: usize, name: []const u8) ?*const sg.StructValueLiteralField {
        for (fields[start..]) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    fn recordAbstractFieldStorageType(
        self: *Semantizer,
        struct_type: *sg.StructType,
        field_index: usize,
        actual_ty: sg.Type,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!void {
        const field = &@constCast(struct_type.fields)[field_index];
        if (typ.typesExactlyEqual(field.ty, actual_ty)) return;
        if (!abs.typesCompatibleForDispatch(field.ty, actual_ty, s)) return;

        if (field.storage_type) |existing_ty| {
            if (typ.typesExactlyEqual(existing_ty, actual_ty)) return;

            const pair = try self.formatTypePairText(existing_ty, actual_ty, s);
            defer pair.deinit();
            const abstract_text = try self.formatTypeText(field.ty, s);
            defer abstract_text.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "field '.{s}' already stores '{s}' for abstract type '{s}', so it cannot also store '{s}'",
                .{ field.name, pair.expected.bytes, abstract_text.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        // Abstract storage remains static: once a field picks a concrete
        // implementer, later field access and codegen use that same backing
        // type instead of introducing runtime interface dispatch.
        field.storage_type = actual_ty;
    }

    fn coerceCallFieldExpr(
        self: *Semantizer,
        expected: sg.Type,
        actual: typ.TypedExpr,
        expr_location: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (typ.typesCompatible(expected, actual.ty)) return actual;

        if (expected == .pointer_type and actual.ty != .pointer_type) {
            const coerced_pointer = try typ.coerceExprToType(expected, actual, expr_location, s, self.allocator, self.diags);
            if (typ.typesCompatible(expected, coerced_pointer.ty)) return coerced_pointer;

            const ptr_expr = switch (expected.pointer_type.mutability) {
                .read_only => try typ.ensureReadOnlyPointer(expr_location, actual, self.allocator, self.diags),
                .read_write => try typ.ensureMutablePointer(expr_location, actual, s, self.allocator, self.diags),
            };
            if (typ.typesCompatible(expected, ptr_expr.ty)) return ptr_expr;
        }

        const coerced = try typ.coerceExprToType(expected, actual, expr_location, s, self.allocator, self.diags);
        if (!typ.typesCompatible(expected, coerced.ty)) {
            const pair = try self.formatTypePairText(expected, coerced.ty, s);
            defer pair.deinit();
            try self.diags.add(
                expr_location,
                .semantic,
                "cannot pass '{s}' where '{s}' is expected",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        return coerced;
    }

    fn coerceCallInputToExpected(
        self: *Semantizer,
        expected: *const sg.StructType,
        input_te: typ.TypedExpr,
        expr_location: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_location, s, self.allocator, self.diags);
        }

        const actual_struct = input_te.ty.struct_type;
        const actual_value = input_te.node.content.struct_value_literal;
        const positional_prefix: usize = @min(actual_value.dispatch_prefix_positional_count, actual_value.fields.len);

        if (positional_prefix > expected.fields.len) {
            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_location, s, self.allocator, self.diags);
        }

        for (actual_value.fields[positional_prefix..]) |actual_field| {
            if (typ.findFieldByName(expected, actual_field.name) == null) {
                return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_location, s, self.allocator, self.diags);
            }
        }

        const coerced_fields = try self.allocator.alloc(sg.StructValueLiteralField, expected.fields.len);
        for (expected.fields[0..positional_prefix], 0..) |exp_field, idx| {
            const actual_field = actual_value.fields[idx];
            const actual_field_ty = actual_struct.fields[idx].ty;
            var field_expr = typ.TypedExpr{
                .node = @constCast(actual_field.value),
                .ty = actual_field_ty,
            };
            field_expr = try self.coerceCallFieldExpr(exp_field.ty, field_expr, expr_location, s);
            coerced_fields[idx] = .{
                .name = exp_field.name,
                .value = field_expr.node,
            };
        }

        for (expected.fields[positional_prefix..], positional_prefix..) |exp_field, idx| {
            const actual_field = findStructValueFieldByNameFrom(actual_value.fields, positional_prefix, exp_field.name);
            const actual_field_ty = findStructTypeFieldByNameFrom(actual_struct.fields, positional_prefix, exp_field.name);

            if (actual_field != null and actual_field_ty != null) {
                var field_expr = typ.TypedExpr{
                    .node = @constCast(actual_field.?.value),
                    .ty = actual_field_ty.?.ty,
                };
                field_expr = try self.coerceCallFieldExpr(exp_field.ty, field_expr, expr_location, s);
                coerced_fields[idx] = .{
                    .name = exp_field.name,
                    .value = field_expr.node,
                };
                continue;
            }

            if (exp_field.default_value) |default_node| {
                if (default_node.content == .reach_directive) {
                    const resolved = try self.resolveReachedArgument(
                        exp_field.name,
                        exp_field.ty,
                        default_node.content.reach_directive,
                        s,
                        expr_location,
                    );
                    coerced_fields[idx] = .{
                        .name = exp_field.name,
                        .value = resolved.node,
                    };
                    continue;
                }
                coerced_fields[idx] = .{
                    .name = exp_field.name,
                    .value = default_node,
                };
                continue;
            }

            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_location, s, self.allocator, self.diags);
        }

        const value_ptr = try self.allocator.create(sg.StructValueLiteral);
        value_ptr.* = .{
            .fields = coerced_fields,
            .ty = .{ .struct_type = expected },
            .dispatch_prefix_positional_count = @intCast(positional_prefix),
        };

        const node = try sg.makeSGNode(.{ .struct_value_literal = value_ptr }, expr_location, self.allocator);
        return .{ .node = node, .ty = .{ .struct_type = expected } };
    }

    fn callInputMatchesDispatch(
        self: *Semantizer,
        expected: *const sg.StructType,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) bool {
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            return abs.typesCompatibleForDispatch(.{ .struct_type = expected }, input_te.ty, s);
        }

        const actual_struct = input_te.ty.struct_type;
        const actual_value = input_te.node.content.struct_value_literal;
        const positional_prefix: usize = @min(actual_value.dispatch_prefix_positional_count, actual_value.fields.len);

        if (positional_prefix > expected.fields.len) return false;

        for (actual_value.fields[positional_prefix..]) |actual_field| {
            if (typ.findFieldByName(expected, actual_field.name) == null) return false;
        }

        for (expected.fields[0..positional_prefix], 0..) |exp_field, idx| {
            if (idx >= actual_struct.fields.len or idx >= actual_value.fields.len) return false;
            const actual_field_expr = typ.TypedExpr{
                .node = @constCast(actual_value.fields[idx].value),
                .ty = actual_struct.fields[idx].ty,
            };
            if (!self.fieldExprMatchesDispatch(exp_field.ty, actual_field_expr, s)) return false;
        }

        for (expected.fields[positional_prefix..]) |exp_field| {
            const actual_field_ty = findStructTypeFieldByNameFrom(actual_struct.fields, positional_prefix, exp_field.name);
            const actual_field_value = findStructValueFieldByNameFrom(actual_value.fields, positional_prefix, exp_field.name);

            if (actual_field_ty != null and actual_field_value != null) {
                const actual_field_expr = typ.TypedExpr{
                    .node = @constCast(actual_field_value.?.value),
                    .ty = actual_field_ty.?.ty,
                };
                if (!self.fieldExprMatchesDispatch(exp_field.ty, actual_field_expr, s)) return false;
                continue;
            }

            if (exp_field.default_value != null) continue;
            return false;
        }

        return true;
    }

    fn callInputSpecificityScore(
        self: *Semantizer,
        expected: *const sg.StructType,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) u32 {
        _ = s;
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            return abs.specificityScore(.{ .struct_type = expected }, input_te.ty);
        }

        const actual_struct = input_te.ty.struct_type;
        const actual_value = input_te.node.content.struct_value_literal;
        const positional_prefix: usize = @min(actual_value.dispatch_prefix_positional_count, actual_value.fields.len);

        var score: u32 = 0;

        for (expected.fields[0..positional_prefix], 0..) |exp_field, idx| {
            if (idx >= actual_struct.fields.len) break;
            var actual_field_expr = typ.TypedExpr{
                .node = @constCast(actual_value.fields[idx].value),
                .ty = actual_struct.fields[idx].ty,
            };
            var used_pointer_lift = false;
            if (self.tryImplicitPointerLiftForDispatch(exp_field.ty, actual_field_expr)) |lifted| {
                actual_field_expr = lifted;
                used_pointer_lift = true;
            }
            score += abs.specificityScore(exp_field.ty, actual_field_expr.ty);
            if (used_pointer_lift) score += 1;
        }

        for (actual_value.fields[positional_prefix..]) |actual_field| {
            const actual_field_ty = findStructTypeFieldByNameFrom(actual_struct.fields, positional_prefix, actual_field.name) orelse continue;
            const exp_field = typ.findFieldByName(expected, actual_field.name) orelse continue;
            var actual_field_expr = typ.TypedExpr{
                .node = @constCast(actual_field.value),
                .ty = actual_field_ty.ty,
            };
            var used_pointer_lift = false;
            if (self.tryImplicitPointerLiftForDispatch(exp_field.ty, actual_field_expr)) |lifted| {
                actual_field_expr = lifted;
                used_pointer_lift = true;
            }
            score += abs.specificityScore(exp_field.ty, actual_field_expr.ty);
            if (used_pointer_lift) score += 1;
        }

        return score;
    }

    fn buildTypeInitializerDispatchInput(
        self: *Semantizer,
        constructed_ty: sg.Type,
        tv_in: typ.TypedExpr,
        init_input_ty: sg.Type,
        loc: tok.Location,
    ) !typ.TypedExpr {
        if (tv_in.ty != .struct_type or tv_in.node.content != .struct_value_literal) {
            return .{ .node = undefined, .ty = init_input_ty };
        }

        const init_struct = init_input_ty.struct_type;
        const user_value = tv_in.node.content.struct_value_literal;
        const args = try self.allocator.alloc(CallArg, user_value.fields.len + 1);

        const fake_binding = try self.allocator.create(sg.BindingDeclaration);
        fake_binding.* = .{
            .name = "__init_target",
            .location = loc,
            .origin_file = self.locationPath(loc),
            .mutability = .variable,
            .ty = init_struct.fields[0].ty,
            .initialization = null,
        };
        const fake_binding_use = try sg.makeSGNode(.{ .binding_use = fake_binding }, loc, self.allocator);
        _ = constructed_ty;
        args[0] = .{
            .name = init_struct.fields[0].name,
            .expr = .{
                .node = fake_binding_use,
                .ty = init_struct.fields[0].ty,
            },
        };
        for (user_value.fields, 0..) |field, idx| {
            args[idx + 1] = .{
                .name = field.name,
                .expr = .{
                    .node = @constCast(field.value),
                    .ty = tv_in.ty.struct_type.fields[idx].ty,
                },
            };
        }

        const positional_prefix: u32 = @intCast(user_value.dispatch_prefix_positional_count + 1);
        return self.buildCallInputWithPositionalPrefix(args, positional_prefix);
    }

    fn makeEmptyStructValueExpr(
        self: *Semantizer,
        loc: tok.Location,
    ) !typ.TypedExpr {
        const struct_ty = try self.allocator.create(sg.StructType);
        struct_ty.* = .{ .fields = &.{} };

        const struct_lit = try self.allocator.create(sg.StructValueLiteral);
        struct_lit.* = .{
            .fields = &.{},
            .ty = .{ .struct_type = struct_ty },
            .dispatch_prefix_positional_count = 0,
        };

        const node = try sg.makeSGNode(.{ .struct_value_literal = struct_lit }, loc, self.allocator);
        node.sem_type = .{ .struct_type = struct_ty };
        return .{ .node = node, .ty = .{ .struct_type = struct_ty } };
    }

    fn resolveTestingFailImpl(
        self: *Semantizer,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        const empty_input = try self.makeEmptyStructValueExpr(loc);
        return try self.resolveQualifiedOverload("testing", "test_fail_impl", empty_input, s, loc);
    }

    fn handleTestingExpectErrorBuiltin(
        self: *Semantizer,
        node_ref: syn.SyntaxRef,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node_ref);
        const call = file.functionCall(node_ref.node) orelse return error.InvalidType;
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        }

        const input_struct = input_te.ty.struct_type;
        const input_value = input_te.node.content.struct_value_literal;
        if (input_struct.fields.len != 2 or input_value.fields.len != 2) {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        }

        const expected_idx = fieldIndexInStruct(input_struct, "expected_reason") orelse {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        };
        const actual_idx = fieldIndexInStruct(input_struct, "actual_result") orelse {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        };

        const actual_info = try self.errableInfoOf(input_struct.fields[actual_idx].ty, file.location(call.input), "'.actual_result'", s);
        const error_payload_struct = switch (actual_info.error_payload_type) {
            .struct_type => |st| st,
            else => return error.Reported,
        };
        const reason_field = typ.findFieldByName(error_payload_struct, "reason") orelse {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "Errable '..error' payload must contain '.reason'",
                .{},
            );
            return error.Reported;
        };
        const reason_field_index = fieldIndexInStruct(error_payload_struct, "reason") orelse unreachable;

        var expected_reason_te = typ.TypedExpr{
            .node = @constCast(input_value.fields[expected_idx].value),
            .ty = input_struct.fields[expected_idx].ty,
        };
        expected_reason_te = try typ.coerceExprToType(reason_field.ty, expected_reason_te, file.location(call.input), s, self.allocator, self.diags);
        if (!typ.typesCompatible(reason_field.ty, expected_reason_te.ty)) {
            const pair = try self.formatTypePairText(reason_field.ty, expected_reason_te.ty, s);
            defer pair.deinit();
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "testing.expect_error expects '.expected_reason' compatible with '{s}', found '{s}'",
                .{ pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const test_fail_fn = try self.resolveTestingFailImpl(s, file.tokenLocation(call.callee_token));
        const result_type = typ.functionReturnType(test_fail_fn);
        const result_info = try self.errableInfoOf(result_type, file.tokenLocation(call.callee_token), "testing.expect_error result", s);

        const expect_err = try self.allocator.create(sg.TestingExpectError);
        const call_position = self.locationLineColumn(file.tokenLocation(call.callee_token));
        expect_err.* = .{
            .expected_reason = expected_reason_te.node,
            .actual_result = input_value.fields[actual_idx].value,
            .actual_error_variant_index = actual_info.error_variant_index,
            .actual_error_payload_type = actual_info.error_payload_type,
            .actual_reason_field_index = reason_field_index,
            .result_type = result_type,
            .result_ok_variant_index = result_info.ok_variant_index,
            .test_fail_function = test_fail_fn,
            .expected_reason_name = switch (expected_reason_te.node.content) {
                .choice_literal => |lit| lit.variant_name,
                else => null,
            },
            .line = call_position.line,
            .column = call_position.column,
            .source_file = self.locationPath(file.tokenLocation(call.callee_token)),
            .source_line = self.sourceLineText(file.tokenLocation(call.callee_token)),
        };

        const node = try sg.makeSGNode(.{ .testing_expect_error = expect_err }, file.tokenLocation(call.callee_token), self.allocator);
        node.sem_type = result_type;
        try s.nodes.append(node);
        return .{ .node = node, .ty = result_type };
    }

    fn resolveQualifiedOverload(
        self: *Semantizer,
        module_name: []const u8,
        fn_name: []const u8,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        const module_dir = s.lookupModuleAlias(module_name) orelse {
            try self.diags.add(
                loc,
                .semantic,
                "unknown module alias '{s}'",
                .{module_name},
            );
            return error.Reported;
        };
        if (isPrivateName(fn_name)) {
            const requester_dir = self.moduleDirForFile(self.locationPath(loc));
            if (!std.mem.eql(u8, requester_dir, module_dir)) {
                try self.addPrivateMemberDiag(loc, "function", fn_name);
                return error.Reported;
            }
        }

        var best: ?*sg.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!std.mem.startsWith(u8, self.locationPath(cand.location), module_dir)) continue;
                    if (!(try self.functionIsVisible(cand, self.locationPath(loc)))) continue;
                    if (!self.callInputMatchesDispatch(&cand.input, input_te, s)) continue;

                    const score = self.callInputSpecificityScore(&cand.input, input_te, s);
                    if (best == null or score < best_score) {
                        best = cand;
                        best_score = score;
                        ambiguous = false;
                    } else if (score == best_score) {
                        if (self.preferCandidateOnEqualSpecificity(kindForResolvedFunction(best.?), kindForResolvedFunction(cand))) {
                            best = cand;
                            ambiguous = false;
                        } else if (!self.preferCandidateOnEqualSpecificity(kindForResolvedFunction(cand), kindForResolvedFunction(best.?))) {
                            ambiguous = true;
                        }
                    }
                }
            }
        }

        if (best == null) {
            if (self.defer_unknown_top_level and self.current_top_node != null) {
                return error.SymbolNotFound;
            }
            try self.addMissingModuleFunctionDiagnostic(module_name, module_dir, fn_name, input_te.ty, s, loc);
            return error.Reported;
        }
        if (ambiguous) {
            try self.addAmbiguousModuleFunctionDiagnostic(module_name, module_dir, fn_name, input_te.ty, s, loc);
            return error.Reported;
        }
        return best.?;
    }

    fn resolveVisibleOverload(
        self: *Semantizer,
        fn_name: []const u8,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        var best: ?*sg.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;
        var hidden_private_match = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!self.callInputMatchesDispatch(&cand.input, input_te, s)) continue;
                    if (!(try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), null))) {
                        hidden_private_match = true;
                        continue;
                    }

                    const score = self.callInputSpecificityScore(&cand.input, input_te, s);
                    if (best == null or score < best_score) {
                        best = cand;
                        best_score = score;
                        ambiguous = false;
                    } else if (score == best_score) {
                        if (self.preferCandidateOnEqualSpecificity(kindForResolvedFunction(best.?), kindForResolvedFunction(cand))) {
                            best = cand;
                            ambiguous = false;
                        } else if (!self.preferCandidateOnEqualSpecificity(kindForResolvedFunction(cand), kindForResolvedFunction(best.?))) {
                            ambiguous = true;
                        }
                    }
                }
            }
        }

        if (best == null and hidden_private_match and isPrivateName(fn_name)) {
            try self.addPrivateMemberDiag(loc, "function", fn_name);
            return error.Reported;
        }
        if (best == null) return error.SymbolNotFound;
        if (ambiguous) return error.AmbiguousOverload;
        return best.?;
    }

    fn hasVisibleFunctionNamed(
        self: *Semantizer,
        fn_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) !bool {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), null)) return true;
                }
            }
        }
        return false;
    }

    fn collectVisibleFunctionSignatures(
        self: *Semantizer,
        fn_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        errdefer buf.deinit();

        var cur: ?*Scope = s;
        var first = true;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!(try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), null))) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try abs.appendFunctionSignature(&buf, cand, s);
                }
            }
            if (sc.generic_functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .abstract_contract) continue;
                    if (isPrivateName(fn_name)) {
                        const requester_dir = self.moduleDirForFile(self.locationPath(loc));
                        const tmpl_dir = self.moduleDirForFile(self.locationPath(tmpl.location));
                        if (!std.mem.eql(u8, requester_dir, tmpl_dir)) continue;
                    }
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try self.appendGenericTemplateSignature(&buf, tmpl, s);
                }
            }
        }

        if (first) try buf.appendSlice("  (none)");
        return try buf.toOwnedSlice();
    }

    fn hasVisibleFunctionInModule(
        self: *Semantizer,
        module_dir: []const u8,
        fn_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) !bool {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), module_dir)) return true;
                }
            }
        }
        return false;
    }

    fn collectModuleFunctionSignatures(
        self: *Semantizer,
        module_dir: []const u8,
        fn_name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        errdefer buf.deinit();

        var cur: ?*Scope = s;
        var first = true;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!(try self.functionMatchesVisibilityFilter(cand, self.locationPath(loc), module_dir))) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try abs.appendFunctionSignature(&buf, cand, s);
                }
            }
            if (sc.generic_functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .abstract_contract) continue;
                    if (!std.mem.startsWith(u8, self.locationPath(tmpl.location), module_dir)) continue;
                    if (isPrivateName(fn_name)) {
                        const requester_dir = self.moduleDirForFile(self.locationPath(loc));
                        if (!std.mem.eql(u8, requester_dir, module_dir)) continue;
                    }
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try self.appendGenericTemplateSignature(&buf, tmpl, s);
                }
            }
        }

        if (first) try buf.appendSlice("  (none)");
        return try buf.toOwnedSlice();
    }

    fn appendGenericTemplateSignature(
        self: *Semantizer,
        buf: *std.array_list.Managed(u8),
        tmpl: gen.GenericTemplate,
        s: *Scope,
    ) !void {
        _ = s;
        try buf.appendSlice(tmpl.name);
        try buf.appendSlice(" (");
        const syntax_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const input = syntax_file.structTypeLiteral(tmpl.input) orelse return error.InvalidType;
        const output = syntax_file.structTypeLiteral(tmpl.output) orelse return error.InvalidType;
        for (input.fields, 0..) |field_node, i| {
            const fld = syntax_file.structTypeField(field_node) orelse return error.InvalidType;
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(syntax_file.tokenText(tmpl.source_db, fld.name_token));
            try buf.appendSlice(": ");
            try self.appendTemplateTypePretty(buf, fld.type_node orelse return error.InvalidType, tmpl);
        }
        try buf.appendSlice(") -> (");
        for (output.fields, 0..) |field_node, i| {
            const fld = syntax_file.structTypeField(field_node) orelse return error.InvalidType;
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(syntax_file.tokenText(tmpl.source_db, fld.name_token));
            try buf.appendSlice(": ");
            try self.appendTemplateTypePretty(buf, fld.type_node orelse return error.InvalidType, tmpl);
        }
        try buf.appendSlice(")");
    }

    fn templateParamDisplayName(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        param_name: []const u8,
    ) ?[]const u8 {
        _ = self;
        for (tmpl.params, 0..) |param, idx| {
            if (!std.mem.eql(u8, param.name, param_name)) continue;
            if (idx < tmpl.param_abstract_constraints.len) {
                if (tmpl.param_abstract_constraints[idx]) |constraint| return constraint.name;
            }
            return param.name;
        }
        return null;
    }

    fn appendTemplateTypePretty(
        self: *Semantizer,
        buf: *std.array_list.Managed(u8),
        node: syn.NodeIndex,
        tmpl: gen.GenericTemplate,
    ) !void {
        const file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const ty = file.syntaxType(node) orelse return error.InvalidType;
        switch (ty) {
            .name => |name| {
                if (name.qualifier_token) |qualifier| {
                    try buf.appendSlice(file.tokenText(tmpl.source_db, qualifier));
                    try buf.appendSlice("::");
                }
                const text = file.tokenText(tmpl.source_db, name.name_token);
                try buf.appendSlice(self.templateParamDisplayName(tmpl, text) orelse text);
            },
            .pointer => |pointer| {
                switch (pointer.mutability) {
                    .read_only => try buf.appendSlice("&"),
                    .read_write => try buf.appendSlice("$&"),
                }
                try self.appendTemplateTypePretty(buf, pointer.child, tmpl);
            },
            .nullable => |child| {
                try buf.appendSlice("?");
                try self.appendTemplateTypePretty(buf, child, tmpl);
            },
            .inferred_errable => |child| {
                try buf.appendSlice("!");
                try self.appendTemplateTypePretty(buf, child, tmpl);
            },
            .array => |array| {
                try buf.appendSlice("[");
                try buf.appendSlice(file.tokenText(tmpl.source_db, array.length_token));
                try buf.appendSlice("]");
                try self.appendTemplateTypePretty(buf, array.element, tmpl);
            },
            .generic => |generic| {
                try self.appendTemplateTypePretty(buf, generic.base, tmpl);
                try buf.appendSlice("#(");
                const arguments = file.structTypeLiteral(generic.arguments) orelse return error.InvalidType;
                for (arguments.fields, 0..) |field_node, idx| {
                    const field = file.structTypeField(field_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(file.tokenText(tmpl.source_db, field.name_token));
                    if (field.type_node) |field_type| {
                        try buf.appendSlice(": ");
                        try self.appendTemplateTypePretty(buf, field_type, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
            .struct_literal => |literal| {
                try buf.appendSlice("(");
                for (literal.fields, 0..) |field_node, idx| {
                    const field = file.structTypeField(field_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(file.tokenText(tmpl.source_db, field.name_token));
                    if (field.type_node) |field_type| {
                        try buf.appendSlice(": ");
                        try self.appendTemplateTypePretty(buf, field_type, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
            .choice_literal => |literal| {
                try buf.appendSlice("(");
                for (literal.variants, 0..) |variant_node, idx| {
                    const variant = file.choiceTypeVariant(variant_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice("..");
                    if (variant.module_qualifier) |qualifier| {
                        try buf.appendSlice(file.tokenText(tmpl.source_db, qualifier));
                        try buf.appendSlice(".");
                    }
                    try buf.appendSlice(file.tokenText(tmpl.source_db, variant.name_token));
                    if (variant.payload_type) |payload| {
                        try buf.appendSlice(" ");
                        try self.appendTemplateTypePretty(buf, payload, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
        }
    }

    fn appendSyntaxTypePretty(
        self: *Semantizer,
        buf: *std.array_list.Managed(u8),
        syntax_ref: syn.SyntaxRef,
    ) !void {
        const file = self.syntaxFile(syntax_ref);
        const ty = file.syntaxType(syntax_ref.node) orelse return error.InvalidType;
        switch (ty) {
            .name => |name| {
                if (name.qualifier_token) |qualifier| {
                    try buf.appendSlice(file.tokenText(&self.diags.source_db, qualifier));
                    try buf.appendSlice("::");
                }
                const text = file.tokenText(&self.diags.source_db, name.name_token);
                try buf.appendSlice(text);
            },
            .pointer => |pointer| {
                switch (pointer.mutability) {
                    .read_only => try buf.appendSlice("&"),
                    .read_write => try buf.appendSlice("$&"),
                }
                try self.appendSyntaxTypePretty(buf, file.ref(pointer.child));
            },
            .nullable => |child| {
                try buf.appendSlice("?");
                try self.appendSyntaxTypePretty(buf, file.ref(child));
            },
            .inferred_errable => |child| {
                try buf.appendSlice("!");
                try self.appendSyntaxTypePretty(buf, file.ref(child));
            },
            .array => |array| {
                try buf.appendSlice("[");
                try buf.appendSlice(file.tokenText(&self.diags.source_db, array.length_token));
                try buf.appendSlice("]");
                try self.appendSyntaxTypePretty(buf, file.ref(array.element));
            },
            .generic => |generic| {
                try self.appendSyntaxTypePretty(buf, file.ref(generic.base));
                try buf.appendSlice("#(");
                const arguments = file.structTypeLiteral(generic.arguments) orelse return error.InvalidType;
                for (arguments.fields, 0..) |field_node, idx| {
                    const field = file.structTypeField(field_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(file.tokenText(&self.diags.source_db, field.name_token));
                    if (field.type_node) |field_type| {
                        try buf.appendSlice(": ");
                        try self.appendSyntaxTypePretty(buf, file.ref(field_type));
                    }
                }
                try buf.appendSlice(")");
            },
            .struct_literal => |literal| {
                try buf.appendSlice("(");
                for (literal.fields, 0..) |field_node, idx| {
                    const field = file.structTypeField(field_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(file.tokenText(&self.diags.source_db, field.name_token));
                    if (field.type_node) |field_type| {
                        try buf.appendSlice(": ");
                        try self.appendSyntaxTypePretty(buf, file.ref(field_type));
                    }
                }
                try buf.appendSlice(")");
            },
            .choice_literal => |literal| {
                try buf.appendSlice("(");
                for (literal.variants, 0..) |variant_node, idx| {
                    const variant = file.choiceTypeVariant(variant_node) orelse return error.InvalidType;
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice("..");
                    if (variant.module_qualifier) |qualifier| {
                        try buf.appendSlice(file.tokenText(&self.diags.source_db, qualifier));
                        try buf.appendSlice(".");
                    }
                    try buf.appendSlice(file.tokenText(&self.diags.source_db, variant.name_token));
                    if (variant.payload_type) |payload| {
                        try buf.appendSlice(" ");
                        try self.appendSyntaxTypePretty(buf, file.ref(payload));
                    }
                }
                try buf.appendSlice(")");
            },
        }
    }

    fn appendSyntaxReachDirective(self: *Semantizer, buf: *std.array_list.Managed(u8), syntax_ref: syn.SyntaxRef) !void {
        const file = self.syntaxFile(syntax_ref);
        const reach = file.reachDirective(syntax_ref.node) orelse return error.InvalidType;
        for (reach.alternatives, 0..) |alt, alt_idx| {
            if (alt_idx != 0) try buf.appendSlice(", ");
            for (file.reachAlternative(alt).?.segments, 0..) |segment, seg_idx| {
                if (seg_idx != 0) try buf.append('.');
                try buf.appendSlice(file.tokenText(&self.diags.source_db, file.mainToken(segment)));
            }
        }
    }

    fn appendSyntaxFunctionSignature(self: *Semantizer, buf: *std.array_list.Managed(u8), syntax_ref: syn.SyntaxRef, decl: syn.FunctionDeclaration) !void {
        const file = self.syntaxFile(syntax_ref);
        try buf.appendSlice(self.functionNameText(syntax_ref).?);
        try buf.appendSlice("(");
        for (file.structTypeLiteral(decl.input).?.fields, 0..) |field_node, idx| {
            const field = file.structTypeField(field_node).?;
            if (idx != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(file.tokenText(&self.diags.source_db, field.name_token));
            if (field.type_node) |field_ty| {
                try buf.appendSlice(": ");
                try self.appendSyntaxTypePretty(buf, file.ref(field_ty));
            }
            if (field.default_value) |default_node| {
                if (file.tag(default_node) == .reach_directive) {
                    try buf.appendSlice(" = #reach ");
                    try self.appendSyntaxReachDirective(buf, file.ref(default_node));
                }
            }
        }
        try buf.appendSlice(") -> (");
        for (file.structTypeLiteral(decl.output).?.fields, 0..) |field_node, idx| {
            const field = file.structTypeField(field_node).?;
            if (idx != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(file.tokenText(&self.diags.source_db, field.name_token));
            if (field.type_node) |field_ty| {
                try buf.appendSlice(": ");
                try self.appendSyntaxTypePretty(buf, file.ref(field_ty));
            }
        }
        try buf.appendSlice(")");
    }

    fn syntaxFunctionVisibleFrom(self: *Semantizer, syntax_ref: syn.SyntaxRef, decl_loc: tok.Location, requester_file: []const u8) !bool {
        if (!isPrivateName(self.functionNameText(syntax_ref).?)) return true;
        return try self.isSameModule(requester_file, self.locationPath(decl_loc));
    }

    fn appendReachDefaultHintForDecl(
        self: *Semantizer,
        out: *std.array_list.Managed(u8),
        syntax_ref: syn.SyntaxRef,
        decl: syn.FunctionDeclaration,
        any_overload: *bool,
    ) !void {
        const file = self.syntaxFile(syntax_ref);
        var decl_has_reach_default = false;
        for (file.structTypeLiteral(decl.input).?.fields) |field_node| {
            const field = file.structTypeField(field_node).?;
            const default_node = field.default_value orelse continue;
            if (file.tag(default_node) != .reach_directive) continue;
            decl_has_reach_default = true;
            break;
        }
        if (!decl_has_reach_default) return;

        if (any_overload.*) try out.appendSlice("\n");
        any_overload.* = true;
        try out.appendSlice("  - ");
        try self.appendSyntaxFunctionSignature(out, syntax_ref, decl);
        try out.appendSlice("\n    omitted #reach defaults:");

        for (file.structTypeLiteral(decl.input).?.fields) |field_node| {
            const field = file.structTypeField(field_node).?;
            const default_node = field.default_value orelse continue;
            if (file.tag(default_node) != .reach_directive) continue;
            try out.appendSlice("\n      - .");
            try out.appendSlice(file.tokenText(&self.diags.source_db, field.name_token));
            try out.appendSlice(" uses #reach [");
            try self.appendSyntaxReachDirective(out, file.ref(default_node));
            try out.appendSlice("]");
            if (field.type_node) |field_ty| {
                try out.appendSlice(" expected as '");
                try self.appendSyntaxTypePretty(out, file.ref(field_ty));
                try out.appendSlice("'");
            }
        }
    }

    fn buildReachDefaultDiagnosticText(
        self: *Semantizer,
        fn_name: []const u8,
        requester_file: []const u8,
    ) !?OwnedText {
        var overloads = std.array_list.Managed(u8).init(self.allocator.*);
        defer overloads.deinit();

        var any_overload = false;
        for (self.syntax_roots) |node| {
            const file = self.syntaxFile(node);
            const decl = if (file.testDeclaration(node.node)) |test_decl|
                test_decl.function
            else
                file.functionDeclaration(node.node) orelse continue;
            if (!std.mem.eql(u8, self.functionNameText(node).?, fn_name)) continue;
            if (!(try self.syntaxFunctionVisibleFrom(node, self.nodeLocation(node), requester_file))) continue;
            try self.appendReachDefaultHintForDecl(&overloads, node, decl, &any_overload);
        }
        if (!any_overload) return null;

        var out = std.array_list.Managed(u8).init(self.allocator.*);
        errdefer out.deinit();
        try out.appendSlice("Overloads with omitted #reach defaults:\n");
        try out.appendSlice(overloads.items);
        try out.appendSlice("\n\nAdd a reachable value in the caller, for example:\n");
        try out.appendSlice("  main(.system: System = System()) -> (.status_code: Int32 = 0) := { ... }\n\n");
        try out.appendSlice("Or pass the omitted argument explicitly.");
        return self.formatOwnedText(try out.toOwnedSlice());
    }

    fn addMissingFunctionDiagnostic(
        self: *Semantizer,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !void {
        if (!(try self.hasVisibleFunctionNamed(fn_name, s, loc))) {
            if (try self.buildReachDefaultDiagnosticText(fn_name, self.locationPath(loc))) |details| {
                defer details.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "function '{s}' exists, but no overload matches the provided arguments.\n{s}",
                    .{ fn_name, details.bytes },
                );
                return;
            }
            try self.diags.add(
                loc,
                .semantic,
                "no function named '{s}' exists",
                .{fn_name},
            );
            return;
        }

        if (input_ty == .struct_type) {
            const sigs = try self.collectVisibleSignatureText(fn_name, input_ty.struct_type, s, loc);
            defer sigs.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "no overload of '{s}' accepts arguments {s}. Available signatures:\n{s}",
                .{ fn_name, sigs.actual.bytes, sigs.available.bytes },
            );
            return;
        }

        try self.diags.add(
            loc,
            .semantic,
            "function '{s}' exists, but no overload matches the provided arguments",
            .{fn_name},
        );
    }

    fn findTemplateFieldUsingParam(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        param_name: []const u8,
    ) ?[]const u8 {
        const file = syn.fileForRef(tmpl.syntax_files, .{ .file_id = tmpl.syntax_file_id, .node = tmpl.input });
        const input = file.structTypeLiteral(tmpl.input) orelse return null;
        for (input.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse continue;
            const ty_node = field.type_node orelse continue;
            if (self.compactTypeUsesParam(file.ref(ty_node), param_name)) return file.tokenText(tmpl.source_db, field.name_token);
        }
        return null;
    }

    fn addMissingAbstractImplementationDiagnostic(
        self: *Semantizer,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !bool {
        return self.addMissingAbstractImplementationDiagnosticMaybeFiltered(fn_name, input_ty, s, loc, null);
    }

    fn addMissingAbstractImplementationDiagnosticMaybeFiltered(
        self: *Semantizer,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
        module_dir_filter: ?[]const u8,
    ) !bool {
        if (input_ty != .struct_type) return false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .abstract_contract) continue;
                    if (module_dir_filter) |module_dir| {
                        if (!std.mem.startsWith(u8, self.locationPath(tmpl.location), module_dir)) continue;
                    }

                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();

                    var i: usize = 0;
                    while (i < tmpl.params.len) : (i += 1) {
                        const constraint = tmpl.param_abstract_constraints[i] orelse continue;
                        const param = tmpl.params[i];
                        if (param.kind != .type) continue;
                        const actual_arg = self.inferGenericArgFromCall(tmpl, param, input_ty, s, &subst) orelse continue;
                        const actual = switch (actual_arg) {
                            .type => |ty| ty,
                            else => continue,
                        };
                        var diagnostic_subst = GenericSubst.init(self.allocator);
                        defer diagnostic_subst.deinit();
                        try diagnostic_subst.types.put(param.name, actual);
                        if (try self.abstractConstraintMatches(actual, constraint, s, &diagnostic_subst)) continue;

                        const actual_str = try self.formatTypeText(actual, s);
                        defer actual_str.deinit();
                        const field_name = self.findTemplateFieldUsingParam(tmpl, param.name) orelse param.name;
                        if (try abs.buildConformanceDetails(constraint.name, actual, s, self.allocator, self.diags)) |details| {
                            defer details.deinit();
                            try self.diags.add(
                                loc,
                                .semantic,
                                "type '{s}' does not implement abstract '{s}' required by parameter '.{s}' of '{s}':\n{s}",
                                .{ actual_str.bytes, constraint.name, field_name, fn_name, details.bytes },
                            );
                        } else {
                            try self.diags.add(
                                loc,
                                .semantic,
                                "type '{s}' does not implement abstract '{s}' required by parameter '.{s}' of '{s}'",
                                .{ actual_str.bytes, constraint.name, field_name, fn_name },
                            );
                        }
                        return true;
                    }
                }
            }
        }

        return false;
    }

    fn addAmbiguousFunctionDiagnostic(
        self: *Semantizer,
        fn_name: []const u8,
        maybe_input_ty: ?sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !void {
        if (maybe_input_ty) |input_ty| {
            if (input_ty == .struct_type) {
                const sigs = try self.collectVisibleSignatureText(fn_name, input_ty.struct_type, s, loc);
                defer sigs.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "ambiguous call to '{s}' for arguments {s}. Possible overloads:\n{s}",
                    .{ fn_name, sigs.actual.bytes, sigs.available.bytes },
                );
                return;
            }
        }

        const candidates_result = self.buildOverloadCandidatesText(
            fn_name,
            if (maybe_input_ty) |input_ty| input_ty else .{ .builtin = .Any },
            s,
        ) catch null;
        const candidates = if (candidates_result) |owned| owned.bytes else "";
        defer if (candidates_result) |owned| owned.deinit();

        try self.diags.add(
            loc,
            .semantic,
            "ambiguous call to '{s}'. Possible overloads:\n{s}",
            .{ fn_name, candidates },
        );
    }

    fn addMissingModuleFunctionDiagnostic(
        self: *Semantizer,
        module_name: []const u8,
        module_dir: []const u8,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !void {
        if (!(try self.hasVisibleFunctionInModule(module_dir, fn_name, s, loc))) {
            try self.diags.add(
                loc,
                .semantic,
                "module '{s}' has no function named '{s}'",
                .{ module_name, fn_name },
            );
            return;
        }

        if (input_ty == .struct_type) {
            const sigs = try self.collectModuleSignatureText(module_dir, fn_name, input_ty.struct_type, s, loc);
            defer sigs.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "module '{s}' has no overload '{s}' accepting arguments {s}. Available signatures:\n{s}",
                .{ module_name, fn_name, sigs.actual.bytes, sigs.available.bytes },
            );
            return;
        }

        try self.diags.add(
            loc,
            .semantic,
            "module '{s}' has function '{s}', but no overload matches the provided arguments",
            .{ module_name, fn_name },
        );
    }

    fn addAmbiguousModuleFunctionDiagnostic(
        self: *Semantizer,
        module_name: []const u8,
        module_dir: []const u8,
        fn_name: []const u8,
        maybe_input_ty: ?sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !void {
        if (maybe_input_ty) |input_ty| {
            if (input_ty == .struct_type) {
                const sigs = try self.collectModuleSignatureText(module_dir, fn_name, input_ty.struct_type, s, loc);
                defer sigs.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "module-qualified call '{s}.{s}' is ambiguous for arguments {s}. Possible overloads:\n{s}",
                    .{ module_name, fn_name, sigs.actual.bytes, sigs.available.bytes },
                );
                return;
            }
        }

        try self.diags.add(
            loc,
            .semantic,
            "module-qualified call '{s}.{s}' is ambiguous",
            .{ module_name, fn_name },
        );
    }

    fn handleTypeInitializer(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        tv_in: typ.TypedExpr,
        type_decl: *sg.TypeDeclaration,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const call = file.functionCall(syntax_ref.node) orelse return error.InvalidType;
        const callee = file.tokenText(&self.diags.source_db, call.callee_token);
        if (tv_in.ty != .struct_type) {
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "expected struct literal arguments when constructing type '{s}'",
                .{callee},
            );
            return error.Reported;
        }

        var init_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer init_fields.deinit();

        const ptr_child = try self.allocator.create(sg.Type);
        ptr_child.* = type_decl.ty;

        const ptr_info = try self.allocator.create(sg.PointerType);
        ptr_info.* = .{ .mutability = .read_write, .child = ptr_child };

        try init_fields.append(.{ .name = "p", .ty = .{ .pointer_type = ptr_info }, .default_value = null });

        const user_struct = tv_in.ty.struct_type;
        for (user_struct.fields) |fld| {
            try init_fields.append(.{ .name = fld.name, .ty = fld.ty, .default_value = null });
        }

        const init_struct = try self.allocator.create(sg.StructType);
        init_struct.* = .{ .fields = try init_fields.toOwnedSlice() };

        const init_input_ty: sg.Type = .{ .struct_type = init_struct };
        const init_input_te = try self.buildTypeInitializerDispatchInput(type_decl.ty, tv_in, init_input_ty, file.location(call.input));
        const init_fn = blk: {
            break :blk self.tryResolveRegularCallCallee(syntax_ref, init_input_te, s, file.location(call.input), "init") catch |err| switch (err) {
                error.SymbolNotFound => {
                    if (type_decl.ty == .struct_type and !(try self.hasVisibleTypeInitializerInit(type_decl.ty, self.locationPath(file.location(call.input)), s))) {
                        return try self.coerceCallInputToExpected(type_decl.ty.struct_type, tv_in, file.location(call.input), s);
                    }

                    const actual = self.formatOwnedText(try typ.formatCallInput(user_struct, s, self.allocator));
                    defer actual.deinit();
                    const available = self.formatOwnedText(try self.collectVisibleTypeInitializerSignatures(type_decl.ty, self.locationPath(file.location(call.input)), s));
                    defer available.deinit();
                    try self.diags.add(
                        file.location(call.input),
                        .semantic,
                        "failed to initialize type '{s}': no visible 'init' overload accepts arguments {s}. Available overloads:\n{s}",
                        .{ callee, actual.bytes, available.bytes },
                    );
                    return error.Reported;
                },
                error.AmbiguousOverload => {
                    const candidates = self.formatOwnedText(try self.collectVisibleTypeInitializerSignatures(type_decl.ty, self.locationPath(file.location(call.input)), s));
                    defer candidates.deinit();
                    try self.diags.add(
                        file.location(call.input),
                        .semantic,
                        "failed to initialize type '{s}': matching 'init' overloads are ambiguous. Candidates:\n{s}",
                        .{ callee, candidates.bytes },
                    );
                    return error.Reported;
                },
                else => return err,
            };
        };

        try self.discoverFunctionReference(init_fn);
        const expected_user_fields = try self.allocator.alloc(sg.StructTypeField, init_fn.input.fields.len - 1);
        std.mem.copyForwards(sg.StructTypeField, expected_user_fields, init_fn.input.fields[1..]);
        const expected_user_struct = try self.allocator.create(sg.StructType);
        expected_user_struct.* = .{ .fields = expected_user_fields };
        const coerced_args = try self.coerceCallInputToExpected(expected_user_struct, tv_in, file.location(call.input), s);

        const type_init = sg.TypeInitializer{
            .type_decl = type_decl,
            .init_fn = init_fn,
            .args = coerced_args.node,
        };

        const init_node = try sg.makeSGNode(.{ .type_initializer = type_init }, file.tokenLocation(call.callee_token), self.allocator);
        return .{ .node = init_node, .ty = type_decl.ty };
    }

    fn hasVisibleTypeInitializerInit(
        self: *Semantizer,
        ty: sg.Type,
        current_file: []const u8,
        s: *Scope,
    ) SemErr!bool {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr("init")) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!(try self.functionIsVisible(cand, current_file))) continue;
                    if (cand.input.fields.len == 0) continue;

                    const first = cand.input.fields[0];
                    if (!std.mem.eql(u8, first.name, "p")) continue;
                    if (first.ty != .pointer_type) continue;

                    const ptr_info = first.ty.pointer_type.*;
                    if (ptr_info.mutability != .read_write) continue;
                    if (!typ.typesStructurallyEqual(ptr_info.child.*, ty)) continue;

                    return true;
                }
            }
        }
        return false;
    }

    fn functionIsTypeInitializerInit(
        self: *Semantizer,
        fd: *const sg.FunctionDeclaration,
        ty: sg.Type,
        current_file: []const u8,
    ) SemErr!bool {
        if (!std.mem.eql(u8, fd.name, "init")) return false;
        if (!(try self.functionIsVisible(fd, current_file))) return false;
        if (fd.input.fields.len == 0) return false;

        const first = fd.input.fields[0];
        if (!std.mem.eql(u8, first.name, "p")) return false;
        if (first.ty != .pointer_type) return false;

        const ptr_info = first.ty.pointer_type.*;
        if (ptr_info.mutability != .read_write) return false;
        return typ.typesStructurallyEqual(ptr_info.child.*, ty);
    }

    fn collectVisibleTypeInitializerSignatures(
        self: *Semantizer,
        ty: sg.Type,
        current_file: []const u8,
        s: *Scope,
    ) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        errdefer buf.deinit();

        var cur: ?*Scope = s;
        var first = true;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr("init")) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!(try self.functionIsTypeInitializerInit(cand, ty, current_file))) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try abs.appendFunctionSignature(&buf, cand, s);
                }
            }
        }

        if (first) try buf.appendSlice("  (none)");
        return try buf.toOwnedSlice();
    }

    fn compactTypeUsesParam(self: *Semantizer, node: syn.SyntaxRef, param: []const u8) bool {
        const file = self.syntaxFile(node);
        return switch (file.syntaxType(node.node) orelse return false) {
            .name => |name| name.qualifier_token == null and std.mem.eql(u8, file.tokenText(&self.diags.source_db, name.name_token), param),
            .pointer => |pointer| self.compactTypeUsesParam(file.ref(pointer.child), param),
            .nullable => |child| self.compactTypeUsesParam(file.ref(child), param),
            .inferred_errable => |child| self.compactTypeUsesParam(file.ref(child), param),
            .array => |array| self.compactTypeUsesParam(file.ref(array.element), param),
            .generic => |generic| blk: {
                if (self.compactTypeUsesParam(file.ref(generic.base), param)) break :blk true;
                const args = file.structTypeLiteral(generic.arguments) orelse break :blk false;
                for (args.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    if (field.type_node) |field_type| if (self.compactTypeUsesParam(file.ref(field_type), param)) break :blk true;
                    if (field.default_value) |value| if (self.syntaxExprUsesParam(file.ref(value), param)) break :blk true;
                }
                break :blk false;
            },
            .struct_literal => |literal| blk: {
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    if (field.type_node) |field_type| if (self.compactTypeUsesParam(file.ref(field_type), param)) break :blk true;
                }
                break :blk false;
            },
            .choice_literal => |literal| blk: {
                for (literal.variants) |variant_node| {
                    const variant = file.choiceTypeVariant(variant_node) orelse continue;
                    if (variant.payload_type) |payload| if (self.compactTypeUsesParam(file.ref(payload), param)) break :blk true;
                }
                break :blk false;
            },
        };
    }

    fn extractCompactTypeArgumentFromActual(
        self: *Semantizer,
        template: syn.SyntaxRef,
        actual: sg.Type,
        param: []const u8,
        s: *Scope,
    ) ?sg.Type {
        const file = self.syntaxFile(template);
        switch (file.syntaxType(template.node) orelse return null) {
            .name => |name| if (name.qualifier_token == null and std.mem.eql(u8, file.tokenText(&self.diags.source_db, name.name_token), param)) return actual,
            .pointer => |pointer| if (actual == .pointer_type) return self.extractCompactTypeArgumentFromActual(file.ref(pointer.child), actual.pointer_type.child.*, param, s),
            .nullable, .inferred_errable => |child| return self.extractCompactTypeArgumentFromActual(file.ref(child), actual, param, s),
            .array => |array| if (actual == .array_type) return self.extractCompactTypeArgumentFromActual(file.ref(array.element), actual.array_type.element_type.*, param, s),
            .struct_literal => |literal| if (actual == .struct_type) {
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    const field_type = field.type_node orelse continue;
                    const name = file.tokenText(&self.diags.source_db, field.name_token);
                    const actual_field = typ.findFieldByName(actual.struct_type, name) orelse continue;
                    if (self.extractCompactTypeArgumentFromActual(file.ref(field_type), actual_field.ty, param, s)) |result| return result;
                }
            },
            .generic => |generic| {
                const base = file.syntaxType(generic.base) orelse return null;
                if (base == .name and base.name.qualifier_token == null and
                    std.mem.eql(u8, file.tokenText(&self.diags.source_db, base.name.name_token), param) and
                    s.lookupAbstractInfo(param) != null) return actual;
                const identity = typ.genericIdentityOf(actual) orelse return null;
                if (base != .name or !std.mem.eql(u8, identity.base_name, file.tokenText(&self.diags.source_db, base.name.name_token))) return null;
                const args = file.structTypeLiteral(generic.arguments) orelse return null;
                for (args.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    const arg_type = field.type_node orelse continue;
                    if (!self.compactTypeUsesParam(file.ref(arg_type), param)) continue;
                    const value = typ.genericIdentityArgByName(identity, file.tokenText(&self.diags.source_db, field.name_token)) orelse continue;
                    if (value == .type) return value.type;
                }
            },
            else => {},
        }
        return null;
    }

    fn extractCompactIntArgumentFromActual(
        self: *Semantizer,
        template: syn.SyntaxRef,
        actual: sg.Type,
        param: []const u8,
        s: *Scope,
    ) ?i64 {
        const file = self.syntaxFile(template);
        switch (file.syntaxType(template.node) orelse return null) {
            .pointer => |pointer| if (actual == .pointer_type) return self.extractCompactIntArgumentFromActual(file.ref(pointer.child), actual.pointer_type.child.*, param, s),
            .struct_literal => |literal| if (actual == .struct_type) {
                for (literal.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    const field_type = field.type_node orelse continue;
                    const actual_field = typ.findFieldByName(actual.struct_type, file.tokenText(&self.diags.source_db, field.name_token)) orelse continue;
                    if (self.extractCompactIntArgumentFromActual(file.ref(field_type), actual_field.ty, param, s)) |value| return value;
                }
            },
            .generic => |generic| {
                const identity = typ.genericIdentityOf(actual) orelse return null;
                const base = file.syntaxType(generic.base) orelse return null;
                if (base != .name or !std.mem.eql(u8, identity.base_name, file.tokenText(&self.diags.source_db, base.name.name_token))) return null;
                const args = file.structTypeLiteral(generic.arguments) orelse return null;
                for (args.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse continue;
                    const expression = field.default_value orelse continue;
                    if (!self.syntaxExprUsesParam(file.ref(expression), param)) continue;
                    const value = typ.genericIdentityArgByName(identity, file.tokenText(&self.diags.source_db, field.name_token)) orelse continue;
                    if (value == .comptime_int) return value.comptime_int;
                }
            },
            else => {},
        }
        return null;
    }

    fn deriveElementTypeFromList(list_type: sg.Type) ?sg.Type {
        return switch (list_type) {
            .array_type => list_type.array_type.element_type.*,
            else => null,
        };
    }

    fn inferGenericArgFromCall(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        param: gen.GenericParam,
        call_input_ty: sg.Type,
        s: *Scope,
        subst: *GenericSubst,
    ) ?gen.GenericArgValue {
        if (call_input_ty != .struct_type) return null;
        const actual = call_input_ty.struct_type;
        const template_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const input = template_file.structTypeLiteral(tmpl.input) orelse return null;
        for (input.fields) |field_node| {
            const field = template_file.structTypeField(field_node) orelse continue;
            const type_node = field.type_node orelse continue;
            const type_ref = template_file.ref(type_node);
            if (!self.compactTypeUsesParam(type_ref, param.name)) continue;
            const field_name = template_file.tokenText(tmpl.source_db, field.name_token);
            if (typ.findFieldByName(actual, field_name)) |actual_field| {
                switch (param.kind) {
                    .type => {
                        if (self.extractCompactTypeArgumentFromActual(type_ref, actual_field.ty, param.name, s)) |res|
                            return .{ .type = res };
                    },
                    .comptime_int => {
                        if (self.extractCompactIntArgumentFromActual(type_ref, actual_field.ty, param.name, s)) |res|
                            return .{ .comptime_int = res };
                    },
                }
            }
        }

        // Heuristic: derive element type when list_type already inferred.
        if (param.kind == .type and std.mem.eql(u8, param.name, "list_value_type")) {
            if (subst.types.get("list_type")) |list_ty| {
                if (deriveElementTypeFromList(list_ty)) |elem_ty| return .{ .type = elem_ty };
            }
        }

        return null;
    }

    fn inferGenericArgFromInitTemplate(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        param: gen.GenericParam,
        init_input_ty: sg.Type,
        s: *Scope,
    ) ?gen.GenericArgValue {
        if (init_input_ty != .struct_type) return null;
        const actual = init_input_ty.struct_type;
        const file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const input = file.structTypeLiteral(tmpl.input) orelse return null;
        if (input.fields.len == 0) return null;

        for (input.fields[1..]) |field_node| {
            const fld = file.structTypeField(field_node) orelse continue;
            const ty_node = file.ref(fld.type_node orelse continue);
            if (!self.compactTypeUsesParam(ty_node, param.name)) continue;
            if (typ.findFieldByName(actual, file.tokenText(tmpl.source_db, fld.name_token))) |actual_field| {
                switch (param.kind) {
                    .type => {
                        if (self.extractCompactTypeArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
                            return .{ .type = res };
                    },
                    .comptime_int => {
                        if (self.extractCompactIntArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
                            return .{ .comptime_int = res };
                    },
                }
            }
        }

        return null;
    }

    fn initializerMatchesInitTemplate(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        init_input_ty: sg.Type,
        subst: *const GenericSubst,
        s: *Scope,
    ) SemErr!bool {
        if (init_input_ty != .struct_type) return false;
        const file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const input = file.structTypeLiteral(tmpl.input) orelse return false;
        if (input.fields.len == 0) return false;
        const actual = init_input_ty.struct_type;

        for (actual.fields) |actual_field| {
            var idx: ?usize = null;
            for (input.fields, 0..) |field_node, field_idx| {
                const field = file.structTypeField(field_node) orelse continue;
                if (std.mem.eql(u8, file.tokenText(tmpl.source_db, field.name_token), actual_field.name)) {
                    idx = field_idx;
                    break;
                }
            }
            if (idx == null or idx.? == 0) return false;
            const expected_field = file.structTypeField(input.fields[idx.?]).?;
            const expected_field_ty = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(expected_field.type_node.?), s, subst);
            if (fld_matches: {
                if (typ.typesExactlyEqual(expected_field_ty, actual_field.ty)) break :fld_matches true;
                if (typ.typesStructurallyEqual(expected_field_ty, actual_field.ty)) break :fld_matches true;
                if (typ.typesCompatible(expected_field_ty, actual_field.ty)) break :fld_matches true;
                break :fld_matches false;
            }) continue;
            return false;
        }

        return true;
    }

    fn instantiateGenericTypeFromInitializer(
        self: *Semantizer,
        name: []const u8,
        init_input_ty: sg.Type,
        s: *Scope,
    ) SemErr!?sg.Type {
        var chosen: ?sg.Type = null;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr("init")) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .regular) continue;
                    const file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
                    const input = file.structTypeLiteral(tmpl.input) orelse continue;
                    if (input.fields.len == 0) continue;
                    const first = file.structTypeField(input.fields[0]) orelse continue;
                    const first_type = file.syntaxType(first.type_node orelse continue) orelse continue;
                    if (first_type != .pointer) continue;
                    const target = file.syntaxType(first_type.pointer.child) orelse continue;
                    if (target != .generic) continue;
                    const base = file.syntaxType(target.generic.base) orelse continue;
                    if (base != .name or !std.mem.eql(u8, file.tokenText(tmpl.source_db, base.name.name_token), name)) continue;

                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();

                    var ok = true;
                    for (tmpl.params) |param| {
                        const inferred = self.inferGenericArgFromInitTemplate(tmpl, param, init_input_ty, s) orelse {
                            ok = false;
                            break;
                        };
                        try self.putGenericArg(&subst, param, inferred);
                    }
                    if (!ok) continue;
                    if (!(try self.initializerMatchesInitTemplate(tmpl, init_input_ty, &subst, s))) continue;

                    const candidate = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(first_type.pointer.child), s, &subst);
                    if (chosen) |existing| {
                        if (!typ.typesExactlyEqual(existing, candidate)) return error.AmbiguousOverload;
                    } else {
                        chosen = candidate;
                    }
                }
            }
        }

        return chosen;
    }

    fn refinedStructTypeWithActual(
        self: *Semantizer,
        expected_ptr: *const sg.StructType,
        actual_ty: sg.Type,
        s: *Scope,
    ) !?*sg.StructType {
        if (actual_ty != .struct_type) return null;
        const actual = actual_ty.struct_type;

        const expected_fields = expected_ptr.fields;
        // These refined structs are an internal dispatch artifact, not user-visible
        // nominal types. We tried caching/canonicalizing them by
        // `(expected_ptr, actual_ty)` to reduce allocations, but the measured
        // `semantizing` times regressed on representative cases:
        // `01_cat_cli` 243.9 ms -> 263.3 ms,
        // `23_file_system_read_write` 191.1 ms -> 204.7 ms,
        // `01_minimal_main` 128.5 ms -> 184.9 ms.
        // Keep this path simple unless a more targeted representation proves
        // faster with data.
        const refined = try self.allocator.alloc(sg.StructTypeField, expected_fields.len);
        var changed = false;

        var idx: usize = 0;
        while (idx < expected_fields.len) : (idx += 1) {
            const exp_field = expected_fields[idx];
            const actual_field_ptr = typ.findFieldByName(actual, exp_field.name);

            var final_ty = exp_field.ty;

            if (actual_field_ptr) |af| {
                const actual_ty_field = af.ty;
                if (typ.typesStructurallyEqual(exp_field.ty, actual_ty_field)) {
                    if (!typ.typesExactlyEqual(exp_field.ty, actual_ty_field)) {
                        final_ty = actual_ty_field;
                        changed = true;
                    }
                } else if (typ.isAny(exp_field.ty)) {
                    final_ty = actual_ty_field;
                    changed = true;
                } else if (abs.typesCompatibleForDispatch(exp_field.ty, actual_ty_field, s)) {
                    final_ty = actual_ty_field;
                    changed = true;
                }
            } else {
                if (exp_field.default_value == null) {
                    return null;
                }
            }

            refined[idx] = .{
                .name = exp_field.name,
                .ty = final_ty,
                .default_value = exp_field.default_value,
            };
        }

        if (!changed) return @constCast(expected_ptr);

        const refined_ptr = try self.allocator.create(sg.StructType);
        refined_ptr.* = .{ .fields = refined };
        return refined_ptr;
    }

    fn instantiateGenericNamed(
        self: *Semantizer,
        name: []const u8,
        stargs: ?syn.SyntaxRef,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
    ) SemErr!*sg.FunctionDeclaration {
        return self.instantiateGenericNamedVisible(name, stargs, call_input, s, allowed_kind, null, null);
    }

    fn instantiateGenericNamedVisible(
        self: *Semantizer,
        name: []const u8,
        stargs: ?syn.SyntaxRef,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
        module_dir_filter: ?[]const u8,
        requester_file: ?[]const u8,
    ) SemErr!*sg.FunctionDeclaration {
        var best: ?PreparedGenericTemplateCandidate = null;
        var ambiguous = false;
        // Some visible templates may still depend on unresolved top-level state
        // and report UnknownType while a different template already matches the
        // call. Keep those as "pending" noise instead of letting them hide an
        // already-valid candidate. If nothing matches, the unknown still
        // propagates so staged semantizing can retry later.
        var has_unknown_candidate = false;
        defer if (best) |*prepared| prepared.deinit();

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != allowed_kind) continue;
                    if (module_dir_filter) |module_dir| {
                        if (!std.mem.startsWith(u8, self.locationPath(tmpl.location), module_dir)) continue;
                        if (requester_file) |requester| {
                            if (isPrivateName(name)) {
                                const requester_dir = self.moduleDirForFile(requester);
                                if (!std.mem.eql(u8, requester_dir, module_dir)) continue;
                            }
                        }
                    }
                    var subst = GenericSubst.init(self.allocator);
                    const dispatch_input = self.materializeTemplateReachDefaultsForDispatch(tmpl, call_input, s) catch |err| switch (err) {
                        error.UnknownType, error.SymbolNotFound => {
                            has_unknown_candidate = true;
                            subst.deinit();
                            continue;
                        },
                        else => return err,
                    };

                    var ok: bool = true;
                    for (tmpl.params) |param| {
                        var found: bool = false;
                        if (stargs) |arguments_ref| {
                            const arguments_file = self.syntaxFile(arguments_ref);
                            const arguments = arguments_file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
                            for (arguments.fields) |field_node| {
                                const field = arguments_file.structTypeField(field_node) orelse return error.InvalidType;
                                const field_name = arguments_file.tokenText(&self.diags.source_db, field.name_token);
                                if (std.mem.eql(u8, field_name, param.name)) {
                                    const resolved = try self.resolveExplicitGenericArg(arguments_file.ref(field_node), param, s, &subst);
                                    try self.putGenericArg(&subst, param, resolved);
                                    found = true;
                                    break;
                                }
                            }
                        }
                        if (!found) {
                            if (self.inferGenericArgFromCall(tmpl, param, dispatch_input.ty, s, &subst) orelse
                                try self.inferGenericArgFromAbstractConstraints(tmpl, param, s, &subst)) |inferred|
                            {
                                try self.putGenericArg(&subst, param, inferred);
                                found = true;
                            }
                        }
                        if (!found) {
                            ok = false;
                            break;
                        }
                    }
                    if (!ok) {
                        subst.deinit();
                        continue;
                    }
                    if (!try self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) {
                        subst.deinit();
                        continue;
                    }

                    const score = self.templateInstantiationDispatchScore(tmpl, dispatch_input, s, &subst) catch |err| switch (err) {
                        error.UnknownType, error.SymbolNotFound => {
                            has_unknown_candidate = true;
                            subst.deinit();
                            continue;
                        },
                        else => return err,
                    } orelse {
                        subst.deinit();
                        continue;
                    };
                    if (best) |*current_best| {
                        if (self.chooseBetterPreparedTemplateCandidate(current_best, score)) {
                            current_best.deinit();
                            current_best.* = .{
                                .tmpl = tmpl,
                                .subst = subst,
                                .dispatch_input = dispatch_input,
                                .score = score,
                            };
                            ambiguous = false;
                        } else if (score == current_best.score) {
                            subst.deinit();
                            ambiguous = true;
                        } else {
                            subst.deinit();
                        }
                    } else {
                        best = .{
                            .tmpl = tmpl,
                            .subst = subst,
                            .dispatch_input = dispatch_input,
                            .score = score,
                        };
                        ambiguous = false;
                    }
                }
            }
        }

        if (ambiguous) return error.AmbiguousOverload;
        if (best) |*prepared| {
            return (try self.instantiateGenericTemplate(name, prepared.tmpl, prepared.dispatch_input, s, &prepared.subst)).?;
        }
        if (has_unknown_candidate) return error.UnknownType;
        return error.SymbolNotFound;
    }

    fn materializeTemplateReachDefaultsForDispatch(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        call_input: typ.TypedExpr,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (call_input.ty != .struct_type or call_input.node.content != .struct_value_literal) return call_input;

        const actual_struct = call_input.ty.struct_type;
        const actual_value = call_input.node.content.struct_value_literal;
        const positional_prefix: usize = @min(actual_value.dispatch_prefix_positional_count, actual_value.fields.len);

        var changed = false;
        var args = std.array_list.Managed(CallArg).init(self.allocator.*);
        defer args.deinit();

        for (actual_value.fields, 0..) |field, idx| {
            try args.append(.{
                .name = field.name,
                .expr = .{
                    .node = @constCast(field.value),
                    .ty = actual_struct.fields[idx].ty,
                },
            });
        }

        const template_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        const template_input = template_file.structTypeLiteral(tmpl.input) orelse return error.InvalidType;
        var empty_subst = GenericSubst.init(self.allocator);
        defer empty_subst.deinit();
        for (template_input.fields) |field_node| {
            const field = template_file.structTypeField(field_node) orelse return error.InvalidType;
            const field_name = template_file.tokenText(tmpl.source_db, field.name_token);
            if (findStructValueFieldByNameFrom(actual_value.fields, positional_prefix, field_name) != null) continue;
            const default_node = field.default_value orelse continue;
            if (template_file.tag(default_node) != .reach_directive) continue;
            const field_type = field.type_node orelse continue;

            const reach_ref = template_file.ref(default_node);
            const reach_te = try self.visitNode(reach_ref, s);
            if (reach_te.node.content != .reach_directive) continue;

            const dispatch_ty = self.resolveSyntaxTypeWithSubstPreservingAbstracts(template_file.ref(field_type), s, &empty_subst) catch |err| switch (err) {
                error.UnknownType => {
                    if (try self.resolveReachedArgumentForInference(
                        field_name,
                        reach_te.node.content.reach_directive,
                        s,
                        template_file.location(default_node),
                    )) |resolved_for_inference| {
                        try args.append(.{
                            .name = field_name,
                            .expr = resolved_for_inference,
                        });
                        changed = true;
                    }
                    continue;
                },
                else => return err,
            };

            const resolved = try self.tryResolveReachedArgumentInLocalScope(
                field_name,
                dispatch_ty,
                reach_te.node.content.reach_directive,
                s,
                template_file.location(default_node),
            ) orelse blk: {
                if (self.currentReachFunctionContext()) |ctx| {
                    if (!std.mem.eql(u8, ctx.function_name, "main")) {
                        const placeholder = try sg.makeSGNode(
                            .{ .reach_directive = reach_te.node.content.reach_directive },
                            template_file.location(default_node),
                            self.allocator,
                        );
                        placeholder.sem_type = dispatch_ty;
                        break :blk typ.TypedExpr{
                            .node = placeholder,
                            .ty = dispatch_ty,
                        };
                    }
                }
                continue;
            };
            try args.append(.{
                .name = field_name,
                .expr = resolved,
            });
            changed = true;
        }

        if (!changed) return call_input;
        return self.buildCallInputWithPositionalPrefix(args.items, @intCast(positional_prefix));
    }

    fn instantiateGenericVisible(
        self: *Semantizer,
        name: []const u8,
        owner: syn.SyntaxRef,
        type_args_syn: []const syn.NodeIndex,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
        module_dir_filter: ?[]const u8,
        requester_file: ?[]const u8,
    ) SemErr!*sg.FunctionDeclaration {
        var best: ?PreparedGenericTemplateCandidate = null;
        var ambiguous = false;
        defer if (best) |*prepared| prepared.deinit();

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != allowed_kind) continue;
                    if (module_dir_filter) |module_dir| {
                        if (!std.mem.startsWith(u8, self.locationPath(tmpl.location), module_dir)) continue;
                        if (requester_file) |requester| {
                            if (isPrivateName(name)) {
                                const requester_dir = self.moduleDirForFile(requester);
                                if (!std.mem.eql(u8, requester_dir, module_dir)) continue;
                            }
                        }
                    }
                    if (tmpl.params.len != type_args_syn.len) continue;

                    var subst = GenericSubst.init(self.allocator);
                    var i: usize = 0;
                    while (i < tmpl.params.len) : (i += 1) {
                        if (tmpl.params[i].kind != .type) continue;
                        const resolved = try self.resolveSyntaxTypeWithMode(self.childRef(owner, type_args_syn[i]), s, false, &subst);
                        try subst.types.put(tmpl.params[i].name, resolved);
                    }
                    if (!try self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) {
                        subst.deinit();
                        continue;
                    }
                    const score = try self.templateInstantiationDispatchScore(tmpl, call_input, s, &subst) orelse {
                        subst.deinit();
                        continue;
                    };

                    if (best) |*current_best| {
                        if (self.chooseBetterPreparedTemplateCandidate(current_best, score)) {
                            current_best.deinit();
                            current_best.* = .{
                                .tmpl = tmpl,
                                .subst = subst,
                                .dispatch_input = call_input,
                                .score = score,
                            };
                            ambiguous = false;
                        } else if (score == current_best.score) {
                            subst.deinit();
                            ambiguous = true;
                        } else {
                            subst.deinit();
                        }
                    } else {
                        best = .{
                            .tmpl = tmpl,
                            .subst = subst,
                            .dispatch_input = call_input,
                            .score = score,
                        };
                        ambiguous = false;
                    }
                }
            }
        }

        if (ambiguous) return error.AmbiguousOverload;
        if (best) |*prepared| {
            return (try self.instantiateGenericTemplate(name, prepared.tmpl, prepared.dispatch_input, s, &prepared.subst)).?;
        }
        return error.SymbolNotFound;
    }

    fn substSatisfiesAbstractConstraints(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        subst: *GenericSubst,
        s: *Scope,
    ) SemErr!bool {
        var i: usize = 0;
        while (i < tmpl.params.len) : (i += 1) {
            const constraint = tmpl.param_abstract_constraints[i] orelse continue;
            const actual = subst.types.get(tmpl.params[i].name) orelse return false;
            if (!try self.abstractConstraintMatches(actual, constraint, s, subst)) return false;
        }
        return true;
    }

    fn abstractConstraintMatches(
        self: *Semantizer,
        concrete: sg.Type,
        constraint: gen.AbstractConstraint,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!bool {
        const resolution = try self.resolveAbstract(concrete, constraint.name, s);
        switch (resolution) {
            .none, .conflicting => return false,
            .unique => |args| {
                defer self.allocator.free(args);
                const requested = constraint.args orelse return true;
                const info = s.lookupAbstractInfo(constraint.name) orelse return false;
                const requested_file = self.syntaxFile(requested);
                const requested_literal = requested_file.structTypeLiteral(requested.node) orelse return false;
                for (requested_literal.fields) |field_node| {
                    const field = requested_file.structTypeField(field_node) orelse return false;
                    const field_name = requested_file.tokenText(&self.diags.source_db, field.name_token);
                    var arg_index: ?usize = null;
                    for (info.params, 0..) |param, index| {
                        if (std.mem.eql(u8, param.name, field_name)) {
                            arg_index = index;
                            break;
                        }
                    }
                    const index = arg_index orelse return false;
                    if (index >= args.len) return false;
                    const associated = args[index] orelse return false;
                    switch (info.params[index].kind) {
                        .type => {
                            const requested_ty = field.type_node orelse return false;
                            const expected = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(
                                requested_file.ref(requested_ty),
                                s,
                                subst,
                            );
                            if (associated != .type or !typ.typesExactlyEqual(expected, associated.type)) return false;
                        },
                        .comptime_int => {
                            const requested_value = field.default_value orelse return false;
                            const expected = try self.resolveComptimeIntExpr(requested_file.ref(requested_value), s, subst);
                            if (associated != .comptime_int or expected != associated.comptime_int) return false;
                        },
                    }
                }
                return true;
            },
        }
    }

    fn inferGenericArgFromAbstractConstraints(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        requested_param: gen.GenericParam,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!?gen.GenericArgValue {
        return self.inferGenericArgFromConstraintAssociations(
            tmpl.params,
            tmpl.param_abstract_constraints,
            requested_param,
            s,
            subst,
        );
    }

    fn inferGenericArgFromConstraintAssociations(
        self: *Semantizer,
        params: []const gen.GenericParam,
        constraints: []const ?gen.AbstractConstraint,
        requested_param: gen.GenericParam,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!?gen.GenericArgValue {
        for (params, 0..) |constrained_param, index| {
            if (constrained_param.kind != .type) continue;
            const constraint = constraints[index] orelse continue;
            const args = constraint.args orelse continue;
            const concrete = subst.types.get(constrained_param.name) orelse continue;
            const info = s.lookupAbstractInfo(constraint.name) orelse continue;

            const args_file = self.syntaxFile(args);
            const args_literal = args_file.structTypeLiteral(args.node) orelse continue;
            for (args_literal.fields) |field_node| {
                const field = args_file.structTypeField(field_node) orelse continue;
                const field_name = args_file.tokenText(&self.diags.source_db, field.name_token);
                const uses_requested = switch (requested_param.kind) {
                    .type => blk: {
                        const arg_type_node = field.type_node orelse break :blk false;
                        const arg_type = args_file.syntaxType(arg_type_node) orelse break :blk false;
                        break :blk switch (arg_type) {
                            .name => |name| std.mem.eql(
                                u8,
                                args_file.tokenText(&self.diags.source_db, name.name_token),
                                requested_param.name,
                            ),
                            else => false,
                        };
                    },
                    .comptime_int => if (field.default_value) |value|
                        self.syntaxExprUsesParam(args_file.ref(value), requested_param.name)
                    else
                        false,
                };
                if (!uses_requested) continue;

                var abstract_param_index: ?usize = null;
                for (info.params, 0..) |abstract_param, param_index| {
                    if (std.mem.eql(u8, abstract_param.name, field_name)) {
                        abstract_param_index = param_index;
                        break;
                    }
                }
                const param_index = abstract_param_index orelse continue;
                const resolution = try self.resolveAbstract(concrete, constraint.name, s);
                const inferred = switch (resolution) {
                    .none, .conflicting => continue,
                    .unique => |resolved| resolved,
                };
                defer self.allocator.free(inferred);
                const inferred_value = inferred[param_index] orelse continue;
                switch (requested_param.kind) {
                    .type => if (inferred_value != .type) continue,
                    .comptime_int => if (inferred_value != .comptime_int) continue,
                }
                return inferred_value;
            }
        }
        return null;
    }

    const AbstractResolution = union(enum) {
        none,
        unique: []?gen.GenericArgValue,
        conflicting,
    };

    fn typeImplementsAbstract(
        self: *Semantizer,
        concrete: sg.Type,
        abstract_name: []const u8,
        s: *Scope,
    ) SemErr!bool {
        const resolution = try self.resolveAbstract(concrete, abstract_name, s);
        return switch (resolution) {
            .none, .conflicting => false,
            .unique => |args| blk: {
                self.allocator.free(args);
                break :blk true;
            },
        };
    }

    fn genericArgValuesEqual(a: gen.GenericArgValue, b: gen.GenericArgValue) bool {
        return switch (a) {
            .type => |left| switch (b) {
                .type => |right| typ.typesExactlyEqual(left, right),
                else => false,
            },
            .comptime_int => |left| switch (b) {
                .comptime_int => |right| left == right,
                else => false,
            },
        };
    }

    fn associatedArgsEqual(a: []const ?gen.GenericArgValue, b: []const ?gen.GenericArgValue) bool {
        if (a.len != b.len) return false;
        for (a, b) |left, right| {
            if (left == null or right == null) {
                if (left != null or right != null) return false;
                continue;
            }
            if (!genericArgValuesEqual(left.?, right.?)) return false;
        }
        return true;
    }

    fn mergeAbstractResolution(
        self: *Semantizer,
        chosen: *?[]?gen.GenericArgValue,
        candidate: []?gen.GenericArgValue,
    ) bool {
        if (chosen.*) |current| {
            if (!associatedArgsEqual(current, candidate)) {
                self.allocator.free(candidate);
                return false;
            }
            self.allocator.free(candidate);
        } else {
            chosen.* = candidate;
        }
        return true;
    }

    // Abstract parameters are associated compile-time information: resolution
    // starts from Self and must produce one unique argument vector. Multiple
    // proof paths are valid only when they agree on that vector.
    fn resolveAbstract(
        self: *Semantizer,
        concrete: sg.Type,
        abstract_name: []const u8,
        s: *Scope,
    ) SemErr!AbstractResolution {
        const info = s.lookupAbstractInfo(abstract_name) orelse return .none;
        var chosen: ?[]?gen.GenericArgValue = null;
        errdefer if (chosen) |args| self.allocator.free(args);

        if (concrete == .abstract_type and
            std.mem.eql(u8, concrete.abstract_type.name, abstract_name) and
            info.params.len == 0)
        {
            chosen = try self.allocator.alloc(?gen.GenericArgValue, 0);
        }

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.abstract_impls.getPtr(abstract_name)) |entries| {
                for (entries.items) |entry| {
                    if (!typ.typesExactlyEqual(entry.ty, concrete)) {
                        if (entry.ty != .abstract_type) continue;
                        const inherited = try self.resolveAbstract(concrete, entry.ty.abstract_type.name, s);
                        switch (inherited) {
                            .none => continue,
                            .conflicting => {
                                if (chosen) |args| self.allocator.free(args);
                                return .conflicting;
                            },
                            .unique => |args| self.allocator.free(args),
                        }
                    }
                    if (entry.args.len != info.params.len) continue;
                    const candidate = try self.allocator.dupe(?gen.GenericArgValue, entry.args);
                    if (!self.mergeAbstractResolution(&chosen, candidate)) {
                        if (chosen) |args| self.allocator.free(args);
                        return .conflicting;
                    }
                }
            }

            if (sc.abstract_impl_templates.getPtr(abstract_name)) |templates| {
                for (templates.items) |tmpl| {
                    var bindings = abs.matchAbstractImplTemplate(tmpl, concrete, self.allocator) orelse continue;
                    defer bindings.deinit();

                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();
                    var type_it = bindings.types.iterator();
                    while (type_it.next()) |entry| try subst.types.put(entry.key_ptr.*, entry.value_ptr.*);
                    var int_it = bindings.ints.iterator();
                    while (int_it.next()) |entry| try subst.ints.put(entry.key_ptr.*, entry.value_ptr.*);

                    var made_progress = true;
                    while (made_progress) {
                        made_progress = false;
                        for (tmpl.params) |param| {
                            const already_bound = switch (param.kind) {
                                .type => subst.types.contains(param.name),
                                .comptime_int => subst.ints.contains(param.name),
                            };
                            if (already_bound) continue;
                            const inferred = try self.inferGenericArgFromConstraintAssociations(
                                tmpl.params,
                                tmpl.param_abstract_constraints,
                                param,
                                s,
                                &subst,
                            ) orelse continue;
                            try self.putGenericArg(&subst, param, inferred);
                            made_progress = true;
                        }
                    }

                    var constraints_hold = true;
                    for (tmpl.param_abstract_constraints, 0..) |constraint_opt, index| {
                        const constraint = constraint_opt orelse continue;
                        const param = tmpl.params[index];
                        if (param.kind != .type) continue;
                        const actual = subst.types.get(param.name) orelse {
                            constraints_hold = false;
                            break;
                        };
                        if (!try self.abstractConstraintMatches(actual, constraint, s, &subst)) {
                            constraints_hold = false;
                            break;
                        }
                    }
                    if (!constraints_hold) continue;

                    const args = tmpl.args orelse {
                        if (info.params.len == 0) {
                            const candidate = try self.allocator.alloc(?gen.GenericArgValue, 0);
                            if (!self.mergeAbstractResolution(&chosen, candidate)) {
                                if (chosen) |selected| self.allocator.free(selected);
                                return .conflicting;
                            }
                        }
                        continue;
                    };
                    const resolved = try self.allocator.alloc(?gen.GenericArgValue, info.params.len);
                    errdefer self.allocator.free(resolved);
                    for (resolved) |*arg| arg.* = null;
                    const args_file = self.syntaxFile(args);
                    const args_literal = args_file.structTypeLiteral(args.node) orelse continue;
                    for (args_literal.fields) |field_node| {
                        const field = args_file.structTypeField(field_node) orelse continue;
                        const field_name = args_file.tokenText(&self.diags.source_db, field.name_token);
                        var param_index: ?usize = null;
                        for (info.params, 0..) |abstract_param, index| {
                            if (std.mem.eql(u8, abstract_param.name, field_name)) {
                                param_index = index;
                                break;
                            }
                        }
                        const index = param_index orelse continue;
                        resolved[index] = switch (info.params[index].kind) {
                            .type => .{ .type = self.resolveSyntaxTypeWithSubstPreservingAbstracts(args_file.ref(field.type_node orelse continue), s, &subst) catch |err| switch (err) {
                                error.UnknownType, error.SymbolNotFound => null,
                                else => return err,
                            } orelse continue },
                            .comptime_int => .{ .comptime_int = self.resolveComptimeIntExpr(args_file.ref(field.default_value orelse continue), s, &subst) catch |err| switch (err) {
                                error.UnknownType, error.SymbolNotFound => null,
                                else => return err,
                            } orelse continue },
                        };
                    }
                    var complete = true;
                    for (resolved) |arg| {
                        if (arg == null) {
                            complete = false;
                            break;
                        }
                    }
                    if (!complete) {
                        self.allocator.free(resolved);
                        continue;
                    }
                    if (!self.mergeAbstractResolution(&chosen, resolved)) {
                        if (chosen) |selected| self.allocator.free(selected);
                        return .conflicting;
                    }
                }
            }
        }
        if (chosen) |args| return .{ .unique = args };
        return .none;
    }

    fn instantiateGenericTemplate(
        self: *Semantizer,
        name: []const u8,
        tmpl: gen.GenericTemplate,
        call_input: typ.TypedExpr,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!?*sg.FunctionDeclaration {
        const template_file = &tmpl.syntax_files[@intFromEnum(tmpl.syntax_file_id)];
        var in_struct_ptr = try self.structTypeFromNodeWithSubst(template_file.ref(tmpl.input), s, subst);

        if (try self.refinedStructTypeWithActual(in_struct_ptr, call_input.ty, s)) |refined| {
            in_struct_ptr = refined;
        }
        if (!self.callInputMatchesDispatch(in_struct_ptr, call_input, s)) return null;

        const out_struct_ptr = try self.structTypeFromNodeWithSubst(template_file.ref(tmpl.output), s, subst);
        if (self.findGenericSpecialization(tmpl, in_struct_ptr, out_struct_ptr, subst)) |existing| {
            self.generic_specialization_cache_hits += 1;
            return existing;
        }

        const fn_ptr = try self.allocator.create(sg.FunctionDeclaration);
        fn_ptr.* = .{
            .id = self.freshFunctionId(),
            .name = tmpl.name,
            .location = tmpl.location,
            .origin_kind = .generic_instantiation,
            .safety_primitive = self.safetyPrimitiveForDeclaration(tmpl.name, self.locationPath(tmpl.location)),
            .is_deinit = std.mem.eql(u8, tmpl.name, "deinit"),
            .generic_dispatch_kind = switch (tmpl.dispatch_kind) {
                .regular => .regular,
                .abstract_contract => .abstract_contract,
            },
            .is_once = false,
            .input = in_struct_ptr.*,
            .output = out_struct_ptr.*,
            .body = null,
            .has_declared_body = tmpl.body != null,
        };

        var child = try Scope.init(self.allocator, s, s.current_fn);
        child.current_fn = fn_ptr;
        var it = subst.types.iterator();
        while (it.next()) |entry| {
            const td = try self.allocator.create(sg.TypeDeclaration);
            td.* = .{ .name = entry.key_ptr.*, .origin_file = self.locationPath(tmpl.location), .ty = entry.value_ptr.* };
            try child.types.put(entry.key_ptr.*, td);
        }
        var it_int = subst.ints.iterator();
        while (it_int.next()) |entry| {
            try child.generic_values.put(entry.key_ptr.*, .{
                .ty = .{ .builtin = .UIntNative },
                .value = .{ .comptime_int = entry.value_ptr.* },
            });
        }

        var input_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        for (in_struct_ptr.fields) |fld| {
            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{ .name = fld.name, .location = tmpl.location, .origin_file = self.locationPath(tmpl.location), .mutability = .variable, .ty = fld.ty, .initialization = null };
            try child.bindings.put(fld.name, bd);
            try input_bindings.append(bd);
        }
        var output_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        for (out_struct_ptr.fields) |fld| {
            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{ .name = fld.name, .location = tmpl.location, .origin_file = self.locationPath(tmpl.location), .mutability = .variable, .ty = fld.ty, .initialization = null };
            try child.bindings.put(fld.name, bd);
            try output_bindings.append(bd);
        }

        var body_cb: ?*sg.CodeBlock = null;
        if (tmpl.body) |body_node| {
            try self.function_reach_stack.append(.{
                .function_name = tmpl.name,
                .location = tmpl.location,
                .input_struct = in_struct_ptr,
                .body_scope = &child,
            });
            defer _ = self.function_reach_stack.pop();
            const body_te = try self.visitNode(body_node, &child);
            body_cb = body_te.node.content.code_block;
        }

        fn_ptr.input = in_struct_ptr.*;
        fn_ptr.input_bindings = try input_bindings.toOwnedSlice();
        fn_ptr.output_bindings = try output_bindings.toOwnedSlice();
        fn_ptr.body = body_cb;

        try s.appendFunction(name, fn_ptr);
        const node = try sg.makeSGNode(.{ .function_declaration = fn_ptr }, tmpl.location, self.allocator);
        try self.root_list.append(node);
        try self.cacheGenericSpecialization(tmpl, in_struct_ptr, out_struct_ptr, subst, fn_ptr);
        self.generic_specializations_created += 1;
        self.clearDeferred(&child);
        return fn_ptr;
    }

    fn clearGenericSpecializationCache(self: *Semantizer) void {
        for (self.generic_specializations.items) |*specialization| specialization.deinit();
        self.generic_specializations.items.len = 0;
    }

    // Specializations are shared across sibling call-site scopes. Generic
    // substitutions retain nominal identity because the specialized body may
    // have resolved different overloads for structurally identical types.
    fn genericSubstitutionsEqual(a: *const GenericSubst, b: *const GenericSubst) bool {
        if (a.types.count() != b.types.count() or a.ints.count() != b.ints.count()) return false;

        var type_it = a.types.iterator();
        while (type_it.next()) |entry| {
            const other = b.types.get(entry.key_ptr.*) orelse return false;
            if (!typ.typesExactlyEqual(entry.value_ptr.*, other)) return false;
        }

        var int_it = a.ints.iterator();
        while (int_it.next()) |entry| {
            const other = b.ints.get(entry.key_ptr.*) orelse return false;
            if (entry.value_ptr.* != other) return false;
        }
        return true;
    }

    fn optionalTypesExactlyEqual(a: ?sg.Type, b: ?sg.Type) bool {
        if (a == null and b == null) return true;
        if (a == null or b == null) return false;
        return typ.typesExactlyEqual(a.?, b.?);
    }

    // Input and output structs are rebuilt at each instantiation attempt, so
    // their container pointers are not identities. Their layout and fields are
    // the specialization signature; nested field types remain nominal.
    fn genericSignatureStructsEqual(a: *const sg.StructType, b: *const sg.StructType) bool {
        if (a.layout != b.layout or a.fields.len != b.fields.len) return false;
        for (a.fields, b.fields) |a_field, b_field| {
            if (!std.mem.eql(u8, a_field.name, b_field.name)) return false;
            if (!typ.typesExactlyEqual(a_field.ty, b_field.ty)) return false;
            if (!optionalTypesExactlyEqual(a_field.storage_type, b_field.storage_type)) return false;
        }
        return true;
    }

    fn findGenericSpecialization(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        input: *const sg.StructType,
        output: *const sg.StructType,
        subst: *const GenericSubst,
    ) ?*sg.FunctionDeclaration {
        for (self.generic_specializations.items) |*specialization| {
            if (specialization.dispatch_kind != tmpl.dispatch_kind) continue;
            if (!std.mem.eql(u8, specialization.template_name, tmpl.name)) continue;
            if (specialization.template_location.offset != tmpl.location.offset or
                specialization.template_location.file != tmpl.location.file) continue;
            if (!genericSubstitutionsEqual(&specialization.subst, subst)) continue;
            if (!genericSignatureStructsEqual(specialization.input, input)) continue;
            if (!genericSignatureStructsEqual(specialization.output, output)) continue;
            return specialization.function;
        }
        return null;
    }

    fn cacheGenericSpecialization(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        input: *const sg.StructType,
        output: *const sg.StructType,
        subst: *const GenericSubst,
        function: *sg.FunctionDeclaration,
    ) !void {
        var owned_subst = GenericSubst.init(self.allocator);
        errdefer owned_subst.deinit();
        try owned_subst.cloneFrom(subst);
        try self.generic_specializations.append(.{
            .template_name = tmpl.name,
            .template_location = tmpl.location,
            .dispatch_kind = tmpl.dispatch_kind,
            .input = input,
            .output = output,
            .subst = owned_subst,
            .function = function,
        });
    }

    fn instantiateCompactGenericTypeNamed(
        self: *Semantizer,
        name: []const u8,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
        outer_subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        const arguments_file = self.syntaxFile(arguments_ref);
        const arguments = arguments_file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
        var cur: ?*Scope = s;
        while (cur) |scope| : (cur = scope.parent) {
            const templates = scope.generic_types.getPtr(name) orelse continue;
            for (templates.items) |template| {
                var subst = GenericSubst.init(self.allocator);
                defer subst.deinit();
                if (outer_subst) |outer| try subst.cloneFrom(outer);

                var complete = true;
                for (template.params) |param| {
                    var found = false;
                    for (arguments.fields) |field_node| {
                        const field = arguments_file.structTypeField(field_node) orelse return error.InvalidType;
                        if (!std.mem.eql(u8, arguments_file.tokenText(&self.diags.source_db, field.name_token), param.name)) continue;
                        const resolved = try self.resolveExplicitGenericArg(arguments_file.ref(field_node), param, s, &subst);
                        try self.putGenericArg(&subst, param, resolved);
                        found = true;
                        break;
                    }
                    if (!found) {
                        complete = false;
                        break;
                    }
                }
                if (!complete) continue;

                for (template.params, 0..) |param, index| {
                    const constraint = template.param_abstract_constraints[index] orelse continue;
                    const actual = subst.types.get(param.name) orelse continue;
                    if (!(try self.abstractConstraintMatches(actual, constraint, s, &subst))) {
                        const desc = try self.formatTypeText(actual, s);
                        defer desc.deinit();
                        try self.diags.add(template.location, .semantic, "type '{s}' does not implement abstract '{s}' required by generic type parameter '.{s}' of '{s}'", .{ desc.bytes, constraint.name, param.name, template.name });
                        return error.Reported;
                    }
                }
                return self.instantiateCompactGenericTypeTemplate(template, s, &subst);
            }
        }
        return error.SymbolNotFound;
    }

    // Type templates are instantiated from compact syntax and from compiler
    // sugar alike. Keeping the body expansion here makes both paths produce
    // the same nominal generic identity.
    fn instantiateCompactGenericTypeTemplate(
        self: *Semantizer,
        template: gen.GenericTypeTemplate,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        const result: sg.Type = switch (self.syntaxFile(template.body).tag(template.body.node)) {
            .struct_type_literal => .{ .struct_type = try self.structTypeFromNodeWithSubst(template.body, s, subst) },
            .choice_type_literal => .{ .choice_type = try self.choiceTypeFromNodeWithSubst(template.body, s, subst) },
            else => return error.InvalidType,
        };
        const identity = try self.allocator.create(sg.GenericTypeIdentity);
        const arg_names = try self.allocator.alloc([]const u8, template.params.len);
        const arg_values = try self.allocator.alloc(sg.GenericIdentityArg, template.params.len);
        for (template.params, 0..) |param, index| {
            arg_names[index] = param.name;
            arg_values[index] = switch (param.kind) {
                .type => .{ .type = subst.types.get(param.name) orelse return error.InvalidType },
                .comptime_int => .{ .comptime_int = subst.ints.get(param.name) orelse return error.InvalidType },
            };
        }
        identity.* = .{ .base_name = template.name, .arg_names = arg_names, .arg_values = arg_values };
        switch (result) {
            .struct_type => |value| @constCast(value).identity = .{ .generic = identity },
            .choice_type => |value| @constCast(value).identity = .{ .generic = identity },
            else => return error.InvalidType,
        }
        return result;
    }

    fn instantiateCompactGenericTypeFromSubstNamed(
        self: *Semantizer,
        name: []const u8,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!sg.Type {
        var current: ?*Scope = s;
        while (current) |scope| : (current = scope.parent) {
            const templates = scope.generic_types.getPtr(name) orelse continue;
            template_loop: for (templates.items) |template| {
                for (template.params) |param| switch (param.kind) {
                    .type => if (subst.types.get(param.name) == null) continue :template_loop,
                    .comptime_int => if (subst.ints.get(param.name) == null) continue :template_loop,
                };
                for (template.params, 0..) |param, index| {
                    const constraint = template.param_abstract_constraints[index] orelse continue;
                    const actual = subst.types.get(param.name) orelse continue;
                    if (!(try self.abstractConstraintMatches(actual, constraint, s, subst))) return error.InvalidType;
                }
                return self.instantiateCompactGenericTypeTemplate(template, s, subst);
            }
        }
        return error.SymbolNotFound;
    }

    fn resolveCompactArrayTypeFromGenericArgs(
        self: *Semantizer,
        location: tok.Location,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(arguments_ref);
        const arguments = file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
        var length: ?i64 = null;
        var element: ?sg.Type = null;
        for (arguments.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const name = file.tokenText(&self.diags.source_db, field.name_token);
            if (std.mem.eql(u8, name, "n")) {
                const value = field.default_value orelse {
                    try self.diags.add(location, .semantic, "Array expects '.n = <comptime integer expression>'", .{});
                    return error.Reported;
                };
                length = try self.resolveComptimeIntExpr(file.ref(value), s, subst);
            } else if (std.mem.eql(u8, name, "t")) {
                if (field.type_node) |type_node| {
                    element = if (subst) |values|
                        try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(type_node), s, values)
                    else
                        try self.resolveSyntaxTypeWithMode(file.ref(type_node), s, true, null);
                } else if (field.default_value) |type_expression| {
                    element = if (subst) |values|
                        try self.resolveTypeExpressionWithSubst(file.ref(type_expression), s, values)
                    else
                        try self.resolveTypeExpression(file.ref(type_expression), s);
                } else {
                    try self.diags.add(location, .semantic, "Array expects '.t: <type>'", .{});
                    return error.Reported;
                }
            } else {
                try self.diags.add(location, .semantic, "Array only accepts '.n' and '.t' parameters", .{});
                return error.Reported;
            }
        }
        const resolved_length = length orelse {
            try self.diags.add(location, .semantic, "Array is missing '.n = <comptime integer expression>'", .{});
            return error.Reported;
        };
        if (resolved_length < 0) {
            try self.diags.add(location, .semantic, "Array length cannot be negative", .{});
            return error.Reported;
        }
        const resolved_element = element orelse {
            try self.diags.add(location, .semantic, "Array is missing '.t: <type>'", .{});
            return error.Reported;
        };
        return self.makeArrayType(@intCast(resolved_length), resolved_element);
    }

    fn resolveCompactChoiceUnionFromGenericArgs(
        self: *Semantizer,
        location: tok.Location,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(arguments_ref);
        const arguments = file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
        if (arguments.fields.len != 2) {
            try self.diags.add(location, .semantic, "choice_union expects exactly '.a: <choice>' and '.b: <choice>'", .{});
            return error.Reported;
        }
        var left: ?sg.Type = null;
        var right: ?sg.Type = null;
        for (arguments.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse return error.InvalidType;
            const name = file.tokenText(&self.diags.source_db, field.name_token);
            const type_node = field.type_node orelse {
                try self.diags.add(file.tokenLocation(field.name_token), .semantic, "choice_union argument '.{s}' must be a type", .{name});
                return error.Reported;
            };
            const resolved = if (subst) |values|
                try self.resolveSyntaxTypeWithSubstPreservingAbstracts(file.ref(type_node), s, values)
            else
                try self.resolveSyntaxTypeWithMode(file.ref(type_node), s, true, null);
            if (std.mem.eql(u8, name, "a")) {
                left = resolved;
            } else if (std.mem.eql(u8, name, "b")) {
                right = resolved;
            } else {
                try self.diags.add(file.tokenLocation(field.name_token), .semantic, "choice_union only accepts '.a' and '.b'", .{});
                return error.Reported;
            }
        }
        const left_type = left orelse {
            try self.diags.add(location, .semantic, "choice_union is missing '.a'", .{});
            return error.Reported;
        };
        const right_type = right orelse {
            try self.diags.add(location, .semantic, "choice_union is missing '.b'", .{});
            return error.Reported;
        };
        if (left_type != .choice_type or right_type != .choice_type) {
            try self.diags.add(location, .semantic, "choice_union arguments must both be choice types", .{});
            return error.Reported;
        }
        const union_type = try self.allocator.create(sg.ChoiceType);
        union_type.* = .{ .variants = &.{} };
        for (left_type.choice_type.variants) |variant| _ = try typ.appendChoiceVariant(union_type, variant, self.allocator);
        for (right_type.choice_type.variants) |variant| _ = try typ.appendChoiceVariant(union_type, variant, self.allocator);
        const variants = @constCast(union_type.variants);
        var index: usize = 1;
        while (index < variants.len) : (index += 1) {
            var cursor = index;
            while (cursor > 0 and std.mem.order(u8, variants[cursor - 1].name, variants[cursor].name) == .gt) : (cursor -= 1) {
                const previous = variants[cursor - 1];
                variants[cursor - 1] = variants[cursor];
                variants[cursor] = previous;
            }
        }
        return .{ .choice_type = union_type };
    }

    fn resolveCompactVirtualTypeFromGenericArgs(
        self: *Semantizer,
        location: tok.Location,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(arguments_ref);
        const arguments = file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
        if (arguments.fields.len != 1) {
            try self.diags.add(location, .semantic, "Virtual expects exactly '.abstract: <Abstract>'", .{});
            return error.Reported;
        }
        const field = file.structTypeField(arguments.fields[0]) orelse return error.InvalidType;
        if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token), "abstract")) {
            try self.diags.add(location, .semantic, "Virtual expects exactly '.abstract: <Abstract>'", .{});
            return error.Reported;
        }
        const abstract_node = field.type_node orelse return error.InvalidType;
        const abstract_syntax = file.syntaxType(abstract_node) orelse return error.InvalidType;
        if (abstract_syntax != .name or abstract_syntax.name.qualifier_token != null) return error.InvalidType;
        const abstract_name = file.tokenText(&self.diags.source_db, abstract_syntax.name.name_token);
        if (s.lookupAbstractInfo(abstract_name) == null) {
            try self.diags.add(file.tokenLocation(field.name_token), .semantic, "'{s}' is not an Abstract type", .{abstract_name});
            return error.Reported;
        }
        const abstract_declaration = s.lookupType(abstract_name) orelse return error.UnknownType;
        if (abstract_declaration.ty != .abstract_type) return error.InvalidType;
        const any_type = try self.allocator.create(sg.Type);
        any_type.* = .{ .builtin = .Any };
        const data_pointer = try self.allocator.create(sg.PointerType);
        data_pointer.* = .{ .mutability = .read_write, .child = any_type };
        const vtable_pointer = try self.allocator.create(sg.PointerType);
        vtable_pointer.* = .{ .mutability = .read_only, .child = any_type };
        const fields = try self.allocator.alloc(sg.StructTypeField, 2);
        fields[0] = .{ .name = "data", .ty = .{ .pointer_type = data_pointer } };
        fields[1] = .{ .name = "vtable", .ty = .{ .pointer_type = vtable_pointer } };
        const arg_names = try self.allocator.alloc([]const u8, 1);
        arg_names[0] = "abstract";
        const arg_values = try self.allocator.alloc(sg.GenericIdentityArg, 1);
        arg_values[0] = .{ .type = abstract_declaration.ty };
        const identity = try self.allocator.create(sg.GenericTypeIdentity);
        identity.* = .{ .base_name = "Virtual", .arg_names = arg_names, .arg_values = arg_values };
        const virtual_type = try self.allocator.create(sg.StructType);
        virtual_type.* = .{ .fields = fields, .identity = .{ .generic = identity } };
        return .{ .struct_type = virtual_type };
    }

    fn resolveCompactSpecialGenericType(
        self: *Semantizer,
        base_name: []const u8,
        location: tok.Location,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!?sg.Type {
        if (std.mem.eql(u8, base_name, "choice_union")) return @as(?sg.Type, try self.resolveCompactChoiceUnionFromGenericArgs(location, arguments_ref, s, subst));
        if (std.mem.eql(u8, base_name, "Array")) return @as(?sg.Type, try self.resolveCompactArrayTypeFromGenericArgs(location, arguments_ref, s, subst));
        if (std.mem.eql(u8, base_name, "Virtual")) return @as(?sg.Type, try self.resolveCompactVirtualTypeFromGenericArgs(location, arguments_ref, s));
        return null;
    }

    fn makeCompactInferredErrableType(
        self: *Semantizer,
        inner_ref: syn.SyntaxRef,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        const inner = if (subst) |values|
            try self.resolveSyntaxTypeWithSubstPreservingAbstracts(inner_ref, s, values)
        else
            try self.resolveSyntaxTypeWithMode(inner_ref, s, true, null);
        const reasons = try self.allocator.create(sg.ChoiceType);
        reasons.* = .{ .variants = &.{} };
        reasons.identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.reasons) };
        var values = GenericSubst.init(self.allocator);
        defer values.deinit();
        if (subst) |outer| try values.cloneFrom(outer);
        try values.types.put("t", inner);
        try values.types.put("reasons", .{ .choice_type = reasons });
        const resolved = self.instantiateCompactGenericTypeFromSubstNamed("Errable", s, &values) catch |err| switch (err) {
            error.SymbolNotFound => return error.UnknownType,
            else => return err,
        };
        const errable = switch (resolved) {
            .choice_type => |choice| choice,
            else => return error.InvalidType,
        };
        @constCast(errable).identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.errable) };
        return resolved;
    }

    fn resolveCompactGenericTypeWithMode(
        self: *Semantizer,
        base_name: []const u8,
        location: tok.Location,
        arguments_ref: syn.SyntaxRef,
        s: *Scope,
        preserve_abstract: bool,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        if (try self.resolveCompactSpecialGenericType(base_name, location, arguments_ref, s, subst)) |special| return special;
        if (s.lookupAbstractInfo(base_name)) |info| {
            const file = self.syntaxFile(arguments_ref);
            const arguments = file.structTypeLiteral(arguments_ref.node) orelse return error.InvalidType;
            for (info.params) |param| {
                var found = false;
                for (arguments.fields) |field_node| {
                    const field = file.structTypeField(field_node) orelse return error.InvalidType;
                    if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token), param.name)) continue;
                    found = true;
                    break;
                }
                if (!found) return error.UnknownType;
            }
            if (preserve_abstract) return (s.lookupType(base_name) orelse return error.UnknownType).ty;
            if (s.lookupAbstractDefault(base_name)) |default| return default.ty;
            return error.AbstractNeedsDefault;
        }
        return self.instantiateCompactGenericTypeNamed(base_name, arguments_ref, s, subst) catch |err| switch (err) {
            error.SymbolNotFound => error.UnknownType,
            else => return err,
        };
    }

    fn resolveCompactNullableType(
        self: *Semantizer,
        inner_ref: syn.SyntaxRef,
        s: *Scope,
        preserve_abstract: bool,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        var values = GenericSubst.init(self.allocator);
        defer values.deinit();
        if (subst) |outer| try values.cloneFrom(outer);
        const inner = if (subst) |outer|
            try self.resolveSyntaxTypeWithSubstPreservingAbstracts(inner_ref, s, outer)
        else
            try self.resolveSyntaxTypeWithMode(inner_ref, s, preserve_abstract, null);
        try values.types.put("t", inner);
        return self.instantiateCompactGenericTypeFromSubstNamed("Nullable", s, &values) catch |err| switch (err) {
            error.SymbolNotFound => error.UnknownType,
            else => return err,
        };
    }

    //──────────────────────────────────────────────────── BINARY OP

    //──────────────────────────────────────────────────── COMPARISON

    fn coercePayloadlessChoiceComparisonSide(
        self: *Semantizer,
        target_ty: sg.Type,
        expr: typ.TypedExpr,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!?typ.TypedExpr {
        if (target_ty != .choice_type) return null;
        if (expr.node.content != .choice_literal) return null;
        if (expr.ty != .builtin or expr.ty.builtin != .Any) return null;

        const raw_variant = expr.node.content.choice_literal;
        if (raw_variant.payload != null) return null;

        const choice_ty = target_ty.choice_type;
        for (choice_ty.variants, 0..) |variant, idx| {
            if (!std.mem.eql(u8, variant.name, raw_variant.variant_name)) continue;

            const typed = try self.allocator.create(sg.ChoiceLiteral);
            typed.* = .{
                .variant_name = raw_variant.variant_name,
                .module_qualifier = raw_variant.module_qualifier,
                .choice_type = choice_ty,
                .variant_index = @intCast(idx),
                .payload = null,
            };
            const typed_node = try sg.makeSGNode(.{ .choice_literal = typed }, loc, self.allocator);
            typed_node.sem_type = target_ty;
            return typ.TypedExpr{ .node = typed_node, .ty = target_ty };
        }

        const choice_text = try self.formatTypeText(target_ty, s);
        defer choice_text.deinit();
        try self.diags.add(
            loc,
            .semantic,
            "choice type '{s}' has no variant '..{s}'",
            .{ choice_text.bytes, raw_variant.variant_name },
        );
        return error.Reported;
    }

    //──────────────────────────────────────────────────── RETURN

    const ErrableInfo = struct {
        ok_variant_index: u32,
        ok_payload_type: sg.Type,
        ok_value_field_index: ?u32,
        error_variant_index: u32,
        error_payload_type: sg.Type,
    };

    const NullableInfo = struct {
        some_variant_index: u32,
        some_payload_type: sg.Type,
        some_value_type: sg.Type,
        some_value_field_index: u32,
        none_variant_index: u32,
    };

    const NullableIfRefinement = struct {
        source_binding: *sg.BindingDeclaration,
        some_variant_index: u32,
        some_payload_type: sg.Type,
        some_value_type: sg.Type,
    };

    fn errorPayloadCanPropagate(self: *Semantizer, source: sg.Type, target: sg.Type) bool {
        _ = self;
        if (typ.typesExactlyEqual(source, target)) return true;
        const source_struct = switch (source) {
            .struct_type => |st| st,
            else => return false,
        };
        const target_struct = switch (target) {
            .struct_type => |st| st,
            else => return false,
        };

        const source_reason = typ.findFieldByName(source_struct, "reason") orelse return false;
        const target_reason = typ.findFieldByName(target_struct, "reason") orelse return false;
        const source_trace = typ.findFieldByName(source_struct, "trace") orelse return false;
        const target_trace = typ.findFieldByName(target_struct, "trace") orelse return false;

        if (!typ.typesExactlyEqual(source_trace.ty, target_trace.ty)) return false;
        if (source_reason.ty != .choice_type or target_reason.ty != .choice_type) return false;
        return typ.choiceTypeIsSupersetOf(target_reason.ty.choice_type, source_reason.ty.choice_type);
    }

    fn absorbErrorPayloadReasons(self: *Semantizer, source: sg.Type, target: sg.Type) SemErr!void {
        const source_struct = switch (source) {
            .struct_type => |st| st,
            else => return,
        };
        const target_struct = switch (target) {
            .struct_type => |st| st,
            else => return,
        };

        const source_reason = typ.findFieldByName(source_struct, "reason") orelse return;
        const target_reason = typ.findFieldByName(target_struct, "reason") orelse return;
        if (source_reason.ty != .choice_type or target_reason.ty != .choice_type) return;
        if (!typ.isOpenInferredReasonsChoice(target_reason.ty.choice_type)) return;

        for (source_reason.ty.choice_type.variants) |variant| {
            _ = try typ.appendChoiceVariant(@constCast(target_reason.ty.choice_type), variant, self.allocator);
        }
    }

    fn lowerErrorPropagation(
        self: *Semantizer,
        value_te: typ.TypedExpr,
        context_te: ?typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const operand_info = try self.errableInfoOf(value_te.ty, loc, "expression", s);

        const current_fn = s.current_fn orelse {
            try self.diags.add(
                loc,
                .semantic,
                "error propagation is only valid inside a function body",
                .{},
            );
            return error.Reported;
        };

        const return_info = try self.errableInfoOf(typ.functionReturnType(current_fn), loc, "current function return type", s);

        if (current_fn.uses_inferred_error_reasons) {
            try self.absorbErrorPayloadReasons(operand_info.error_payload_type, return_info.error_payload_type);
        } else if (!self.errorPayloadCanPropagate(operand_info.error_payload_type, return_info.error_payload_type)) {
            const pair = try self.formatTypePairText(return_info.error_payload_type, operand_info.error_payload_type, s);
            defer pair.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "cannot propagate error payload '{s}' into function return payload '{s}'",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        if (context_te) |ctx| {
            const is_c_string =
                ctx.ty == .pointer_type and
                ctx.ty.pointer_type.mutability == .read_only and
                ctx.ty.pointer_type.child.* == .builtin and
                ctx.ty.pointer_type.child.*.builtin == .Char;

            const is_string_view = blk: {
                const string_view_decl = s.lookupType("StringView") orelse break :blk false;
                if (!typeDeclIsReady(string_view_decl)) break :blk false;
                break :blk typ.typesExactlyEqual(ctx.ty, string_view_decl.ty);
            };

            if (!is_c_string and !is_string_view) {
                const desc = try self.formatTypeText(ctx.ty, s);
                defer desc.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "operator '!!' expects a context of type '&Char' or 'StringView', found '{s}'",
                    .{desc.bytes},
                );
                return error.Reported;
            }
        }

        const node = if (context_te) |ctx| blk: {
            const err_ctx = try self.allocator.create(sg.ErrorContext);
            const source_line = self.sourceLineText(loc);
            const position = self.locationLineColumn(loc);
            err_ctx.* = .{
                .errable_value = value_te.node,
                .context = ctx.node,
                .cleanup_nodes = try self.collectActiveEarlyCleanupNodes(s),
                .ok_variant_index = operand_info.ok_variant_index,
                .ok_value_field_index = operand_info.ok_value_field_index,
                .error_variant_index = operand_info.error_variant_index,
                .propagated_errable_type = typ.functionReturnType(current_fn),
                .propagated_error_variant_index = return_info.error_variant_index,
                .ok_payload_type = operand_info.ok_payload_type,
                .error_payload_type = operand_info.error_payload_type,
                .propagated_error_payload_type = return_info.error_payload_type,
                .line = position.line,
                .column = position.column,
                .source_file = self.locationPath(loc),
                .source_line = source_line,
            };
            break :blk try sg.makeSGNode(.{ .error_context = err_ctx }, loc, self.allocator);
        } else blk: {
            const err_prop = try self.allocator.create(sg.ErrorPropagation);
            const source_line = self.sourceLineText(loc);
            const position = self.locationLineColumn(loc);
            err_prop.* = .{
                .errable_value = value_te.node,
                .cleanup_nodes = try self.collectActiveEarlyCleanupNodes(s),
                .ok_variant_index = operand_info.ok_variant_index,
                .ok_value_field_index = operand_info.ok_value_field_index,
                .error_variant_index = operand_info.error_variant_index,
                .propagated_errable_type = typ.functionReturnType(current_fn),
                .propagated_error_variant_index = return_info.error_variant_index,
                .ok_payload_type = operand_info.ok_payload_type,
                .error_payload_type = operand_info.error_payload_type,
                .propagated_error_payload_type = return_info.error_payload_type,
                .line = position.line,
                .column = position.column,
                .source_file = self.locationPath(loc),
                .source_line = source_line,
            };
            break :blk try sg.makeSGNode(.{ .error_propagation = err_prop }, loc, self.allocator);
        };

        try s.nodes.append(node);
        return .{ .node = node, .ty = operand_info.ok_payload_type };
    }

    fn tryNullableInfoOfType(
        self: *Semantizer,
        ty: sg.Type,
    ) ?NullableInfo {
        _ = self;
        if (ty != .choice_type) return null;

        var some_payload_ty: ?sg.Type = null;
        var some_value_ty: ?sg.Type = null;
        var some_value_field_index: u32 = 0;
        var some_variant_index: u32 = 0;
        var found_none = false;
        var none_variant_index: u32 = 0;

        for (ty.choice_type.variants, 0..) |variant, idx| {
            if (std.mem.eql(u8, variant.name, "some")) {
                const payload_ty = variant.payload_type orelse return null;
                const payload_struct = switch (payload_ty) {
                    .struct_type => |st| st,
                    else => return null,
                };
                const value_field = typ.findFieldByName(payload_struct, "value") orelse return null;
                some_payload_ty = payload_ty;
                some_value_ty = value_field.ty;
                some_value_field_index = fieldIndexInStruct(payload_struct, "value") orelse 0;
                some_variant_index = @intCast(idx);
            } else if (std.mem.eql(u8, variant.name, "none")) {
                if (variant.payload_type != null) return null;
                found_none = true;
                none_variant_index = @intCast(idx);
            }
        }

        if (some_payload_ty == null or some_value_ty == null or !found_none) return null;

        return .{
            .some_variant_index = some_variant_index,
            .some_payload_type = some_payload_ty.?,
            .some_value_type = some_value_ty.?,
            .some_value_field_index = some_value_field_index,
            .none_variant_index = none_variant_index,
        };
    }

    fn nullableInfoOf(
        self: *Semantizer,
        ty: sg.Type,
        loc: tok.Location,
        comptime what: []const u8,
        s: *Scope,
    ) SemErr!NullableInfo {
        return self.tryNullableInfoOfType(ty) orelse blk: {
            const desc = try self.formatTypeText(ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "{s} must have '..some(.value: T)' and '..none', found '{s}'",
                .{ what, desc.bytes },
            );
            break :blk error.Reported;
        };
    }

    fn errableInfoOf(
        self: *Semantizer,
        ty: sg.Type,
        loc: tok.Location,
        comptime what: []const u8,
        s: *Scope,
    ) SemErr!ErrableInfo {
        if (ty != .choice_type) {
            const desc = try self.formatTypeText(ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "{s} for error propagation must be an Errable-like choice, found '{s}'",
                .{ what, desc.bytes },
            );
            return error.Reported;
        }

        var ok_payload_type: ?sg.Type = null;
        var ok_value_field_index: ?u32 = null;
        var error_payload: ?sg.Type = null;
        var ok_variant_index: u32 = 0;
        var error_variant_index: u32 = 0;

        for (ty.choice_type.variants, 0..) |variant, idx| {
            if (std.mem.eql(u8, variant.name, "ok")) {
                const payload_ty = variant.payload_type orelse {
                    try self.diags.add(loc, .semantic, "Errable '..ok' must carry a payload", .{});
                    return error.Reported;
                };
                ok_payload_type = payload_ty;
                if (payload_ty == .struct_type) {
                    if (typ.findFieldByName(payload_ty.struct_type, "value")) |value_field| {
                        if (payload_ty.struct_type.fields.len == 1) {
                            ok_payload_type = value_field.ty;
                            ok_value_field_index = fieldIndexInStruct(payload_ty.struct_type, "value");
                        }
                    }
                }
                ok_variant_index = @intCast(idx);
            } else if (std.mem.eql(u8, variant.name, "error")) {
                error_payload = variant.payload_type;
                error_variant_index = @intCast(idx);
            }
        }

        if (ok_payload_type == null or error_payload == null) {
            const desc = try self.formatTypeText(ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "{s} for error propagation must have '..ok' and '..error' payload variants, found '{s}'",
                .{ what, desc.bytes },
            );
            return error.Reported;
        }

        try self.validateErrorPayloadShape(error_payload.?, loc, s);

        return .{
            .ok_variant_index = ok_variant_index,
            .ok_payload_type = ok_payload_type.?,
            .ok_value_field_index = ok_value_field_index,
            .error_variant_index = error_variant_index,
            .error_payload_type = error_payload.?,
        };
    }

    fn fieldIndexInStruct(st: *const sg.StructType, name: []const u8) ?u32 {
        for (st.fields, 0..) |field, idx| {
            if (std.mem.eql(u8, field.name, name)) return @intCast(idx);
        }
        return null;
    }

    fn validateErrorPayloadShape(
        self: *Semantizer,
        error_payload_ty: sg.Type,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!void {
        const error_struct = switch (error_payload_ty) {
            .struct_type => |st| st,
            else => {
                const desc = try self.formatTypeText(error_payload_ty, s);
                defer desc.deinit();
                try self.diags.add(
                    loc,
                    .semantic,
                    "Errable '..error' payload must be a struct with '.reason' and '.trace', found '{s}'",
                    .{desc.bytes},
                );
                return error.Reported;
            },
        };

        const reason_field = typ.findFieldByName(error_struct, "reason");
        const trace_field = typ.findFieldByName(error_struct, "trace");
        if (reason_field == null or trace_field == null) {
            try self.diags.add(
                loc,
                .semantic,
                "Errable '..error' payload must contain '.reason' and '.trace'",
                .{},
            );
            return error.Reported;
        }

        if (reason_field.?.ty != .choice_type) {
            try self.diags.add(
                loc,
                .semantic,
                "Errable '.reason' field must be a choice of declared options",
                .{},
            );
            return error.Reported;
        }
        for (reason_field.?.ty.choice_type.variants) |variant| {
            if (variant.payload_type != null) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "Errable '.reason' choices cannot carry payloads",
                    .{},
                );
                return error.Reported;
            }
        }

        const trace_struct = switch (trace_field.?.ty) {
            .struct_type => |st| st,
            else => {
                try self.diags.add(
                    loc,
                    .semantic,
                    "Errable '.trace' field must be a struct containing '.entries'",
                    .{},
                );
                return error.Reported;
            },
        };

        if (typ.findFieldByName(trace_struct, "entries") == null) {
            try self.diags.add(
                loc,
                .semantic,
                "Errable '.trace' field must contain '.entries'",
                .{},
            );
            return error.Reported;
        }
    }

    //──────────────────────────────────────────────────── IF

    fn choiceTagTestForCondition(self: *Semantizer, condition: *const sg.SGNode) ?sg.ChoiceTagTest {
        _ = self;
        const comparison = switch (condition.content) {
            .comparison => |value| value,
            else => return null,
        };
        const then_has_variant = switch (comparison.operator) {
            .equal => true,
            .not_equal => false,
            else => return null,
        };
        const left_literal = switch (comparison.left.content) {
            .choice_literal => |value| value,
            else => null,
        };
        const right_literal = switch (comparison.right.content) {
            .choice_literal => |value| value,
            else => null,
        };
        const choice_value: *const sg.SGNode = if (left_literal != null)
            comparison.right
        else if (right_literal != null)
            comparison.left
        else
            return null;
        const literal = left_literal orelse right_literal.?;
        if (literal.payload != null or choice_value.sem_type == null or choice_value.sem_type.? != .choice_type) return null;
        return .{
            .choice_value = choice_value,
            .choice_type = choice_value.sem_type.?.choice_type,
            .variant_index = literal.variant_index,
            .then_has_variant = then_has_variant,
        };
    }

    fn applyNullableThenRefinement(
        self: *Semantizer,
        refinement: NullableIfRefinement,
        child: *Scope,
        loc: tok.Location,
    ) SemErr!void {
        if (!typ.isTypeCopyable(refinement.some_value_type, child)) return;

        const source_use = try sg.makeSGNode(.{ .binding_use = refinement.source_binding }, loc, self.allocator);
        source_use.sem_type = refinement.source_binding.ty;

        const payload_access = try self.allocator.create(sg.ChoicePayloadAccess);
        payload_access.* = .{
            .choice_value = source_use,
            .variant_index = refinement.some_variant_index,
            .payload_type = refinement.some_payload_type,
        };
        const payload_node = try sg.makeSGNode(.{ .choice_payload_access = payload_access }, loc, self.allocator);
        payload_node.sem_type = refinement.some_payload_type;

        var init_expr = try self.buildStructFieldAccessFromTypedExpr(
            .{ .node = payload_node, .ty = refinement.some_payload_type },
            "value",
            loc,
            child,
        );
        init_expr = try self.ensureValuePositionAllowed(init_expr, loc, child);

        const synthetic_name = try self.makeSyntheticName("nullable_some");
        const binding = try self.allocator.create(sg.BindingDeclaration);
        binding.* = .{
            .name = synthetic_name,
            .location = refinement.source_binding.location,
            .origin_file = refinement.source_binding.origin_file,
            .mutability = .constant,
            .ty = refinement.some_value_type,
            .initialization = init_expr.node,
        };

        try child.bindings.put(binding.name, binding);
        try child.refined_bindings.put(refinement.source_binding.name, binding);
        const decl_node = try sg.makeSGNode(.{ .binding_declaration = binding }, loc, self.allocator);
        try child.nodes.append(decl_node);
        try self.maybeScheduleAutoDeinit(binding, loc, child);
    }

    fn handleWhile(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(node);
        const w = file.whileStatement(node.node) orelse return error.InvalidType;
        const start_len = s.nodes.items.len;

        const cond = try self.visitNode(file.ref(w.condition), s);
        const body_te = try self.visitNode(file.ref(w.body), s);

        s.nodes.items.len = start_len;

        const while_ptr = try self.allocator.create(sg.WhileStatement);
        while_ptr.* = .{
            .condition = cond.node,
            .body = body_te.node.content.code_block,
        };

        const n = try sg.makeSGNode(.{ .while_statement = while_ptr }, self.nodeLocation(node), self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn handleBreak(
        self: *Semantizer,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const n = try sg.makeSGNode(.{ .break_statement = .{} }, loc, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn handleContinue(
        self: *Semantizer,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const n = try sg.makeSGNode(.{ .continue_statement = .{} }, loc, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── ADDRESS OF
    fn handleAddressOf(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const addr = file.addressOf(syntax_ref.node) orelse return error.InvalidType;
        if (file.indexAccess(addr.value)) |ia| {
            const base = try self.visitNode(file.ref(ia.value), s);
            if (base.ty != .array_type and base.node.content != .list_literal) {
                return self.handleBorrowedIndexAccess(file.ref(addr.value), addr.mutability, s);
            }
        }

        const te = try self.visitNode(file.ref(addr.value), s);
        return switch (addr.mutability) {
            .read_only => try typ.ensureReadOnlyPointer(file.location(addr.value), te, self.allocator, self.diags),
            .read_write => try typ.ensureMutablePointer(file.location(addr.value), te, s, self.allocator, self.diags),
        };
    }

    fn handleDefer(
        self: *Semantizer,
        expr: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;
        const te = try self.visitNode(expr, s);

        if (s.nodes.items.len > start_len) {
            const new_nodes = s.nodes.items[start_len..];
            try self.registerDefer(s, new_nodes);
            s.nodes.items.len = start_len;
        } else if (te.node.content == .function_call) {
            try self.registerDefer(s, &[_]*sg.SGNode{te.node});
        }

        return .{ .node = te.node, .ty = .{ .builtin = .Any } };
    }

    fn cancelAutoDeinitForBinding(self: *Semantizer, binding: *sg.BindingDeclaration, s: *Scope) bool {
        var cur: ?*Scope = s;
        while (cur) |scope_ptr| : (cur = scope_ptr.parent) {
            var idx: usize = 0;
            while (idx < scope_ptr.deferred.items.len) : (idx += 1) {
                const group = scope_ptr.deferred.items[idx];
                if (group.nodes.len != 1) continue;
                const node = group.nodes[0];
                if (node.content != .auto_deinit_binding) continue;
                if (node.content.auto_deinit_binding.binding != binding) continue;
                self.allocator.free(group.nodes);
                _ = scope_ptr.deferred.orderedRemove(idx);
                return true;
            }
        }
        return false;
    }

    fn handleKeep(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const statement = file.keepStatement(syntax_ref.node) orelse return error.InvalidType;
        const name = file.tokenText(&self.diags.source_db, statement.name_token);
        const location = file.tokenLocation(statement.name_token);
        const binding = s.lookupBinding(name) orelse {
            try self.diags.add(
                location,
                .semantic,
                "cannot keep unknown binding '{s}'",
                .{name},
            );
            return error.Reported;
        };

        if (!self.cancelAutoDeinitForBinding(binding, s)) {
            if (self.defer_unknown_top_level and self.current_top_node != null) {
                return error.SymbolNotFound;
            }
            try self.diags.add(
                location,
                .semantic,
                "cannot keep binding '{s}': no automatic deinit is scheduled",
                .{name},
            );
            return error.Reported;
        }

        const use_node = try sg.makeSGNode(.{ .binding_use = binding }, location, self.allocator);
        use_node.sem_type = binding.ty;
        return .{ .node = use_node, .ty = .{ .builtin = .Any } };
    }

    fn dereferenceReachPathValue(
        self: *Semantizer,
        te: typ.TypedExpr,
    ) SemErr!typ.TypedExpr {
        if (te.ty != .pointer_type) return te;

        const ptr_info_ptr = te.ty.pointer_type;
        const ptr_info = ptr_info_ptr.*;
        const base_ty = ptr_info.child.*;

        const der_ptr = try self.allocator.create(sg.Dereference);
        der_ptr.* = .{ .pointer = te.node, .ty = base_ty, .pointer_type = ptr_info_ptr };

        const node = try sg.makeSGNode(.{ .dereference = der_ptr.* }, te.node.location, self.allocator);
        node.sem_type = base_ty;
        return .{ .node = node, .ty = base_ty };
    }

    //──────────────────────────────────────────────────── DEREFERENCE
    fn handleDereference(
        self: *Semantizer,
        inner: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const te = try self.visitNode(inner, s);

        if (te.ty != .pointer_type) {
            const ty_str = try self.formatTypeText(te.ty, s);
            defer ty_str.deinit();
            try self.diags.add(
                self.nodeLocation(inner),
                .semantic,
                "cannot dereference value of type '{s}'; expected a pointer",
                .{ty_str.bytes},
            );
            return error.Reported;
        }
        const ptr_info_ptr = te.ty.pointer_type;
        const ptr_info = ptr_info_ptr.*;
        const base_ty = ptr_info.child.*; // T

        const der_ptr = try self.allocator.create(sg.Dereference);
        der_ptr.* = .{ .pointer = te.node, .ty = base_ty, .pointer_type = ptr_info_ptr };

        const n = try sg.makeSGNode(.{ .dereference = der_ptr.* }, self.nodeLocation(inner), self.allocator);
        n.sem_type = base_ty;

        return .{ .node = n, .ty = base_ty };
    }

    //────────────────────────────────────────────────── POINTER ASSIGNMENT
    const CallArg = struct {
        name: []const u8,
        expr: typ.TypedExpr,
    };

    const GenericParamSyntaxInfo = struct {
        params: []const gen.GenericParam,
        abstract_constraints: []const ?gen.AbstractConstraint,
    };

    fn buildCallInputWithPositionalPrefix(
        self: *Semantizer,
        args: []const CallArg,
        positional_prefix_count: u32,
    ) !typ.TypedExpr {
        var ty_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        var val_fields = std.array_list.Managed(sg.StructValueLiteralField).init(self.allocator.*);

        for (args) |arg| {
            try ty_fields.append(.{ .name = arg.name, .ty = arg.expr.ty, .default_value = null });
            try val_fields.append(.{ .name = arg.name, .value = arg.expr.node });
        }

        const ty_slice = try ty_fields.toOwnedSlice();
        ty_fields.deinit();

        const struct_ptr = try self.allocator.create(sg.StructType);
        struct_ptr.* = .{ .fields = ty_slice };

        const val_slice = try val_fields.toOwnedSlice();
        val_fields.deinit();

        const lit_ptr = try self.allocator.create(sg.StructValueLiteral);
        lit_ptr.* = .{
            .fields = val_slice,
            .ty = .{ .struct_type = struct_ptr },
            .dispatch_prefix_positional_count = positional_prefix_count,
        };

        const node = try sg.makeSGNode(.{ .struct_value_literal = lit_ptr }, undefined, self.allocator);

        return .{ .node = node, .ty = .{ .struct_type = struct_ptr } };
    }

    fn buildCallInput(self: *Semantizer, args: []const CallArg) !typ.TypedExpr {
        return self.buildCallInputWithPositionalPrefix(args, @intCast(args.len));
    }

    fn buildNamedCallInput(self: *Semantizer, args: []const CallArg) !typ.TypedExpr {
        return self.buildCallInputWithPositionalPrefix(args, 0);
    }

    fn handlePointerAssignment(
        self: *Semantizer,
        syntax_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(syntax_ref);
        const pa = file.pointerAssignment(syntax_ref.node) orelse return error.InvalidType;
        var rhs = try self.visitNode(file.ref(pa.value), s);

        if (file.structFieldAccess(pa.target)) |sa| {
            const target_te = try self.visitNode(file.ref(pa.target), s);
            if (target_te.node.content != .struct_field_access)
                return error.InvalidType;
            const sf = target_te.node.content.struct_field_access;

            const base = try self.visitNode(file.ref(sa.value), s);
            const ptr_self = try typ.ensureMutablePointer(file.location(sa.value), base, s, self.allocator, self.diags);

            const ptr_info = ptr_self.ty.pointer_type.*;
            if (ptr_info.child.* != .struct_type) {
                const desc = try self.formatTypeText(ptr_self.ty, s);
                defer desc.deinit();
                try self.diags.add(
                    file.location(sa.value),
                    .semantic,
                    "cannot assign field on value of type '{s}'",
                    .{desc.bytes},
                );
                return error.Reported;
            }

            const struct_type = @constCast(ptr_info.child.*.struct_type);
            if (sf.field_index >= struct_type.fields.len) return error.SymbolNotFound;
            const field_index: usize = @intCast(sf.field_index);
            const declared_field_ty = struct_type.fields[field_index].ty;
            rhs = try typ.coerceExprToType(declared_field_ty, rhs, file.location(pa.value), s, self.allocator, self.diags);
            try self.recordAbstractFieldStorageType(struct_type, field_index, rhs.ty, file.location(pa.value), s);
            const field_ty = typ.effectiveStructFieldType(struct_type.fields[field_index]);

            if (!typ.typesExactlyEqual(field_ty, rhs.ty)) {
                const pair = try self.formatTypePairText(field_ty, rhs.ty, s);
                defer pair.deinit();
                try self.diags.add(
                    file.location(pa.value),
                    .semantic,
                    "cannot assign '{s}' to '{s}' (explicit casts not supported yet)",
                    .{ pair.actual.bytes, pair.expected.bytes },
                );
                return error.Reported;
            }

            const store = sg.StructFieldStore{
                .struct_ptr = ptr_self.node,
                .struct_type = struct_type,
                .field_index = sf.field_index,
                .field_type = field_ty,
                .value = rhs.node,
            };

            const node = try sg.makeSGNode(.{ .struct_field_store = store }, undefined, self.allocator);
            try s.nodes.append(node);
            return .{ .node = node, .ty = .{ .builtin = .Any } };
        }

        if (file.tag(pa.target) != .dereference) return error.InvalidType;

        const tgt_te = try self.visitNode(file.ref(pa.target), s);
        const deref_sg = tgt_te.node.content.dereference;

        rhs = try typ.coerceExprToType(deref_sg.ty, rhs, file.location(pa.value), s, self.allocator, self.diags);

        if (deref_sg.pointer_type.*.mutability != .read_write) {
            const ptr_ty: sg.Type = .{ .pointer_type = deref_sg.pointer_type };
            const ptr_str = try self.formatTypeText(ptr_ty, s);
            defer ptr_str.deinit();
            try self.diags.add(
                file.location(pa.target),
                .semantic,
                "cannot assign through pointer '{s}' because it is read-only; use '$&' when acquiring it",
                .{ptr_str.bytes},
            );
            return error.Reported;
        }

        if (!typ.typesStructurallyEqual(deref_sg.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(deref_sg.ty, rhs.ty, s);
            defer pair.deinit();
            try self.diags.add(
                file.location(pa.value),
                .semantic,
                "cannot assign '{s}' to '{s}' (explicit casts not supported yet)",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        const n = try sg.makeSGNode(.{ .pointer_assignment = .{
            .pointer = deref_sg.pointer,
            .value = rhs.node,
        } }, undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn extractTypeArgument(self: *Semantizer, call_ref: syn.SyntaxRef, s: *Scope) SemErr!sg.Type {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const arg_node = call.input;
        if (file.tag(arg_node) != .struct_value_literal) {
            try self.diags.add(
                file.location(arg_node),
                .semantic,
                "builtin expects .type argument (example: .type = Int32)",
                .{},
            );
            return error.Reported;
        }

        const svl = file.structValueLiteral(arg_node).?;
        if (svl.fields.len != 1) {
            try self.diags.add(
                file.location(arg_node),
                .semantic,
                "builtin expects a single '.type' argument",
                .{},
            );
            return error.Reported;
        }

        const field = file.valueField(svl.fields[0]).?;
        if (field.name_token == null or !std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token.?), "type")) {
            try self.diags.add(
                file.location(field.value),
                .semantic,
                "expected '.type' argument",
                .{},
            );
            return error.Reported;
        }

        return self.resolveTypeExpression(file.ref(field.value), s);
    }

    fn extractNamedTypeArgument(
        self: *Semantizer,
        call_ref: syn.SyntaxRef,
        arg_name: []const u8,
        s: *Scope,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const stargs = call.type_arguments_struct orelse {
            try self.diags.add(
                file.tokenLocation(call.callee_token),
                .semantic,
                "cast expects named type arguments like cast#(.to: UIntNative)(.value = ...)",
                .{},
            );
            return error.Reported;
        };

        for (file.structTypeLiteral(stargs).?.fields) |field_node| {
            const field = file.structTypeField(field_node).?;
            if (!std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token), arg_name)) continue;
            const field_ty = field.type_node orelse {
                try self.diags.add(
                    file.tokenLocation(field.name_token),
                    .semantic,
                    "type argument '.{s}' must specify a type",
                    .{arg_name},
                );
                return error.Reported;
            };
            return self.resolveSyntaxType(file.ref(field_ty), s);
        }

        try self.diags.add(
            file.tokenLocation(call.callee_token),
            .semantic,
            "cast expects type argument '.{s}'",
            .{arg_name},
        );
        return error.Reported;
    }

    fn extractValueArgument(
        self: *Semantizer,
        call_ref: syn.SyntaxRef,
        arg_name: []const u8,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        return self.visitNode(try self.extractValueArgumentNode(call_ref, arg_name), s);
    }

    fn extractValueArgumentNode(self: *Semantizer, call_ref: syn.SyntaxRef, arg_name: []const u8) SemErr!syn.SyntaxRef {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const input = file.structValueLiteral(call.input) orelse {
            try self.diags.add(file.location(call.input), .semantic, "builtin expects '.{s}' argument", .{arg_name});
            return error.Reported;
        };
        if (input.fields.len == 1) {
            const field = file.valueField(input.fields[0]).?;
            if (input.positional_prefix_count == 1 or (field.name_token != null and
                std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token.?), arg_name)))
                return file.ref(field.value);
        }
        try self.diags.add(file.location(call.input), .semantic, "builtin expects a single '.{s}' argument", .{arg_name});
        return error.Reported;
    }

    fn handleCastBuiltin(self: *Semantizer, call_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const value_te = try self.extractValueArgument(call_ref, "value", s);
        const target_ty = try self.extractNamedTypeArgument(call_ref, "to", s);

        if (typ.typesExactlyEqual(value_te.ty, target_ty)) {
            return value_te;
        }

        const source_is_ptr = value_te.ty == .pointer_type;
        const target_is_ptr = target_ty == .pointer_type;
        const source_is_native_uint = value_te.ty == .builtin and value_te.ty.builtin == .UIntNative;
        const target_is_native_uint = target_ty == .builtin and target_ty.builtin == .UIntNative;

        const compatible_pointer_cast = source_is_ptr and target_is_ptr and typ.typesCompatible(target_ty, value_te.ty);
        if (!((source_is_ptr and target_is_native_uint) or (source_is_native_uint and target_is_ptr) or compatible_pointer_cast)) {
            const pair = try self.formatTypePairText(target_ty, value_te.ty, s);
            defer pair.deinit();
            try self.diags.add(
                file.location(call.input),
                .semantic,
                "unsupported explicit cast from '{s}' to '{s}'",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        const cast_node = try sg.makeSGNode(.{ .explicit_cast = .{
            .value = value_te.node,
            .target_type = target_ty,
        } }, file.location(call.input), self.allocator);
        try s.nodes.append(cast_node);
        return .{ .node = cast_node, .ty = target_ty };
    }

    fn resolveTypeExpression(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!sg.Type {
        if (self.syntaxFile(node).syntaxType(node.node) != null) return self.resolveSyntaxType(node, s);
        const file = self.syntaxFile(node);
        if (file.tag(node.node) == .identifier) {
            return self.resolveSyntaxTypeName(node, file.mainToken(node.node), null, s, false) catch {
                try self.diags.add(file.location(node.node), .semantic, "unknown type '{s}'", .{file.tokenText(&self.diags.source_db, file.mainToken(node.node))});
                return error.Reported;
            };
        }
        if (file.functionCall(node.node)) |call| {
            if (std.mem.eql(u8, file.tokenText(&self.diags.source_db, call.callee_token), "type_of")) return (try self.extractValueArgument(node, "value", s)).ty;
            try self.diags.add(file.location(node.node), .semantic, "unsupported expression in '.type' argument", .{});
            return error.Reported;
        }

        try self.diags.add(self.nodeLocation(node), .semantic, "expected type expression", .{});
        return error.Reported;
    }

    fn resolveSyntaxTypeName(
        self: *Semantizer,
        owner: syn.SyntaxRef,
        name_token: syn.TokenIndex,
        qualifier_token: ?syn.TokenIndex,
        s: *Scope,
        preserve_abstract: bool,
    ) SemErr!sg.Type {
        const name = self.tokenText(owner, name_token);
        const location = self.tokenLocation(owner, qualifier_token orelse name_token);
        if (qualifier_token) |qualifier| {
            const module_name = self.tokenText(owner, qualifier);
            const module_dir = s.lookupModuleAlias(module_name) orelse return error.UnknownType;
            const declaration = s.lookupTypeInModule(module_dir, name) orelse return error.UnknownType;
            if (!(try self.typeIsVisible(declaration, self.locationPath(location)))) {
                try self.addPrivateMemberDiag(location, "type", name);
                return error.Reported;
            }
            return declaration.ty;
        }
        if (typ.builtinFromName(name)) |builtin| return .{ .builtin = builtin };
        if (s.lookupAbstractInfo(name) != null) {
            if (preserve_abstract) return (s.lookupType(name) orelse return error.UnknownType).ty;
            if (s.lookupAbstractDefault(name)) |default| return default.ty;
            return error.AbstractNeedsDefault;
        }
        const declaration = s.lookupType(name) orelse return error.UnknownType;
        if (!typeDeclIsReady(declaration)) return error.UnknownType;
        if (!(try self.typeIsVisible(declaration, self.locationPath(location)))) {
            try self.addPrivateMemberDiag(location, "type", name);
            return error.Reported;
        }
        return declaration.ty;
    }

    fn resolveSyntaxType(self: *Semantizer, node: syn.SyntaxRef, s: *Scope) SemErr!sg.Type {
        return self.resolveSyntaxTypeWithMode(node, s, false, null);
    }

    fn resolveSyntaxTypeWithMode(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        preserve_abstract: bool,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(node);
        return switch (file.syntaxType(node.node) orelse return error.InvalidType) {
            .name => |name| blk: {
                if (subst) |values| if (name.qualifier_token == null) {
                    if (values.types.get(self.tokenText(node, name.name_token))) |mapped| break :blk mapped;
                };
                break :blk try self.resolveSyntaxTypeName(node, name.name_token, name.qualifier_token, s, preserve_abstract);
            },
            .pointer => |pointer| blk: {
                const child = try self.allocator.create(sg.Type);
                child.* = try self.resolveSyntaxTypeWithMode(file.ref(pointer.child), s, preserve_abstract, subst);
                const semantic_pointer = try self.allocator.create(sg.PointerType);
                semantic_pointer.* = .{ .mutability = @enumFromInt(@intFromEnum(pointer.mutability)), .child = child };
                break :blk .{ .pointer_type = semantic_pointer };
            },
            .array => |array| blk: {
                const length = std.fmt.parseInt(usize, self.tokenText(node, array.length_token), 0) catch return error.InvalidType;
                break :blk try self.makeArrayType(length, try self.resolveSyntaxTypeWithMode(file.ref(array.element), s, preserve_abstract, subst));
            },
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse return error.InvalidType;
                if (base != .name or base.name.qualifier_token != null) return error.InvalidType;
                const base_name = file.tokenText(&self.diags.source_db, base.name.name_token);
                break :blk try self.resolveCompactGenericTypeWithMode(
                    base_name,
                    file.tokenLocation(base.name.name_token),
                    file.ref(generic.arguments),
                    s,
                    preserve_abstract,
                    subst,
                );
            },
            .struct_literal => .{ .struct_type = if (subst) |values| try self.structTypeFromNodeWithSubst(node, s, values) else try self.structTypeFromNode(node, s) },
            .choice_literal => .{ .choice_type = if (subst) |values| try self.choiceTypeFromNodeWithSubst(node, s, values) else try self.choiceTypeFromNode(node, s) },
            .nullable => |inner| try self.resolveCompactNullableType(file.ref(inner), s, preserve_abstract, subst),
            .inferred_errable => |inner| try self.makeCompactInferredErrableType(file.ref(inner), s, subst),
        };
    }

    fn resolveSyntaxTypeWithSubstPreservingAbstracts(
        self: *Semantizer,
        node: syn.SyntaxRef,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        const file = self.syntaxFile(node);
        return switch (file.syntaxType(node.node) orelse return error.InvalidType) {
            .name => |name| blk: {
                if (name.qualifier_token == null) {
                    const text = self.tokenText(node, name.name_token);
                    if (subst.types.get(text)) |mapped| break :blk mapped;
                }
                break :blk try self.resolveSyntaxTypeName(node, name.name_token, name.qualifier_token, s, true);
            },
            .pointer => |pointer| blk: {
                const child = try self.allocator.create(sg.Type);
                child.* = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(self.childRef(node, pointer.child), s, subst);
                const semantic_pointer = try self.allocator.create(sg.PointerType);
                semantic_pointer.* = .{ .mutability = @enumFromInt(@intFromEnum(pointer.mutability)), .child = child };
                break :blk .{ .pointer_type = semantic_pointer };
            },
            .array => |array| blk: {
                const length = std.fmt.parseInt(usize, self.tokenText(node, array.length_token), 0) catch return error.InvalidType;
                const element = try self.resolveSyntaxTypeWithSubstPreservingAbstracts(self.childRef(node, array.element), s, subst);
                break :blk try self.makeArrayType(length, element);
            },
            .generic => |generic| blk: {
                const base = file.syntaxType(generic.base) orelse return error.InvalidType;
                if (base != .name or base.name.qualifier_token != null) return error.InvalidType;
                const base_name = file.tokenText(&self.diags.source_db, base.name.name_token);
                if (s.lookupAbstractInfo(base_name) != null) {
                    if (subst.types.get(base_name)) |mapped| break :blk mapped;
                }
                break :blk try self.resolveCompactGenericTypeWithMode(
                    base_name,
                    file.tokenLocation(base.name.name_token),
                    file.ref(generic.arguments),
                    s,
                    true,
                    subst,
                );
            },
            .struct_literal => .{ .struct_type = try self.structTypeFromNodeWithSubst(node, s, subst) },
            .choice_literal => .{ .choice_type = try self.choiceTypeFromNodeWithSubst(node, s, subst) },
            .nullable => |inner| try self.resolveCompactNullableType(file.ref(inner), s, true, subst),
            .inferred_errable => |inner| try self.makeCompactInferredErrableType(file.ref(inner), s, subst),
        };
    }

    fn syntaxExprUsesParam(self: *Semantizer, node: syn.SyntaxRef, param_name: []const u8) bool {
        const file = self.syntaxFile(node);
        return switch (file.tag(node.node)) {
            .identifier => std.mem.eql(u8, file.tokenText(&self.diags.source_db, file.mainToken(node.node)), param_name),
            .binary_add,
            .binary_subtract,
            .binary_multiply,
            .binary_divide,
            .binary_modulo,
            .compare_equal,
            .compare_not_equal,
            .compare_less,
            .compare_greater,
            .compare_less_equal,
            .compare_greater_equal,
            .logical_and,
            .logical_or,
            => if (file.binaryOperation(node.node)) |operation|
                self.syntaxExprUsesParam(file.ref(operation.lhs), param_name) or
                    self.syntaxExprUsesParam(file.ref(operation.rhs), param_name)
            else
                false,
            else => false,
        };
    }

    fn inferArrayTypeFromList(
        self: *Semantizer,
        ll: *const sg.ListLiteral,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!*sg.ArrayType {
        if (ll.elements.len == 0) {
            try self.diags.add(
                loc,
                .semantic,
                "cannot infer array type from empty list literal; specify the type explicitly",
                .{},
            );
            return error.Reported;
        }

        const first_ty = ll.element_types[0];
        for (ll.element_types, 0..) |elem_ty, idx| {
            if (typ.typesStructurallyEqual(first_ty, elem_ty)) continue;
            const pair = try self.formatTypePairText(first_ty, elem_ty, s);
            defer pair.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "array element {d} has type '{s}', expected '{s}'",
                .{ idx, pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        const arr_ty = try self.makeArrayType(ll.elements.len, first_ty);
        return @constCast(arr_ty.array_type);
    }

    //──────────────────────────────────────────────────── HELPERS
    fn handleBuiltinTypeInfo(
        self: *Semantizer,
        kind: typ.BuiltinTypeInfoKind,
        call_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const target_ty = try self.extractTypeArgument(call_ref, s);

        const value = switch (kind) {
            .size => typ.computeTypeSize(target_ty),
            .alignment => typ.computeTypeAlignment(target_ty),
        };

        const file = self.syntaxFile(call_ref);
        const loc = file.location(file.functionCall(call_ref.node).?.input);
        if (value > std.math.maxInt(i64)) return error.InvalidType;
        return try typ.makeIntLiteral(self.allocator, loc, @intCast(value), .{ .builtin = .UIntNative });
    }

    fn handleLengthBuiltin(
        self: *Semantizer,
        call_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const arg_loc = file.location(call.input);
        const input = file.structValueLiteral(call.input) orelse return error.SymbolNotFound;
        if (input.fields.len != 1) return error.SymbolNotFound;
        const field = file.valueField(input.fields[0]).?;
        if (input.positional_prefix_count != 1 and (field.name_token == null or
            !std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token.?), "value")))
            return error.SymbolNotFound;
        const value_te = try self.visitNode(file.ref(field.value), s);

        switch (value_te.node.content) {
            .list_literal => |ll| {
                const len_u64: u64 = @intCast(ll.elements.len);
                if (len_u64 > std.math.maxInt(i64)) {
                    try self.diags.add(
                        arg_loc,
                        .semantic,
                        "length result exceeds supported integer range",
                        .{},
                    );
                    return error.Reported;
                }
                return try typ.makeIntLiteral(self.allocator, arg_loc, @intCast(len_u64), .{ .builtin = .UIntNative });
            },
            .array_literal => |al| {
                const len_u64: u64 = @intCast(al.length);
                if (len_u64 > std.math.maxInt(i64)) {
                    try self.diags.add(
                        arg_loc,
                        .semantic,
                        "length result exceeds supported integer range",
                        .{},
                    );
                    return error.Reported;
                }
                return try typ.makeIntLiteral(self.allocator, arg_loc, @intCast(len_u64), .{ .builtin = .UIntNative });
            },
            else => {},
        }

        if (value_te.ty == .array_type) {
            const arr = value_te.ty.array_type.*;
            const len_u64: u64 = @intCast(arr.length);
            if (len_u64 > std.math.maxInt(i64)) {
                try self.diags.add(
                    arg_loc,
                    .semantic,
                    "length result exceeds supported integer range",
                    .{},
                );
                return error.Reported;
            }
            return try typ.makeIntLiteral(self.allocator, arg_loc, @intCast(len_u64), .{ .builtin = .UIntNative });
        }

        return error.SymbolNotFound;
    }

    fn handleTypeOf(self: *Semantizer, call_ref: syn.SyntaxRef, s: *Scope) SemErr!typ.TypedExpr {
        const value = try self.extractValueArgument(call_ref, "value", s);
        const file = self.syntaxFile(call_ref);
        return typ.makeTypeLiteral(self.allocator, file.location(file.functionCall(call_ref.node).?.input), value.ty);
    }

    fn handleIsBuiltin(
        self: *Semantizer,
        call_ref: syn.SyntaxRef,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const file = self.syntaxFile(call_ref);
        const call = file.functionCall(call_ref.node) orelse return error.InvalidType;
        const arg_node = call.input;
        if (file.tag(arg_node) != .struct_value_literal) {
            try self.diags.add(
                file.location(arg_node),
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const svl = file.structValueLiteral(arg_node).?;
        var value_field: ?syn.ValueField = null;
        var variant_field: ?syn.ValueField = null;

        for (svl.fields, 0..) |field_node, idx| {
            const field = file.valueField(field_node).?;
            if (idx < svl.positional_prefix_count) {
                if (idx == 0) {
                    if (value_field != null) {
                        try self.addDuplicateIsBuiltinArgument(file.location(arg_node));
                        return error.Reported;
                    }
                    value_field = field;
                } else if (idx == 1) {
                    if (variant_field != null) {
                        try self.addDuplicateIsBuiltinArgument(file.location(arg_node));
                        return error.Reported;
                    }
                    variant_field = field;
                } else {
                    try self.diags.add(
                        file.location(field_node),
                        .semantic,
                        "is only accepts two positional arguments: value and variant",
                        .{},
                    );
                    return error.Reported;
                }
            } else if (std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token.?), "value")) {
                if (value_field != null) {
                    try self.addDuplicateIsBuiltinArgument(file.location(field_node));
                    return error.Reported;
                }
                value_field = field;
            } else if (std.mem.eql(u8, file.tokenText(&self.diags.source_db, field.name_token.?), "variant")) {
                if (variant_field != null) {
                    try self.addDuplicateIsBuiltinArgument(file.location(field_node));
                    return error.Reported;
                }
                variant_field = field;
            } else {
                try self.diags.add(
                    file.location(field_node),
                    .semantic,
                    "is only accepts '.value' and '.variant' arguments",
                    .{},
                );
                return error.Reported;
            }
        }

        if (value_field == null or variant_field == null) {
            try self.diags.add(
                file.location(arg_node),
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const value_te = try self.visitNode(file.ref(value_field.?.value), s);
        if (value_te.ty != .choice_type) {
            const desc = try self.formatTypeText(value_te.ty, s);
            defer desc.deinit();
            try self.diags.add(
                file.location(value_field.?.value),
                .semantic,
                "is expects '.value' to be a choice, found '{s}'",
                .{desc.bytes},
            );
            return error.Reported;
        }

        const variant_te = blk_variant: {
            const variant_node = variant_field.?.value;
            if (file.choiceLiteral(variant_node)) |raw_variant| {
                if (raw_variant.payload == null) {
                    const choice_ty = value_te.ty.choice_type;
                    for (choice_ty.variants, 0..) |variant, idx| {
                        if (!std.mem.eql(u8, variant.name, file.tokenText(&self.diags.source_db, raw_variant.name_token))) continue;

                        const typed = try self.allocator.create(sg.ChoiceLiteral);
                        typed.* = .{
                            .variant_name = file.tokenText(&self.diags.source_db, raw_variant.name_token),
                            .choice_type = choice_ty,
                            .variant_index = @intCast(idx),
                            .payload = null,
                        };
                        const typed_node = try sg.makeSGNode(.{ .choice_literal = typed }, file.location(variant_node), self.allocator);
                        typed_node.sem_type = value_te.ty;
                        break :blk_variant typ.TypedExpr{ .node = typed_node, .ty = value_te.ty };
                    }

                    const choice_text = try self.formatTypeText(value_te.ty, s);
                    defer choice_text.deinit();
                    try self.diags.add(
                        file.location(variant_node),
                        .semantic,
                        "choice type '{s}' has no variant '..{s}'",
                        .{ choice_text.bytes, file.tokenText(&self.diags.source_db, raw_variant.name_token) },
                    );
                    return error.Reported;
                }
            }

            var coerced = try self.visitNode(file.ref(variant_node), s);
            coerced = try typ.coerceExprToType(value_te.ty, coerced, file.location(variant_field.?.value), s, self.allocator, self.diags);
            break :blk_variant coerced;
        };

        if (!typ.typesExactlyEqual(value_te.ty, variant_te.ty)) {
            try self.diags.add(
                file.location(variant_field.?.value),
                .semantic,
                "is expects '.variant' to belong to the same choice type as '.value'",
                .{},
            );
            return error.Reported;
        }

        const cmp_ptr = try self.allocator.create(sg.Comparison);
        cmp_ptr.* = .{
            .operator = .equal,
            .left = value_te.node,
            .right = variant_te.node,
        };

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, file.location(arg_node), self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Bool } };
    }

    fn registerDefer(self: *Semantizer, s: *Scope, nodes: []const *sg.SGNode) !void {
        if (nodes.len == 0) return;
        const copy = try self.allocator.alloc(*sg.SGNode, nodes.len);
        std.mem.copyForwards(*sg.SGNode, copy, nodes);
        try s.deferred.append(.{ .nodes = copy });
    }

    fn clearDeferred(self: *Semantizer, s: *Scope) void {
        for (s.deferred.items) |group| self.allocator.free(group.nodes);
        s.deferred.deinit();
    }

    fn maybeScheduleAutoDeinit(
        self: *Semantizer,
        binding: *sg.BindingDeclaration,
        loc: tok.Location,
        s: *Scope,
    ) !void {
        if (s.parent == null) return;
        if (typeCanHaveVisibleAutoDeinit(binding.ty)) {
            if (try self.findVisibleAutoDeinit(binding, loc, s)) |resolved| {
                try self.discoverFunctionReference(resolved.function);
                const auto_ptr = try self.allocator.create(sg.AutoDeinitBinding);
                auto_ptr.* = .{
                    .binding = binding,
                    .deinit_fn = resolved.function,
                    .input = resolved.input.node,
                    .self_field_index = resolved.self_field_index,
                    .fields = &.{},
                };

                const call_node = try sg.makeSGNode(.{ .auto_deinit_binding = auto_ptr }, loc, self.allocator);
                try self.registerDefer(s, &[_]*sg.SGNode{call_node});
                return;
            }
        }

        const fields = try buildStructuralAutoDeinitFields(self, binding.ty, loc, s, self.allocator);
        if (fields.len == 0) return;
        try self.discoverAutoDeinitFieldFunctions(fields);
        const auto_ptr = try self.allocator.create(sg.AutoDeinitBinding);
        auto_ptr.* = .{
            .binding = binding,
            .deinit_fn = null,
            .input = null,
            .fields = fields,
        };

        const call_node = try sg.makeSGNode(.{ .auto_deinit_binding = auto_ptr }, loc, self.allocator);
        try self.registerDefer(s, &[_]*sg.SGNode{call_node});
    }

    fn discoverAutoDeinitFieldFunctions(self: *Semantizer, fields: []const sg.AutoDeinitField) !void {
        for (fields) |field| {
            if (field.deinit_fn) |function| try self.discoverFunctionReference(function);
            try self.discoverAutoDeinitFieldFunctions(field.fields);
        }
    }

    // ─────────────────────────────────────────────────── Helpers reintento
    fn pushTopLevelForRetry(self: *Semantizer) !void {
        if (!self.defer_unknown_top_level) return;
        if (self.current_top_node) |ptr| {
            self.retry_enqueue_attempts += 1;
            for (self.pending_next.items) |pending| {
                if (pending.file_id == ptr.file_id and pending.node == ptr.node) return;
            }
            try self.pending_next.append(ptr);
            self.retry_enqueue_unique += 1;
            switch (self.nodeTag(ptr)) {
                .function_declaration, .function_declaration_once, .test_declaration => self.retry_function_nodes += 1,
                .type_declaration, .c_enum_declaration, .c_union_declaration => self.retry_type_nodes += 1,
                .symbol_declaration_constant, .symbol_declaration_variable => self.retry_symbol_nodes += 1,
                else => self.retry_other_nodes += 1,
            }
        }
    }
    fn walkAutoDeinitOnceReachability(
        self: *Semantizer,
        auto: *const sg.AutoDeinitBinding,
        current_fn: *const sg.FunctionDeclaration,
        loc: tok.Location,
        state: *OnceTraversalState,
    ) SemErr!void {
        if (auto.deinit_fn) |deinit_fn| {
            if (deinit_fn.is_once) {
                try self.recordOnceConsumption(deinit_fn, current_fn, loc, state);
            }
            try self.walkFunctionOnceReachability(deinit_fn, loc, state);
        }

        try self.walkAutoDeinitFieldsOnceReachability(auto.fields, current_fn, loc, state);
    }

    fn walkAutoDeinitFieldsOnceReachability(
        self: *Semantizer,
        fields: []const sg.AutoDeinitField,
        current_fn: *const sg.FunctionDeclaration,
        loc: tok.Location,
        state: *OnceTraversalState,
    ) SemErr!void {
        for (fields) |field| {
            if (field.deinit_fn) |deinit_fn| {
                if (deinit_fn.is_once) {
                    try self.recordOnceConsumption(deinit_fn, current_fn, loc, state);
                }
                try self.walkFunctionOnceReachability(deinit_fn, loc, state);
            }
            try self.walkAutoDeinitFieldsOnceReachability(field.fields, current_fn, loc, state);
        }
    }
};

fn cleanupRootBinding(node: *const sg.SGNode) ?*const sg.BindingDeclaration {
    return switch (node.content) {
        .binding_use => |binding| binding,
        .address_of => |inner| cleanupRootBinding(inner),
        .dereference => |deref| cleanupRootBinding(deref.pointer),
        .struct_field_access => |access| cleanupRootBinding(access.struct_value),
        .array_index => |index| cleanupRootBinding(index.array_ptr),
        else => null,
    };
}

fn buildStructuralAutoDeinitFields(
    sema: *Semantizer,
    ty: sg.Type,
    loc: tok.Location,
    s: *Scope,
    allocator: *const std.mem.Allocator,
) ![]const sg.AutoDeinitField {
    return switch (ty) {
        .struct_type => |st| blk: {
            var fields = std.array_list.Managed(sg.AutoDeinitField).init(allocator.*);
            errdefer fields.deinit();

            for (st.fields, 0..) |field, idx| {
                if (try sema.findVisibleAutoDeinitForType(field.ty, loc, s)) |deinit_info| {
                    try fields.append(.{
                        .field_index = @intCast(idx),
                        .deinit_fn = deinit_info.function,
                        .input = deinit_info.input.node,
                        .self_field_index = deinit_info.self_field_index,
                        .fields = &.{},
                    });
                    continue;
                }

                const nested = try buildStructuralAutoDeinitFields(sema, field.ty, loc, s, allocator);
                if (nested.len > 0) {
                    try fields.append(.{
                        .field_index = @intCast(idx),
                        .deinit_fn = null,
                        .input = null,
                        .self_field_index = 0,
                        .fields = nested,
                    });
                    continue;
                }

                if (!typ.isTypeTriviallyCopyable(field.ty, s)) {
                    fields.deinit();
                    break :blk &.{};
                }
            }

            break :blk try fields.toOwnedSlice();
        },
        else => &.{},
    };
}

fn typeCanHaveVisibleAutoDeinit(ty: sg.Type) bool {
    // Anonymous types do not own a nominal `deinit`; their cleanup is purely
    // structural. Restricting visible deinit lookup to nominal identities keeps
    // the semantics aligned with the language model and avoids repeating
    // expensive nominal lookup work for anonymous locals inside function bodies.
    // Current timing data still shows most `semantizing` cost concentrated in
    // function bodies, especially local declarations and cleanup-sensitive work,
    // so this remains a hot path worth keeping cheap and explicit.
    return switch (ty) {
        .struct_type => |st| st.identity != null,
        .choice_type => |ct| ct.identity != null,
        .array_type => |arr| arr.identity != null,
        else => false,
    };
}

//────────────────────────────────────────────────────────────────────── BUILDER SCOPE

fn binaryOpVerb(op: tok.BinaryOperator) []const u8 {
    return switch (op) {
        .addition => "add",
        .subtraction => "subtract",
        .multiplication => "multiply",
        .division => "divide",
        .modulo => "mod",
    };
}
