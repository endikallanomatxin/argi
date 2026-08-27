const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");
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

const CallAccessMode = enum {
    value,
    read,
    write,
};

const CallBindingAccess = struct {
    root_name: []const u8,
    mode: CallAccessMode,
    access_node: *const sg.SGNode,
};

const ReachFunctionContext = struct {
    function_name: []const u8,
    location: tok.Location,
    input_struct: *sg.StructType,
    body_scope: *Scope,
};

const SignatureTypeCacheMode = enum {
    preserving_abstracts,
    signature_predeclaration,
};

const SignatureTypeCacheKey = struct {
    node: *const syn.Type,
    mode: SignatureTypeCacheMode,
};

const PendingFunctionBody = struct {
    top_node: *const syn.STNode,
    decl: syn.FunctionDeclaration,
    location: tok.Location,
    function: *sg.FunctionDeclaration,
    is_test: bool = false,
    prepared_scope: ?*Scope = null,
    prepared_input_struct: ?*sg.StructType = null,
};

pub const SemantizerOptions = struct {
    include_tests: bool = false,
    selected_test_name: ?[]const u8 = null,
    implicit_testing_module_dir: ?[]const u8 = null,
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
    st_nodes: []const *syn.STNode, // entrada
    root_list: std.array_list.Managed(*sg.SGNode), // buffer mut
    root_nodes: []const *sg.SGNode = &.{}, // slice final
    diags: *diagnostic.Diagnostics,
    options: SemantizerOptions,

    // ── Reintentos top-level
    pending_now: std.array_list.Managed(*const syn.STNode),
    pending_next: std.array_list.Managed(*const syn.STNode),
    defer_unknown_top_level: bool = false,
    current_top_node: ?*const syn.STNode = null,
    max_retry_rounds: u32 = 8,
    retry_enqueue_attempts: u32 = 0,
    retry_enqueue_unique: u32 = 0,
    retry_function_nodes: u32 = 0,
    retry_type_nodes: u32 = 0,
    retry_symbol_nodes: u32 = 0,
    retry_other_nodes: u32 = 0,
    function_semantize_mode: FunctionSemantizeMode = .full,
    pending_function_bodies: std.array_list.Managed(PendingFunctionBody),
    signature_type_cache: std.AutoHashMap(SignatureTypeCacheKey, sg.Type),
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
        st: []const *syn.STNode,
        diags: *diagnostic.Diagnostics,
        options: SemantizerOptions,
    ) Semantizer {
        return .{
            .allocator = alloc,
            .io = io,
            .st_nodes = st,
            .root_list = std.array_list.Managed(*sg.SGNode).init(alloc.*),
            .diags = diags,
            .options = options,
            .pending_now = std.array_list.Managed(*const syn.STNode).init(alloc.*),
            .pending_next = std.array_list.Managed(*const syn.STNode).init(alloc.*),
            .pending_function_bodies = std.array_list.Managed(PendingFunctionBody).init(alloc.*),
            .signature_type_cache = std.AutoHashMap(SignatureTypeCacheKey, sg.Type).init(alloc.*),
            .function_reach_stack = std.array_list.Managed(ReachFunctionContext).init(alloc.*),
        };
    }

    fn freshFunctionId(self: *Semantizer) u32 {
        const id = self.next_function_id;
        self.next_function_id += 1;
        return id;
    }

    fn topLevelNodeIsTest(self: *Semantizer, n: *const syn.STNode) bool {
        _ = self;
        return n.content == .test_declaration;
    }

    fn topLevelNodeIsCallable(self: *Semantizer, n: *const syn.STNode) bool {
        return switch (n.content) {
            .function_declaration => true,
            .test_declaration => self.options.include_tests,
            else => false,
        };
    }

    fn functionDeclFromTopLevelNode(self: *Semantizer, n: *const syn.STNode) syn.FunctionDeclaration {
        _ = self;
        return switch (n.content) {
            .function_declaration => |decl| decl,
            .test_declaration => |decl| decl.decl,
            else => unreachable,
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

    fn ignoreOrLogStagedTopLevelError(self: *Semantizer, n: *const syn.STNode, err: anyerror) void {
        _ = self;
        switch (err) {
            error.Reported, error.UnknownType, error.SymbolNotFound => return,
            else => {},
        }

        log.warn(
            "staged top-level semantizing of '{s}' failed at {s}:{d}:{d} with {s}",
            .{
                @tagName(std.meta.activeTag(n.content)),
                n.location.file,
                n.location.line,
                n.location.column,
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
        self.signature_type_cache.clearRetainingCapacity();
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
        self.function_semantize_mode = .full;
        self.pending_function_bodies.items.len = 0;

        // 1) Pasada inicial: estabiliza primero top-level de soporte y sólo
        // después entra en funciones. Esto evita que los cuerpos se conviertan
        // en la fuente principal de dependencias top-level pendientes.
        const initial_start = nowNs(self.io);
        self.defer_unknown_top_level = true;
        const support_top_level_start = nowNs(self.io);
        for (self.st_nodes) |n| {
            if (self.topLevelNodeIsCallable(n)) continue;
            if (n.content == .test_declaration and !self.options.include_tests) continue;
            self.current_top_node = n;
            _ = self.visitNode(n.*, &global) catch |err| {
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
                if (self.visitNode(pn.*, &global)) |_| {
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
        for (self.st_nodes) |n| {
            if (!self.topLevelNodeIsCallable(n)) continue;
            self.current_top_node = n;
            _ = self.visitNode(n.*, &global) catch |err| {
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
                if (self.visitNode(pn.*, &global)) |_| {
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
                if (pn.content == .function_declaration) continue;
                self.current_top_node = pn;
                if (self.visitNode(pn.*, &global)) |_| {
                    progressed = true;
                } else |_| {
                    // Las causas distintas de UnknownType ya se reportan dentro.
                    // UnknownType vuelve a entrar en pending_next si procede.
                }
            }
            for (self.pending_now.items) |pn| {
                if (pn.content != .function_declaration) continue;
                self.current_top_node = pn;
                if (self.visitNode(pn.*, &global)) |_| {
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
                _ = self.visitNode(pn.*, &global) catch |err| {
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
        top_node: *const syn.STNode,
        decl: syn.FunctionDeclaration,
        loc: tok.Location,
        function: *sg.FunctionDeclaration,
        is_test: bool,
    ) !void {
        for (self.pending_function_bodies.items) |pending| {
            if (std.mem.eql(u8, pending.location.file, loc.file) and pending.location.offset == loc.offset) return;
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

        // Output defaults belong to the body-facing execution state, so only
        // stage them once every callable interface is complete.
        const output_defaults_start = nowNs(self.io);
        for (self.pending_function_bodies.items, 0..) |*pending, idx| {
            if (deferred[idx]) continue;
            self.current_top_node = pending.top_node;
            self.prepareRegularFunctionBodyScope(pending, global) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => {
                    try self.pushTopLevelForRetry();
                    deferred[idx] = true;
                },
                else => return err,
            };
        }
        timings.output_defaults_ns = @intCast(nowNs(self.io) - output_defaults_start);

        const body_start = nowNs(self.io);
        for (self.pending_function_bodies.items, 0..) |*pending, idx| {
            if (deferred[idx]) continue;
            self.current_top_node = pending.top_node;
            self.semantizePreparedFunctionBody(pending) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => {
                    try self.pushTopLevelForRetry();
                    deferred[idx] = true;
                },
                else => return err,
            };
        }
        timings.body_ns = @intCast(nowNs(self.io) - body_start);
        self.current_top_node = null;
        return timings;
    }

    fn predeclareTopLevelSymbols(self: *Semantizer, global: *Scope) SemErr!void {
        for (self.st_nodes) |node| {
            switch (node.content) {
                .symbol_declaration => |decl| {
                    try self.predeclareTopLevelImportAlias(decl, global, node.location);
                    try self.predeclareTopLevelBinding(decl, global, node.location);
                },
                .abstract_declaration => |decl| try self.predeclareTopLevelAbstract(decl, global),
                .type_declaration => |decl| try self.predeclareTopLevelType(decl, global),
                .choice_option_declaration => |decl| try self.predeclareTopLevelChoiceOption(decl, global, node.location),
                .function_declaration => |decl| try self.predeclareTopLevelFunction(decl, global, node.location, false),
                .test_declaration => |decl| if (self.options.include_tests) try self.predeclareTopLevelFunction(decl.decl, global, node.location, true),
                else => {},
            }
        }
    }

    fn predeclareTopLevelAbstract(
        self: *Semantizer,
        decl: syn.AbstractDeclaration,
        global: *Scope,
    ) SemErr!void {
        if (global.abstracts.contains(decl.name.string)) return;
        if (global.types.contains(decl.name.string)) return;

        const info = try self.allocator.create(abs.AbstractInfo);
        info.* = .{
            .name = decl.name.string,
            .requirements = &.{},
            .param_names = decl.generic_params,
        };

        const abs_ty = try self.allocator.create(sg.AbstractType);
        abs_ty.* = .{ .name = decl.name.string };

        const td = try self.allocator.create(sg.TypeDeclaration);
        td.* = .{
            .name = decl.name.string,
            .origin_file = decl.name.location.file,
            .ty = .{ .abstract_type = abs_ty },
        };

        try global.abstracts.put(decl.name.string, info);
        try global.types.put(decl.name.string, td);
    }

    fn predeclareTopLevelImportAlias(
        self: *Semantizer,
        decl: syn.SymbolDeclaration,
        global: *Scope,
        loc: tok.Location,
    ) SemErr!void {
        const value = decl.value orelse return;
        if (value.*.content != .import_statement) return;
        if (global.module_aliases.contains(decl.name.string)) return;

        const resolved = source_files.resolveImportDir(self.allocator, self.io, loc.file, value.*.content.import_statement.path) catch return;
        try global.module_aliases.put(decl.name.string, resolved);
    }

    fn predeclareTopLevelBinding(
        self: *Semantizer,
        decl: syn.SymbolDeclaration,
        global: *Scope,
        loc: tok.Location,
    ) SemErr!void {
        // Typed top-level bindings need a stub before full semantizing so other
        // files in the same folder module can refer to them without depending on
        // per-file declaration order.
        if (decl.value) |value| {
            if (value.*.content == .import_statement) return;
        }
        const binding_ty_node = decl.type orelse return;
        if (global.bindings.contains(decl.name.string)) return;
        if (global.module_aliases.contains(decl.name.string)) return;

        const ty = self.resolveType(binding_ty_node, global) catch |err| switch (err) {
            error.UnknownType, error.SymbolNotFound => return,
            else => return err,
        };
        if (ty == .abstract_type) return;

        const bd = try self.allocator.create(sg.BindingDeclaration);
        bd.* = .{
            .name = decl.name.string,
            .location = loc,
            .origin_file = loc.file,
            .mutability = decl.mutability,
            .ty = ty,
            .initialization = null,
        };
        try global.bindings.put(decl.name.string, bd);
    }

    fn predeclareTopLevelType(
        self: *Semantizer,
        decl: syn.TypeDeclaration,
        global: *Scope,
    ) SemErr!void {
        if (decl.generic_params.len > 0 or decl.generic_params_struct != null) return;
        if (global.types.contains(decl.name.string)) return;

        switch (decl.value.*.content) {
            .struct_type_literal => {
                const stub = try self.allocator.create(sg.StructType);
                stub.* = .{ .fields = &.{} };

                const td = try self.allocator.create(sg.TypeDeclaration);
                td.* = .{
                    .name = decl.name.string,
                    .origin_file = decl.value.location.file,
                    .ty = .{ .struct_type = stub },
                };
                try global.types.put(decl.name.string, td);
            },
            .choice_type_literal => {
                const stub = try self.allocator.create(sg.ChoiceType);
                stub.* = .{ .variants = &.{} };

                const td = try self.allocator.create(sg.TypeDeclaration);
                td.* = .{
                    .name = decl.name.string,
                    .origin_file = decl.value.location.file,
                    .ty = .{ .choice_type = stub },
                };
                try global.types.put(decl.name.string, td);
            },
            else => {},
        }
    }

    fn predeclareTopLevelChoiceOption(
        self: *Semantizer,
        decl: syn.ChoiceOptionDeclaration,
        global: *Scope,
        loc: tok.Location,
    ) SemErr!void {
        if (global.choice_options.contains(decl.name.string)) return;

        const option_decl = try self.allocator.create(sg.ChoiceOptionDeclaration);
        option_decl.* = .{
            .name = decl.name.string,
            .origin_file = loc.file,
            .id = self.next_choice_option_id,
        };
        self.next_choice_option_id += 1;
        try global.choice_options.put(decl.name.string, option_decl);
    }

    fn predeclareTopLevelFunction(
        self: *Semantizer,
        decl: syn.FunctionDeclaration,
        global: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!void {
        if (decl.generic_params.len > 0 or decl.generic_params_struct != null) return;
        try self.requireExplicitFunctionFieldTypes(decl, loc);

        if (try self.abstractContractNameForFunctionDecl(decl, global) != null) return;

        if (global.functions.getPtr(decl.name.string)) |list_ptr| {
            for (list_ptr.items) |cand| {
                if (std.mem.eql(u8, cand.location.file, loc.file) and cand.location.offset == loc.offset) return;
            }
        }

        var child = try Scope.init(self.allocator, global, null);

        var in_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer in_fields.deinit();
        for (decl.input.fields) |*fld| {
            const field_ty = &fld.type.?;
            const ty = self.resolveCachedSignatureType(field_ty, .signature_predeclaration, &child) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => return,
                else => return err,
            };

            try in_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = if (fld.default_value != null) try self.makeNoopNode(fld.name.location) else null,
            });

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .constant,
                .ty = ty,
                .initialization = null,
            };
            try child.bindings.put(fld.name.string, bd);
        }

        var out_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer out_fields.deinit();
        var uses_inferred_error_reasons = false;
        for (decl.output.fields) |*fld| {
            const field_ty = &fld.type.?;
            const ty = if (self.inferableErrableInnerTypeFromOutput(field_ty.*)) |inner| blk: {
                uses_inferred_error_reasons = true;
                break :blk self.makeInferredErrableTypeForSignaturePredeclaration(inner, &child, fld.name.location) catch |err| switch (err) {
                    error.UnknownType, error.SymbolNotFound => return,
                    else => return err,
                };
            } else self.resolveCachedSignatureType(field_ty, .signature_predeclaration, &child) catch |err| switch (err) {
                error.UnknownType, error.SymbolNotFound => return,
                else => return err,
            };

            try out_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = if (fld.default_value != null) try self.makeNoopNode(fld.name.location) else null,
            });
        }

        const in_struct_ptr = try self.allocator.create(sg.StructType);
        in_struct_ptr.* = .{ .fields = try in_fields.toOwnedSlice() };

        const fn_ptr = try self.allocator.create(sg.FunctionDeclaration);
        fn_ptr.* = .{
            .id = self.freshFunctionId(),
            .name = decl.name.string,
            .location = loc,
            .safety_primitive = self.safetyPrimitiveForDeclaration(decl.name.string, loc.file),
            .is_deinit = std.mem.eql(u8, decl.name.string, "deinit"),
            .is_once = decl.is_once,
            .is_test = is_test,
            .input = in_struct_ptr.*,
            .output = .{ .fields = try out_fields.toOwnedSlice() },
            .body = null,
            .uses_inferred_error_reasons = uses_inferred_error_reasons,
            .output_bindings = &.{},
        };

        if (global.functions.getPtr(decl.name.string)) |list_ptr| {
            for (list_ptr.items) |cand| {
                if (typ.typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = &fn_ptr.input })) {
                    return;
                }
            }
        }

        try global.appendFunction(decl.name.string, fn_ptr);
    }

    fn abstractContractNameForFunctionDecl(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
    ) SemErr!?[]const u8 {
        _ = self;
        for (f.input.fields) |field| {
            const field_ty = field.type.?;
            switch (field_ty) {
                .type_name => |tn| {
                    if (p.lookupAbstractInfo(tn.string) != null) return tn.string;
                },
                .generic_type_instantiation => |g| {
                    if (p.lookupAbstractInfo(g.base_name.string) != null) return g.base_name.string;
                },
                .pointer_type => |ptr_info| switch (ptr_info.child.*) {
                    .type_name => |tn| {
                        if (p.lookupAbstractInfo(tn.string) != null) return tn.string;
                    },
                    .generic_type_instantiation => |g| {
                        if (p.lookupAbstractInfo(g.base_name.string) != null) return g.base_name.string;
                    },
                    else => {},
                },
                else => {},
            }
        }
        return null;
    }

    fn requireExplicitFunctionFieldTypes(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        loc: tok.Location,
    ) SemErr!void {
        _ = loc;
        for (f.input.fields) |field| {
            if (field.type != null) continue;
            try self.diags.add(
                field.name.location,
                .semantic,
                "function input field '.{s}' requires an explicit type",
                .{field.name.string},
            );
            return error.Reported;
        }
        for (f.output.fields) |field| {
            if (field.type != null) continue;
            try self.diags.add(
                field.name.location,
                .semantic,
                "function output field '.{s}' requires an explicit type",
                .{field.name.string},
            );
            return error.Reported;
        }
    }

    fn validateTestSignature(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        loc: tok.Location,
        p: *Scope,
    ) SemErr!void {
        _ = p;
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
        if (f.input.fields.len != 1) {
            try self.diags.add(loc, .semantic, "tests must declare exactly one input: '.system: System = System()'", .{});
            return error.Reported;
        }
        const system_field = f.input.fields[0];
        if (!std.mem.eql(u8, system_field.name.string, "system")) {
            try self.diags.add(system_field.name.location, .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        const system_type = system_field.type orelse {
            try self.diags.add(system_field.name.location, .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        };
        if (system_type != .type_name or !std.mem.eql(u8, system_type.type_name.string, "System")) {
            try self.diags.add(system_field.name.location, .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        const system_default = system_field.default_value orelse {
            try self.diags.add(system_field.name.location, .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        };
        if (system_default.content != .function_call or !std.mem.eql(u8, system_default.content.function_call.callee, "System")) {
            try self.diags.add(system_default.location, .semantic, "tests must declare '.system: System = System()' as their only input", .{});
            return error.Reported;
        }
        if (f.output.fields.len != 1) {
            try self.diags.add(loc, .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        }
        const result_field = f.output.fields[0];
        if (!std.mem.eql(u8, result_field.name.string, "result")) {
            try self.diags.add(result_field.name.location, .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        }
        const result_type = result_field.type orelse {
            try self.diags.add(result_field.name.location, .semantic, "tests must return exactly '-> !()' in v1", .{});
            return error.Reported;
        };
        switch (result_type) {
            .inferred_errable => |inner| switch (inner.*) {
                .struct_type_literal => |st| {
                    if (st.fields.len != 0) {
                        try self.diags.add(result_field.name.location, .semantic, "tests must return exactly '-> !()' in v1", .{});
                        return error.Reported;
                    }
                },
                else => {
                    try self.diags.add(result_field.name.location, .semantic, "tests must return exactly '-> !()' in v1", .{});
                    return error.Reported;
                },
            },
            else => {
                try self.diags.add(result_field.name.location, .semantic, "tests must return exactly '-> !()' in v1", .{});
                return error.Reported;
            },
        }
    }

    fn resolveCachedSignatureType(
        self: *Semantizer,
        type_node: *const syn.Type,
        mode: SignatureTypeCacheMode,
        s: *Scope,
    ) SemErr!sg.Type {
        const key: SignatureTypeCacheKey = .{
            .node = type_node,
            .mode = mode,
        };
        if (self.signature_type_cache.get(key)) |cached| return cached;

        const resolved = switch (mode) {
            .preserving_abstracts => try self.resolveTypePreservingAbstracts(type_node.*, s),
            .signature_predeclaration => try self.resolveTypeForSignaturePredeclaration(type_node.*, s),
        };
        try self.signature_type_cache.put(key, resolved);
        return resolved;
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
        for (self.diags.source_files) |f| {
            if (!std.mem.eql(u8, f.path, loc.file)) continue;

            var lines = std.mem.splitScalar(u8, f.code, '\n');
            var line_index: u32 = 1;
            while (lines.next()) |line| : (line_index += 1) {
                if (line_index != loc.line) continue;
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

    fn makeInferredErrableType(self: *Semantizer, inner: syn.Type, s: *Scope, loc: tok.Location) SemErr!sg.Type {
        const empty_choice = syn.ChoiceTypeLiteral{ .variants = &.{} };
        const reason_fields = try self.allocator.alloc(syn.StructTypeLiteralField, 2);
        reason_fields[0] = .{
            .name = .{ .string = "t", .location = loc },
            .type = inner,
            .default_value = null,
        };
        reason_fields[1] = .{
            .name = .{ .string = "reasons", .location = loc },
            .type = syn.Type{ .choice_type_literal = empty_choice },
            .default_value = null,
        };

        const errable_ast = syn.Type{ .generic_type_instantiation = .{
            .base_name = .{ .string = "Errable", .location = loc },
            .args = .{ .fields = reason_fields },
        } };

        const resolved = try self.resolveTypePreservingAbstracts(errable_ast, s);
        const errable_choice = switch (resolved) {
            .choice_type => |choice_ty| choice_ty,
            else => return error.InvalidType,
        };

        const reason_choice = typ.errableReasonChoiceFromType(resolved) orelse return error.InvalidType;
        @constCast(errable_choice).identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.errable) };
        @constCast(reason_choice).identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.reasons) };
        return resolved;
    }

    fn makeInferredErrableTypeForSignaturePredeclaration(
        self: *Semantizer,
        inner: syn.Type,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!sg.Type {
        const empty_choice = syn.ChoiceTypeLiteral{ .variants = &.{} };
        const reason_fields = try self.allocator.alloc(syn.StructTypeLiteralField, 2);
        reason_fields[0] = .{
            .name = .{ .string = "t", .location = loc },
            .type = inner,
            .default_value = null,
        };
        reason_fields[1] = .{
            .name = .{ .string = "reasons", .location = loc },
            .type = syn.Type{ .choice_type_literal = empty_choice },
            .default_value = null,
        };

        const errable_ast = syn.Type{ .generic_type_instantiation = .{
            .base_name = .{ .string = "Errable", .location = loc },
            .args = .{ .fields = reason_fields },
        } };

        const resolved = try self.resolveTypeForSignaturePredeclaration(errable_ast, s);
        const errable_choice = switch (resolved) {
            .choice_type => |choice_ty| choice_ty,
            else => return error.InvalidType,
        };

        const reason_choice = typ.errableReasonChoiceFromType(resolved) orelse return error.InvalidType;
        @constCast(errable_choice).identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.errable) };
        @constCast(reason_choice).identity = .{ .inferred_choice = try self.nextInferredChoiceIdentity(.reasons) };
        return resolved;
    }

    fn inferableErrableInnerTypeFromOutput(self: *Semantizer, ty: syn.Type) ?syn.Type {
        _ = self;
        return switch (ty) {
            .inferred_errable => |inner| inner.*,
            .generic_type_instantiation => |g| blk: {
                if (!std.mem.eql(u8, g.base_name.string, "Errable")) break :blk null;

                var inner_ty: ?syn.Type = null;
                var has_reasons = false;
                for (g.args.fields) |field| {
                    if (std.mem.eql(u8, field.name.string, "t")) {
                        if (field.type) |field_ty| inner_ty = field_ty;
                    } else if (std.mem.eql(u8, field.name.string, "reasons")) {
                        has_reasons = true;
                    }
                }
                if (has_reasons) break :blk null;
                break :blk inner_ty;
            },
            else => null,
        };
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

    fn collectActiveDeferredNodes(self: *Semantizer, s: *Scope) ![]const *sg.SGNode {
        var collected = std.array_list.Managed(*sg.SGNode).init(self.allocator.*);
        errdefer collected.deinit();

        var cur: ?*Scope = s;
        const current_fn = s.current_fn;
        while (cur) |scope_ptr| : (cur = scope_ptr.parent) {
            if (scope_ptr.current_fn != current_fn) break;

            var d_idx: usize = scope_ptr.deferred.items.len;
            while (d_idx > 0) : (d_idx -= 1) {
                const group = scope_ptr.deferred.items[d_idx - 1];
                try collected.appendSlice(group.nodes);
            }
        }

        return try collected.toOwnedSlice();
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
        const synthetic_call = syn.FunctionCall{
            .callee = "deinit",
            .callee_loc = loc,
            .module_qualifier = null,
            .type_arguments = null,
            .type_arguments_struct = null,
            .input = undefined,
        };

        const chosen = self.tryResolveRegularCallCallee(synthetic_call, input_te, s, loc) catch return null;
        const coerced_input = self.coerceCallInputToExpected(&chosen.input, input_te, &syn.STNode{
            .location = loc,
            .content = .{ .identifier = binding.name },
        }, s) catch return null;

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
            .origin_file = loc.file,
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
                    for (tmpl.input.fields) |field| {
                        const field_ty = field.type.?;
                        if (field_ty != .pointer_type) continue;
                        if (field_ty.pointer_type.mutability != .read_write) continue;
                        try candidate_names.put(field.name.string, {});
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
        const synthetic_call = syn.FunctionCall{
            .callee = "copy",
            .callee_loc = loc,
            .module_qualifier = null,
            .type_arguments = null,
            .type_arguments_struct = null,
            .input = undefined,
        };

        const chosen = self.tryResolveRegularCallCallee(synthetic_call, input_te, s, loc) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };
        const coerced_input = self.coerceCallInputToExpected(&chosen.input, input_te, &syn.STNode{
            .location = loc,
            .content = .{ .identifier = "copy" },
        }, s) catch |err| switch (err) {
            error.SymbolNotFound => return null,
            else => return err,
        };

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
        if (typ.isTypeTriviallyCopyable(expr.ty, s)) return expr;

        const named_input = try self.buildNamedCallInput(&[_]CallArg{
            .{ .name = "self", .expr = expr },
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
            .{ .name = "__arg0", .expr = expr },
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
                first.first_location.file,
                first.first_location.line,
                first.first_location.column,
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

    fn makeSynNode(self: *Semantizer, content: syn.Content, location: tok.Location) !*syn.STNode {
        const node = try self.allocator.create(syn.STNode);
        node.* = .{
            .location = location,
            .content = content,
        };
        return node;
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
            if (!std.mem.startsWith(u8, cand.location.file, dir)) return false;
        }
        return self.functionIsVisible(cand, requester_file);
    }

    fn syntaxNodeContainsPipePlaceholder(n: *const syn.STNode) bool {
        return switch (n.content) {
            .pipe_placeholder => true,
            .struct_field_access => |sfa| syntaxNodeContainsPipePlaceholder(sfa.struct_value),
            .choice_payload_access => |acc| syntaxNodeContainsPipePlaceholder(acc.choice_value),
            .error_propagation => |prop| syntaxNodeContainsPipePlaceholder(prop.value),
            .error_context => |ctx| syntaxNodeContainsPipePlaceholder(ctx.value) or syntaxNodeContainsPipePlaceholder(ctx.context),
            .address_of => |addr| syntaxNodeContainsPipePlaceholder(addr.value),
            .binary_operation => |bo| syntaxNodeContainsPipePlaceholder(bo.left) or syntaxNodeContainsPipePlaceholder(bo.right),
            .comparison => |cmp| syntaxNodeContainsPipePlaceholder(cmp.left) or syntaxNodeContainsPipePlaceholder(cmp.right),
            .logical_operation => |lo| syntaxNodeContainsPipePlaceholder(lo.left) or syntaxNodeContainsPipePlaceholder(lo.right),
            .index_access => |ia| syntaxNodeContainsPipePlaceholder(ia.value) or syntaxNodeContainsPipePlaceholder(ia.index),
            .function_call => |fc| syntaxNodeContainsPipePlaceholder(fc.input),
            .struct_value_literal => |sv| blk: {
                for (sv.fields) |field| {
                    if (syntaxNodeContainsPipePlaceholder(field.value)) break :blk true;
                }
                break :blk false;
            },
            .list_literal => |ll| blk: {
                for (ll.elements) |elem| {
                    if (syntaxNodeContainsPipePlaceholder(elem)) break :blk true;
                }
                break :blk false;
            },
            .choice_literal => |cl| if (cl.payload) |payload| syntaxNodeContainsPipePlaceholder(payload) else false,
            else => false,
        };
    }

    fn handlePipeFieldAccess(
        self: *Semantizer,
        base: typ.TypedExpr,
        field_name: syn.Name,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (base.ty == .array_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "type '{s}' has no field '.{s}'",
                .{ desc.bytes, field_name.string },
            );
            return error.Reported;
        }

        if (base.ty != .struct_type) {
            if (base.node.content == .function_call) {
                const fc = base.node.content.function_call;
                if (fc.callee.output.fields.len == 1) {
                    const only_field = fc.callee.output.fields[0];
                    if (std.mem.eql(u8, only_field.name, field_name.string)) {
                        return base;
                    }
                }
            }

            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "cannot access field '.{s}' on value of type '{s}'",
                .{ field_name.string, desc.bytes },
            );
            return error.Reported;
        }

        const st = base.ty.struct_type;
        var idx: ?u32 = null;
        var fty: sg.Type = undefined;
        for (st.fields, 0..) |f, i| {
            if (std.mem.eql(u8, f.name, field_name.string)) {
                idx = @intCast(i);
                fty = typ.effectiveStructFieldType(f);
                break;
            }
        }
        if (idx == null) return error.FieldsNotFound;

        const fa = try self.allocator.create(sg.StructFieldAccess);
        fa.* = .{
            .struct_value = base.node,
            .field_name = field_name.string,
            .field_index = idx.?,
        };

        const node = try sg.makeSGNode(.{ .struct_field_access = fa }, loc, self.allocator);
        return .{ .node = node, .ty = fty };
    }

    fn handlePipeChoicePayloadAccess(
        self: *Semantizer,
        base: typ.TypedExpr,
        variant_name: syn.Name,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (base.ty != .choice_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "cannot access choice payload '..{s}' on value of type '{s}'",
                .{ variant_name.string, desc.bytes },
            );
            return error.Reported;
        }

        const choice_ty = base.ty.choice_type;
        for (choice_ty.variants, 0..) |variant, idx| {
            if (!std.mem.eql(u8, variant.name, variant_name.string)) continue;
            const payload_ty = variant.payload_type orelse {
                try self.diags.add(
                    loc,
                    .semantic,
                    "choice variant '..{s}' has no payload",
                    .{variant_name.string},
                );
                return error.Reported;
            };

            const access = try self.allocator.create(sg.ChoicePayloadAccess);
            access.* = .{
                .choice_value = base.node,
                .variant_index = @intCast(idx),
                .payload_type = payload_ty,
            };
            const node = try sg.makeSGNode(.{ .choice_payload_access = access }, loc, self.allocator);
            return .{ .node = node, .ty = payload_ty };
        }

        const choice_text = try self.formatTypeText(.{ .choice_type = choice_ty }, s);
        defer choice_text.deinit();
        try self.diags.add(
            loc,
            .semantic,
            "choice type '{s}' has no variant '..{s}'",
            .{ choice_text.bytes, variant_name.string },
        );
        return error.Reported;
    }

    fn handlePipeAddressOf(
        self: *Semantizer,
        inner: typ.TypedExpr,
        mutability: syn.PointerMutability,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (inner.ty == .pointer_type and mutability == .read_only) {
            return inner;
        }

        switch (inner.node.content) {
            .binding_use => |binding| {
                if (mutability == .read_write and binding.mutability != .variable) {
                    try self.diags.add(
                        loc,
                        .semantic,
                        "binding '{s}' is immutable; declare it with '::' or take '&{s}' instead of '$&{s}'",
                        .{ binding.name, binding.name, binding.name },
                    );
                    return error.Reported;
                }
            },
            .struct_field_access => {},
            .dereference => |deref| {
                if (mutability == .read_write and deref.pointer_type.mutability != .read_write) {
                    try self.diags.add(
                        loc,
                        .semantic,
                        "cannot assign through this pointer because it is read-only; use '$&' when acquiring it",
                        .{},
                    );
                    return error.Reported;
                }
            },
            else => {
                try self.diags.add(
                    loc,
                    .semantic,
                    "cannot take the address of this expression; only addressable values support '&'",
                    .{},
                );
                return error.Reported;
            },
        }

        const child = try self.allocator.create(sg.Type);
        child.* = inner.ty;

        const ptr_ty = try self.allocator.create(sg.PointerType);
        ptr_ty.* = .{ .mutability = mutability, .child = child };

        const addr_node = try sg.makeSGNode(.{ .address_of = inner.node }, loc, self.allocator);
        return .{ .node = addr_node, .ty = .{ .pointer_type = ptr_ty } };
    }

    fn evalPipeArg(
        self: *Semantizer,
        arg: *const syn.STNode,
        left: typ.TypedExpr,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (!syntaxNodeContainsPipePlaceholder(arg)) {
            return self.visitNode(arg.*, s);
        }

        return switch (arg.content) {
            .pipe_placeholder => left,
            .struct_field_access => |sfa| self.handlePipeFieldAccess(
                try self.evalPipeArg(sfa.struct_value, left, s),
                sfa.field_name,
                arg.location,
                s,
            ),
            .choice_payload_access => |acc| self.handlePipeChoicePayloadAccess(
                try self.evalPipeArg(acc.choice_value, left, s),
                acc.variant_name,
                arg.location,
                s,
            ),
            .address_of => |addr| self.handlePipeAddressOf(
                try self.evalPipeArg(addr.value, left, s),
                addr.mutability,
                arg.location,
            ),
            else => blk: {
                try self.diags.add(
                    arg.location,
                    .semantic,
                    "pipe placeholders are only supported as '_', '&_', '$&_', '_.field', or '..variant' payload access for now",
                    .{},
                );
                break :blk error.Reported;
            },
        };
    }

    //────────────────────────────────────────────────────────────────── visitors
    pub fn visitNode(self: *Semantizer, n: syn.STNode, s: *Scope) SemErr!typ.TypedExpr {
        return switch (n.content) {
            .choice_option_declaration => |decl| self.handleChoiceOptionDecl(decl, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in choice option declaration '..{s}': {s}",
                    .{ decl.name.string, @errorName(err) },
                );
                break :blk err;
            },
            .symbol_declaration => |d| self.handleSymbolDecl(d, s, n.location) catch |err| blk: {
                switch (err) {
                    error.Reported => break :blk err,
                    error.SymbolNotFound => {
                        if (self.defer_unknown_top_level and self.current_top_node != null) {
                            try self.pushTopLevelForRetry();
                            break :blk error.Reported;
                        }
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "unknown symbol in declaration of '{s}'",
                            .{d.name.string},
                        );
                    },
                    error.UnknownType => {
                        if (self.defer_unknown_top_level and self.current_top_node != null) {
                            try self.pushTopLevelForRetry();
                            break :blk error.Reported; // sin diagnóstico por ahora
                        }
                        // Diagnóstico normal (no diferido)
                        if (d.type) |tp| if (tp == .type_name) {
                            try self.diags.add(
                                n.location,
                                .semantic,
                                "unknown type '{s}' in declaration of '{s}'",
                                .{ tp.type_name.string, d.name.string },
                            );
                            break :blk err;
                        };
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "unknown type in declaration of '{s}'",
                            .{d.name.string},
                        );
                    },
                    error.AbstractNeedsDefault => {
                        if (d.type) |tp2| {
                            if (tp2 == .type_name) {
                                try self.diags.add(
                                    n.location,
                                    .semantic,
                                    "cannot use abstract '{s}' as a type for a symbol. Use a concrete type or add a default concrete type to the abstract type ('{s} defaultsto <Type>')",
                                    .{ tp2.type_name.string, tp2.type_name.string },
                                );
                                break :blk error.Reported;
                            }
                        }
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "cannot use abstract type without a default (add 'defaultsto' or use a concrete type)",
                            .{},
                        );
                        break :blk error.Reported;
                    },
                    else => {
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "error in symbol declaration '{s}': {s}",
                            .{ d.name.string, @errorName(err) },
                        );
                    },
                }
                break :blk err;
            },

            .abstract_declaration => |ad| self.handleAbstractDecl(ad, s) catch |err| blk: {
                if (err == error.UnknownType and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in abstract declaration '{s}': {s}",
                    .{ ad.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .abstract_implements => |rel| self.handleAbstractImplements(rel, s, n.location) catch |err| blk: {
                if ((err == error.UnknownType or err == error.SymbolNotFound) and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in abstract implements for '{s}': {s}",
                    .{ rel.concrete_name.string, @errorName(err) },
                );
                break :blk err;
            },

            .abstract_defaultsto => |rel| self.handleAbstractDefault(rel, s, n.location) catch |err| blk: {
                if ((err == error.UnknownType or err == error.SymbolNotFound) and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in abstract defaultsto for '{s}': {s}",
                    .{ rel.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .type_declaration => |d| self.handleTypeDecl(d, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.UnknownType and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported; // sin diagnóstico todavía
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in type declaration '{s}': {s}",
                    .{ d.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .function_declaration => |d| self.handleFuncDecl(d, s, n.location, false) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.AbstractNeedsDefault) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "abstract types without a default are not supported in function outputs yet",
                        .{},
                    );
                    break :blk error.Reported;
                }
                if ((err == error.UnknownType or err == error.SymbolNotFound) and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in function declaration '{s}': {s}",
                    .{ d.name.string, @errorName(err) },
                );
                break :blk err;
            },
            .test_declaration => |d| self.handleTestDecl(d, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if ((err == error.UnknownType or err == error.SymbolNotFound) and s.parent == null and self.defer_unknown_top_level) {
                    try self.pushTopLevelForRetry();
                    break :blk error.Reported;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in test declaration '{s}': {s}",
                    .{ d.decl.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .assignment => |a| self.handleAssignment(a, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.SymbolNotFound and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in assignment '{s}': {s}",
                    .{ a.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .expression_statement => |expr| blk: {
                const te = self.visitNode(expr.*, s) catch |err| {
                    if (err == error.Reported) break :blk err;
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in expression statement: {s}",
                        .{@errorName(err)},
                    );
                    break :blk err;
                };
                try s.nodes.append(te.node);
                break :blk .{ .node = te.node, .ty = te.ty };
            },

            .identifier => |id| self.handleIdentifier(id, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in identifier '{s}': {s}",
                    .{ id, @errorName(err) },
                );
                break :blk err;
            },

            .move_expression => |inner| self.handleMove(inner, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in move expression: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .pipe_placeholder => blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "the '_' pipe placeholder is only valid on the right-hand side of a pipe expression",
                    .{},
                );
                break :blk error.Reported;
            },

            .literal => |l| self.handleLiteral(l, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in literal '{any}': {s}",
                    .{ l, @errorName(err) },
                );
                break :blk err;
            },

            .choice_literal => |name| self.handleChoiceLiteral(name, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in choice literal '..{s}': {s}",
                    .{ name.name.string, @errorName(err) },
                );
                break :blk err;
            },

            .struct_value_literal => |sl| self.handleStructValLit(sl, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in struct value literal: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .struct_type_literal => |st| self.handleStructTypeLit(st, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in struct type literal: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .choice_type_literal => blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "choice type literals are only valid inside type declarations or type annotations",
                    .{},
                );
                break :blk error.Reported;
            },

            .reach_directive => |reach| self.handleReachDirective(reach, n.location) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in #reach directive: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .struct_field_access => |sfa| self.handleStructFieldAccess(sfa, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.SymbolNotFound and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in struct field access '{s}': {s}",
                    .{ sfa.field_name.string, @errorName(err) },
                );
                break :blk err;
            },

            .choice_payload_access => |acc| self.handleChoicePayloadAccess(acc, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in choice payload access '..{s}': {s}",
                    .{ acc.variant_name.string, @errorName(err) },
                );
                break :blk err;
            },

            .error_propagation => |prop| self.handleErrorPropagation(prop, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in error propagation operator '!': {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .error_context => |ctx| self.handleErrorContext(ctx, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in contextual error propagation operator '!!': {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .list_literal => |ll| self.handleListLiteral(ll, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in list literal: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .index_access => |ia| self.handleIndexAccess(ia, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in index access: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .index_assignment => |ia| self.handleIndexAssignment(ia, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in index assignment: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .function_call => |fc| self.handleCall(fc, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.SymbolNotFound and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err == error.AmbiguousOverload) {
                    const tv_in = self.visitNode(fc.input.*, s) catch null;
                    try self.addAmbiguousFunctionDiagnostic(
                        fc.callee,
                        if (tv_in) |te| te.ty else null,
                        s,
                        n.location,
                    );
                    break :blk error.Reported;
                } else {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in function call '{s}': {s}",
                        .{ fc.callee, @errorName(err) },
                    );
                }
                break :blk err;
            },

            .pipe_expression => |pe| self.handlePipe(pe, s, n.location) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in pipe expression: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .code_block => |blk| self.handleCodeBlock(blk, s) catch |err| blk_ret: {
                if (err == error.Reported) break :blk_ret err;
                if (err == error.SymbolNotFound and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk_ret err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in code block: {s}",
                    .{@errorName(err)},
                );
                break :blk_ret err;
            },

            .binary_operation => |bo| self.handleBinOp(bo, n.location, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in binary operation '{any}': {s}",
                    .{ bo.operator, @errorName(err) },
                );
                break :blk err;
            },

            .comparison => |c| self.handleComparison(c, n.location, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in comparison '{any}': {s}",
                    .{ c.operator, @errorName(err) },
                );
                break :blk err;
            },

            .logical_operation => |lo| self.handleLogicalOperation(lo, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in logical operation: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .return_statement => |r| self.handleReturn(r, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in return statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .break_statement => self.handleBreak(n.location, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in break statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .continue_statement => self.handleContinue(n.location, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in continue statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .defer_statement => |expr| self.handleDefer(expr, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in defer statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .keep_statement => |name| self.handleKeep(name, s) catch |err| blk: {
                if (err == error.SymbolNotFound and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in keep statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .if_statement => |ifs| self.handleIf(ifs, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in if statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .for_statement => |f| self.handleFor(f, s, n.location) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in for statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .while_statement => |w| self.handleWhile(w, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in while statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .match_statement => |m| self.handleMatch(m, s) catch |err| blk: {
                if ((err == error.SymbolNotFound or err == error.UnknownType) and self.defer_unknown_top_level and self.current_top_node != null) {
                    break :blk err;
                }
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in match statement: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .import_statement => self.handleImportStatement(n.location) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in import statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .address_of => |p| self.handleAddressOf(p, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in address-of operation: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .dereference => |p| self.handleDereference(p, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in dereference operation: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },

            .pointer_assignment => |pa| self.handlePointerAssignment(pa, s) catch |err| blk: {
                if (err != error.Reported) {
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "error in pointer assignment: {s}",
                        .{@errorName(err)},
                    );
                }
                break :blk err;
            },
        };
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
        return try self.isSameModule(requester_file, fd.location.file);
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
    fn handleAbstractDecl(
        self: *Semantizer,
        ad: syn.AbstractDeclaration,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        // Store abstract info (resolved requirements) in scope
        var reqs = std.array_list.Managed(abs.AbstractFunctionReqSem).init(self.allocator.*);
        const generic_params = ad.generic_params;
        for (ad.requires_functions) |rf| {
            // Build input struct resolving types; track Self/generic/abstract usages
            var in_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
            var input_generic = std.array_list.Managed(?u32).init(self.allocator.*);
            var input_abstract = std.array_list.Managed(?[]const u8).init(self.allocator.*);
            var self_idxs = std.array_list.Managed(u32).init(self.allocator.*);
            var input_pointer_self_idxs = std.array_list.Managed(u32).init(self.allocator.*);

            for (rf.input.fields, 0..) |fld, i| {
                var ty: sg.Type = .{ .builtin = .Any };
                var generic_idx_opt: ?u32 = null;
                var abstract_req: ?[]const u8 = null;

                if (fld.type) |t| {
                    switch (t) {
                        .type_name => |tn| {
                            const name = tn.string;
                            if (std.mem.eql(u8, name, "Self")) {
                                try self_idxs.append(@intCast(i));
                            } else {
                                var found: bool = false;
                                for (generic_params, 0..) |gp, gi| {
                                    if (std.mem.eql(u8, gp, name)) {
                                        generic_idx_opt = @intCast(gi);
                                        found = true;
                                        break;
                                    }
                                }
                                if (!found) {
                                    if (s.lookupAbstractInfo(name) != null) {
                                        abstract_req = name;
                                    } else {
                                        ty = try self.resolveType(t, s);
                                    }
                                }
                            }
                        },
                        .generic_type_instantiation => |g| {
                            if (s.lookupAbstractInfo(g.base_name.string) != null) {
                                abstract_req = g.base_name.string;
                            } else {
                                ty = try self.resolveType(t, s);
                            }
                        },
                        else => {
                            if (t == .pointer_type) {
                                const ptr_info = t.pointer_type;
                                const child_node = ptr_info.child.*;
                                switch (child_node) {
                                    .type_name => |tn| {
                                        if (std.mem.eql(u8, tn.string, "Self")) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            try input_pointer_self_idxs.append(@intCast(i));
                                        } else if (s.lookupAbstractInfo(tn.string) != null) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            abstract_req = tn.string;
                                        } else {
                                            ty = try self.resolveType(t, s);
                                        }
                                    },
                                    .generic_type_instantiation => |g| {
                                        if (s.lookupAbstractInfo(g.base_name.string) != null) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            abstract_req = g.base_name.string;
                                        } else {
                                            ty = try self.resolveType(t, s);
                                        }
                                    },
                                    else => {
                                        ty = try self.resolveType(t, s);
                                    },
                                }
                            }
                        },
                    }
                }

                try in_fields.append(.{ .name = fld.name.string, .ty = ty, .default_value = null });
                try input_generic.append(generic_idx_opt);
                try input_abstract.append(abstract_req);
            }

            const in_struct = sg.StructType{ .fields = try in_fields.toOwnedSlice() };
            const input_generic_slice = try input_generic.toOwnedSlice();
            const input_abstract_slice = try input_abstract.toOwnedSlice();

            in_fields.deinit();
            input_generic.deinit();
            input_abstract.deinit();

            // Build output struct, tracking generics/abstracts similarly
            var out_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
            var output_generic = std.array_list.Managed(?u32).init(self.allocator.*);
            var output_abstract = std.array_list.Managed(?[]const u8).init(self.allocator.*);
            var output_self_idxs = std.array_list.Managed(u32).init(self.allocator.*);
            var output_pointer_self_idxs = std.array_list.Managed(u32).init(self.allocator.*);

            for (rf.output.fields, 0..) |fld, i| {
                var ty: sg.Type = .{ .builtin = .Any };
                var generic_idx_opt: ?u32 = null;
                var abstract_req: ?[]const u8 = null;

                if (fld.type) |t| {
                    switch (t) {
                        .type_name => |tn| {
                            const name = tn.string;
                            if (std.mem.eql(u8, name, "Self")) {
                                try output_self_idxs.append(@intCast(i));
                            } else {
                                var found: bool = false;
                                for (generic_params, 0..) |gp, gi| {
                                    if (std.mem.eql(u8, gp, name)) {
                                        generic_idx_opt = @intCast(gi);
                                        found = true;
                                        break;
                                    }
                                }
                                if (!found) {
                                    if (s.lookupAbstractInfo(name) != null) {
                                        abstract_req = name;
                                    } else {
                                        ty = try self.resolveType(t, s);
                                    }
                                }
                            }
                        },
                        .generic_type_instantiation => |g| {
                            if (s.lookupAbstractInfo(g.base_name.string) != null) {
                                abstract_req = g.base_name.string;
                            } else {
                                ty = try self.resolveType(t, s);
                            }
                        },
                        else => {
                            if (t == .pointer_type) {
                                const ptr_info = t.pointer_type;
                                const child_node = ptr_info.child.*;
                                switch (child_node) {
                                    .type_name => |tn| {
                                        if (std.mem.eql(u8, tn.string, "Self")) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            try output_pointer_self_idxs.append(@intCast(i));
                                        } else if (s.lookupAbstractInfo(tn.string) != null) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            abstract_req = tn.string;
                                        } else {
                                            ty = try self.resolveType(t, s);
                                        }
                                    },
                                    .generic_type_instantiation => |g| {
                                        if (s.lookupAbstractInfo(g.base_name.string) != null) {
                                            ty = try typ.pointerToAny(ptr_info.mutability, self.allocator);
                                            abstract_req = g.base_name.string;
                                        } else {
                                            ty = try self.resolveType(t, s);
                                        }
                                    },
                                    else => {
                                        ty = try self.resolveType(t, s);
                                    },
                                }
                            }
                        },
                    }
                }

                try out_fields.append(.{ .name = fld.name.string, .ty = ty, .default_value = null });
                try output_generic.append(generic_idx_opt);
                try output_abstract.append(abstract_req);
            }

            const out_struct = sg.StructType{ .fields = try out_fields.toOwnedSlice() };
            const output_generic_slice = try output_generic.toOwnedSlice();
            const output_abstract_slice = try output_abstract.toOwnedSlice();

            out_fields.deinit();
            output_generic.deinit();
            output_abstract.deinit();

            try reqs.append(.{
                .name = rf.name.string,
                .input = in_struct,
                .output = out_struct,
                .input_self_indices = try self_idxs.toOwnedSlice(),
                .output_self_indices = try output_self_idxs.toOwnedSlice(),
                .input_pointer_self_indices = try input_pointer_self_idxs.toOwnedSlice(),
                .output_pointer_self_indices = try output_pointer_self_idxs.toOwnedSlice(),
                .input_generic_param_indices = input_generic_slice,
                .output_generic_param_indices = output_generic_slice,
                .input_abstract_requirements = input_abstract_slice,
                .output_abstract_requirements = output_abstract_slice,
            });
            self_idxs.deinit();
            output_self_idxs.deinit();
            input_pointer_self_idxs.deinit();
            output_pointer_self_idxs.deinit();
        }

        const requirements = try reqs.toOwnedSlice();
        reqs.deinit();

        const info = if (s.abstracts.get(ad.name.string)) |existing|
            existing
        else blk: {
            const created = try self.allocator.create(abs.AbstractInfo);
            created.* = .{
                .name = ad.name.string,
                .requirements = &.{},
                .param_names = generic_params,
            };
            try s.abstracts.put(ad.name.string, created);
            break :blk created;
        };
        info.requirements = requirements;
        info.param_names = generic_params;
        const virtual_methods = try self.allocator.alloc(*sg.VirtualMethodRegistry, requirements.len);
        for (virtual_methods) |*registry| {
            registry.* = try self.allocator.create(sg.VirtualMethodRegistry);
            registry.*.* = .{ .implementations = std.array_list.Managed(*const sg.FunctionDeclaration).init(self.allocator.*) };
        }
        info.virtual_methods = virtual_methods;

        const td = if (s.types.get(ad.name.string)) |existing| blk: {
            if (existing.ty != .abstract_type) return error.SymbolAlreadyDefined;
            break :blk existing;
        } else blk: {
            const abs_ty = try self.allocator.create(sg.AbstractType);
            abs_ty.* = .{ .name = ad.name.string };
            const created = try self.allocator.create(sg.TypeDeclaration);
            created.* = .{ .name = ad.name.string, .origin_file = ad.name.location.file, .ty = .{ .abstract_type = abs_ty } };
            try s.types.put(ad.name.string, created);
            break :blk created;
        };

        const n = try self.appendTypeDeclarationNodeIfMissing(s, td, ad.name.location);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    // For now, relations are recorded as no-ops to accept syntax without enforcing.
    fn abstractNameFromImplementsTarget(abstract_ty: syn.Type) ?[]const u8 {
        return switch (abstract_ty) {
            .type_name => |name| name.string,
            .generic_type_instantiation => |g| g.base_name.string,
            else => null,
        };
    }

    fn concreteTypePatternFromImplements(
        self: *Semantizer,
        rel: syn.AbstractImplements,
        s: *Scope,
        loc: tok.Location,
    ) !syn.Type {
        if (rel.generic_params_struct != null or rel.generic_params.len != 0) {
            const params_struct = try self.genericParamsStructOrNames(rel.generic_params_struct, rel.generic_params, loc);
            const pattern_fields = try self.allocator.alloc(syn.StructTypeLiteralField, params_struct.fields.len);

            for (params_struct.fields, 0..) |field, idx| {
                const field_ty = field.type orelse {
                    pattern_fields[idx] = .{
                        .name = field.name,
                        .type = .{ .type_name = field.name },
                        .default_value = null,
                    };
                    continue;
                };

                const is_type_param =
                    (field_ty == .type_name and std.mem.eql(u8, field_ty.type_name.string, "Type")) or
                    (field_ty == .type_name and s.lookupAbstractInfo(field_ty.type_name.string) != null) or
                    (field_ty == .generic_type_instantiation and s.lookupAbstractInfo(field_ty.generic_type_instantiation.base_name.string) != null);

                if (is_type_param) {
                    pattern_fields[idx] = .{
                        .name = field.name,
                        .type = .{ .type_name = field.name },
                        .default_value = null,
                    };
                    continue;
                }

                const value_node = try self.makeSynNode(.{ .identifier = field.name.string }, loc);
                pattern_fields[idx] = .{
                    .name = field.name,
                    .type = null,
                    .default_value = value_node,
                };
            }

            return .{
                .generic_type_instantiation = .{
                    .base_name = rel.concrete_name,
                    .args = .{ .fields = pattern_fields },
                },
            };
        }

        return .{ .type_name = rel.concrete_name };
    }

    fn handleAbstractImplements(
        self: *Semantizer,
        rel: syn.AbstractImplements,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const abstract_name = abstractNameFromImplementsTarget(rel.abstract_ty) orelse return error.UnknownType;
        const concrete_pattern = try self.concreteTypePatternFromImplements(rel, s, loc);

        if (rel.generic_params_struct == null and rel.generic_params.len == 0) {
            const concrete_direct = self.resolveType(concrete_pattern, s) catch |err| switch (err) {
                error.UnknownType, error.AbstractNeedsDefault => null,
                else => return err,
            };
            if (concrete_direct) |concrete_ty| {
                try s.appendAbstractImpl(abstract_name, .{ .ty = concrete_ty, .location = loc });
                const n = try self.makeNoopNode(loc);
                try s.nodes.append(n);
                return .{ .node = n, .ty = .{ .builtin = .Any } };
            }
        }

        if (rel.generic_params_struct != null or rel.generic_params.len != 0 or concrete_pattern == .generic_type_instantiation) {
            var params_buf = std.array_list.Managed(gen.GenericParam).init(self.allocator.*);
            defer params_buf.deinit();

            if (rel.generic_params_struct != null or rel.generic_params.len != 0) {
                const params_struct = try self.genericParamsStructOrNames(rel.generic_params_struct, rel.generic_params, loc);
                const explicit_params = try self.genericParamDefsFromSyntax(params_struct, s);
                for (explicit_params) |param| try params_buf.append(param);
            }

            try self.collectHiddenImplementsParamsFromType(concrete_pattern, &params_buf, s);
            const params = try params_buf.toOwnedSlice();
            try s.appendAbstractImplTemplate(abstract_name, .{
                .params = params,
                .ty = concrete_pattern,
                .location = loc,
            });

            const n = try self.makeNoopNode(loc);
            try s.nodes.append(n);
            return .{ .node = n, .ty = .{ .builtin = .Any } };
        }

        const concrete_ty = try self.resolveType(concrete_pattern, s);

        // Defer conformance checks until call sites or a validation pass.

        try s.appendAbstractImpl(abstract_name, .{ .ty = concrete_ty, .location = loc });

        const n = try self.makeNoopNode(loc);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn handleAbstractDefault(
        self: *Semantizer,
        rel: syn.AbstractDefault,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const concrete_ty = try self.resolveType(rel.ty, s);
        try s.abstract_defaults.put(rel.name.string, .{ .ty = concrete_ty, .location = loc });
        const n = try self.makeNoopNode(loc);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //─────────────────────────────────────────────────────────  LITERALS
    fn handleLiteral(self: *Semantizer, lit: tok.Literal, s: *Scope) SemErr!typ.TypedExpr {
        var value_literal: sg.ValueLiteral = undefined;
        var ty: sg.Type = .{ .builtin = .Int32 };

        switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt| {
                value_literal = .{ .int_literal = std.fmt.parseInt(i64, txt, 0) catch 0 };
            },
            .regular_float_literal, .scientific_float_literal => |txt| {
                ty = .{ .builtin = .Float32 };
                value_literal = .{ .float_literal = std.fmt.parseFloat(f64, txt) catch 0.0 };
            },
            .char_literal => |c| {
                ty = .{ .builtin = .Char };
                value_literal = .{ .char_literal = c };
            },
            .string_literal => |text| {
                // Language-level string literals semantize as borrowed read-only
                // text views. Raw `&Char` is kept as an explicit interop boundary
                // through helpers in core/strings/c_strings.rg.
                const string_view_decl = s.lookupType("StringView") orelse return error.UnknownType;
                if (!typeDeclIsReady(string_view_decl)) return error.UnknownType;
                ty = string_view_decl.ty;
                value_literal = .{ .string_literal = text };
            },
            .bool_literal => |b| {
                ty = .{ .builtin = .Bool };
                value_literal = .{ .bool_literal = b };
            },
        }

        const ptr = try self.allocator.create(sg.ValueLiteral);
        ptr.* = value_literal;
        const n = try sg.makeSGNode(.{ .value_literal = ptr.* }, undefined, self.allocator);
        n.sem_type = ty;
        return .{ .node = n, .ty = ty };
    }

    fn handleChoiceLiteral(self: *Semantizer, lit: syn.ChoiceLiteral, s: *Scope) SemErr!typ.TypedExpr {
        var payload: ?*const sg.SGNode = null;
        if (lit.payload) |payload_node| {
            var payload_te = try self.visitNode(payload_node.*, s);
            payload_te = try self.ensureValuePositionAllowed(payload_te, payload_node.location, s);
            payload_te.node.sem_type = payload_te.ty;
            payload = payload_te.node;
        }

        const node = try self.allocator.create(sg.ChoiceLiteral);
        node.* = .{
            .variant_name = lit.name.string,
            .module_qualifier = if (lit.module_qualifier) |qualifier| qualifier.string else null,
            .choice_type = undefined,
            .variant_index = 0,
            .payload = payload,
        };
        const n = try sg.makeSGNode(.{ .choice_literal = node }, lit.name.location, self.allocator);
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
                    const requester_dir = self.moduleDirForFile(loc.file);
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

    fn handleChoiceOptionDecl(
        self: *Semantizer,
        decl: syn.ChoiceOptionDeclaration,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (s.parent != null) {
            try self.diags.add(loc, .semantic, "choice options can only be declared at module scope", .{});
            return error.Reported;
        }
        const option_decl = if (s.choice_options.get(decl.name.string)) |existing|
            existing
        else blk: {
            const created = try self.allocator.create(sg.ChoiceOptionDeclaration);
            created.* = .{
                .name = decl.name.string,
                .origin_file = loc.file,
                .id = self.next_choice_option_id,
            };
            self.next_choice_option_id += 1;
            try s.choice_options.put(decl.name.string, created);
            break :blk created;
        };

        const node = try self.appendChoiceOptionDeclarationNodeIfMissing(s, option_decl, loc);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    //─────────────────────────────────────────────────────────  IDENTIFIER
    fn handleIdentifier(
        self: *Semantizer,
        name: []const u8,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (s.bindingMoveLocation(name)) |move_loc| {
            if (std.mem.eql(u8, move_loc.file, loc.file) and move_loc.line == loc.line and move_loc.column == loc.column) {
                const b = s.lookupBinding(name) orelse return error.SymbolNotFound;
                if (!(try self.bindingIsVisible(b, loc.file))) {
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
                .{ name, move_loc.file, move_loc.line, move_loc.column },
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
        if (!(try self.bindingIsVisible(b, loc.file))) {
            try self.addPrivateMemberDiag(loc, "value", name);
            return error.Reported;
        }
        const n = try sg.makeSGNode(.{ .binding_use = b }, loc, self.allocator);
        n.sem_type = b.ty;
        return .{ .node = n, .ty = b.ty };
    }

    fn handleReachDirective(
        self: *Semantizer,
        reach: syn.ReachDirective,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const reach_ptr = try self.semanticReachDirectiveFromSyntax(reach);
        const node = try sg.makeSGNode(.{ .reach_directive = reach_ptr }, loc, self.allocator);
        node.sem_type = .{ .builtin = .Any };
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    fn semanticReachDirectiveFromSyntax(
        self: *Semantizer,
        reach: syn.ReachDirective,
    ) !*sg.ReachDirective {
        var alternatives = try self.allocator.alloc(sg.ReachAlternative, reach.alternatives.len);
        for (reach.alternatives, 0..) |alt, idx| {
            var segments = try self.allocator.alloc([]const u8, alt.segments.len);
            for (alt.segments, 0..) |segment, seg_idx| {
                segments[seg_idx] = segment.string;
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
                if (!(try self.isSameModule(field_loc.file, td.origin_file))) {
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
            .origin_file = ctx.location.file,
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

    fn formatReachDirectiveForSyntax(self: *Semantizer, reach: syn.ReachDirective) ![]u8 {
        var buf = std.array_list.Managed(u8).init(self.allocator.*);
        for (reach.alternatives, 0..) |alt, alt_idx| {
            if (alt_idx != 0) try buf.appendSlice(", ");
            for (alt.segments, 0..) |segment, seg_idx| {
                if (seg_idx != 0) try buf.append('.');
                try buf.appendSlice(segment.string);
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

    fn tryResolveReachedArgument(
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

        if (self.currentReachFunctionContext()) |ctx| {
            if (!std.mem.eql(u8, ctx.function_name, "main")) {
                return try self.ensurePropagatedReachedField(field_name, expected_ty, reach, loc, ctx);
            }
        }

        return null;
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
        inner: *const syn.STNode,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (inner.content != .identifier) {
            const value = try self.visitNode(inner.*, s);
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

        const name = inner.content.identifier;
        const binding = s.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(binding, loc.file))) {
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
            if (!(std.mem.eql(u8, move_loc.file, loc.file) and move_loc.line == loc.line and move_loc.column == loc.column)) {
                try self.diags.add(
                    inner.location,
                    .semantic,
                    "binding '{s}' was moved and cannot be used again (moved at {s}:{d}:{d})",
                    .{ binding.name, move_loc.file, move_loc.line, move_loc.column },
                );
                return error.Reported;
            }
        }
        try s.markBindingMoved(binding.name, loc);

        const binding_use = try sg.makeSGNode(.{ .binding_use = binding }, inner.location, self.allocator);
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
    fn handleCodeBlock(
        self: *Semantizer,
        blk: syn.CodeBlock,
        parent: *Scope,
    ) SemErr!typ.TypedExpr {
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        var ret_val: ?*sg.SGNode = null;
        var ret_ty: sg.Type = .{ .builtin = .Any };

        for (blk.items, 0..) |st, idx| {
            const te = try self.visitNode(st.*, &child);
            const is_last = idx + 1 == blk.items.len;
            if (is_last and st.*.content == .expression_statement) {
                ret_val = te.node;
                ret_ty = te.ty;
                continue;
            }
            if (st.*.content == .function_call) {
                try child.nodes.append(te.node);
            }
        }

        var d_idx: usize = child.deferred.items.len;
        while (d_idx > 0) : (d_idx -= 1) {
            const group = child.deferred.items[d_idx - 1];
            for (group.nodes) |node| try child.nodes.append(node);
        }

        const slice = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);

        const cb = try self.allocator.create(sg.CodeBlock);
        cb.* = .{ .nodes = slice, .ret_val = ret_val };

        const n = try sg.makeSGNode(.{ .code_block = cb }, undefined, self.allocator);
        try parent.nodes.append(n);
        return .{ .node = n, .ty = ret_ty };
    }

    //──────────────────────────────────────────────────── SYMBOL DECLARATION
    fn handleSymbolDecl(
        self: *Semantizer,
        d: syn.SymbolDeclaration,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (d.value) |v| {
            if (v.*.content == .import_statement) {
                const resolved = source_files.resolveImportDir(self.allocator, self.io, loc.file, v.*.content.import_statement.path) catch {
                    try self.diags.add(
                        v.*.location,
                        .semantic,
                        "failed to resolve import '{s}'",
                        .{v.*.content.import_statement.path},
                    );
                    return error.Reported;
                };

                if (s.lookupModuleAlias(d.name.string)) |existing| {
                    if (!std.mem.eql(u8, existing, resolved)) return error.SymbolAlreadyDefined;
                    return try typ.makeTypeLiteral(self.allocator, loc, .{ .builtin = .Any });
                }

                if (s.bindings.contains(d.name.string)) return error.SymbolAlreadyDefined;
                try s.module_aliases.put(d.name.string, resolved);
                return try typ.makeTypeLiteral(self.allocator, loc, .{ .builtin = .Any });
            }
        }

        const predeclared_binding = if (s.parent == null) s.bindings.get(d.name.string) else null;
        const reuses_predeclared_binding = if (predeclared_binding) |bd|
            std.mem.eql(u8, bd.location.file, loc.file) and bd.location.offset == loc.offset
        else
            false;

        if (s.bindings.contains(d.name.string) and !reuses_predeclared_binding) {
            return error.SymbolAlreadyDefined;
        }
        if (s.lookupModuleAlias(d.name.string) != null) {
            return error.SymbolAlreadyDefined;
        }

        var init_node: ?*syn.STNode = null;
        var init_te_opt: ?typ.TypedExpr = null;
        if (d.value) |v| {
            init_node = v;
            if (v.*.content == .reach_directive) {
                const reach_syntax = v.*.content.reach_directive;
                const reach = try self.semanticReachDirectiveFromSyntax(reach_syntax);
                if (d.type) |t| {
                    const expected_ty = try self.resolveType(t, s);
                    if (expected_ty == .abstract_type) return error.AbstractNeedsDefault;
                    const resolved = try self.resolveReachedArgument(
                        d.name.string,
                        expected_ty,
                        reach,
                        s,
                        v.*.location,
                    );
                    init_te_opt = resolved;
                } else {
                    const inferred = try self.resolveReachedArgumentForInference(
                        d.name.string,
                        reach,
                        s,
                        v.*.location,
                    ) orelse {
                        const reach_text = try self.formatReachDirectiveForSyntax(reach_syntax);
                        defer self.allocator.free(reach_text);
                        try self.diags.add(
                            v.*.location,
                            .semantic,
                            "cannot infer type for '.{s}' from #reach [{s}]",
                            .{ d.name.string, reach_text },
                        );
                        return error.Reported;
                    };

                    const resolved = try self.resolveReachedArgument(
                        d.name.string,
                        inferred.ty,
                        reach,
                        s,
                        v.*.location,
                    );
                    init_te_opt = resolved;
                }
            } else {
                init_te_opt = try self.visitNode(v.*, s);
            }
        }
        var ty: sg.Type = .{ .builtin = .Int32 };
        if (d.type) |t| {
            ty = try self.resolveType(t, s);
            if (ty == .abstract_type) return error.AbstractNeedsDefault;
        } else if (init_te_opt) |te| {
            ty = te.ty;
        }

        if (init_te_opt) |te_initial| {
            if (d.type) |_| {
                init_te_opt = try typ.coerceExprToType(ty, te_initial, init_node.?, s, self.allocator, self.diags);
            } else if (te_initial.node.content == .list_literal) {
                const arr_info = try self.inferArrayTypeFromList(te_initial.node.content.list_literal, init_node.?.location, s);
                ty = .{ .array_type = arr_info };
                init_te_opt = try typ.convertListLiteralToArray(te_initial, arr_info, init_node.?.location, s, self.allocator, self.diags);
            }
        }

        if (init_te_opt) |init_te| {
            init_te_opt = try self.ensureValuePositionAllowed(init_te, init_node.?.location, s);
        }

        const bd = if (reuses_predeclared_binding)
            predeclared_binding.?
        else blk: {
            const created = try self.allocator.create(sg.BindingDeclaration);
            created.* = .{
                .name = d.name.string,
                .location = loc,
                .origin_file = loc.file,
                .mutability = d.mutability,
                .ty = ty,
                .initialization = null,
            };
            try s.bindings.put(d.name.string, created);
            break :blk created;
        };
        bd.mutability = d.mutability;
        bd.ty = ty;
        bd.initialization = null;

        s.clearBindingMoved(d.name.string);
        const n = try self.appendBindingDeclarationNodeIfMissing(s, bd, loc);

        if (init_te_opt) |init_te| bd.initialization = init_te.node;

        try self.maybeScheduleAutoDeinit(bd, loc, s);

        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── TYPE DECLARATION
    fn handleTypeDecl(
        self: *Semantizer,
        d: syn.TypeDeclaration,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (d.generic_params.len > 0) {
            const params_struct = try self.genericParamsStructOrNames(
                d.generic_params_struct,
                d.generic_params,
                d.name.location,
            );
            const generic_info = try self.genericParamDefsAndConstraintsFromSyntax(params_struct, s);
            // Register as generic type template
            try s.appendGenericTypeTemplate(d.name.string, .{
                .name = d.name.string,
                .location = d.value.location,
                .params = generic_info.params,
                .param_abstract_constraints = generic_info.abstract_constraints,
                .body = d.value,
            });
            // No concrete type emitted now
            const noop = try self.makeNoopNode(d.value.location);
            try s.nodes.append(noop);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        } else {
            return switch (d.value.*.content) {
                .struct_type_literal => |st_lit| blk_struct: {
                    if (d.kind == .c_enum) return error.NotYetImplemented;
                    var td: *sg.TypeDeclaration = undefined;
                    if (s.types.get(d.name.string)) |existing| {
                        td = existing;
                    } else {
                        const stub = try self.allocator.create(sg.StructType);
                        stub.* = .{ .fields = &.{}, .layout = if (d.kind == .c_union) .c_union else .regular };
                        td = try self.allocator.create(sg.TypeDeclaration);
                        td.* = .{ .name = d.name.string, .origin_file = d.value.location.file, .ty = .{ .struct_type = stub } };
                        try s.types.put(d.name.string, td);
                        _ = try self.appendTypeDeclarationNodeIfMissing(s, td, d.value.location);
                    }

                    const st_ptr = try self.structTypeFromLiteral(st_lit, s);
                    const dst_const = td.ty.struct_type;
                    const dst: *sg.StructType = @constCast(dst_const);
                    dst.fields = st_ptr.fields;
                    dst.layout = if (d.kind == .c_union) .c_union else .regular;
                    if (dst.identity == null) {
                        const identity = try self.allocator.create(sg.GenericTypeIdentity);
                        identity.* = .{
                            .base_name = d.name.string,
                            .arg_names = &.{},
                            .arg_values = &.{},
                        };
                        dst.identity = .{ .generic = identity };
                    }
                    _ = try self.appendTypeDeclarationNodeIfMissing(s, td, d.value.location);
                    const noop = try self.makeNoopNode(d.value.location);
                    break :blk_struct .{ .node = noop, .ty = .{ .builtin = .Any } };
                },
                .choice_type_literal => |ct_lit| blk_choice: {
                    if (d.kind == .c_union) return error.NotYetImplemented;
                    var td: *sg.TypeDeclaration = undefined;
                    if (s.types.get(d.name.string)) |existing| {
                        if (existing.ty != .choice_type) return error.SymbolAlreadyDefined;
                        td = existing;
                    } else {
                        const stub = try self.allocator.create(sg.ChoiceType);
                        stub.* = .{ .variants = &.{}, .layout = if (d.kind == .c_enum) .c_enum else .regular };

                        td = try self.allocator.create(sg.TypeDeclaration);
                        td.* = .{
                            .name = d.name.string,
                            .origin_file = d.value.location.file,
                            .ty = .{ .choice_type = stub },
                        };
                        try s.types.put(d.name.string, td);

                        _ = try self.appendTypeDeclarationNodeIfMissing(s, td, d.value.location);
                    }

                    var variants = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
                    for (ct_lit.variants, 0..) |variant, idx| {
                        if (d.kind == .c_enum and variant.payload_type != null) {
                            try self.diags.add(
                                variant.name.location,
                                .semantic,
                                "CEnum variant '..{s}' cannot carry a payload",
                                .{variant.name.string},
                            );
                            return error.Reported;
                        }
                        const payload_type = if (variant.payload_type) |pt| try self.resolveTypePreservingAbstracts(pt, s) else null;
                        const option_decl = if (payload_type == null) blk_option: {
                            if (variant.module_qualifier) |qualifier| {
                                break :blk_option try self.resolveChoiceOptionReference(
                                    qualifier.string,
                                    variant.name.string,
                                    variant.name.location,
                                    s,
                                );
                            }
                            break :blk_option self.resolveChoiceOptionReference(
                                null,
                                variant.name.string,
                                variant.name.location,
                                s,
                            ) catch |err| switch (err) {
                                error.SymbolNotFound => null,
                                else => return err,
                            };
                        } else null;
                        try variants.append(.{
                            .name = variant.name.string,
                            .value = if (option_decl) |decl| @intCast(decl.id) else @intCast(idx),
                            .payload_type = payload_type,
                            .option_decl = option_decl,
                        });
                    }

                    const choice_ptr_const = td.ty.choice_type;
                    const choice_ptr: *sg.ChoiceType = @constCast(choice_ptr_const);
                    choice_ptr.variants = try variants.toOwnedSlice();
                    choice_ptr.layout = if (d.kind == .c_enum) .c_enum else .regular;
                    if (choice_ptr.identity == null) {
                        const identity = try self.allocator.create(sg.GenericTypeIdentity);
                        identity.* = .{
                            .base_name = d.name.string,
                            .arg_names = &.{},
                            .arg_values = &.{},
                        };
                        choice_ptr.identity = .{ .generic = identity };
                    }
                    variants.deinit();

                    _ = try self.appendTypeDeclarationNodeIfMissing(s, td, d.value.location);
                    const noop = try self.makeNoopNode(d.value.location);
                    break :blk_choice .{ .node = noop, .ty = .{ .builtin = .Any } };
                },
                else => error.NotYetImplemented,
            };
        }
    }

    //──────────────────────────────────────────────────── FUNCTION DECLARATION
    fn handleFuncDecl(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!typ.TypedExpr {
        return switch (self.function_semantize_mode) {
            .full => self.handleFuncDeclFull(f, p, loc, is_test),
            .interface_only => self.handleFuncDeclInterface(f, p, loc, is_test),
            .body_only => self.handleFuncDeclBody(f, p, loc, is_test),
        };
    }

    fn handleTestDecl(
        self: *Semantizer,
        td: syn.TestDeclaration,
        p: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (p.parent != null) {
            try self.diags.add(loc, .semantic, "tests are only supported at top level", .{});
            return error.Reported;
        }
        try self.validateTestSignature(td.decl, loc, p);
        return self.handleFuncDecl(td.decl, p, loc, true);
    }

    fn handleFuncDeclFull(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!typ.TypedExpr {
        try self.requireExplicitFunctionFieldTypes(f, loc);
        // Register generic template and skip direct emission
        if (f.generic_params.len > 0 or f.generic_params_struct != null) {
            if (f.is_once) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "once is not supported on generic functions yet",
                    .{},
                );
                return error.Reported;
            }
            const params_struct = try self.genericParamsStructOrNames(
                f.generic_params_struct,
                f.generic_params,
                f.name.location,
            );
            const generic_info = try self.genericParamDefsAndConstraintsFromSyntax(params_struct, p);
            try p.appendGenericFunctionTemplate(f.name.string, .{
                .name = f.name.string,
                .location = loc,
                .params = generic_info.params,
                .param_abstract_constraints = generic_info.abstract_constraints,
                .dispatch_kind = .regular,
                .input = f.input,
                .output = f.output,
                .body = f.body,
            });
            // Return a no-op node for generic template
            const noop = try self.makeNoopNode(loc);
            try p.nodes.append(noop);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }

        if (try self.registerAbstractContractTemplateIfNeeded(f, p, loc)) {
            const noop = try self.makeNoopNode(loc);
            try p.nodes.append(noop);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }

        if (f.is_once and f.body == null) {
            try self.diags.add(
                loc,
                .semantic,
                "once is not supported on extern functions",
                .{},
            );
            return error.Reported;
        }

        var child = try Scope.init(self.allocator, p, null);
        // ── entrada
        var in_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        var input_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        defer input_bindings.deinit();
        for (f.input.fields) |fld| {
            const ty = self.resolveTypePreservingAbstracts(fld.type.?, &child) catch |err| return err;
            const dvp = if (fld.default_value) |n|
                ((self.visitNode(n.*, &child) catch |err| return err)).node
            else
                null;

            try in_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = dvp,
            });

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .constant,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name.string, bd);
            try input_bindings.append(bd);
        }
        const in_struct_ptr = try self.allocator.create(sg.StructType);
        in_struct_ptr.* = .{ .fields = try in_fields.toOwnedSlice() };
        in_fields.deinit();
        const input_binding_slice = try input_bindings.toOwnedSlice();
        input_bindings.deinit();

        // ── salida
        var out_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        var output_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        defer output_bindings.deinit();
        var uses_inferred_error_reasons = false;
        for (f.output.fields) |fld| {
            const ty = if (self.inferableErrableInnerTypeFromOutput(fld.type.?)) |inner| blk: {
                uses_inferred_error_reasons = true;
                break :blk self.makeInferredErrableType(inner, &child, fld.name.location) catch |err| return err;
            } else self.resolveTypePreservingAbstracts(fld.type.?, &child) catch |err| return err;
            const dvp = if (fld.default_value) |n|
                ((self.visitNode(n.*, &child) catch |err| return err)).node
            else
                null;

            try out_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = dvp,
            });

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .variable,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name.string, bd);
            try output_bindings.append(bd);
        }
        const out_struct = sg.StructType{ .fields = try out_fields.toOwnedSlice() };
        const output_binding_slice = try output_bindings.toOwnedSlice();
        out_fields.deinit();
        output_bindings.deinit();

        var existing_fn: ?*sg.FunctionDeclaration = null;
        if (p.functions.getPtr(f.name.string)) |list_ptr| {
            for (list_ptr.items) |cand| {
                if (std.mem.eql(u8, cand.location.file, loc.file) and cand.location.offset == loc.offset) {
                    existing_fn = cand;
                    break;
                }
            }
        }

        const fn_ptr = blk: {
            if (existing_fn) |cand| {
                cand.input = in_struct_ptr.*;
                cand.output = out_struct;
                cand.is_test = is_test;
                cand.uses_inferred_error_reasons = uses_inferred_error_reasons;
                cand.input_bindings = input_binding_slice;
                cand.output_bindings = output_binding_slice;
                break :blk cand;
            }

            const created = try self.allocator.create(sg.FunctionDeclaration);
            created.* = .{
                .id = self.freshFunctionId(),
                .name = f.name.string,
                .location = loc,
                .safety_primitive = self.safetyPrimitiveForDeclaration(f.name.string, loc.file),
                .is_deinit = std.mem.eql(u8, f.name.string, "deinit"),
                .is_once = f.is_once,
                .is_test = is_test,
                .input = in_struct_ptr.*,
                .output = out_struct,
                .body = null,
                .uses_inferred_error_reasons = uses_inferred_error_reasons,
                .input_bindings = input_binding_slice,
                .output_bindings = output_binding_slice,
            };

            if (p.functions.getPtr(f.name.string)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (typ.typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = &created.input })) {
                        return error.SymbolAlreadyDefined;
                    }
                }
            }
            try p.appendFunction(f.name.string, created);
            break :blk created;
        };

        if (is_test)
            try self.appendTestDeclarationNodeIfMissing(p, fn_ptr, loc)
        else
            try self.appendFunctionDeclarationNodeIfMissing(p, fn_ptr, loc);
        child.current_fn = fn_ptr;

        // ── cuerpo
        var body_cb: ?*sg.CodeBlock = null;
        if (f.body) |body_node| {
            try self.function_reach_stack.append(.{
                .function_name = f.name.string,
                .location = loc,
                .input_struct = in_struct_ptr,
                .body_scope = &child,
            });
            defer _ = self.function_reach_stack.pop();
            const body_te = try self.visitNode(body_node.*, &child);
            body_cb = body_te.node.content.code_block;
        }

        fn_ptr.input = in_struct_ptr.*;
        fn_ptr.body = body_cb;
        self.clearDeferred(&child);
        const noop = try self.makeNoopNode(loc);
        return .{ .node = noop, .ty = .{ .builtin = .Any } };
    }

    fn handleFuncDeclInterface(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!typ.TypedExpr {
        const fn_ptr = try self.registerFunctionInterface(f, p, loc, is_test);
        if (fn_ptr) |resolved_fn| {
            const top_node = self.current_top_node orelse {
                try self.diags.add(loc, .semantic, "internal error: missing top-level function node during staged semantizing", .{});
                return error.Reported;
            };
            try self.enqueuePendingFunctionBody(top_node, f, loc, resolved_fn, is_test);
        }
        const noop = try self.makeNoopNode(loc);
        return .{ .node = noop, .ty = .{ .builtin = .Any } };
    }

    fn handleFuncDeclBody(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!typ.TypedExpr {
        _ = f;
        _ = p;
        _ = is_test;
        const noop = try self.makeNoopNode(loc);
        return .{ .node = noop, .ty = .{ .builtin = .Any } };
    }

    fn registerFunctionInterface(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
        is_test: bool,
    ) SemErr!?*sg.FunctionDeclaration {
        try self.requireExplicitFunctionFieldTypes(f, loc);
        if (f.generic_params.len > 0 or f.generic_params_struct != null) {
            if (f.is_once) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "once is not supported on generic functions yet",
                    .{},
                );
                return error.Reported;
            }
            const params_struct = try self.genericParamsStructOrNames(
                f.generic_params_struct,
                f.generic_params,
                f.name.location,
            );
            const generic_info = try self.genericParamDefsAndConstraintsFromSyntax(params_struct, p);
            try p.appendGenericFunctionTemplate(f.name.string, .{
                .name = f.name.string,
                .location = loc,
                .params = generic_info.params,
                .param_abstract_constraints = generic_info.abstract_constraints,
                .dispatch_kind = .regular,
                .input = f.input,
                .output = f.output,
                .body = f.body,
            });
            return null;
        }

        if (try self.registerAbstractContractTemplateIfNeeded(f, p, loc)) return null;

        if (f.is_once and f.body == null) {
            try self.diags.add(
                loc,
                .semantic,
                "once is not supported on extern functions",
                .{},
            );
            return error.Reported;
        }

        var child = try Scope.init(self.allocator, p, null);
        var in_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer in_fields.deinit();
        var input_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        defer input_bindings.deinit();
        for (f.input.fields) |*fld| {
            const field_ty = &fld.type.?;
            const ty = try self.resolveCachedSignatureType(field_ty, .preserving_abstracts, &child);

            try in_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = null,
            });

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .constant,
                .ty = ty,
                .initialization = null,
            };
            try child.bindings.put(fld.name.string, bd);
            try input_bindings.append(bd);
        }
        const in_struct_ptr = try self.allocator.create(sg.StructType);
        in_struct_ptr.* = .{ .fields = try in_fields.toOwnedSlice() };

        var out_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        defer out_fields.deinit();
        var output_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        defer output_bindings.deinit();
        var uses_inferred_error_reasons = false;
        for (f.output.fields) |*fld| {
            const field_ty = &fld.type.?;
            const ty = if (self.inferableErrableInnerTypeFromOutput(field_ty.*)) |inner| blk: {
                uses_inferred_error_reasons = true;
                break :blk try self.makeInferredErrableType(inner, &child, fld.name.location);
            } else try self.resolveCachedSignatureType(field_ty, .preserving_abstracts, &child);

            try out_fields.append(.{
                .name = fld.name.string,
                .ty = ty,
                .default_value = null,
            });

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .variable,
                .ty = ty,
                .initialization = null,
            };
            try output_bindings.append(bd);
        }

        var existing_fn: ?*sg.FunctionDeclaration = null;
        if (p.functions.getPtr(f.name.string)) |list_ptr| {
            for (list_ptr.items) |cand| {
                if (std.mem.eql(u8, cand.location.file, loc.file) and cand.location.offset == loc.offset) {
                    existing_fn = cand;
                    break;
                }
            }
        }

        const output_binding_slice = try output_bindings.toOwnedSlice();
        const input_binding_slice = try input_bindings.toOwnedSlice();
        const out_struct = sg.StructType{ .fields = try out_fields.toOwnedSlice() };

        const fn_ptr = blk: {
            if (existing_fn) |cand| {
                cand.input = in_struct_ptr.*;
                cand.output = out_struct;
                cand.is_test = is_test;
                cand.uses_inferred_error_reasons = uses_inferred_error_reasons;
                cand.input_bindings = input_binding_slice;
                cand.output_bindings = output_binding_slice;
                break :blk cand;
            }

            const created = try self.allocator.create(sg.FunctionDeclaration);
            created.* = .{
                .id = self.freshFunctionId(),
                .name = f.name.string,
                .location = loc,
                .safety_primitive = self.safetyPrimitiveForDeclaration(f.name.string, loc.file),
                .is_deinit = std.mem.eql(u8, f.name.string, "deinit"),
                .is_once = f.is_once,
                .is_test = is_test,
                .input = in_struct_ptr.*,
                .output = out_struct,
                .body = null,
                .uses_inferred_error_reasons = uses_inferred_error_reasons,
                .input_bindings = input_binding_slice,
                .output_bindings = output_binding_slice,
            };

            if (p.functions.getPtr(f.name.string)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (typ.typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = &created.input })) {
                        return null;
                    }
                }
            }
            try p.appendFunction(f.name.string, created);
            break :blk created;
        };

        if (is_test)
            try self.appendTestDeclarationNodeIfMissing(p, fn_ptr, loc)
        else
            try self.appendFunctionDeclarationNodeIfMissing(p, fn_ptr, loc);
        self.clearDeferred(&child);
        return fn_ptr;
    }

    fn prepareFunctionInputDefaults(
        self: *Semantizer,
        pending: *PendingFunctionBody,
        p: *Scope,
    ) SemErr!void {
        const f = pending.decl;
        const loc = pending.location;
        const fn_ptr = pending.function;

        const child = try self.allocator.create(Scope);
        child.* = try Scope.init(self.allocator, p, null);
        child.current_fn = fn_ptr;

        const input_struct_ptr = try self.allocator.create(sg.StructType);
        var prepared_input_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        if (!functionHasAnyDefaults(f.input.fields)) {
            input_struct_ptr.* = .{ .fields = fn_ptr.input.fields };
            for (f.input.fields, 0..) |fld, idx| {
                const bd = try self.allocator.create(sg.BindingDeclaration);
                bd.* = .{
                    .name = fld.name.string,
                    .location = fld.name.location,
                    .origin_file = loc.file,
                    .mutability = .constant,
                    .ty = fn_ptr.input.fields[idx].ty,
                    .initialization = null,
                };
                try child.bindings.put(fld.name.string, bd);
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

        for (f.input.fields, 0..) |fld, idx| {
            const ty = input_struct_ptr.fields[idx].ty;
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, child)).node
            else
                null;

            input_fields[idx].default_value = dvp;

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = fld.name.string,
                .location = fld.name.location,
                .origin_file = loc.file,
                .mutability = .constant,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name.string, bd);
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
        const child = pending.prepared_scope orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared input scope during staged semantizing", .{});
            return error.Reported;
        };
        const input_struct_ptr = pending.prepared_input_struct orelse {
            try self.diags.add(pending.location, .semantic, "internal error: missing prepared function input during staged semantizing", .{});
            return error.Reported;
        };

        if (!functionHasAnyDefaults(f.output.fields)) {
            for (f.output.fields, 0..) |fld, idx| {
                const bd = @constCast(fn_ptr.output_bindings[idx]);
                bd.initialization = null;
                try child.bindings.put(fld.name.string, bd);
            }
            fn_ptr.input = input_struct_ptr.*;
            return;
        }

        const output_fields = try self.allocator.alloc(sg.StructTypeField, fn_ptr.output.fields.len);
        @memcpy(output_fields, fn_ptr.output.fields);

        for (f.output.fields, 0..) |fld, idx| {
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, child)).node
            else
                null;

            output_fields[idx].default_value = dvp;

            const bd = @constCast(fn_ptr.output_bindings[idx]);
            bd.initialization = dvp;
            try child.bindings.put(fld.name.string, bd);
        }

        fn_ptr.output = .{ .fields = output_fields };
        fn_ptr.input = input_struct_ptr.*;
    }

    fn functionHasAnyDefaults(fields: []const syn.StructTypeLiteralField) bool {
        for (fields) |field| {
            if (field.default_value != null) return true;
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

        var body_cb: ?*sg.CodeBlock = null;
        if (f.body) |body_node| {
            try self.function_reach_stack.append(.{
                .function_name = f.name.string,
                .location = loc,
                .input_struct = input_struct_ptr,
                .body_scope = child,
            });
            defer _ = self.function_reach_stack.pop();
            const body_te = try self.visitNode(body_node.*, child);
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

    fn appendChoiceOptionDeclarationNodeIfMissing(
        self: *Semantizer,
        s: *Scope,
        option_decl: *sg.ChoiceOptionDeclaration,
        loc: tok.Location,
    ) !*sg.SGNode {
        for (s.nodes.items) |node| {
            if (node.content != .choice_option_declaration) continue;
            if (node.content.choice_option_declaration == option_decl) return node;
        }

        const node = try sg.makeSGNode(.{ .choice_option_declaration = option_decl }, loc, self.allocator);
        try s.nodes.append(node);
        if (s.parent == null) try self.root_list.append(node);
        return node;
    }

    fn genericParamsStructOrNames(
        self: *Semantizer,
        params_struct: ?syn.StructTypeLiteral,
        names: []const []const u8,
        loc: tok.Location,
    ) !syn.StructTypeLiteral {
        if (params_struct) |st| return st;

        var fields = try self.allocator.alloc(syn.StructTypeLiteralField, names.len);
        for (names, 0..) |name, idx| {
            fields[idx] = .{
                .name = .{ .string = name, .location = loc },
                .type = .{ .type_name = .{ .string = "Type", .location = loc } },
                .default_value = null,
            };
        }
        return .{ .fields = fields };
    }

    fn genericParamDefsFromSyntax(
        self: *Semantizer,
        params_struct: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr![]const gen.GenericParam {
        return (try self.genericParamDefsAndConstraintsFromSyntax(params_struct, s)).params;
    }

    fn genericParamDefsAndConstraintsFromSyntax(
        self: *Semantizer,
        params_struct: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!GenericParamSyntaxInfo {
        var params = try self.allocator.alloc(gen.GenericParam, params_struct.fields.len);
        var constraints = try self.allocator.alloc(?[]const u8, params_struct.fields.len);
        for (params_struct.fields, 0..) |field, idx| {
            constraints[idx] = null;
            const field_ty = field.type orelse {
                params[idx] = .{
                    .name = field.name.string,
                    .kind = .type,
                    .value_type = null,
                };
                continue;
            };

            if (field_ty == .type_name and std.mem.eql(u8, field_ty.type_name.string, "Type")) {
                params[idx] = .{
                    .name = field.name.string,
                    .kind = .type,
                    .value_type = null,
                };
                continue;
            }

            if (field_ty == .type_name and s.lookupAbstractInfo(field_ty.type_name.string) != null) {
                params[idx] = .{
                    .name = field.name.string,
                    .kind = .type,
                    .value_type = null,
                };
                constraints[idx] = field_ty.type_name.string;
                continue;
            }

            if (field_ty == .generic_type_instantiation and s.lookupAbstractInfo(field_ty.generic_type_instantiation.base_name.string) != null) {
                params[idx] = .{
                    .name = field.name.string,
                    .kind = .type,
                    .value_type = null,
                };
                constraints[idx] = field_ty.generic_type_instantiation.base_name.string;
                continue;
            }

            params[idx] = .{
                .name = field.name.string,
                .kind = .comptime_int,
                .value_type = try self.resolveType(field_ty, s),
            };
        }
        return .{
            .params = params,
            .abstract_constraints = constraints,
        };
    }

    fn hasGenericParamNamed(params: []const gen.GenericParam, name: []const u8) bool {
        for (params) |param| {
            if (std.mem.eql(u8, param.name, name)) return true;
        }
        return false;
    }

    fn collectHiddenComptimeParamsFromValueExpr(
        self: *Semantizer,
        node: *const syn.STNode,
        params: *std.array_list.Managed(gen.GenericParam),
        s: *Scope,
    ) !void {
        switch (node.content) {
            .identifier => |name| {
                if (hasGenericParamNamed(params.items, name)) return;
                if (typ.builtinFromName(name) != null) return;
                if (s.lookupType(name) != null) return;
                if (s.lookupBinding(name) != null) return;
                try params.append(.{
                    .name = name,
                    .kind = .comptime_int,
                    .value_type = .{ .builtin = .UIntNative },
                });
            },
            .binary_operation => |bo| {
                try self.collectHiddenComptimeParamsFromValueExpr(bo.left, params, s);
                try self.collectHiddenComptimeParamsFromValueExpr(bo.right, params, s);
            },
            else => {},
        }
    }

    fn collectHiddenImplementsParamsFromType(
        self: *Semantizer,
        ty: syn.Type,
        params: *std.array_list.Managed(gen.GenericParam),
        s: *Scope,
    ) !void {
        switch (ty) {
            .inferred_errable => |inner| try self.collectHiddenImplementsParamsFromType(inner.*, params, s),
            .pointer_type => |ptr_info| try self.collectHiddenImplementsParamsFromType(ptr_info.child.*, params, s),
            .array_type => |arr_info| try self.collectHiddenImplementsParamsFromType(arr_info.element.*, params, s),
            .struct_type_literal => |st| {
                for (st.fields) |field| {
                    if (field.type) |field_ty| {
                        try self.collectHiddenImplementsParamsFromType(field_ty, params, s);
                    }
                    if (field.default_value) |value_expr| {
                        try self.collectHiddenComptimeParamsFromValueExpr(value_expr, params, s);
                    }
                }
            },
            .choice_type_literal => |ct| {
                for (ct.variants) |variant| {
                    if (variant.payload_type) |payload_ty| {
                        try self.collectHiddenImplementsParamsFromType(payload_ty, params, s);
                    }
                }
            },
            .generic_type_instantiation => |g| {
                for (g.args.fields) |field| {
                    if (field.type) |field_ty| {
                        try self.collectHiddenImplementsParamsFromType(field_ty, params, s);
                    }
                    if (field.default_value) |value_expr| {
                        try self.collectHiddenComptimeParamsFromValueExpr(value_expr, params, s);
                    }
                }
            },
            .type_name => {},
        }
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

    fn parseComptimeIntLiteral(self: *Semantizer, lit: tok.Literal, loc: tok.Location) ?i64 {
        _ = self;
        _ = loc;
        return switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt| std.fmt.parseInt(i64, txt, 0) catch null,
            else => null,
        };
    }

    fn resolveComptimeIntExpr(
        self: *Semantizer,
        node: *const syn.STNode,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!i64 {
        return switch (node.content) {
            .literal => |lit| self.parseComptimeIntLiteral(lit, node.location) orelse {
                try self.diags.add(
                    node.location,
                    .semantic,
                    "expected comptime integer literal",
                    .{},
                );
                return error.Reported;
            },
            .identifier => |name| blk: {
                if (subst) |subst_ptr| {
                    if (subst_ptr.ints.get(name)) |value| break :blk value;
                }
                if (s.lookupGenericValue(name)) |binding| {
                    break :blk switch (binding.value) {
                        .comptime_int => |value| value,
                        else => {
                            try self.diags.add(
                                node.location,
                                .semantic,
                                "generic value '{s}' is not a comptime integer",
                                .{name},
                            );
                            return error.Reported;
                        },
                    };
                }
                try self.diags.add(
                    node.location,
                    .semantic,
                    "unknown comptime integer '{s}'",
                    .{name},
                );
                return error.Reported;
            },
            .binary_operation => |bo| blk: {
                const left = try self.resolveComptimeIntExpr(bo.left, s, subst);
                const right = try self.resolveComptimeIntExpr(bo.right, s, subst);
                break :blk switch (bo.operator) {
                    .addition => left + right,
                    .subtraction => left - right,
                    .multiplication => left * right,
                    .division => blk_div: {
                        if (right == 0) {
                            try self.diags.add(
                                node.location,
                                .semantic,
                                "division by zero in comptime integer expression",
                                .{},
                            );
                            return error.Reported;
                        }
                        break :blk_div @divTrunc(left, right);
                    },
                    .modulo => blk_mod: {
                        if (right == 0) {
                            try self.diags.add(
                                node.location,
                                .semantic,
                                "modulo by zero in comptime integer expression",
                                .{},
                            );
                            return error.Reported;
                        }
                        break :blk_mod @mod(left, right);
                    },
                };
            },
            else => {
                try self.diags.add(
                    node.location,
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
        node: *const syn.STNode,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        return switch (node.content) {
            .identifier => |name| blk: {
                if (subst.types.get(name)) |mapped| break :blk mapped;
                const ty_ast = syn.Type{ .type_name = syn.Name{ .string = name, .location = node.location } };
                break :blk self.resolveType(ty_ast, s) catch {
                    try self.diags.add(
                        node.location,
                        .semantic,
                        "unknown type '{s}'",
                        .{name},
                    );
                    return error.Reported;
                };
            },
            .struct_type_literal => |lit| blk: {
                const struct_ty = try self.structTypeFromLiteralWithSubst(lit, s, subst);
                break :blk .{ .struct_type = struct_ty };
            },
            .function_call => |fc| blk: {
                if (std.mem.eql(u8, fc.callee, "type_of")) {
                    break :blk try self.typeOfCallResultType(fc, s);
                }
                try self.diags.add(
                    node.location,
                    .semantic,
                    "unsupported expression in type generic argument",
                    .{},
                );
                return error.Reported;
            },
            else => {
                try self.diags.add(
                    node.location,
                    .semantic,
                    "expected type expression",
                    .{},
                );
                return error.Reported;
            },
        };
    }

    fn resolveArrayTypeFromGenericArgs(
        self: *Semantizer,
        loc: tok.Location,
        gen_args: syn.StructTypeLiteral,
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        var length_opt: ?i64 = null;
        var element_ty_opt: ?sg.Type = null;

        for (gen_args.fields) |field| {
            if (std.mem.eql(u8, field.name.string, "n")) {
                const value_node = field.default_value orelse {
                    try self.diags.add(
                        loc,
                        .semantic,
                        "Array expects '.n = <comptime integer expression>'",
                        .{},
                    );
                    return error.Reported;
                };
                length_opt = try self.resolveComptimeIntExpr(value_node, s, subst);
            } else if (std.mem.eql(u8, field.name.string, "t")) {
                if (field.type) |field_ty| {
                    element_ty_opt = if (subst) |subst_ptr|
                        try self.resolveTypeWithSubst(field_ty, s, subst_ptr)
                    else
                        try self.resolveType(field_ty, s);
                } else if (field.default_value) |type_expr| {
                    element_ty_opt = if (subst) |subst_ptr|
                        try self.resolveTypeExpressionWithSubst(type_expr, s, subst_ptr)
                    else
                        try self.resolveTypeExpression(type_expr, s);
                } else {
                    try self.diags.add(
                        loc,
                        .semantic,
                        "Array expects '.t: <type>'",
                        .{},
                    );
                    return error.Reported;
                }
            } else {
                try self.diags.add(
                    loc,
                    .semantic,
                    "Array only accepts '.n' and '.t' parameters",
                    .{},
                );
                return error.Reported;
            }
        }

        const length = length_opt orelse {
            try self.diags.add(
                loc,
                .semantic,
                "Array is missing '.n = <comptime integer expression>'",
                .{},
            );
            return error.Reported;
        };
        if (length < 0) {
            try self.diags.add(
                loc,
                .semantic,
                "Array length cannot be negative",
                .{},
            );
            return error.Reported;
        }

        const element_ty = element_ty_opt orelse {
            try self.diags.add(
                loc,
                .semantic,
                "Array is missing '.t: <type>'",
                .{},
            );
            return error.Reported;
        };

        return try self.makeArrayType(@intCast(length), element_ty);
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

    fn resolveSpecialGenericType(
        self: *Semantizer,
        g: @FieldType(syn.Type, "generic_type_instantiation"),
        s: *Scope,
        subst: ?*const GenericSubst,
    ) SemErr!?sg.Type {
        if (std.mem.eql(u8, g.base_name.string, "Array")) {
            return try self.resolveArrayTypeFromGenericArgs(g.base_name.location, g.args, s, subst);
        }
        if (std.mem.eql(u8, g.base_name.string, "Virtual")) {
            return try self.resolveVirtualTypeFromGenericArgs(g.base_name.location, g.args, s);
        }

        return null;
    }

    fn resolveVirtualTypeFromGenericArgs(
        self: *Semantizer,
        location: tok.Location,
        args: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!sg.Type {
        if (args.fields.len != 1 or !std.mem.eql(u8, args.fields[0].name.string, "abstract")) {
            try self.diags.add(location, .semantic, "Virtual expects exactly '.abstract: <Abstract>'", .{});
            return error.Reported;
        }
        const abstract_syntax = args.fields[0].type orelse return error.InvalidType;
        const abstract_name = switch (abstract_syntax) {
            .type_name => |name| name.string,
            else => return error.InvalidType,
        };
        if (s.lookupAbstractInfo(abstract_name) == null) {
            try self.diags.add(args.fields[0].name.location, .semantic, "'{s}' is not an Abstract type", .{abstract_name});
            return error.Reported;
        }
        const abstract_decl = s.lookupType(abstract_name) orelse return error.UnknownType;
        if (abstract_decl.ty != .abstract_type) return error.InvalidType;

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
        arg_values[0] = .{ .type = abstract_decl.ty };
        const identity = try self.allocator.create(sg.GenericTypeIdentity);
        identity.* = .{ .base_name = "Virtual", .arg_names = arg_names, .arg_values = arg_values };
        const virtual_type = try self.allocator.create(sg.StructType);
        virtual_type.* = .{ .fields = fields, .identity = .{ .generic = identity } };
        return .{ .struct_type = virtual_type };
    }

    fn resolveExplicitGenericArg(
        self: *Semantizer,
        field: syn.StructTypeLiteralField,
        param: gen.GenericParam,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!gen.GenericArgValue {
        return switch (param.kind) {
            .type => blk: {
                if (field.type) |ty_node| {
                    break :blk .{ .type = try self.resolveTypeWithSubst(ty_node, s, subst) };
                }
                if (field.default_value) |type_expr| {
                    break :blk .{ .type = try self.resolveTypeExpressionWithSubst(type_expr, s, subst) };
                }
                try self.diags.add(
                    field.name.location,
                    .semantic,
                    "generic parameter '.{s}' expects a type argument",
                    .{param.name},
                );
                return error.Reported;
            },
            .comptime_int => blk: {
                const value_node = field.default_value orelse {
                    try self.diags.add(
                        field.name.location,
                        .semantic,
                        "generic parameter '.{s}' expects a comptime integer expression",
                        .{param.name},
                    );
                    return error.Reported;
                };
                const value = try self.resolveComptimeIntExpr(value_node, s, subst);
                if (param.value_type) |value_ty| {
                    if (!self.intValueFitsType(value, value_ty)) {
                        try self.diags.add(
                            value_node.location,
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

    fn makeGenericIdentityArg(self: *Semantizer, value: gen.GenericArgValue) sg.GenericIdentityArg {
        _ = self;
        return switch (value) {
            .type => |ty| .{ .type = ty },
            .comptime_int => |int_value| .{ .comptime_int = int_value },
        };
    }

    fn valueExprUsesParam(node: *const syn.STNode, param: []const u8) bool {
        return switch (node.content) {
            .identifier => |name| std.mem.eql(u8, name, param),
            .binary_operation => |bo| valueExprUsesParam(bo.left, param) or valueExprUsesParam(bo.right, param),
            else => false,
        };
    }

    fn rewriteAbstractTypeForTemplate(
        self: *Semantizer,
        ty: syn.Type,
        hidden_name: []const u8,
        abstract_name: []const u8,
    ) !syn.Type {
        return switch (ty) {
            .type_name => |tn| {
                if (std.mem.eql(u8, tn.string, abstract_name)) {
                    return .{ .type_name = .{ .string = hidden_name, .location = tn.location } };
                }
                return ty;
            },
            .inferred_errable => |inner| blk: {
                const rewritten = try self.rewriteAbstractTypeForTemplate(inner.*, hidden_name, abstract_name);
                const child = try self.allocator.create(syn.Type);
                child.* = rewritten;
                break :blk .{ .inferred_errable = child };
            },
            .generic_type_instantiation => |g| {
                if (std.mem.eql(u8, g.base_name.string, abstract_name)) {
                    return .{ .type_name = .{ .string = hidden_name, .location = g.base_name.location } };
                }
                return ty;
            },
            .pointer_type => |ptr_info| blk: {
                const child = try self.allocator.create(syn.Type);
                child.* = try self.rewriteAbstractTypeForTemplate(ptr_info.child.*, hidden_name, abstract_name);

                const ptr = try self.allocator.create(syn.PointerType);
                ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };
                break :blk .{ .pointer_type = ptr };
            },
            .array_type => |arr_info| blk: {
                const element = try self.allocator.create(syn.Type);
                element.* = try self.rewriteAbstractTypeForTemplate(arr_info.element.*, hidden_name, abstract_name);

                const arr = try self.allocator.create(syn.ArrayType);
                arr.* = .{
                    .length = arr_info.length,
                    .element = element,
                };
                break :blk .{ .array_type = arr };
            },
            .struct_type_literal => |st| blk: {
                var fields = try self.allocator.alloc(syn.StructTypeLiteralField, st.fields.len);
                for (st.fields, 0..) |field, i| {
                    fields[i] = field;
                    if (field.type) |field_ty| {
                        fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, abstract_name);
                    }
                }
                break :blk .{ .struct_type_literal = .{ .fields = fields } };
            },
            .choice_type_literal => ty,
        };
    }

    fn outputUsesAbstractWithoutDefault(self: *Semantizer, ty: syn.Type, s: *Scope) bool {
        return switch (ty) {
            .type_name => |tn| {
                if (s.lookupAbstractInfo(tn.string) != null and s.lookupAbstractDefault(tn.string) == null) return true;
                return false;
            },
            .inferred_errable => |inner| self.outputUsesAbstractWithoutDefault(inner.*, s),
            .generic_type_instantiation => |g| {
                if (s.lookupAbstractInfo(g.base_name.string) != null and s.lookupAbstractDefault(g.base_name.string) == null) return true;
                return false;
            },
            .pointer_type => |ptr_info| self.outputUsesAbstractWithoutDefault(ptr_info.child.*, s),
            .array_type => |arr_info| self.outputUsesAbstractWithoutDefault(arr_info.element.*, s),
            .struct_type_literal => |st| blk: {
                for (st.fields) |field| {
                    if (field.type) |field_ty| {
                        if (self.outputUsesAbstractWithoutDefault(field_ty, s)) break :blk true;
                    }
                }
                break :blk false;
            },
            .choice_type_literal => |ct| blk: {
                for (ct.variants) |variant| {
                    if (variant.payload_type) |payload_ty| {
                        if (self.outputUsesAbstractWithoutDefault(payload_ty, s)) break :blk true;
                    }
                }
                break :blk false;
            },
        };
    }

    fn registerAbstractContractTemplateIfNeeded(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
    ) SemErr!bool {
        if (f.generic_params.len != 0) return false;

        var rewritten_input_fields = try self.allocator.alloc(syn.StructTypeLiteralField, f.input.fields.len);
        var hidden_param_names = std.array_list.Managed([]const u8).init(self.allocator.*);
        defer hidden_param_names.deinit();
        var hidden_constraints = std.array_list.Managed(?[]const u8).init(self.allocator.*);
        defer hidden_constraints.deinit();
        var has_abstract_input = false;

        for (f.input.fields, 0..) |field, i| {
            rewritten_input_fields[i] = field;
            if (field.type) |field_ty| {
                switch (field_ty) {
                    .type_name => |tn| {
                        if (p.lookupAbstractInfo(tn.string) != null) {
                            has_abstract_input = true;
                            const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                            try hidden_param_names.append(hidden_name);
                            try hidden_constraints.append(tn.string);
                            rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, tn.string);
                        }
                    },
                    .generic_type_instantiation => |g| {
                        if (p.lookupAbstractInfo(g.base_name.string) != null) {
                            has_abstract_input = true;
                            const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                            try hidden_param_names.append(hidden_name);
                            try hidden_constraints.append(g.base_name.string);
                            rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, g.base_name.string);
                        }
                    },
                    .pointer_type => |ptr_info| {
                        switch (ptr_info.child.*) {
                            .type_name => {
                                const child_name = ptr_info.child.*.type_name.string;
                                if (p.lookupAbstractInfo(child_name) != null) {
                                    has_abstract_input = true;
                                    const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                                    try hidden_param_names.append(hidden_name);
                                    try hidden_constraints.append(child_name);
                                    rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, child_name);
                                }
                            },
                            .generic_type_instantiation => |g| {
                                const child_name = g.base_name.string;
                                if (p.lookupAbstractInfo(child_name) != null) {
                                    has_abstract_input = true;
                                    const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                                    try hidden_param_names.append(hidden_name);
                                    try hidden_constraints.append(child_name);
                                    rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, child_name);
                                }
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }

        if (!has_abstract_input) return false;

        for (f.output.fields) |field| {
            if (field.type) |field_ty| {
                if (self.outputUsesAbstractWithoutDefault(field_ty, p)) return error.AbstractNeedsDefault;
            }
        }

        const template = gen.GenericTemplate{
            .name = f.name.string,
            .location = loc,
            .params = blk: {
                const hidden_names = try hidden_param_names.toOwnedSlice();
                const params = try self.allocator.alloc(gen.GenericParam, hidden_names.len);
                for (hidden_names, 0..) |hidden_name, idx| {
                    params[idx] = .{
                        .name = hidden_name,
                        .kind = .type,
                        .value_type = null,
                    };
                }
                break :blk params;
            },
            .param_abstract_constraints = try hidden_constraints.toOwnedSlice(),
            .dispatch_kind = .abstract_contract,
            .input = .{ .fields = rewritten_input_fields },
            .output = f.output,
            .body = f.body,
        };
        try p.appendGenericFunctionTemplate(f.name.string, template);

        return true;
    }

    //──────────────────────────────────────────────────── ASSIGNMENT
    fn handleAssignment(
        self: *Semantizer,
        a: syn.Assignment,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const b = s.lookupBinding(a.name.string) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(b, a.name.location.file))) {
            try self.addPrivateMemberDiag(a.name.location, "value", a.name.string);
            return error.Reported;
        }
        if (s.bindingMoveLocation(b.name)) |move_loc| {
            try self.diags.add(
                a.name.location,
                .semantic,
                "binding '{s}' was moved and cannot be reassigned (moved at {s}:{d}:{d})",
                .{ b.name, move_loc.file, move_loc.line, move_loc.column },
            );
            return error.Reported;
        }
        if (b.mutability == .constant and b.initialization != null) {
            try self.diags.add(
                a.name.location,
                .semantic,
                "binding '{s}' is constant and cannot be reassigned after initialization",
                .{b.name},
            );
            return error.Reported;
        }

        var rhs = try self.visitNode(a.value.*, s);
        rhs = try typ.coerceExprToType(b.ty, rhs, a.value, s, self.allocator, self.diags);
        rhs = try self.ensureValuePositionAllowed(rhs, a.value.location, s);
        if (!typ.typesExactlyEqual(b.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(b.ty, rhs.ty, s);
            defer pair.deinit();
            try self.diags.add(
                a.value.*.location,
                .semantic,
                "cannot assign '{s}' to '{s}' (explicit casts not supported yet)",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        const asg = try self.allocator.create(sg.Assignment);
        asg.* = .{ .sym_id = b, .value = rhs.node };

        const n = try sg.makeSGNode(.{ .binding_assignment = asg }, undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── STRUCT VALUE LITERAL
    fn handleStructValLit(
        self: *Semantizer,
        sl: syn.StructValueLiteral,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var fields_buf = std.array_list.Managed(sg.StructValueLiteralField).init(self.allocator.*);

        for (sl.fields) |f| {
            var tv = try self.visitNode(f.value.*, s);
            tv = try self.ensureValuePositionAllowed(tv, f.value.location, s);
            try fields_buf.append(.{ .name = f.name.string, .value = tv.node });
        }

        const fields = try fields_buf.toOwnedSlice();
        fields_buf.deinit();

        const st_ptr = try self.structTypeFromVal(sl, s);

        const lit = try self.allocator.create(sg.StructValueLiteral);
        lit.* = .{
            .fields = fields,
            .ty = .{ .struct_type = st_ptr },
            .dispatch_prefix_positional_count = sl.positional_prefix_count,
        };

        const n = try sg.makeSGNode(.{ .struct_value_literal = lit }, undefined, self.allocator);
        return .{ .node = n, .ty = .{ .struct_type = st_ptr } };
    }

    fn handleStructTypeLit(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var val_fields = std.array_list.Managed(sg.StructValueLiteralField).init(self.allocator.*);
        var ty_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);

        for (st.fields) |fld| {
            if (fld.default_value == null)
                return error.NotYetImplemented;

            const tv = try self.visitNode(fld.default_value.?.*, s);

            try val_fields.append(.{ .name = fld.name.string, .value = tv.node });
            try ty_fields.append(.{ .name = fld.name.string, .ty = tv.ty, .default_value = null });
        }

        const vals = try val_fields.toOwnedSlice();
        const tys = try ty_fields.toOwnedSlice();
        val_fields.deinit();
        ty_fields.deinit();

        const st_ptr = try self.allocator.create(sg.StructType);
        st_ptr.* = .{ .fields = tys };

        const lit_ptr = try self.allocator.create(sg.StructValueLiteral);
        lit_ptr.* = .{
            .fields = vals,
            .ty = .{ .struct_type = st_ptr },
            .dispatch_prefix_positional_count = 0,
        };

        const node_ptr = try sg.makeSGNode(.{ .struct_value_literal = lit_ptr }, undefined, self.allocator);
        return .{ .node = node_ptr, .ty = .{ .struct_type = st_ptr } };
    }

    //──────────────────────────────────────────────────── STRUCT FIELD ACCESS
    fn handleStructFieldAccess(
        self: *Semantizer,
        ma: syn.StructFieldAccess,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (ma.struct_value.*.content == .identifier) {
            const base_name = ma.struct_value.*.content.identifier;
            if (s.lookupModuleAlias(base_name)) |module_dir| {
                return self.handleModuleFieldAccess(module_dir, ma.field_name.string, s, ma.struct_value.*.location);
            }
        }

        const base = try self.visitNode(ma.struct_value.*, s);

        if (base.ty != .struct_type) {
            if (base.node.content == .function_call) {
                const fc = base.node.content.function_call;
                if (fc.callee.output.fields.len == 1) {
                    const only_field = fc.callee.output.fields[0];
                    if (std.mem.eql(u8, only_field.name, ma.field_name.string)) {
                        return base;
                    }
                }
            }

            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                ma.struct_value.*.location,
                .semantic,
                "cannot access field '.{s}' on value of type '{s}'",
                .{ ma.field_name.string, desc.bytes },
            );
            return error.Reported;
        }

        return self.buildStructFieldAccessFromTypedExpr(base, ma.field_name.string, ma.field_name.location, s);
    }

    fn handleChoicePayloadAccess(
        self: *Semantizer,
        acc: syn.ChoicePayloadAccess,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (acc.choice_value.*.content == .identifier) {
            const base_name = acc.choice_value.*.content.identifier;
            if (s.lookupModuleAlias(base_name) != null) {
                const lit = syn.ChoiceLiteral{
                    .name = acc.variant_name,
                    .module_qualifier = .{ .string = base_name, .location = acc.choice_value.*.location },
                    .payload = null,
                };
                return self.handleChoiceLiteral(lit, s);
            }
        }

        const base = if (acc.choice_value.*.content == .identifier) blk: {
            const binding_name = acc.choice_value.*.content.identifier;
            if (s.lookupBinding(binding_name)) |binding| {
                const node = try sg.makeSGNode(.{ .binding_use = binding }, acc.choice_value.*.location, self.allocator);
                node.sem_type = binding.ty;
                break :blk typ.TypedExpr{ .node = node, .ty = binding.ty };
            }
            break :blk try self.visitNode(acc.choice_value.*, s);
        } else try self.visitNode(acc.choice_value.*, s);
        if (base.ty != .choice_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                acc.choice_value.*.location,
                .semantic,
                "cannot access choice payload '..{s}' on value of type '{s}'",
                .{ acc.variant_name.string, desc.bytes },
            );
            return error.Reported;
        }

        const choice_ty = base.ty.choice_type;
        for (choice_ty.variants, 0..) |variant, idx| {
            if (!std.mem.eql(u8, variant.name, acc.variant_name.string)) continue;
            const payload_ty = variant.payload_type orelse {
                try self.diags.add(
                    acc.variant_name.location,
                    .semantic,
                    "choice variant '..{s}' has no payload",
                    .{acc.variant_name.string},
                );
                return error.Reported;
            };

            const access = try self.allocator.create(sg.ChoicePayloadAccess);
            access.* = .{
                .choice_value = base.node,
                .variant_index = @intCast(idx),
                .payload_type = payload_ty,
            };
            const node = try sg.makeSGNode(.{ .choice_payload_access = access }, acc.variant_name.location, self.allocator);
            return .{ .node = node, .ty = payload_ty };
        }

        const choice_text = try self.formatTypeText(.{ .choice_type = choice_ty }, s);
        defer choice_text.deinit();
        try self.diags.add(
            acc.variant_name.location,
            .semantic,
            "choice type '{s}' has no variant '..{s}'",
            .{ choice_text.bytes, acc.variant_name.string },
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
        if (!(try self.bindingIsVisible(binding, loc.file))) {
            try self.addPrivateMemberDiag(loc, "value", field_name);
            return error.Reported;
        }

        const n = try sg.makeSGNode(.{ .binding_use = binding }, loc, self.allocator);
        return .{ .node = n, .ty = binding.ty };
    }

    //──────────────────────────────────────────────────── LIST LITERAL
    fn handleListLiteral(
        self: *Semantizer,
        ll: syn.ListLiteral,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var expected_elem_ty_opt: ?sg.Type = null;
        if (ll.element_type) |elt_ty_syn| {
            expected_elem_ty_opt = try self.resolveType(elt_ty_syn, s);
        }

        var elems = std.array_list.Managed(*sg.SGNode).init(self.allocator.*);
        var elem_types = std.array_list.Managed(sg.Type).init(self.allocator.*);
        defer {
            elems.deinit();
            elem_types.deinit();
        }

        for (ll.elements, 0..) |elem_node, idx| {
            const elem_te = try self.visitNode(elem_node.*, s);

            if (expected_elem_ty_opt) |exp_ty| {
                if (!typ.typesStructurallyEqual(exp_ty, elem_te.ty)) {
                    const pair = try self.formatTypePairText(exp_ty, elem_te.ty, s);
                    defer pair.deinit();
                    try self.diags.add(
                        elem_node.*.location,
                        .semantic,
                        "list element {d} has type '{s}', expected '{s}'",
                        .{ idx, pair.actual.bytes, pair.expected.bytes },
                    );
                    return error.Reported;
                }
            }

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

        const node = try sg.makeSGNode(.{ .list_literal = lit_ptr }, undefined, self.allocator);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    fn handleIndexAccess(
        self: *Semantizer,
        ia: syn.IndexAccess,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const base = try self.visitNode(ia.value.*, s);
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };

        if (base.ty == .array_type) {
            var idx_te = try self.visitNode(ia.index.*, s);
            idx_te = try typ.coerceExprToType(native_uint_ty, idx_te, ia.index, s, self.allocator, self.diags);
            if (!typ.typesExactlyEqual(idx_te.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(idx_te.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    ia.index.*.location,
                    .semantic,
                    "array index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            const arr_type_ptr = base.ty.array_type;
            const elem_ty = arr_type_ptr.*.element_type.*;
            const ro_self = try typ.ensureReadOnlyPointer(ia.value, base, self.allocator, self.diags);

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
            var idx_te = try self.visitNode(ia.index.*, s);
            idx_te = try typ.coerceExprToType(native_uint_ty, idx_te, ia.index, s, self.allocator, self.diags);

            if (!typ.typesExactlyEqual(idx_te.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(idx_te.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    ia.index.*.location,
                    .semantic,
                    "list literal index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            if (idx_te.node.content != .value_literal) {
                try self.diags.add(
                    ia.index.*.location,
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
                        ia.index.*.location,
                        .semantic,
                        "index into a list literal must be a 'UIntNative' integer literal",
                        .{},
                    );
                    break :blk 0;
                },
            };

            if (raw_index < 0 or raw_index >= ll.elements.len) {
                try self.diags.add(
                    ia.index.*.location,
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

        const ro_self = try typ.ensureReadOnlyPointer(ia.value, base, self.allocator, self.diags);
        return self.lowerIndexedOperatorCall(
            "operator get[]",
            ro_self,
            ia.index,
            ia.value.*.location,
            s,
        );
    }

    fn lowerIndexedOperatorCall(
        self: *Semantizer,
        name: []const u8,
        self_expr: typ.TypedExpr,
        index_node: *syn.STNode,
        call_loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const empty_args = syn.StructTypeLiteral{ .fields = &.{} };
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };
        var idx = try self.visitNode(index_node.*, s);
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
            idx = try typ.coerceExprToType(native_uint_ty, idx, index_node, s, self.allocator, self.diags);
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
        input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, index_node, s);

        const call_ptr = try self.allocator.create(sg.FunctionCall);
        call_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, call_loc, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = typ.functionReturnType(chosen_fn) };
    }

    fn handleBorrowedIndexAccess(
        self: *Semantizer,
        ia: syn.IndexAccess,
        mutability: syn.PointerMutability,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const base = try self.visitNode(ia.value.*, s);

        const operator_name = switch (mutability) {
            .read_only => "operator get_ro_pointer[]",
            .read_write => "operator get_rw_pointer[]",
        };

        const self_expr = switch (mutability) {
            .read_only => try typ.ensureReadOnlyPointer(ia.value, base, self.allocator, self.diags),
            .read_write => try typ.ensureMutablePointer(ia.value, base, s, self.allocator, self.diags),
        };

        return self.lowerIndexedOperatorCall(
            operator_name,
            self_expr,
            ia.index,
            ia.value.*.location,
            s,
        );
    }

    fn handleIndexAssignment(
        self: *Semantizer,
        ia: syn.IndexAssignment,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (ia.target.*.content != .index_access) return error.InvalidType;
        const idx = ia.target.*.content.index_access;
        const native_uint_ty: sg.Type = .{ .builtin = .UIntNative };

        const base = try self.visitNode(idx.value.*, s);

        if (base.ty == .array_type) {
            var index_expr = try self.visitNode(idx.index.*, s);
            index_expr = try typ.coerceExprToType(native_uint_ty, index_expr, idx.index, s, self.allocator, self.diags);
            if (!typ.typesExactlyEqual(index_expr.ty, native_uint_ty)) {
                const idx_ty = try self.formatTypeText(index_expr.ty, s);
                defer idx_ty.deinit();
                try self.diags.add(
                    idx.index.*.location,
                    .semantic,
                    "array index must be 'UIntNative', got '{s}'",
                    .{idx_ty.bytes},
                );
                return error.Reported;
            }

            const value_expr = try self.visitNode(ia.value.*, s);
            const arr_type_ptr = base.ty.array_type;
            const elem_ty = arr_type_ptr.*.element_type.*;

            if (!typ.typesStructurallyEqual(elem_ty, value_expr.ty)) {
                const pair = try self.formatTypePairText(elem_ty, value_expr.ty, s);
                defer pair.deinit();
                try self.diags.add(
                    ia.value.*.location,
                    .semantic,
                    "cannot assign value of type '{s}' to array element of type '{s}'",
                    .{ pair.actual.bytes, pair.expected.bytes },
                );
                return error.Reported;
            }

            const ptr_self = try typ.ensureMutablePointer(idx.value, base, s, self.allocator, self.diags);

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

        var index_expr = try self.visitNode(idx.index.*, s);
        const value_expr = try self.visitNode(ia.value.*, s);

        const ptr_self = try typ.ensureMutablePointer(idx.value, base, s, self.allocator, self.diags);

        const name = "operator set[]";
        const empty_args = syn.StructTypeLiteral{ .fields = &.{} };
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
            chosen = self.resolveVisibleOverload(name, input_te, s, ia.target.*.location) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.AmbiguousOverload => {
                    try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, ia.target.*.location);
                    return error.Reported;
                },
                else => return err,
            };
        }

        if (chosen == null and !typ.typesExactlyEqual(index_expr.ty, native_uint_ty)) {
            index_expr = try typ.coerceExprToType(native_uint_ty, index_expr, idx.index, s, self.allocator, self.diags);
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
                chosen = self.resolveVisibleOverload(name, input_te, s, ia.target.*.location) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, ia.target.*.location);
                        return error.Reported;
                    },
                    else => return err,
                };
            }
        }

        const chosen_fn = chosen orelse {
            try self.addMissingFunctionDiagnostic(name, input_te.ty, s, ia.target.*.location);
            return error.Reported;
        };
        input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, ia.target, s);

        const call_ptr = try self.allocator.create(sg.FunctionCall);
        call_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, ia.target.*.location, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    //────────────────────────────────────────────────────  AUX STRUCT TYPES
    pub fn structTypeFromLiteral(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!*sg.StructType {
        var buf = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        for (st.fields) |*f| {
            const field_ty = if (f.type) |*ty| ty else continue;
            const ty = try self.resolveCachedSignatureType(field_ty, .preserving_abstracts, s);
            const dvp = if (f.default_value) |n|
                (try self.visitNode(n.*, s)).node
            else
                null;

            try buf.append(.{ .name = f.name.string, .ty = ty, .default_value = dvp });
        }

        const slice = try buf.toOwnedSlice();
        buf.deinit();

        const ptr = try self.allocator.create(sg.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    pub fn structTypeFromLiteralWithSubst(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!*sg.StructType {
        var buf = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        for (st.fields) |f| {
            const ty = try self.resolveTypeWithSubstPreservingAbstracts(f.type.?, s, subst);
            const dvp = if (f.default_value) |n|
                (try self.visitNode(n.*, s)).node
            else
                null;
            try buf.append(.{ .name = f.name.string, .ty = ty, .default_value = dvp });
        }
        const slice = try buf.toOwnedSlice();
        buf.deinit();
        const ptr = try self.allocator.create(sg.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    pub fn choiceTypeFromLiteral(
        self: *Semantizer,
        ct: syn.ChoiceTypeLiteral,
        s: *Scope,
    ) SemErr!*sg.ChoiceType {
        var subst = GenericSubst.init(self.allocator);
        defer subst.deinit();
        return self.choiceTypeFromLiteralWithSubst(ct, s, &subst);
    }

    pub fn choiceTypeFromLiteralWithSubst(
        self: *Semantizer,
        ct: syn.ChoiceTypeLiteral,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!*sg.ChoiceType {
        var variants = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
        for (ct.variants, 0..) |variant, idx| {
            const payload_type = if (variant.payload_type) |pt|
                try self.resolveTypeWithSubstPreservingAbstracts(pt, s, subst)
            else
                null;
            const option_decl = if (payload_type == null) blk_option: {
                if (variant.module_qualifier) |qualifier| {
                    break :blk_option try self.resolveChoiceOptionReference(
                        qualifier.string,
                        variant.name.string,
                        variant.name.location,
                        s,
                    );
                }
                break :blk_option self.resolveChoiceOptionReference(
                    null,
                    variant.name.string,
                    variant.name.location,
                    s,
                ) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    else => return err,
                };
            } else null;
            try variants.append(.{
                .name = variant.name.string,
                .value = if (option_decl) |decl| @intCast(decl.id) else @intCast(idx),
                .payload_type = payload_type,
                .option_decl = option_decl,
            });
        }

        const ptr = try self.allocator.create(sg.ChoiceType);
        ptr.* = .{ .variants = try variants.toOwnedSlice() };
        variants.deinit();
        return ptr;
    }

    fn structTypeFromVal(
        self: *Semantizer,
        sv: syn.StructValueLiteral,
        s: *Scope,
    ) SemErr!*sg.StructType {
        var buf = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);

        for (sv.fields) |f| {
            const tv = try self.visitNode(f.value.*, s);
            try buf.append(.{ .name = f.name.string, .ty = tv.ty, .default_value = null });
        }

        const slice = try buf.toOwnedSlice();
        buf.deinit();

        const ptr = try self.allocator.create(sg.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    //──────────────────────────────────────────────────── FUNCTION CALL
    fn handleToVirtual(self: *Semantizer, call: syn.FunctionCall, s: *Scope) SemErr!typ.TypedExpr {
        const type_args = call.type_arguments_struct orelse {
            try self.diags.add(call.callee_loc, .semantic, "to_virtual requires '#(.abstract: <Abstract>)'", .{});
            return error.Reported;
        };
        const virtual_syntax = syn.Type{ .generic_type_instantiation = .{
            .base_name = .{ .string = "Virtual", .location = call.callee_loc },
            .args = type_args,
        } };
        const virtual_type = try self.resolveTypePreservingAbstracts(virtual_syntax, s);
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
        if (call.input.content != .struct_value_literal) return error.InvalidType;
        const input = call.input.content.struct_value_literal;
        if (input.fields.len != 1 or !std.mem.eql(u8, input.fields[0].name.string, "value")) return error.InvalidType;
        const value = try self.visitNode(input.fields[0].value.*, s);
        if (value.ty != .pointer_type) {
            try self.diags.add(input.fields[0].value.location, .semantic, "to_virtual '.value' must be a reference", .{});
            return error.Reported;
        }
        const concrete_type = value.ty.pointer_type.child.*;
        if (!abs.typeImplementsAbstract(abstract_type.name, concrete_type, s)) {
            const concrete_text = try self.formatTypeText(concrete_type, s);
            defer concrete_text.deinit();
            try self.diags.add(input.fields[0].value.location, .semantic, "type '{s}' does not implement Abstract '{s}'", .{ concrete_text.bytes, abstract_type.name });
            return error.Reported;
        }
        const abstract_info = s.lookupAbstractInfo(abstract_type.name) orelse return error.SymbolNotFound;
        const methods = try self.allocator.alloc(*const sg.FunctionDeclaration, abstract_info.requirements.len);
        for (abstract_info.requirements, 0..) |*requirement, index| {
            const expected_input = try abs.buildExpectedInputWithConcrete(requirement, concrete_type, self.allocator);
            methods[index] = abs.resolveOverload(requirement.name, .{ .struct_type = expected_input }, s) catch |err| switch (err) {
                error.SymbolNotFound, error.AmbiguousOverload => {
                    try self.diags.add(call.callee_loc, .semantic, "cannot build Virtual vtable for '{s}': requirement '{s}' has no unique concrete implementation", .{ abstract_type.name, requirement.name });
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
        const virtualize = try self.allocator.create(sg.Virtualize);
        virtualize.* = .{
            .value = value.node,
            .concrete_type = concrete_type,
            .abstract_type = abstract_type,
            .virtual_type = virtual_type.struct_type,
            .methods = methods,
            .safety_methods = abstract_info.virtual_methods,
            .location = call.callee_loc,
        };
        const node = try sg.makeSGNode(.{ .virtualize = virtualize }, call.callee_loc, self.allocator);
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

    fn handleCall(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (std.mem.eql(u8, call.callee, "size_of"))
            return self.handleBuiltinTypeInfo(.size, call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "alignment_of"))
            return self.handleBuiltinTypeInfo(.alignment, call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "cast"))
            return self.handleCastBuiltin(call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "to_virtual"))
            return self.handleToVirtual(call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "type_of"))
            return self.handleTypeOf(call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "is"))
            return self.handleIsBuiltin(call, s) catch |err| switch (err) {
                error.Reported => return err,
                else => err,
            };
        if (std.mem.eql(u8, call.callee, "length")) len_blk: {
            const len_res = self.handleLengthBuiltin(call, s) catch |err| switch (err) {
                error.Reported => return err,
                error.SymbolNotFound => break :len_blk,
                else => return err,
            };
            return len_res;
        }
        if ((std.mem.eql(u8, call.callee, "unwrap_or") or std.mem.eql(u8, call.callee, "unwrap_or_do")) and call.module_qualifier == null and call.type_arguments == null and call.type_arguments_struct == null) {
            const unwrap_res = self.handleNullableUnwrapCall(call, s) catch |err| switch (err) {
                error.Reported => return err,
                error.SymbolNotFound => null,
                else => return err,
            };
            if (unwrap_res) |te| return te;
        }

        const tv_in = try self.visitNode(call.input.*, s);
        // `testing.expect_error(...)` is a dedicated builtin in v1 instead of a
        // generic helper over arbitrary `Errable` values. That keeps native
        // testing independent from the generic/choice-heavy call paths that
        // previously made this helper brittle.
        if (call.module_qualifier != null and std.mem.eql(u8, call.module_qualifier.?, "testing") and std.mem.eql(u8, call.callee, "expect_error")) {
            return try self.handleTestingExpectErrorBuiltin(call, tv_in, s);
        }
        if (typ.builtinFromName(call.callee)) |builtin_ty| {
            if (builtin_ty == .Void) {
                if (tv_in.ty != .struct_type or tv_in.ty.struct_type.fields.len != 0) {
                    try self.diags.add(
                        call.input.*.location,
                        .semantic,
                        "builtin 'Void' does not accept initializer arguments",
                        .{},
                    );
                    return error.Reported;
                }

                const lit = try self.allocator.create(sg.StructValueLiteral);
                lit.* = .{
                    .fields = &.{},
                    .ty = .{ .builtin = .Void },
                    .dispatch_prefix_positional_count = 0,
                };
                const node = try sg.makeSGNode(.{ .struct_value_literal = lit }, call.callee_loc, self.allocator);
                node.sem_type = .{ .builtin = .Void };
                return .{ .node = node, .ty = .{ .builtin = .Void } };
            }
        }
        if (s.lookupType(call.callee)) |type_decl| {
            if (!(try self.typeIsVisible(type_decl, call.input.*.location.file))) {
                try self.addPrivateMemberDiag(call.input.*.location, "type", call.callee);
                return error.Reported;
            }
            return self.handleTypeInitializer(call, tv_in, type_decl, s);
        }
        if (call.type_arguments_struct) |stargs| {
            const generic_type = syn.Type{ .generic_type_instantiation = .{
                .base_name = .{
                    .string = call.callee,
                    .location = call.callee_loc,
                },
                .args = stargs,
            } };
            const instantiated_ty = self.resolveType(generic_type, s) catch |err| switch (err) {
                error.UnknownType, error.AbstractNeedsDefault => null,
                else => return err,
            };
            if (instantiated_ty) |ty| {
                const type_decl = try self.allocator.create(sg.TypeDeclaration);
                type_decl.* = .{
                    .name = call.callee,
                    .origin_file = call.input.*.location.file,
                    .ty = ty,
                };
                return self.handleTypeInitializer(call, tv_in, type_decl, s);
            }
        }

        if (tv_in.ty == .struct_type) {
            const inferred_ty = self.instantiateGenericTypeFromInitializer(call.callee, tv_in.ty, s) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.AmbiguousOverload => {
                    try self.diags.add(
                        call.input.*.location,
                        .semantic,
                        "generic type initializer for '{s}' is ambiguous",
                        .{call.callee},
                    );
                    return error.Reported;
                },
                else => return err,
            };
            if (inferred_ty) |ty| {
                const type_decl = try self.allocator.create(sg.TypeDeclaration);
                type_decl.* = .{
                    .name = call.callee,
                    .origin_file = call.input.*.location.file,
                    .ty = ty,
                };
                return self.handleTypeInitializer(call, tv_in, type_decl, s);
            }
        }

        if (tv_in.ty != .struct_type) return error.InvalidType;
        if (try self.tryHandleVirtualCall(call, tv_in, s)) |virtual_call| return virtual_call;

        const chosen = self.resolveRegularCallCallee(call, tv_in, s, call.input.*.location) catch |err| switch (err) {
            error.AmbiguousOverload => {
                if (call.module_qualifier) |module_name| {
                    const module_dir = s.lookupModuleAlias(module_name) orelse {
                        try self.diags.add(call.callee_loc, .semantic, "unknown module alias '{s}'", .{module_name});
                        return error.Reported;
                    };
                    try self.addAmbiguousModuleFunctionDiagnostic(module_name, module_dir, call.callee, tv_in.ty, s, call.callee_loc);
                } else {
                    try self.addAmbiguousFunctionDiagnostic(call.callee, tv_in.ty, s, call.callee_loc);
                }
                return error.Reported;
            },
            else => {
                return err;
            },
        };
        const coerced_input = try self.coerceCallInputToExpected(&chosen.input, tv_in, call.input, s);
        const consumed_auto_deinit = self.explicitDeinitAutoCleanupTarget(chosen, coerced_input, s);

        const fc_ptr = try self.allocator.create(sg.FunctionCall);
        fc_ptr.* = .{
            .callee = chosen,
            .input = coerced_input.node,
            .consumes_auto_deinit = consumed_auto_deinit,
        };

        const n = try sg.makeSGNode(.{ .function_call = fc_ptr }, call.callee_loc, self.allocator);

        const result_ty = typ.functionReturnType(chosen);

        return .{ .node = n, .ty = result_ty };
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

    fn tryHandleVirtualCall(self: *Semantizer, call: syn.FunctionCall, input: typ.TypedExpr, s: *Scope) SemErr!?typ.TypedExpr {
        if (call.module_qualifier != null or call.type_arguments != null or call.type_arguments_struct != null) return null;
        if (input.ty != .struct_type or input.node.content != .struct_value_literal) return null;
        const input_type = input.ty.struct_type;
        for (input_type.fields, 0..) |actual_field, self_index| {
            const abstract_type = virtualAbstractType(actual_field.ty) orelse continue;
            if (actual_field.ty != .pointer_type) continue;
            const info = s.lookupAbstractInfo(abstract_type.name) orelse return error.SymbolNotFound;
            for (info.requirements, 0..) |*requirement, method_index| {
                if (!std.mem.eql(u8, requirement.name, call.callee)) continue;
                if (!containsU32Index(requirement.input_pointer_self_indices, self_index)) continue;
                if (requirement.input_self_indices.len != 0 or requirement.output_self_indices.len != 0 or requirement.output_pointer_self_indices.len != 0) {
                    try self.diags.add(call.callee_loc, .semantic, "Abstract method '{s}' is not virtual-safe because Self escapes by value or output", .{call.callee});
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
                const coerced_input = try self.coerceCallInputToExpected(&requirement.input, input, call.input, s);
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
                const node = try sg.makeSGNode(.{ .virtual_call = virtual_call }, call.callee_loc, self.allocator);
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

    fn handleNullableUnwrapCall(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (call.input.*.content != .struct_value_literal) return error.SymbolNotFound;

        const input_syn = call.input.*.content.struct_value_literal;
        var value_node: ?*const syn.STNode = null;
        var default_node: ?*const syn.STNode = null;
        for (input_syn.fields) |field| {
            if (std.mem.eql(u8, field.name.string, "value")) {
                value_node = field.value;
            } else if (std.mem.eql(u8, field.name.string, "default")) {
                default_node = field.value;
            }
        }
        if (value_node == null or default_node == null) return error.SymbolNotFound;

        const value_te = try self.visitNode(value_node.?.*, s);
        const nullable_info = try self.nullableInfoOf(value_te.ty, value_node.?.location, "unwrap_or left operand", s);
        var fallback_te = try self.visitNode(default_node.?.*, s);
        fallback_te = try typ.coerceExprToType(nullable_info.some_value_type, fallback_te, default_node.?, s, self.allocator, self.diags);
        const unwrap_ptr = try self.allocator.create(sg.NullableUnwrapOr);
        unwrap_ptr.* = .{
            .nullable_value = value_te.node,
            .fallback_value = fallback_te.node,
            .some_variant_index = nullable_info.some_variant_index,
            .some_value_field_index = nullable_info.some_value_field_index,
            .result_type = nullable_info.some_value_type,
        };

        const n = try sg.makeSGNode(.{ .nullable_unwrap_or = unwrap_ptr }, call.callee_loc, self.allocator);
        n.sem_type = nullable_info.some_value_type;
        return .{ .node = n, .ty = nullable_info.some_value_type };
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

    fn extractCallBindingAccess(
        self: *Semantizer,
        field_value: *const sg.SGNode,
        field_ty: sg.Type,
    ) ?CallBindingAccess {
        _ = self;
        return switch (field_value.content) {
            .binding_use => |binding| .{
                .root_name = binding.name,
                .mode = .value,
                .access_node = field_value,
            },
            .struct_field_access,
            .choice_payload_access,
            .array_index,
            .dereference,
            => blk: {
                const root_name = extractBindingRootName(field_value) orelse break :blk null;
                break :blk .{
                    .root_name = root_name,
                    .mode = .value,
                    .access_node = field_value,
                };
            },
            .address_of => |inner| blk: {
                if (field_ty != .pointer_type) break :blk null;
                const root_name = extractBindingRootName(inner) orelse break :blk null;

                const mode: CallAccessMode = switch (field_ty.pointer_type.mutability) {
                    .read_only => .read,
                    .read_write => .write,
                };
                break :blk .{
                    .root_name = root_name,
                    .mode = mode,
                    .access_node = inner,
                };
            },
            else => null,
        };
    }

    fn extractBindingRootName(node: *const sg.SGNode) ?[]const u8 {
        return switch (node.content) {
            .binding_use => |binding| binding.name,
            .struct_field_access => |acc| extractBindingRootName(acc.struct_value),
            .choice_payload_access => |acc| extractBindingRootName(acc.choice_value),
            .array_index => |acc| extractBindingRootName(acc.array_ptr),
            .dereference => |deref| extractBindingRootName(deref.pointer),
            else => null,
        };
    }

    fn indexNodesMayAlias(left: *const sg.SGNode, right: *const sg.SGNode) bool {
        if (left.content == .value_literal and right.content == .value_literal) {
            const l = left.content.value_literal;
            const r = right.content.value_literal;
            if (l == .int_literal and r == .int_literal) {
                return l.int_literal == r.int_literal;
            }
        }

        return true;
    }

    fn accessNodesMayAlias(left: *const sg.SGNode, right: *const sg.SGNode) bool {
        return switch (left.content) {
            .binding_use => switch (right.content) {
                .binding_use => std.mem.eql(u8, left.content.binding_use.name, right.content.binding_use.name),
                .struct_field_access => accessNodesMayAlias(left, right.content.struct_field_access.struct_value),
                .choice_payload_access => accessNodesMayAlias(left, right.content.choice_payload_access.choice_value),
                .array_index => accessNodesMayAlias(left, right.content.array_index.array_ptr),
                .dereference => false,
                else => false,
            },
            .struct_field_access => |lacc| switch (right.content) {
                .binding_use => accessNodesMayAlias(lacc.struct_value, right),
                .struct_field_access => |racc| lacc.field_index == racc.field_index and accessNodesMayAlias(lacc.struct_value, racc.struct_value),
                else => false,
            },
            .choice_payload_access => |lacc| switch (right.content) {
                .binding_use => accessNodesMayAlias(lacc.choice_value, right),
                .choice_payload_access => |racc| lacc.variant_index == racc.variant_index and accessNodesMayAlias(lacc.choice_value, racc.choice_value),
                else => false,
            },
            .array_index => |lacc| switch (right.content) {
                .binding_use => accessNodesMayAlias(lacc.array_ptr, right),
                .array_index => |racc| accessNodesMayAlias(lacc.array_ptr, racc.array_ptr) and indexNodesMayAlias(lacc.index, racc.index),
                .dereference => accessNodesMayAlias(lacc.array_ptr, right),
                else => false,
            },
            .dereference => |lderef| switch (right.content) {
                .dereference => |rderef| accessNodesMayAlias(lderef.pointer, rderef.pointer),
                .struct_field_access => accessNodesMayAlias(left, right.content.struct_field_access.struct_value),
                .choice_payload_access => accessNodesMayAlias(left, right.content.choice_payload_access.choice_value),
                .array_index => accessNodesMayAlias(left, right.content.array_index.array_ptr),
                else => false,
            },
            else => false,
        };
    }

    fn callModesConflict(a: CallAccessMode, b: CallAccessMode) bool {
        return a == .write or b == .write;
    }

    fn modeText(mode: CallAccessMode) []const u8 {
        return switch (mode) {
            .value => "value",
            .read => "&",
            .write => "$&",
        };
    }

    fn checkCallBindingExclusivity(
        self: *Semantizer,
        callee_name: []const u8,
        input_te: typ.TypedExpr,
        loc: tok.Location,
    ) SemErr!void {
        if (input_te.ty != .struct_type) return;
        if (input_te.node.content != .struct_value_literal) return;

        const input_ty = input_te.ty.struct_type;
        const input_value = input_te.node.content.struct_value_literal;

        var i: usize = 0;
        while (i < input_value.fields.len) : (i += 1) {
            const left = self.extractCallBindingAccess(input_value.fields[i].value, input_ty.fields[i].ty) orelse continue;

            var j: usize = i + 1;
            while (j < input_value.fields.len) : (j += 1) {
                const right = self.extractCallBindingAccess(input_value.fields[j].value, input_ty.fields[j].ty) orelse continue;
                if (!std.mem.eql(u8, left.root_name, right.root_name)) continue;
                if (!accessNodesMayAlias(left.access_node, right.access_node)) continue;
                if (!callModesConflict(left.mode, right.mode)) continue;

                try self.diags.add(
                    loc,
                    .semantic,
                    "binding '{s}' cannot be passed as '{s}' and '{s}' in the same call to '{s}'",
                    .{ left.root_name, modeText(left.mode), modeText(right.mode), callee_name },
                );
                return error.Reported;
            }
        }
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

    fn resolveRegularCallCallee(
        self: *Semantizer,
        call: syn.FunctionCall,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        return self.tryResolveRegularCallCallee(call, input_te, s, loc) catch |err| switch (err) {
            error.SymbolNotFound => {
                if (self.defer_unknown_top_level and self.current_top_node != null) {
                    return error.SymbolNotFound;
                }
                if (call.module_qualifier) |module_name| {
                    const module_dir = s.lookupModuleAlias(module_name) orelse {
                        try self.diags.add(loc, .semantic, "unknown module alias '{s}'", .{module_name});
                        return error.Reported;
                    };
                    if (try self.addMissingAbstractImplementationDiagnosticMaybeFiltered(call.callee, input_te.ty, s, loc, module_dir)) {
                        return error.Reported;
                    }
                    try self.addMissingModuleFunctionDiagnostic(module_name, module_dir, call.callee, input_te.ty, s, loc);
                    return error.Reported;
                }
                if (try self.addMissingAbstractImplementationDiagnostic(call.callee, input_te.ty, s, loc)) {
                    return error.Reported;
                }
                try self.addMissingFunctionDiagnostic(call.callee, input_te.ty, s, loc);
                return error.Reported;
            },
            else => return err,
        };
    }

    fn tryResolveRegularCallCallee(
        self: *Semantizer,
        call: syn.FunctionCall,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        const qualified_module_dir = if (call.module_qualifier) |module_name|
            s.lookupModuleAlias(module_name)
        else
            null;
        var chosen: *sg.FunctionDeclaration = undefined;
        if (call.type_arguments_struct) |stargs| {
            chosen = self.instantiateGenericNamedVisible(call.callee, stargs, input_te, s, .regular, qualified_module_dir, loc.file) catch |err| switch (err) {
                error.SymbolNotFound => try self.instantiateGenericNamedVisible(call.callee, stargs, input_te, s, .abstract_contract, qualified_module_dir, loc.file),
                else => return err,
            };
        } else if (call.type_arguments) |targs| {
            chosen = self.instantiateGenericVisible(call.callee, targs, input_te, s, .regular, qualified_module_dir, loc.file) catch |err| switch (err) {
                error.SymbolNotFound => try self.instantiateGenericVisible(call.callee, targs, input_te, s, .abstract_contract, qualified_module_dir, loc.file),
                else => return err,
            };
        } else {
            const empty_args = syn.StructTypeLiteral{ .fields = &.{} };
            var has_unknown_candidate = false;
            const inferred = self.instantiateGenericNamedVisible(call.callee, empty_args, input_te, s, .regular, qualified_module_dir, loc.file) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.UnknownType => blk: {
                    has_unknown_candidate = true;
                    break :blk null;
                },
                else => return err,
            };

            const visible_declared = if (call.module_qualifier) |module_name|
                try self.resolveQualifiedDeclaredOverloadMaybe(module_name, call.callee, input_te, s, loc)
            else
                try self.resolveVisibleDeclaredOverloadMaybe(call.callee, input_te, s, loc);
            const abstract_inferred = if (call.module_qualifier != null)
                self.instantiateGenericNamedVisible(
                    call.callee,
                    empty_args,
                    input_te,
                    s,
                    .abstract_contract,
                    qualified_module_dir,
                    loc.file,
                ) catch |inner_err| switch (inner_err) {
                    error.SymbolNotFound => null,
                    error.UnknownType => blk: {
                        has_unknown_candidate = true;
                        break :blk null;
                    },
                    else => return inner_err,
                }
            else
                self.instantiateGenericNamed(call.callee, empty_args, input_te, s, .abstract_contract) catch |inner_err| switch (inner_err) {
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
        var in_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.input, s, subst);

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
            const requester_dir = self.moduleDirForFile(loc.file);
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
                    if (!std.mem.startsWith(u8, cand.location.file, module_dir)) continue;
                    if (!(try self.functionIsVisible(cand, loc.file))) continue;
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
                    if (!(try self.functionMatchesVisibilityFilter(cand, loc.file, null))) {
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

    fn buildNamedPipeInput(
        self: *Semantizer,
        field_names: []const []const u8,
        args: []const typ.TypedExpr,
    ) !typ.TypedExpr {
        var call_args = std.array_list.Managed(CallArg).init(self.allocator.*);
        defer call_args.deinit();

        for (field_names, 0..) |field_name, idx| {
            try call_args.append(.{ .name = field_name, .expr = args[idx] });
        }

        return self.buildNamedCallInput(call_args.items);
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
        expr_node: *const syn.STNode,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (typ.typesCompatible(expected, actual.ty)) return actual;

        if (expected == .pointer_type and actual.ty != .pointer_type) {
            const coerced_pointer = try typ.coerceExprToType(expected, actual, expr_node, s, self.allocator, self.diags);
            if (typ.typesCompatible(expected, coerced_pointer.ty)) return coerced_pointer;

            const ptr_expr = switch (expected.pointer_type.mutability) {
                .read_only => try typ.ensureReadOnlyPointer(expr_node, actual, self.allocator, self.diags),
                .read_write => try typ.ensureMutablePointer(expr_node, actual, s, self.allocator, self.diags),
            };
            if (typ.typesCompatible(expected, ptr_expr.ty)) return ptr_expr;
        }

        const coerced = try typ.coerceExprToType(expected, actual, expr_node, s, self.allocator, self.diags);
        if (!typ.typesCompatible(expected, coerced.ty)) {
            const pair = try self.formatTypePairText(expected, coerced.ty, s);
            defer pair.deinit();
            try self.diags.add(
                expr_node.location,
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
        expr_node: *const syn.STNode,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_node, s, self.allocator, self.diags);
        }

        const actual_struct = input_te.ty.struct_type;
        const actual_value = input_te.node.content.struct_value_literal;
        const positional_prefix: usize = @min(actual_value.dispatch_prefix_positional_count, actual_value.fields.len);

        if (positional_prefix > expected.fields.len) {
            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_node, s, self.allocator, self.diags);
        }

        for (actual_value.fields[positional_prefix..]) |actual_field| {
            if (typ.findFieldByName(expected, actual_field.name) == null) {
                return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_node, s, self.allocator, self.diags);
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
            field_expr = try self.coerceCallFieldExpr(exp_field.ty, field_expr, expr_node, s);
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
                field_expr = try self.coerceCallFieldExpr(exp_field.ty, field_expr, expr_node, s);
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
                        expr_node.location,
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

            return try typ.coerceExprToType(.{ .struct_type = expected }, input_te, expr_node, s, self.allocator, self.diags);
        }

        const value_ptr = try self.allocator.create(sg.StructValueLiteral);
        value_ptr.* = .{
            .fields = coerced_fields,
            .ty = .{ .struct_type = expected },
            .dispatch_prefix_positional_count = @intCast(positional_prefix),
        };

        const node = try sg.makeSGNode(.{ .struct_value_literal = value_ptr }, expr_node.location, self.allocator);
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
            .origin_file = loc.file,
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

    fn handlePipe(
        self: *Semantizer,
        pipe: syn.PipeExpression,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const left_te = try self.visitNode(pipe.left.*, s);
        if (pipe.right.content == .function_call) {
            const call = pipe.right.content.function_call;

            if (call.input.*.content != .struct_value_literal) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "pipe right-hand side must be a call with explicit arguments",
                    .{},
                );
                return error.Reported;
            }

            const sv = call.input.*.content.struct_value_literal;
            if (sv.fields.len == 0) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "pipe right-hand side must use at least one argument placeholder",
                    .{},
                );
                return error.Reported;
            }

            var args = std.array_list.Managed(CallArg).init(self.allocator.*);
            defer args.deinit();

            var found_placeholder = false;
            for (sv.fields) |field| {
                if (syntaxNodeContainsPipePlaceholder(field.value)) {
                    found_placeholder = true;
                    break;
                }
            }
            if (!found_placeholder) {
                try self.diags.add(
                    loc,
                    .semantic,
                    "pipe right-hand side must use at least one argument placeholder",
                    .{},
                );
                return error.Reported;
            }

            for (sv.fields) |field| {
                try args.append(.{
                    .name = field.name.string,
                    .expr = try self.evalPipeArg(field.value, left_te, s),
                });
            }

            var input_te = try self.buildCallInputWithPositionalPrefix(args.items, sv.positional_prefix_count);

            if (std.mem.eql(u8, call.callee, "is")) {
                return self.handleIsBuiltinFromInput(input_te, loc, s);
            }

            const chosen = try self.resolveRegularCallCallee(
                .{
                    .callee = call.callee,
                    .callee_loc = call.callee_loc,
                    .module_qualifier = call.module_qualifier,
                    .type_arguments = call.type_arguments,
                    .type_arguments_struct = call.type_arguments_struct,
                    .input = call.input,
                },
                input_te,
                s,
                loc,
            );
            input_te = try self.coerceCallInputToExpected(&chosen.input, input_te, call.input, s);

            const fc_ptr = try self.allocator.create(sg.FunctionCall);
            fc_ptr.* = .{ .callee = chosen, .input = input_te.node };

            const n = try sg.makeSGNode(.{ .function_call = fc_ptr }, loc, self.allocator);
            return .{ .node = n, .ty = typ.functionReturnType(chosen) };
        }

        if (!syntaxNodeContainsPipePlaceholder(pipe.right)) {
            try self.diags.add(
                loc,
                .semantic,
                "pipe right-hand side must use at least one argument placeholder",
                .{},
            );
            return error.Reported;
        }

        return self.evalPipeArg(pipe.right, left_te, s);
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
        call: syn.FunctionCall,
        input_te: typ.TypedExpr,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (input_te.ty != .struct_type or input_te.node.content != .struct_value_literal) {
            try self.diags.add(
                call.input.*.location,
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
                call.input.*.location,
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        }

        const expected_idx = fieldIndexInStruct(input_struct, "expected_reason") orelse {
            try self.diags.add(
                call.input.*.location,
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        };
        const actual_idx = fieldIndexInStruct(input_struct, "actual_result") orelse {
            try self.diags.add(
                call.input.*.location,
                .semantic,
                "testing.expect_error expects '.expected_reason' and '.actual_result' arguments",
                .{},
            );
            return error.Reported;
        };

        const actual_info = try self.errableInfoOf(input_struct.fields[actual_idx].ty, call.input.*.location, "'.actual_result'", s);
        const error_payload_struct = switch (actual_info.error_payload_type) {
            .struct_type => |st| st,
            else => return error.Reported,
        };
        const reason_field = typ.findFieldByName(error_payload_struct, "reason") orelse {
            try self.diags.add(
                call.input.*.location,
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
        expected_reason_te = try typ.coerceExprToType(reason_field.ty, expected_reason_te, call.input, s, self.allocator, self.diags);
        if (!typ.typesCompatible(reason_field.ty, expected_reason_te.ty)) {
            const pair = try self.formatTypePairText(reason_field.ty, expected_reason_te.ty, s);
            defer pair.deinit();
            try self.diags.add(
                call.input.*.location,
                .semantic,
                "testing.expect_error expects '.expected_reason' compatible with '{s}', found '{s}'",
                .{ pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const test_fail_fn = try self.resolveTestingFailImpl(s, call.callee_loc);
        const result_type = typ.functionReturnType(test_fail_fn);
        const result_info = try self.errableInfoOf(result_type, call.callee_loc, "testing.expect_error result", s);

        const expect_err = try self.allocator.create(sg.TestingExpectError);
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
            .line = call.callee_loc.line,
            .column = call.callee_loc.column,
            .source_file = call.callee_loc.file,
            .source_line = self.sourceLineText(call.callee_loc),
        };

        const node = try sg.makeSGNode(.{ .testing_expect_error = expect_err }, call.callee_loc, self.allocator);
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
            const requester_dir = self.moduleDirForFile(loc.file);
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
                    if (!std.mem.startsWith(u8, cand.location.file, module_dir)) continue;
                    if (!(try self.functionIsVisible(cand, loc.file))) continue;
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
                    if (!(try self.functionMatchesVisibilityFilter(cand, loc.file, null))) {
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
                    if (try self.functionMatchesVisibilityFilter(cand, loc.file, null)) return true;
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
                    if (!(try self.functionMatchesVisibilityFilter(cand, loc.file, null))) continue;
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
                        const requester_dir = self.moduleDirForFile(loc.file);
                        const tmpl_dir = self.moduleDirForFile(tmpl.location.file);
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
                    if (try self.functionMatchesVisibilityFilter(cand, loc.file, module_dir)) return true;
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
                    if (!(try self.functionMatchesVisibilityFilter(cand, loc.file, module_dir))) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try abs.appendFunctionSignature(&buf, cand, s);
                }
            }
            if (sc.generic_functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .abstract_contract) continue;
                    if (!std.mem.startsWith(u8, tmpl.location.file, module_dir)) continue;
                    if (isPrivateName(fn_name)) {
                        const requester_dir = self.moduleDirForFile(loc.file);
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
        for (tmpl.input.fields, 0..) |fld, i| {
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(fld.name.string);
            try buf.appendSlice(": ");
            try self.appendTemplateTypePretty(buf, fld.type.?, tmpl);
        }
        try buf.appendSlice(") -> (");
        for (tmpl.output.fields, 0..) |fld, i| {
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(fld.name.string);
            try buf.appendSlice(": ");
            try self.appendTemplateTypePretty(buf, fld.type.?, tmpl);
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
                if (tmpl.param_abstract_constraints[idx]) |constraint| return constraint;
            }
            return param.name;
        }
        return null;
    }

    fn appendTemplateTypePretty(
        self: *Semantizer,
        buf: *std.array_list.Managed(u8),
        ty: syn.Type,
        tmpl: gen.GenericTemplate,
    ) !void {
        switch (ty) {
            .type_name => |tn| {
                try buf.appendSlice(self.templateParamDisplayName(tmpl, tn.string) orelse tn.string);
            },
            .pointer_type => |ptr_info| {
                switch (ptr_info.mutability) {
                    .read_only => try buf.appendSlice("&"),
                    .read_write => try buf.appendSlice("$&"),
                }
                try self.appendTemplateTypePretty(buf, ptr_info.child.*, tmpl);
            },
            .inferred_errable => |inner| {
                try buf.appendSlice("!");
                try self.appendTemplateTypePretty(buf, inner.*, tmpl);
            },
            .array_type => |arr_info| {
                var len_buf: [32]u8 = undefined;
                const len_text = std.fmt.bufPrint(&len_buf, "[{d}]", .{arr_info.length}) catch unreachable;
                try buf.appendSlice(len_text);
                try self.appendTemplateTypePretty(buf, arr_info.element.*, tmpl);
            },
            .generic_type_instantiation => |g| {
                try buf.appendSlice(g.base_name.string);
                try buf.appendSlice("#(");
                for (g.args.fields, 0..) |field, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(field.name.string);
                    if (field.type) |field_ty| {
                        try buf.appendSlice(": ");
                        try self.appendTemplateTypePretty(buf, field_ty, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
            .struct_type_literal => |st| {
                try buf.appendSlice("(");
                for (st.fields, 0..) |field, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(field.name.string);
                    if (field.type) |field_ty| {
                        try buf.appendSlice(": ");
                        try self.appendTemplateTypePretty(buf, field_ty, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
            .choice_type_literal => |ct| {
                try buf.appendSlice("(");
                for (ct.variants, 0..) |variant, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice("..");
                    if (variant.module_qualifier) |qualifier| {
                        try buf.appendSlice(qualifier.string);
                        try buf.appendSlice(".");
                    }
                    try buf.appendSlice(variant.name.string);
                    if (variant.payload_type) |payload| {
                        try buf.appendSlice(" ");
                        try self.appendTemplateTypePretty(buf, payload, tmpl);
                    }
                }
                try buf.appendSlice(")");
            },
        }
    }

    fn appendSyntaxTypePretty(self: *Semantizer, buf: *std.array_list.Managed(u8), ty: syn.Type) !void {
        switch (ty) {
            .type_name => |tn| try buf.appendSlice(tn.string),
            .pointer_type => |ptr_info| {
                switch (ptr_info.mutability) {
                    .read_only => try buf.appendSlice("&"),
                    .read_write => try buf.appendSlice("$&"),
                }
                try self.appendSyntaxTypePretty(buf, ptr_info.child.*);
            },
            .inferred_errable => |inner| {
                try buf.appendSlice("!");
                try self.appendSyntaxTypePretty(buf, inner.*);
            },
            .array_type => |arr_info| {
                var len_buf: [32]u8 = undefined;
                const len_text = std.fmt.bufPrint(&len_buf, "[{d}]", .{arr_info.length}) catch unreachable;
                try buf.appendSlice(len_text);
                try self.appendSyntaxTypePretty(buf, arr_info.element.*);
            },
            .generic_type_instantiation => |g| {
                try buf.appendSlice(g.base_name.string);
                try buf.appendSlice("#(");
                for (g.args.fields, 0..) |field, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(field.name.string);
                    if (field.type) |field_ty| {
                        try buf.appendSlice(": ");
                        try self.appendSyntaxTypePretty(buf, field_ty);
                    }
                }
                try buf.appendSlice(")");
            },
            .struct_type_literal => |st| {
                try buf.appendSlice("(");
                for (st.fields, 0..) |field, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(field.name.string);
                    if (field.type) |field_ty| {
                        try buf.appendSlice(": ");
                        try self.appendSyntaxTypePretty(buf, field_ty);
                    }
                }
                try buf.appendSlice(")");
            },
            .choice_type_literal => |ct| {
                try buf.appendSlice("(");
                for (ct.variants, 0..) |variant, idx| {
                    if (idx != 0) try buf.appendSlice(", ");
                    try buf.appendSlice("..");
                    if (variant.module_qualifier) |qualifier| {
                        try buf.appendSlice(qualifier.string);
                        try buf.appendSlice(".");
                    }
                    try buf.appendSlice(variant.name.string);
                    if (variant.payload_type) |payload| {
                        try buf.appendSlice(" ");
                        try self.appendSyntaxTypePretty(buf, payload);
                    }
                }
                try buf.appendSlice(")");
            },
        }
    }

    fn appendSyntaxReachDirective(self: *Semantizer, buf: *std.array_list.Managed(u8), reach: syn.ReachDirective) !void {
        _ = self;
        for (reach.alternatives, 0..) |alt, alt_idx| {
            if (alt_idx != 0) try buf.appendSlice(", ");
            for (alt.segments, 0..) |segment, seg_idx| {
                if (seg_idx != 0) try buf.append('.');
                try buf.appendSlice(segment.string);
            }
        }
    }

    fn appendSyntaxFunctionSignature(self: *Semantizer, buf: *std.array_list.Managed(u8), decl: syn.FunctionDeclaration) !void {
        try buf.appendSlice(decl.name.string);
        try buf.appendSlice("(");
        for (decl.input.fields, 0..) |field, idx| {
            if (idx != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(field.name.string);
            if (field.type) |field_ty| {
                try buf.appendSlice(": ");
                try self.appendSyntaxTypePretty(buf, field_ty);
            }
            if (field.default_value) |default_node| {
                if (default_node.content == .reach_directive) {
                    try buf.appendSlice(" = #reach ");
                    try self.appendSyntaxReachDirective(buf, default_node.content.reach_directive);
                }
            }
        }
        try buf.appendSlice(") -> (");
        for (decl.output.fields, 0..) |field, idx| {
            if (idx != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(field.name.string);
            if (field.type) |field_ty| {
                try buf.appendSlice(": ");
                try self.appendSyntaxTypePretty(buf, field_ty);
            }
        }
        try buf.appendSlice(")");
    }

    fn syntaxFunctionVisibleFrom(self: *Semantizer, decl: syn.FunctionDeclaration, decl_loc: tok.Location, requester_file: []const u8) !bool {
        if (!isPrivateName(decl.name.string)) return true;
        return try self.isSameModule(requester_file, decl_loc.file);
    }

    fn appendReachDefaultHintForDecl(
        self: *Semantizer,
        out: *std.array_list.Managed(u8),
        decl: syn.FunctionDeclaration,
        any_overload: *bool,
    ) !void {
        var decl_has_reach_default = false;
        for (decl.input.fields) |field| {
            const default_node = field.default_value orelse continue;
            if (default_node.content != .reach_directive) continue;
            decl_has_reach_default = true;
            break;
        }
        if (!decl_has_reach_default) return;

        if (any_overload.*) try out.appendSlice("\n");
        any_overload.* = true;
        try out.appendSlice("  - ");
        try self.appendSyntaxFunctionSignature(out, decl);
        try out.appendSlice("\n    omitted #reach defaults:");

        for (decl.input.fields) |field| {
            const default_node = field.default_value orelse continue;
            if (default_node.content != .reach_directive) continue;
            try out.appendSlice("\n      - .");
            try out.appendSlice(field.name.string);
            try out.appendSlice(" uses #reach [");
            try self.appendSyntaxReachDirective(out, default_node.content.reach_directive);
            try out.appendSlice("]");
            if (field.type) |field_ty| {
                try out.appendSlice(" expected as '");
                try self.appendSyntaxTypePretty(out, field_ty);
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
        for (self.st_nodes) |node| {
            const decl = switch (node.content) {
                .function_declaration => |decl| decl,
                .test_declaration => |td| td.decl,
                else => continue,
            };
            if (!std.mem.eql(u8, decl.name.string, fn_name)) continue;
            if (!(try self.syntaxFunctionVisibleFrom(decl, node.location, requester_file))) continue;
            try self.appendReachDefaultHintForDecl(&overloads, decl, &any_overload);
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
            if (try self.buildReachDefaultDiagnosticText(fn_name, loc.file)) |details| {
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
        for (tmpl.input.fields) |fld| {
            const ty_node = fld.type.?;
            if (self.typeUsesParam(ty_node, param_name)) return fld.name.string;
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
                        if (!std.mem.startsWith(u8, tmpl.location.file, module_dir)) continue;
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
                        if (abs.typeImplementsAbstract(constraint, actual, s)) continue;

                        const actual_str = try self.formatTypeText(actual, s);
                        defer actual_str.deinit();
                        const field_name = self.findTemplateFieldUsingParam(tmpl, param.name) orelse param.name;
                        if (try abs.buildConformanceDetails(constraint, actual, s, self.allocator)) |details| {
                            defer details.deinit();
                            try self.diags.add(
                                loc,
                                .semantic,
                                "type '{s}' does not implement abstract '{s}' required by parameter '.{s}' of '{s}':\n{s}",
                                .{ actual_str.bytes, constraint, field_name, fn_name, details.bytes },
                            );
                        } else {
                            try self.diags.add(
                                loc,
                                .semantic,
                                "type '{s}' does not implement abstract '{s}' required by parameter '.{s}' of '{s}'",
                                .{ actual_str.bytes, constraint, field_name, fn_name },
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
        call: syn.FunctionCall,
        tv_in: typ.TypedExpr,
        type_decl: *sg.TypeDeclaration,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (tv_in.ty != .struct_type) {
            try self.diags.add(
                call.input.*.location,
                .semantic,
                "expected struct literal arguments when constructing type '{s}'",
                .{call.callee},
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
        const init_input_te = try self.buildTypeInitializerDispatchInput(type_decl.ty, tv_in, init_input_ty, call.input.*.location);
        const init_fn = blk: {
            if (call.type_arguments_struct) |stargs| {
                const instantiated = self.instantiateGenericNamed("init", stargs, init_input_te, s, .regular) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    else => return err,
                };
                if (instantiated) |fn_decl| break :blk fn_decl;
            } else if (call.type_arguments) |targs| {
                const instantiated = self.instantiateGeneric("init", targs, init_input_te, s, .regular) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    else => return err,
                };
                if (instantiated) |fn_decl| break :blk fn_decl;
            }

            const synthetic_init_call = syn.FunctionCall{
                .callee = "init",
                .callee_loc = call.callee_loc,
                .module_qualifier = null,
                .type_arguments = call.type_arguments,
                .type_arguments_struct = call.type_arguments_struct,
                .input = call.input,
            };

            break :blk self.tryResolveRegularCallCallee(synthetic_init_call, init_input_te, s, call.input.*.location) catch |err| switch (err) {
                error.SymbolNotFound => {
                    if (type_decl.ty == .struct_type and !(try self.hasVisibleTypeInitializerInit(type_decl.ty, call.input.*.location.file, s))) {
                        return try self.coerceCallInputToExpected(type_decl.ty.struct_type, tv_in, call.input, s);
                    }

                    const actual = self.formatOwnedText(try typ.formatCallInput(user_struct, s, self.allocator));
                    defer actual.deinit();
                    const available = self.formatOwnedText(try self.collectVisibleTypeInitializerSignatures(type_decl.ty, call.input.*.location.file, s));
                    defer available.deinit();
                    try self.diags.add(
                        call.input.*.location,
                        .semantic,
                        "failed to initialize type '{s}': no visible 'init' overload accepts arguments {s}. Available overloads:\n{s}",
                        .{ call.callee, actual.bytes, available.bytes },
                    );
                    return error.Reported;
                },
                error.AmbiguousOverload => {
                    const candidates = self.formatOwnedText(try self.collectVisibleTypeInitializerSignatures(type_decl.ty, call.input.*.location.file, s));
                    defer candidates.deinit();
                    try self.diags.add(
                        call.input.*.location,
                        .semantic,
                        "failed to initialize type '{s}': matching 'init' overloads are ambiguous. Candidates:\n{s}",
                        .{ call.callee, candidates.bytes },
                    );
                    return error.Reported;
                },
                else => return err,
            };
        };

        const expected_user_fields = try self.allocator.alloc(sg.StructTypeField, init_fn.input.fields.len - 1);
        std.mem.copyForwards(sg.StructTypeField, expected_user_fields, init_fn.input.fields[1..]);
        const expected_user_struct = try self.allocator.create(sg.StructType);
        expected_user_struct.* = .{ .fields = expected_user_fields };
        const coerced_args = try self.coerceCallInputToExpected(expected_user_struct, tv_in, call.input, s);

        const type_init = sg.TypeInitializer{
            .type_decl = type_decl,
            .init_fn = init_fn,
            .args = coerced_args.node,
        };

        const init_node = try sg.makeSGNode(.{ .type_initializer = type_init }, call.callee_loc, self.allocator);
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

    fn typeUsesParam(self: *Semantizer, ty: syn.Type, param: []const u8) bool {
        return switch (ty) {
            .type_name => std.mem.eql(u8, ty.type_name.string, param),
            .inferred_errable => |inner| self.typeUsesParam(inner.*, param),
            .pointer_type => |ptr_info| self.typeUsesParam(ptr_info.child.*, param),
            .array_type => |arr_info| self.typeUsesParam(arr_info.element.*, param),
            .generic_type_instantiation => |g| blk: {
                for (g.args.fields) |fld| {
                    if (fld.type) |sub_ty| {
                        if (self.typeUsesParam(sub_ty, param)) break :blk true;
                    }
                    if (fld.default_value) |value_expr| {
                        if (valueExprUsesParam(value_expr, param)) break :blk true;
                    }
                }
                break :blk false;
            },
            .struct_type_literal => |st| blk_struct: {
                for (st.fields) |fld| {
                    if (fld.type) |sub_ty| {
                        if (self.typeUsesParam(sub_ty, param)) break :blk_struct true;
                    }
                }
                break :blk_struct false;
            },
            .choice_type_literal => |ct| blk_choice: {
                for (ct.variants) |variant| {
                    if (variant.payload_type) |payload_ty| {
                        if (self.typeUsesParam(payload_ty, param)) break :blk_choice true;
                    }
                }
                break :blk_choice false;
            },
        };
    }

    fn extractTypeArgumentFromActual(
        self: *Semantizer,
        template_ty: syn.Type,
        actual_ty: sg.Type,
        param_name: []const u8,
        s: *Scope,
    ) ?sg.Type {
        switch (template_ty) {
            .type_name => |tn| {
                if (std.mem.eql(u8, tn.string, param_name)) return actual_ty;
            },
            .inferred_errable => |inner| {
                return self.extractTypeArgumentFromActual(inner.*, actual_ty, param_name, s);
            },
            .pointer_type => |ptr_info| {
                if (actual_ty != .pointer_type) return null;
                return self.extractTypeArgumentFromActual(
                    ptr_info.child.*,
                    actual_ty.pointer_type.child.*,
                    param_name,
                    s,
                );
            },
            .array_type => |arr_info| {
                if (actual_ty != .array_type) return null;
                return self.extractTypeArgumentFromActual(
                    arr_info.element.*,
                    actual_ty.array_type.element_type.*,
                    param_name,
                    s,
                );
            },
            .struct_type_literal => |st| {
                if (actual_ty != .struct_type) return null;
                const actual_struct = actual_ty.struct_type;
                for (st.fields) |fld| {
                    if (fld.type) |sub_ty| {
                        if (typ.findFieldByName(actual_struct, fld.name.string)) |actual_field| {
                            if (self.extractTypeArgumentFromActual(sub_ty, actual_field.ty, param_name, s)) |res|
                                return res;
                        }
                    }
                }
            },
            .choice_type_literal => return null,
            .generic_type_instantiation => |g| return self.extractTypeArgumentFromGenericInstantiation(g, actual_ty, param_name, s),
        }
        return null;
    }

    fn extractComptimeIntArgumentFromActual(
        self: *Semantizer,
        template_ty: syn.Type,
        actual_ty: sg.Type,
        param_name: []const u8,
        s: *Scope,
    ) ?i64 {
        switch (template_ty) {
            .pointer_type => |ptr_info| {
                if (actual_ty != .pointer_type) return null;
                return self.extractComptimeIntArgumentFromActual(
                    ptr_info.child.*,
                    actual_ty.pointer_type.child.*,
                    param_name,
                    s,
                );
            },
            .struct_type_literal => |st| {
                if (actual_ty != .struct_type) return null;
                const actual_struct = actual_ty.struct_type;
                for (st.fields) |fld| {
                    if (fld.type) |sub_ty| {
                        if (typ.findFieldByName(actual_struct, fld.name.string)) |actual_field| {
                            if (self.extractComptimeIntArgumentFromActual(sub_ty, actual_field.ty, param_name, s)) |res|
                                return res;
                        }
                    }
                }
            },
            .generic_type_instantiation => |g| return extractComptimeIntArgumentFromGenericInstantiation(g, actual_ty, param_name, s),
            else => {},
        }
        return null;
    }

    fn extractTypeArgumentFromGenericInstantiation(
        self: *Semantizer,
        g: @FieldType(syn.Type, "generic_type_instantiation"),
        actual_ty: sg.Type,
        param_name: []const u8,
        s: *Scope,
    ) ?sg.Type {
        _ = s;
        const identity = typ.genericIdentityOf(actual_ty) orelse return null;
        if (!std.mem.eql(u8, identity.base_name, g.base_name.string)) return null;

        for (g.args.fields) |arg_field| {
            if (arg_field.type) |arg_ty| {
                if (!self.typeUsesParam(arg_ty, param_name)) continue;
                if (typ.genericIdentityArgByName(identity, arg_field.name.string)) |arg_value| {
                    switch (arg_value) {
                        .type => |arg_ty_value| return arg_ty_value,
                        else => {},
                    }
                }
            }
        }

        return null;
    }

    fn extractComptimeIntArgumentFromGenericInstantiation(
        g: @FieldType(syn.Type, "generic_type_instantiation"),
        actual_ty: sg.Type,
        param_name: []const u8,
        s: *Scope,
    ) ?i64 {
        _ = s;
        const identity = typ.genericIdentityOf(actual_ty) orelse return null;
        if (!std.mem.eql(u8, identity.base_name, g.base_name.string)) return null;

        for (g.args.fields) |arg_field| {
            if (arg_field.default_value) |value_expr| {
                if (!valueExprUsesParam(value_expr, param_name)) continue;
                if (typ.genericIdentityArgByName(identity, arg_field.name.string)) |arg_value| {
                    switch (arg_value) {
                        .comptime_int => |value| return value,
                        else => {},
                    }
                }
            }
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
        for (tmpl.input.fields) |fld| {
            const ty_node = fld.type.?;
            if (!self.typeUsesParam(ty_node, param.name)) continue;
            if (typ.findFieldByName(actual, fld.name.string)) |actual_field| {
                switch (param.kind) {
                    .type => {
                        if (self.extractTypeArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
                            return .{ .type = res };
                    },
                    .comptime_int => {
                        if (self.extractComptimeIntArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
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
        if (tmpl.input.fields.len == 0) return null;

        for (tmpl.input.fields[1..]) |fld| {
            const ty_node = fld.type.?;
            if (!self.typeUsesParam(ty_node, param.name)) continue;
            if (typ.findFieldByName(actual, fld.name.string)) |actual_field| {
                switch (param.kind) {
                    .type => {
                        if (self.extractTypeArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
                            return .{ .type = res };
                    },
                    .comptime_int => {
                        if (self.extractComptimeIntArgumentFromActual(ty_node, actual_field.ty, param.name, s)) |res|
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
        if (tmpl.input.fields.len == 0) return false;
        const actual = init_input_ty.struct_type;

        for (actual.fields) |actual_field| {
            var idx: ?usize = null;
            for (tmpl.input.fields, 0..) |field, field_idx| {
                if (std.mem.eql(u8, field.name.string, actual_field.name)) {
                    idx = field_idx;
                    break;
                }
            }
            if (idx == null or idx.? == 0) return false;
            const expected_field = tmpl.input.fields[idx.?];
            const expected_field_ty = try self.resolveTypeWithSubst(expected_field.type.?, s, subst);
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
                    if (tmpl.input.fields.len == 0) continue;

                    const first_field = tmpl.input.fields[0];
                    const first_ptr = switch (first_field.type.?) {
                        .pointer_type => |ptr| ptr,
                        else => continue,
                    };
                    const target_ty = switch (first_ptr.child.*) {
                        .generic_type_instantiation => |g| g,
                        else => continue,
                    };
                    if (!std.mem.eql(u8, target_ty.base_name.string, name)) continue;

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

                    const candidate = try self.resolveTypeWithSubst(first_ptr.child.*, s, &subst);
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
        stargs: syn.StructTypeLiteral,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
    ) SemErr!*sg.FunctionDeclaration {
        return self.instantiateGenericNamedVisible(name, stargs, call_input, s, allowed_kind, null, null);
    }

    fn instantiateGenericNamedVisible(
        self: *Semantizer,
        name: []const u8,
        stargs: syn.StructTypeLiteral,
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
                        if (!std.mem.startsWith(u8, tmpl.location.file, module_dir)) continue;
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
                        for (stargs.fields) |fld| {
                            if (std.mem.eql(u8, fld.name.string, param.name)) {
                                const resolved = try self.resolveExplicitGenericArg(fld, param, s, &subst);
                                try self.putGenericArg(&subst, param, resolved);
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            if (self.inferGenericArgFromCall(tmpl, param, dispatch_input.ty, s, &subst)) |inferred| {
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
                    if (!self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) {
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

    fn instantiateGenericNamedWithBoundTypeArg(
        self: *Semantizer,
        name: []const u8,
        bound_param_name: []const u8,
        bound_type: sg.Type,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
    ) SemErr!*sg.FunctionDeclaration {
        var best: ?PreparedGenericTemplateCandidate = null;
        var ambiguous = false;
        defer if (best) |*prepared| prepared.deinit();

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != allowed_kind) continue;

                    var subst = GenericSubst.init(self.allocator);
                    const dispatch_input = try self.materializeTemplateReachDefaultsForDispatch(tmpl, call_input, s);

                    var ok = false;
                    for (tmpl.params) |param| {
                        if (!std.mem.eql(u8, param.name, bound_param_name)) continue;
                        if (param.kind != .type) break;
                        try subst.types.put(param.name, bound_type);
                        ok = true;
                        break;
                    }
                    if (!ok) continue;

                    ok = true;
                    for (tmpl.params) |param| {
                        if (std.mem.eql(u8, param.name, bound_param_name)) continue;
                        if (self.inferGenericArgFromCall(tmpl, param, dispatch_input.ty, s, &subst)) |inferred| {
                            try self.putGenericArg(&subst, param, inferred);
                            continue;
                        }
                        ok = false;
                        break;
                    }
                    if (!ok) {
                        subst.deinit();
                        continue;
                    }
                    if (!self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) {
                        subst.deinit();
                        continue;
                    }
                    const score = try self.templateInstantiationDispatchScore(tmpl, dispatch_input, s, &subst) orelse {
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
        return error.SymbolNotFound;
    }

    fn resolveTemplateReachDispatchType(
        self: *Semantizer,
        tmpl: gen.GenericTemplate,
        ty_node: syn.Type,
        s: *Scope,
    ) SemErr!sg.Type {
        var subst = GenericSubst.init(self.allocator);
        defer subst.deinit();

        for (tmpl.params, 0..) |param, idx| {
            const constraint_name = tmpl.param_abstract_constraints[idx] orelse continue;
            const constraint_type_decl = s.lookupType(constraint_name) orelse return error.SymbolNotFound;
            try subst.types.put(param.name, constraint_type_decl.ty);
        }

        return self.resolveTypeWithSubstPreservingAbstracts(ty_node, s, &subst);
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

        for (tmpl.input.fields) |field| {
            if (findStructValueFieldByNameFrom(actual_value.fields, positional_prefix, field.name.string) != null) continue;
            if (field.default_value == null) continue;
            if (field.default_value.?.content != .reach_directive) continue;
            if (field.type == null) continue;

            const reach_te = try self.visitNode(field.default_value.?.*, s);
            if (reach_te.node.content != .reach_directive) continue;

            const dispatch_ty = self.resolveTemplateReachDispatchType(tmpl, field.type.?, s) catch |err| switch (err) {
                error.UnknownType => {
                    if (try self.resolveReachedArgumentForInference(
                        field.name.string,
                        reach_te.node.content.reach_directive,
                        s,
                        field.default_value.?.location,
                    )) |resolved_for_inference| {
                        try args.append(.{
                            .name = field.name.string,
                            .expr = resolved_for_inference,
                        });
                        changed = true;
                    }
                    continue;
                },
                else => return err,
            };

            const resolved = try self.tryResolveReachedArgumentInLocalScope(
                field.name.string,
                dispatch_ty,
                reach_te.node.content.reach_directive,
                s,
                field.default_value.?.location,
            ) orelse blk: {
                if (self.currentReachFunctionContext()) |ctx| {
                    if (!std.mem.eql(u8, ctx.function_name, "main")) {
                        const placeholder = try sg.makeSGNode(
                            .{ .reach_directive = reach_te.node.content.reach_directive },
                            field.default_value.?.location,
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
                .name = field.name.string,
                .expr = resolved,
            });
            changed = true;
        }

        if (!changed) return call_input;
        return self.buildCallInputWithPositionalPrefix(args.items, @intCast(positional_prefix));
    }

    fn instantiateGeneric(
        self: *Semantizer,
        name: []const u8,
        type_args_syn: []const syn.Type,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
    ) SemErr!*sg.FunctionDeclaration {
        return self.instantiateGenericVisible(name, type_args_syn, call_input, s, allowed_kind, null, null);
    }

    fn instantiateGenericVisible(
        self: *Semantizer,
        name: []const u8,
        type_args_syn: []const syn.Type,
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
                        if (!std.mem.startsWith(u8, tmpl.location.file, module_dir)) continue;
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
                        const resolved = try self.resolveTypeWithSubst(type_args_syn[i], s, &subst);
                        try subst.types.put(tmpl.params[i].name, resolved);
                    }
                    if (!self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) {
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
    ) bool {
        _ = self;
        var i: usize = 0;
        while (i < tmpl.params.len) : (i += 1) {
            const constraint = tmpl.param_abstract_constraints[i] orelse continue;
            const actual = subst.types.get(tmpl.params[i].name) orelse return false;
            if (!abs.typeImplementsAbstract(constraint, actual, s)) return false;
        }
        return true;
    }

    fn instantiateGenericTemplate(
        self: *Semantizer,
        name: []const u8,
        tmpl: gen.GenericTemplate,
        call_input: typ.TypedExpr,
        s: *Scope,
        subst: *GenericSubst,
    ) SemErr!?*sg.FunctionDeclaration {
        var in_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.input, s, subst);

        if (try self.refinedStructTypeWithActual(in_struct_ptr, call_input.ty, s)) |refined| {
            in_struct_ptr = refined;
        }
        if (!self.callInputMatchesDispatch(in_struct_ptr, call_input, s)) return null;

        if (try self.findExistingFunctionExactInputInModule(name, in_struct_ptr, tmpl.location.file, tmpl.dispatch_kind, s)) |existing| {
            return existing;
        }

        const out_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.output, s, subst);

        const fn_ptr = try self.allocator.create(sg.FunctionDeclaration);
        fn_ptr.* = .{
            .id = self.freshFunctionId(),
            .name = tmpl.name,
            .location = tmpl.location,
            .origin_kind = .generic_instantiation,
            .safety_primitive = self.safetyPrimitiveForDeclaration(tmpl.name, tmpl.location.file),
            .is_deinit = std.mem.eql(u8, tmpl.name, "deinit"),
            .generic_dispatch_kind = switch (tmpl.dispatch_kind) {
                .regular => .regular,
                .abstract_contract => .abstract_contract,
            },
            .is_once = false,
            .input = in_struct_ptr.*,
            .output = out_struct_ptr.*,
            .body = null,
        };

        var child = try Scope.init(self.allocator, s, s.current_fn);
        child.current_fn = fn_ptr;
        var it = subst.types.iterator();
        while (it.next()) |entry| {
            const td = try self.allocator.create(sg.TypeDeclaration);
            td.* = .{ .name = entry.key_ptr.*, .origin_file = tmpl.location.file, .ty = entry.value_ptr.* };
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
            bd.* = .{ .name = fld.name, .location = tmpl.location, .origin_file = tmpl.location.file, .mutability = .variable, .ty = fld.ty, .initialization = null };
            try child.bindings.put(fld.name, bd);
            try input_bindings.append(bd);
        }
        var output_bindings = std.array_list.Managed(*const sg.BindingDeclaration).init(self.allocator.*);
        for (out_struct_ptr.fields) |fld| {
            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{ .name = fld.name, .location = tmpl.location, .origin_file = tmpl.location.file, .mutability = .variable, .ty = fld.ty, .initialization = null };
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
            const body_te = try self.visitNode(body_node.*, &child);
            body_cb = body_te.node.content.code_block;
        }

        fn_ptr.input = in_struct_ptr.*;
        fn_ptr.input_bindings = try input_bindings.toOwnedSlice();
        fn_ptr.output_bindings = try output_bindings.toOwnedSlice();
        fn_ptr.body = body_cb;

        try s.appendFunction(name, fn_ptr);
        const node = try sg.makeSGNode(.{ .function_declaration = fn_ptr }, tmpl.location, self.allocator);
        try self.root_list.append(node);
        self.clearDeferred(&child);
        return fn_ptr;
    }

    fn findExistingFunctionExactInputInModule(
        self: *Semantizer,
        name: []const u8,
        input: *const sg.StructType,
        module_file: []const u8,
        dispatch_kind: gen.GenericDispatchKind,
        s: *Scope,
    ) !?*sg.FunctionDeclaration {
        _ = self;
        const module_dir = std.fs.path.dirname(module_file) orelse ".";

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(name)) |fns| {
                for (fns.items) |cand| {
                    if (!std.mem.startsWith(u8, cand.location.file, module_dir)) continue;
                    if (cand.origin_kind != .generic_instantiation) continue;
                    const cand_dispatch_kind = cand.generic_dispatch_kind orelse .regular;
                    const expected_dispatch_kind: sg.FunctionDeclaration.GenericDispatchKind = switch (dispatch_kind) {
                        .regular => .regular,
                        .abstract_contract => .abstract_contract,
                    };
                    if (cand_dispatch_kind != expected_dispatch_kind) continue;
                    if (typ.typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = input })) {
                        return cand;
                    }
                }
            }
        }

        return null;
    }

    pub fn instantiateGenericTypeNamed(
        self: *Semantizer,
        name: []const u8,
        stargs: syn.StructTypeLiteral,
        s: *Scope,
        outer_subst: ?*const GenericSubst,
    ) SemErr!sg.Type {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_types.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();

                    if (outer_subst) |outer| {
                        try subst.cloneFrom(outer);
                    }

                    var ok: bool = true;
                    for (tmpl.params) |param| {
                        var found: bool = false;
                        for (stargs.fields) |fld| {
                            if (std.mem.eql(u8, fld.name.string, param.name)) {
                                const resolved = try self.resolveExplicitGenericArg(fld, param, s, &subst);
                                try self.putGenericArg(&subst, param, resolved);
                                found = true;
                                break;
                            }
                        }
                        if (!found) {
                            ok = false;
                            break;
                        }
                    }
                    if (!ok) continue;

                    for (tmpl.params, 0..) |param, index| {
                        const constraint = tmpl.param_abstract_constraints[index] orelse continue;
                        const actual = subst.types.get(param.name) orelse continue;
                        if (abs.typeImplementsAbstract(constraint, actual, s)) continue;

                        const actual_text = try self.formatTypeText(actual, s);
                        defer actual_text.deinit();
                        try self.diags.add(
                            tmpl.location,
                            .semantic,
                            "type '{s}' does not implement abstract '{s}' required by generic type parameter '.{s}' of '{s}'",
                            .{ actual_text.bytes, constraint, param.name, tmpl.name },
                        );
                        return error.Reported;
                    }

                    return switch (tmpl.body.*.content) {
                        .struct_type_literal => |st| blk_struct: {
                            const st_ptr = try self.structTypeFromLiteralWithSubst(st, s, &subst);
                            const arg_names = try self.allocator.alloc([]const u8, tmpl.params.len);
                            const arg_values = try self.allocator.alloc(sg.GenericIdentityArg, tmpl.params.len);
                            var i: usize = 0;
                            while (i < tmpl.params.len) : (i += 1) {
                                arg_names[i] = tmpl.params[i].name;
                                arg_values[i] = switch (tmpl.params[i].kind) {
                                    .type => .{ .type = subst.types.get(tmpl.params[i].name).? },
                                    .comptime_int => .{ .comptime_int = subst.ints.get(tmpl.params[i].name).? },
                                };
                            }

                            const identity = try self.allocator.create(sg.GenericTypeIdentity);
                            identity.* = .{
                                .base_name = tmpl.name,
                                .arg_names = arg_names,
                                .arg_values = arg_values,
                            };
                            st_ptr.identity = .{ .generic = identity };
                            break :blk_struct .{ .struct_type = st_ptr };
                        },
                        .choice_type_literal => |ct| blk_choice: {
                            const choice_ptr = try self.choiceTypeFromLiteralWithSubst(ct, s, &subst);
                            const arg_names = try self.allocator.alloc([]const u8, tmpl.params.len);
                            const arg_values = try self.allocator.alloc(sg.GenericIdentityArg, tmpl.params.len);
                            var i: usize = 0;
                            while (i < tmpl.params.len) : (i += 1) {
                                arg_names[i] = tmpl.params[i].name;
                                arg_values[i] = switch (tmpl.params[i].kind) {
                                    .type => .{ .type = subst.types.get(tmpl.params[i].name).? },
                                    .comptime_int => .{ .comptime_int = subst.ints.get(tmpl.params[i].name).? },
                                };
                            }

                            const identity = try self.allocator.create(sg.GenericTypeIdentity);
                            identity.* = .{
                                .base_name = tmpl.name,
                                .arg_names = arg_names,
                                .arg_values = arg_values,
                            };
                            choice_ptr.identity = .{ .generic = identity };
                            break :blk_choice .{ .choice_type = choice_ptr };
                        },
                        else => error.NotYetImplemented,
                    };
                }
            }
        }
        return error.SymbolNotFound;
    }

    //──────────────────────────────────────────────────── BINARY OP
    fn handleBinOp(
        self: *Semantizer,
        bo: syn.BinaryOperation,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var lhs = try self.visitNode(bo.left.*, s);
        var rhs = try self.visitNode(bo.right.*, s);

        const operator_name = switch (bo.operator) {
            .addition => "operator +",
            else => null,
        };

        if (operator_name) |name| {
            var input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "left", .expr = lhs },
                .{ .name = "right", .expr = rhs },
            });
            const empty_args = syn.StructTypeLiteral{ .fields = &.{} };

            var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, bo.left.*.location) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, bo.left.*.location);
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
                input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, bo.left, s);

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
        if ((bo.operator == .addition or bo.operator == .subtraction) and lhs_is_ptr != rhs_is_ptr) {
            try self.diags.add(
                bo.left.*.location,
                .semantic,
                "pointer arithmetic is not allowed; cast explicitly to an integer, perform the arithmetic, and cast back",
                .{},
            );
            return error.Reported;
        }

        rhs = try typ.coerceExprToType(lhs.ty, rhs, bo.right, s, self.allocator, self.diags);
        lhs = try typ.coerceExprToType(rhs.ty, lhs, bo.left, s, self.allocator, self.diags);

        if (!typ.typesExactlyEqual(lhs.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(lhs.ty, rhs.ty, s);
            defer pair.deinit();
            const verb = binaryOpVerb(bo.operator);
            try self.diags.add(
                bo.left.*.location,
                .semantic,
                "cannot {s} '{s}' and '{s}'",
                .{ verb, pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const bin = try self.allocator.create(sg.BinaryOperation);
        bin.* = .{ .operator = bo.operator, .left = lhs.node, .right = rhs.node };

        const n = try sg.makeSGNode(.{ .binary_operation = bin.* }, loc, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = lhs.ty };
    }

    //──────────────────────────────────────────────────── COMPARISON
    fn handleComparison(
        self: *Semantizer,
        c: syn.Comparison,
        loc: tok.Location,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var lhs = try self.visitNode(c.left.*, s);
        var rhs = try self.visitNode(c.right.*, s);

        const operator_name = switch (c.operator) {
            .equal => "operator ==",
            .not_equal => "operator !=",
            else => null,
        };

        if (operator_name) |name| {
            var input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "left", .expr = lhs },
                .{ .name = "right", .expr = rhs },
            });
            const empty_args = syn.StructTypeLiteral{ .fields = &.{} };

            var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, c.left.*.location) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, c.left.*.location);
                        return error.Reported;
                    },
                    else => return err,
                };
            }

            if (chosen) |chosen_fn| {
                input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, c.left, s);

                const result_ty = typ.functionReturnType(chosen_fn);
                if (!typ.typesExactlyEqual(result_ty, .{ .builtin = .Bool })) {
                    const actual = try self.formatTypeText(result_ty, s);
                    defer actual.deinit();
                    try self.diags.add(
                        c.left.*.location,
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

        if (c.operator == .equal or c.operator == .not_equal) {
            if (try self.coercePayloadlessChoiceComparisonSide(lhs.ty, rhs, c.right.*.location, s)) |coerced_rhs| {
                rhs = coerced_rhs;
            }
            if (try self.coercePayloadlessChoiceComparisonSide(rhs.ty, lhs, c.left.*.location, s)) |coerced_lhs| {
                lhs = coerced_lhs;
            }
        }

        rhs = try typ.coerceExprToType(lhs.ty, rhs, c.right, s, self.allocator, self.diags);
        lhs = try typ.coerceExprToType(rhs.ty, lhs, c.left, s, self.allocator, self.diags);

        if (!typ.typesExactlyEqual(lhs.ty, rhs.ty)) {
            const pair = try self.formatTypePairText(lhs.ty, rhs.ty, s);
            defer pair.deinit();
            try self.diags.add(
                c.left.*.location,
                .semantic,
                "cannot compare '{s}' and '{s}'",
                .{ pair.expected.bytes, pair.actual.bytes },
            );
            return error.Reported;
        }

        const cmp_ptr = try self.allocator.create(sg.Comparison);
        cmp_ptr.* = .{
            .operator = c.operator,
            .left = lhs.node,
            .right = rhs.node,
        };

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, loc, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Bool } };
    }

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

    fn handleLogicalOperation(
        self: *Semantizer,
        lo: syn.LogicalOperation,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var lhs = try self.visitNode(lo.left.*, s);
        var rhs = try self.visitNode(lo.right.*, s);
        const bool_ty: sg.Type = .{ .builtin = .Bool };

        lhs = try typ.coerceExprToType(bool_ty, lhs, lo.left, s, self.allocator, self.diags);
        rhs = try typ.coerceExprToType(bool_ty, rhs, lo.right, s, self.allocator, self.diags);

        if (!typ.typesExactlyEqual(lhs.ty, bool_ty)) {
            const actual = try self.formatTypeText(lhs.ty, s);
            defer actual.deinit();
            try self.diags.add(
                lo.left.*.location,
                .semantic,
                "left operand of logical operator must be 'Bool', got '{s}'",
                .{actual.bytes},
            );
            return error.Reported;
        }

        if (!typ.typesExactlyEqual(rhs.ty, bool_ty)) {
            const actual = try self.formatTypeText(rhs.ty, s);
            defer actual.deinit();
            try self.diags.add(
                lo.right.*.location,
                .semantic,
                "right operand of logical operator must be 'Bool', got '{s}'",
                .{actual.bytes},
            );
            return error.Reported;
        }

        const logical_ptr = try self.allocator.create(sg.LogicalOperation);
        logical_ptr.* = .{
            .operator = lo.operator,
            .left = lhs.node,
            .right = rhs.node,
        };

        const node = try sg.makeSGNode(.{ .logical_operation = logical_ptr.* }, lo.left.*.location, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = bool_ty };
    }

    //──────────────────────────────────────────────────── RETURN
    fn handleReturn(
        self: *Semantizer,
        r: syn.ReturnStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var e = if (r.expression) |ex| (try self.visitNode(ex.*, s)) else null;
        if (r.expression) |ex| {
            if (e) |te| e = try self.ensureValuePositionAllowed(te, ex.location, s);
        }

        const rs = try self.allocator.create(sg.ReturnStatement);
        const cleanup_nodes = try self.collectActiveEarlyCleanupNodes(s);
        rs.* = .{
            .expression = if (e) |te| te.node else null,
            .cleanup_nodes = cleanup_nodes,
        };

        const n = try sg.makeSGNode(.{ .return_statement = rs }, if (r.expression) |ex| ex.location else undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn handleErrorPropagation(
        self: *Semantizer,
        prop: syn.ErrorPropagation,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const value_te = try self.visitNode(prop.value.*, s);
        return self.lowerErrorPropagation(value_te, null, s, loc);
    }

    fn handleErrorContext(
        self: *Semantizer,
        ctx: syn.ErrorContext,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const value_te = try self.visitNode(ctx.value.*, s);
        var context_te = try self.visitNode(ctx.context.*, s);
        context_te = try self.ensureValuePositionAllowed(context_te, ctx.context.location, s);
        return self.lowerErrorPropagation(value_te, context_te, s, loc);
    }

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
                .line = loc.line,
                .column = loc.column,
                .source_file = loc.file,
                .source_line = source_line,
            };
            break :blk try sg.makeSGNode(.{ .error_context = err_ctx }, loc, self.allocator);
        } else blk: {
            const err_prop = try self.allocator.create(sg.ErrorPropagation);
            const source_line = self.sourceLineText(loc);
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
                .line = loc.line,
                .column = loc.column,
                .source_file = loc.file,
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
    fn handleIf(
        self: *Semantizer,
        ifs: syn.IfStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;

        const cond = try self.visitNode(ifs.condition.*, s);
        const nullable_refinement = try self.extractNullableIfRefinement(ifs.condition, s);

        const then_te = switch (ifs.then_block.*.content) {
            .code_block => |blk| try self.handleCodeBlockWithNullableRefinement(blk, s, nullable_refinement, ifs.condition.location),
            else => try self.visitNode(ifs.then_block.*, s),
        };

        const else_cb = if (ifs.else_block) |eb| blk: {
            var else_scope = try Scope.init(self.allocator, s, s.current_fn);
            break :blk (try self.visitNode(eb.*, &else_scope)).node.content.code_block;
        } else null;

        s.nodes.items.len = start_len;

        const if_ptr = try self.allocator.create(sg.IfStatement);
        if_ptr.* = .{
            .condition = cond.node,
            .then_block = then_te.node.content.code_block,
            .else_block = else_cb,
        };

        const n = try sg.makeSGNode(.{ .if_statement = if_ptr }, undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn extractNullableIfRefinement(
        self: *Semantizer,
        condition: *const syn.STNode,
        s: *Scope,
    ) SemErr!?NullableIfRefinement {
        if (condition.content != .function_call) return null;

        const call = condition.content.function_call;
        if (!std.mem.eql(u8, call.callee, "is")) return null;
        if (call.module_qualifier != null or call.type_arguments != null or call.type_arguments_struct != null) return null;
        if (call.input.*.content != .struct_value_literal) return null;

        const input = call.input.*.content.struct_value_literal;
        var value_field: ?syn.StructValueLiteralField = null;
        var variant_field: ?syn.StructValueLiteralField = null;
        for (input.fields) |field| {
            if (std.mem.eql(u8, field.name.string, "value")) {
                value_field = field;
            } else if (std.mem.eql(u8, field.name.string, "variant")) {
                variant_field = field;
            }
        }

        const value_node = value_field orelse return null;
        const variant_node = variant_field orelse return null;
        if (value_node.value.*.content != .identifier) return null;
        if (variant_node.value.*.content != .choice_literal) return null;

        const variant_lit = variant_node.value.*.content.choice_literal;
        if (variant_lit.payload != null) return null;

        const binding_name = value_node.value.*.content.identifier;
        const binding = s.lookupBinding(binding_name) orelse return null;
        const nullable_info = self.tryNullableInfoOfType(binding.ty) orelse return null;

        if (!std.mem.eql(u8, variant_lit.name.string, "some")) return null;
        if (!std.mem.eql(u8, binding.ty.choice_type.variants[nullable_info.some_variant_index].name, variant_lit.name.string)) return null;

        return .{
            .source_binding = binding,
            .some_variant_index = nullable_info.some_variant_index,
            .some_payload_type = nullable_info.some_payload_type,
            .some_value_type = nullable_info.some_value_type,
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

    fn handleCodeBlockWithNullableRefinement(
        self: *Semantizer,
        blk: syn.CodeBlock,
        parent: *Scope,
        refinement: ?NullableIfRefinement,
        refinement_loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        var child = try Scope.init(self.allocator, parent, parent.current_fn);
        if (refinement) |value| {
            try self.applyNullableThenRefinement(value, &child, refinement_loc);
        }

        var ret_val: ?*sg.SGNode = null;
        var ret_ty: sg.Type = .{ .builtin = .Any };

        for (blk.items, 0..) |st, idx| {
            const te = try self.visitNode(st.*, &child);
            const is_last = idx + 1 == blk.items.len;
            if (is_last and st.*.content == .expression_statement) {
                ret_val = te.node;
                ret_ty = te.ty;
                continue;
            }
            if (st.*.content == .function_call) {
                try child.nodes.append(te.node);
            }
        }

        var d_idx: usize = child.deferred.items.len;
        while (d_idx > 0) : (d_idx -= 1) {
            const group = child.deferred.items[d_idx - 1];
            for (group.nodes) |node| try child.nodes.append(node);
        }

        const slice = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);

        const cb = try self.allocator.create(sg.CodeBlock);
        cb.* = .{ .nodes = slice, .ret_val = ret_val };

        const n = try sg.makeSGNode(.{ .code_block = cb }, undefined, self.allocator);
        try parent.nodes.append(n);
        return .{ .node = n, .ty = ret_ty };
    }

    fn handleWhile(
        self: *Semantizer,
        w: syn.WhileStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;

        const cond = try self.visitNode(w.condition.*, s);
        const body_te = try self.visitNode(w.body.*, s);

        s.nodes.items.len = start_len;

        const while_ptr = try self.allocator.create(sg.WhileStatement);
        while_ptr.* = .{
            .condition = cond.node,
            .body = body_te.node.content.code_block,
        };

        const n = try sg.makeSGNode(.{ .while_statement = while_ptr }, undefined, self.allocator);
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

    fn handleFor(
        self: *Semantizer,
        f: syn.ForStatement,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const iterable_te = try self.visitNode(f.iterable.*, s);
        return self.lowerForOverIterator(f, iterable_te.ty, s, loc);
    }

    fn lowerForOverIterator(
        self: *Semantizer,
        f: syn.ForStatement,
        iterable_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        const iterable_abstract_name = switch (f.item_mode) {
            .by_value => "Iterable",
            .by_borrow => "ROPointerIterable",
            .by_mut_borrow => "RWPointerIterable",
        };
        const iterator_ctor_name = switch (f.item_mode) {
            .by_value => "to_iterator",
            .by_borrow => "to_ro_pointer_iterator",
            .by_mut_borrow => "to_rw_pointer_iterator",
        };
        const iterator_next_name = "next";
        const iterable_needs_mutability = switch (f.item_mode) {
            .by_mut_borrow => true,
            else => false,
        };
        const iterable_copyable = typ.isTypeCopyable(iterable_ty, s);
        const iterable_name = try self.makeSyntheticName("iterable");
        const iterator_name = try self.makeSyntheticName("iterator");
        const iterable_direct_ok = iterable_ty == .pointer_type and
            (!iterable_needs_mutability or iterable_ty.pointer_type.mutability == .read_write) and
            abs.typeImplementsAbstract(iterable_abstract_name, iterable_ty.pointer_type.child.*, s);

        const iterable_ident = if (iterable_copyable and f.iterable.*.content != .identifier)
            try self.makeSynNode(.{ .identifier = iterable_name }, loc)
        else
            f.iterable;

        if (!iterable_copyable and f.iterable.*.content != .identifier) {
            try self.diags.add(
                f.iterable.location,
                .semantic,
                "for cannot iterate a non-copyable expression directly; bind it to a name first",
                .{},
            );
            return error.Reported;
        }

        if (!abs.typeImplementsAbstract(iterable_abstract_name, iterable_ty, s) and !iterable_direct_ok) {
            const iterable_ty_text = try self.formatTypeText(iterable_ty, s);
            defer iterable_ty_text.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "for expects a type implementing abstract '{s}', got '{s}'",
                .{ iterable_abstract_name, iterable_ty_text.bytes },
            );
            return error.Reported;
        }

        const to_iterator_fields = try self.allocator.alloc(syn.StructValueLiteralField, 1);
        to_iterator_fields[0] = .{
            .name = .{ .string = "value", .location = loc },
            .value = if (iterable_direct_ok)
                iterable_ident
            else
                try self.makeSynNode(.{ .address_of = .{
                    .value = iterable_ident,
                    .mutability = if (iterable_needs_mutability) .read_write else .read_only,
                } }, loc),
        };
        const to_iterator_arg = try self.makeSynNode(.{ .struct_value_literal = .{
            .fields = to_iterator_fields,
        } }, loc);
        const to_iterator_call = try self.makeSynNode(.{ .function_call = .{
            .callee = iterator_ctor_name,
            .callee_loc = loc,
            .module_qualifier = null,
            .type_arguments = null,
            .type_arguments_struct = null,
            .input = to_iterator_arg,
        } }, loc);

        var iterator_check_scope_storage: ?Scope = null;
        var iterator_check_scope: *Scope = s;
        defer if (iterator_check_scope_storage) |*tmp_scope| self.clearDeferred(tmp_scope);

        if (iterable_copyable and f.iterable.*.content != .identifier) {
            iterator_check_scope_storage = try Scope.init(self.allocator, s, s.current_fn);
            const tmp_binding = try self.allocator.create(sg.BindingDeclaration);
            tmp_binding.* = .{
                .name = iterable_name,
                .location = loc,
                .origin_file = loc.file,
                .mutability = if (iterable_needs_mutability) .variable else .constant,
                .ty = iterable_ty,
                .initialization = null,
            };
            try iterator_check_scope_storage.?.bindings.put(iterable_name, tmp_binding);
            iterator_check_scope = &iterator_check_scope_storage.?;
        }

        const iterator_te = try self.visitNode(to_iterator_call.*, iterator_check_scope);
        if (!abs.typeImplementsAbstract("Iterator", iterator_te.ty, iterator_check_scope)) {
            const iterator_ty = try self.formatTypeText(iterator_te.ty, iterator_check_scope);
            defer iterator_ty.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "for expects '{s}(.value = ...)' to return a type implementing abstract '{s}', got '{s}'",
                .{ iterator_ctor_name, "Iterator", iterator_ty.bytes },
            );
            return error.Reported;
        }

        const iterator_decl = try self.makeSynNode(.{ .symbol_declaration = .{
            .name = .{ .string = iterator_name, .location = loc },
            .type = null,
            .mutability = .variable,
            .value = to_iterator_call,
        } }, loc);

        const iterator_ident = try self.makeSynNode(.{ .identifier = iterator_name }, loc);
        const iterator_ro_addr = try self.makeSynNode(.{ .address_of = .{
            .value = iterator_ident,
            .mutability = .read_only,
        } }, loc);
        const iterator_rw_addr = try self.makeSynNode(.{ .address_of = .{
            .value = iterator_ident,
            .mutability = .read_write,
        } }, loc);

        const has_next_fields = try self.allocator.alloc(syn.StructValueLiteralField, 1);
        has_next_fields[0] = .{
            .name = .{ .string = "self", .location = loc },
            .value = iterator_ro_addr,
        };
        const has_next_arg = try self.makeSynNode(.{ .struct_value_literal = .{
            .fields = has_next_fields,
        } }, loc);
        const has_next_call = try self.makeSynNode(.{ .function_call = .{
            .callee = "has_next",
            .callee_loc = loc,
            .module_qualifier = null,
            .type_arguments = null,
            .type_arguments_struct = null,
            .input = has_next_arg,
        } }, loc);

        const next_fields = try self.allocator.alloc(syn.StructValueLiteralField, 1);
        next_fields[0] = .{
            .name = .{ .string = "self", .location = loc },
            .value = iterator_rw_addr,
        };
        const next_arg = try self.makeSynNode(.{ .struct_value_literal = .{
            .fields = next_fields,
        } }, loc);
        const next_call = try self.makeSynNode(.{ .function_call = .{
            .callee = iterator_next_name,
            .callee_loc = loc,
            .module_qualifier = null,
            .type_arguments = null,
            .type_arguments_struct = null,
            .input = next_arg,
        } }, loc);

        const item_decl = try self.makeSynNode(.{ .symbol_declaration = .{
            .name = f.item_name,
            .type = null,
            .mutability = .constant,
            .value = next_call,
        } }, loc);

        const while_body_items = try self.allocator.alloc(*syn.STNode, 2);
        while_body_items[0] = item_decl;
        while_body_items[1] = f.body;
        const while_body = try self.makeSynNode(.{ .code_block = .{
            .items = while_body_items,
        } }, loc);
        const while_stmt = try self.makeSynNode(.{ .while_statement = .{
            .condition = has_next_call,
            .body = while_body,
        } }, loc);

        const item_count: usize = if (iterable_copyable and f.iterable.*.content != .identifier) 3 else 2;
        const lowered_items = try self.allocator.alloc(*syn.STNode, item_count);
        var idx: usize = 0;
        if (item_count == 3) {
            lowered_items[0] = try self.makeSynNode(.{ .symbol_declaration = .{
                .name = .{ .string = iterable_name, .location = loc },
                .type = null,
                .mutability = .constant,
                .value = f.iterable,
            } }, loc);
            idx = 1;
        }
        lowered_items[idx] = iterator_decl;
        lowered_items[idx + 1] = while_stmt;

        const lowered = try self.makeSynNode(.{ .code_block = .{
            .items = lowered_items,
        } }, loc);
        return self.visitNode(lowered.*, s);
    }

    fn handleMatch(
        self: *Semantizer,
        m: syn.MatchStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;
        const match_requires_move = for (m.cases) |case_syn| {
            if (case_syn.payload_binding) |payload_binding| {
                if (!std.mem.eql(u8, payload_binding.name.string, "_") and payload_binding.mode == .by_move) break true;
            }
        } else false;

        const value_te = if (match_requires_move) blk: {
            if (m.value.*.content == .identifier) {
                break :blk try self.handleMove(m.value, s, m.value.location);
            }

            const te = try self.visitNode(m.value.*, s);
            if (typ.expressionNeedsCopyForValuePosition(te.node)) {
                try self.diags.add(
                    m.value.location,
                    .semantic,
                    "match payload move bindings currently only support named bindings or temporary expressions",
                    .{},
                );
                return error.Reported;
            }
            break :blk te;
        } else try self.visitNode(m.value.*, s);
        if (value_te.ty != .choice_type) {
            const desc = try self.formatTypeText(value_te.ty, s);
            defer desc.deinit();
            try self.diags.add(
                m.value.location,
                .semantic,
                "match expects a choice value, found '{s}'",
                .{desc.bytes},
            );
            return error.Reported;
        }

        const choice_ty = value_te.ty.choice_type;
        var cases = std.array_list.Managed(sg.SwitchCase).init(self.allocator.*);

        for (m.cases) |case_syn| {
            var found_idx: ?u32 = null;
            var payload_ty: ?sg.Type = null;
            for (choice_ty.variants, 0..) |variant, idx| {
                if (std.mem.eql(u8, variant.name, case_syn.variant_name.string)) {
                    found_idx = @intCast(idx);
                    payload_ty = variant.payload_type;
                    break;
                }
            }

            if (found_idx == null) {
                const choice_text = try self.formatTypeText(value_te.ty, s);
                defer choice_text.deinit();
                try self.diags.add(
                    case_syn.variant_name.location,
                    .semantic,
                    "choice type '{s}' has no variant '..{s}'",
                    .{ choice_text.bytes, case_syn.variant_name.string },
                );
                return error.Reported;
            }

            const case_body = try self.handleMatchCaseBody(value_te, found_idx.?, payload_ty, case_syn, s);

            const lit_ptr = try self.allocator.create(sg.ChoiceLiteral);
            lit_ptr.* = .{
                .variant_name = case_syn.variant_name.string,
                .choice_type = choice_ty,
                .variant_index = found_idx.?,
                .payload = null,
            };
            const lit_node = try sg.makeSGNode(.{ .choice_literal = lit_ptr }, case_syn.variant_name.location, self.allocator);
            lit_node.sem_type = value_te.ty;

            try cases.append(.{
                .value = lit_node,
                .variant_index = found_idx.?,
                .body = case_body,
            });
        }

        s.nodes.items.len = start_len;

        const switch_ptr = try self.allocator.create(sg.SwitchStatement);
        switch_ptr.* = .{
            .expression = value_te.node,
            .cases = try cases.toOwnedSlice(),
            .default_case = null,
        };

        const node = try sg.makeSGNode(.{ .switch_statement = switch_ptr }, m.value.location, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Any } };
    }

    fn handleMatchCaseBody(
        self: *Semantizer,
        choice_value: typ.TypedExpr,
        variant_index: u32,
        payload_ty: ?sg.Type,
        case_syn: syn.MatchCase,
        parent: *Scope,
    ) SemErr!*const sg.CodeBlock {
        var child = try Scope.init(self.allocator, parent, parent.current_fn);

        if (case_syn.payload_binding) |payload_binding| {
            const binding_name = payload_binding.name;
            if (std.mem.eql(u8, binding_name.string, "_")) {
                if (payload_ty == null) {
                    try self.diags.add(
                        binding_name.location,
                        .semantic,
                        "choice variant '..{s}' has no payload to bind",
                        .{case_syn.variant_name.string},
                    );
                    return error.Reported;
                }
            } else {
                const resolved_payload_ty = payload_ty orelse {
                    try self.diags.add(
                        binding_name.location,
                        .semantic,
                        "choice variant '..{s}' has no payload to bind",
                        .{case_syn.variant_name.string},
                    );
                    return error.Reported;
                };

                const access = try self.allocator.create(sg.ChoicePayloadAccess);
                access.* = .{
                    .choice_value = choice_value.node,
                    .variant_index = variant_index,
                    .payload_type = resolved_payload_ty,
                };
                const access_node = try sg.makeSGNode(.{ .choice_payload_access = access }, binding_name.location, self.allocator);
                access_node.sem_type = resolved_payload_ty;

                const init_expr: typ.TypedExpr = switch (payload_binding.mode) {
                    .by_value => try self.ensureValuePositionAllowed(
                        .{ .node = access_node, .ty = resolved_payload_ty },
                        binding_name.location,
                        parent,
                    ),
                    .by_move => .{ .node = access_node, .ty = resolved_payload_ty },
                    .by_borrow => try typ.makeAddressablePointer(
                        access_node,
                        resolved_payload_ty,
                        .read_only,
                        binding_name.location,
                        self.allocator,
                        self.diags,
                    ),
                    .by_mut_borrow => try typ.makeAddressablePointer(
                        access_node,
                        resolved_payload_ty,
                        .read_write,
                        binding_name.location,
                        self.allocator,
                        self.diags,
                    ),
                };

                const bd = try self.allocator.create(sg.BindingDeclaration);
                bd.* = .{
                    .name = binding_name.string,
                    .location = binding_name.location,
                    .origin_file = binding_name.location.file,
                    .mutability = .constant,
                    .ty = init_expr.ty,
                    .initialization = init_expr.node,
                };

                try child.bindings.put(binding_name.string, bd);
                const decl_node = try sg.makeSGNode(.{ .binding_declaration = bd }, binding_name.location, self.allocator);
                try child.nodes.append(decl_node);
                try self.maybeScheduleAutoDeinit(bd, binding_name.location, &child);
            }
        } else if (payload_ty != null) {
            try self.diags.add(
                case_syn.variant_name.location,
                .semantic,
                "choice variant '..{s}' carries a payload and match must bind it explicitly; use '..{s} _' to ignore it",
                .{ case_syn.variant_name.string, case_syn.variant_name.string },
            );
            return error.Reported;
        }

        const body_cb = case_syn.body.content.code_block;
        for (body_cb.items) |st| {
            const te = try self.visitNode(st.*, &child);
            if (st.*.content == .function_call) {
                try child.nodes.append(te.node);
            }
        }

        var d_idx: usize = child.deferred.items.len;
        while (d_idx > 0) : (d_idx -= 1) {
            const group = child.deferred.items[d_idx - 1];
            for (group.nodes) |node| try child.nodes.append(node);
        }

        const slice = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);

        const cb = try self.allocator.create(sg.CodeBlock);
        cb.* = .{ .nodes = slice, .ret_val = null };
        return cb;
    }

    //──────────────────────────────────────────────────── ADDRESS OF
    fn handleAddressOf(
        self: *Semantizer,
        addr: syn.AddressOf,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        switch (addr.value.*.content) {
            .index_access => |ia| {
                const base = try self.visitNode(ia.value.*, s);
                if (base.ty != .array_type and base.node.content != .list_literal) {
                    return self.handleBorrowedIndexAccess(ia, addr.mutability, s);
                }
            },
            else => {},
        }

        const te = try self.visitNode(addr.value.*, s);
        return switch (addr.mutability) {
            .read_only => try typ.ensureReadOnlyPointer(addr.value, te, self.allocator, self.diags),
            .read_write => try typ.ensureMutablePointer(addr.value, te, s, self.allocator, self.diags),
        };
    }

    fn handleDefer(
        self: *Semantizer,
        expr: *syn.STNode,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;
        const te = try self.visitNode(expr.*, s);

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
        name: syn.Name,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const binding = s.lookupBinding(name.string) orelse {
            try self.diags.add(
                name.location,
                .semantic,
                "cannot keep unknown binding '{s}'",
                .{name.string},
            );
            return error.Reported;
        };

        if (!self.cancelAutoDeinitForBinding(binding, s)) {
            if (self.defer_unknown_top_level and self.current_top_node != null) {
                return error.SymbolNotFound;
            }
            try self.diags.add(
                name.location,
                .semantic,
                "cannot keep binding '{s}': no automatic deinit is scheduled",
                .{name.string},
            );
            return error.Reported;
        }

        const use_node = try sg.makeSGNode(.{ .binding_use = binding }, name.location, self.allocator);
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
        inner: *syn.STNode,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const te = try self.visitNode(inner.*, s);

        if (te.ty != .pointer_type) {
            const ty_str = try self.formatTypeText(te.ty, s);
            defer ty_str.deinit();
            try self.diags.add(
                inner.*.location,
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

        const n = try sg.makeSGNode(.{ .dereference = der_ptr.* }, undefined, self.allocator);
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
        abstract_constraints: []const ?[]const u8,
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
        pa: syn.PointerAssignment,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var rhs = try self.visitNode(pa.value.*, s);

        if (pa.target.*.content == .struct_field_access) {
            const sa = pa.target.*.content.struct_field_access;
            const target_te = try self.visitNode(pa.target.*, s);
            if (target_te.node.content != .struct_field_access)
                return error.InvalidType;
            const sf = target_te.node.content.struct_field_access;

            const base = try self.visitNode(sa.struct_value.*, s);
            const ptr_self = try typ.ensureMutablePointer(sa.struct_value, base, s, self.allocator, self.diags);

            const ptr_info = ptr_self.ty.pointer_type.*;
            if (ptr_info.child.* != .struct_type) {
                const desc = try self.formatTypeText(ptr_self.ty, s);
                defer desc.deinit();
                try self.diags.add(
                    sa.struct_value.location,
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
            rhs = try typ.coerceExprToType(declared_field_ty, rhs, pa.value, s, self.allocator, self.diags);
            try self.recordAbstractFieldStorageType(struct_type, field_index, rhs.ty, pa.value.*.location, s);
            const field_ty = typ.effectiveStructFieldType(struct_type.fields[field_index]);

            if (!typ.typesExactlyEqual(field_ty, rhs.ty)) {
                const pair = try self.formatTypePairText(field_ty, rhs.ty, s);
                defer pair.deinit();
                try self.diags.add(
                    pa.value.*.location,
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

        if (pa.target.*.content != .dereference) return error.InvalidType;

        const tgt_te = try self.visitNode(pa.target.*, s);
        const deref_sg = tgt_te.node.content.dereference;

        rhs = try typ.coerceExprToType(deref_sg.ty, rhs, pa.value, s, self.allocator, self.diags);

        if (deref_sg.pointer_type.*.mutability != .read_write) {
            const ptr_ty: sg.Type = .{ .pointer_type = deref_sg.pointer_type };
            const ptr_str = try self.formatTypeText(ptr_ty, s);
            defer ptr_str.deinit();
            try self.diags.add(
                pa.target.*.location,
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
                pa.value.*.location,
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

    fn extractTypeArgument(self: *Semantizer, call: syn.FunctionCall, s: *Scope) SemErr!sg.Type {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects .type argument (example: .type = Int32)",
                .{},
            );
            return error.Reported;
        }

        const svl = arg_node.content.struct_value_literal;
        if (svl.fields.len != 1) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects a single '.type' argument",
                .{},
            );
            return error.Reported;
        }

        const field = svl.fields[0];
        if (!std.mem.eql(u8, field.name.string, "type")) {
            try self.diags.add(
                field.value.*.location,
                .semantic,
                "expected '.type' argument",
                .{},
            );
            return error.Reported;
        }

        return self.resolveTypeExpression(field.value, s);
    }

    fn extractNamedTypeArgument(
        self: *Semantizer,
        call: syn.FunctionCall,
        arg_name: []const u8,
        s: *Scope,
    ) SemErr!sg.Type {
        const stargs = call.type_arguments_struct orelse {
            try self.diags.add(
                call.callee_loc,
                .semantic,
                "cast expects named type arguments like cast#(.to: UIntNative)(.value = ...)",
                .{},
            );
            return error.Reported;
        };

        for (stargs.fields) |field| {
            if (!std.mem.eql(u8, field.name.string, arg_name)) continue;
            const field_ty = field.type orelse {
                try self.diags.add(
                    field.name.location,
                    .semantic,
                    "type argument '.{s}' must specify a type",
                    .{arg_name},
                );
                return error.Reported;
            };
            return self.resolveType(field_ty, s);
        }

        try self.diags.add(
            call.callee_loc,
            .semantic,
            "cast expects type argument '.{s}'",
            .{arg_name},
        );
        return error.Reported;
    }

    fn extractValueArgument(
        self: *Semantizer,
        call: syn.FunctionCall,
        arg_name: []const u8,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects '.{s}' argument",
                .{arg_name},
            );
            return error.Reported;
        }

        const svl = arg_node.content.struct_value_literal;
        if (svl.fields.len == 1 and svl.positional_prefix_count == 1) {
            return self.visitNode(svl.fields[0].value.*, s);
        }

        if (svl.fields.len != 1 or !std.mem.eql(u8, svl.fields[0].name.string, arg_name)) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects a single '.{s}' argument",
                .{arg_name},
            );
            return error.Reported;
        }

        return self.visitNode(svl.fields[0].value.*, s);
    }

    fn extractValueArgumentNode(self: *Semantizer, call: syn.FunctionCall, arg_name: []const u8) SemErr!*const syn.STNode {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects '.{s}' argument",
                .{arg_name},
            );
            return error.Reported;
        }
        const svl = arg_node.content.struct_value_literal;
        if (svl.fields.len == 1 and svl.positional_prefix_count == 1) {
            return svl.fields[0].value;
        }
        if (svl.fields.len != 1 or !std.mem.eql(u8, svl.fields[0].name.string, arg_name)) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "builtin expects a single '.{s}' argument",
                .{arg_name},
            );
            return error.Reported;
        }
        return svl.fields[0].value;
    }

    fn handleCastBuiltin(self: *Semantizer, call: syn.FunctionCall, s: *Scope) SemErr!typ.TypedExpr {
        const value_te = try self.extractValueArgument(call, "value", s);
        const target_ty = try self.extractNamedTypeArgument(call, "to", s);

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
                call.input.*.location,
                .semantic,
                "unsupported explicit cast from '{s}' to '{s}'",
                .{ pair.actual.bytes, pair.expected.bytes },
            );
            return error.Reported;
        }

        const cast_node = try sg.makeSGNode(.{ .explicit_cast = .{
            .value = value_te.node,
            .target_type = target_ty,
        } }, call.input.*.location, self.allocator);
        try s.nodes.append(cast_node);
        return .{ .node = cast_node, .ty = target_ty };
    }

    fn resolveTypeExpression(self: *Semantizer, node: *const syn.STNode, s: *Scope) SemErr!sg.Type {
        return switch (node.content) {
            .identifier => |name| blk: {
                const ty_ast = syn.Type{ .type_name = syn.Name{ .string = name, .location = node.location } };
                break :blk self.resolveType(ty_ast, s) catch {
                    try self.diags.add(
                        node.location,
                        .semantic,
                        "unknown type '{s}'",
                        .{name},
                    );
                    return error.Reported;
                };
            },
            .struct_type_literal => |lit| blk: {
                const struct_ty = try self.structTypeFromLiteral(lit, s);
                break :blk .{ .struct_type = struct_ty };
            },
            .function_call => |fc| blk: {
                if (std.mem.eql(u8, fc.callee, "type_of")) {
                    break :blk try self.typeOfCallResultType(fc, s);
                }
                try self.diags.add(
                    node.location,
                    .semantic,
                    "unsupported expression in '.type' argument",
                    .{},
                );
                return error.Reported;
            },
            else => blk_invalid: {
                try self.diags.add(
                    node.location,
                    .semantic,
                    "expected type expression",
                    .{},
                );
                break :blk_invalid error.Reported;
            },
        };
    }

    fn typeOfCallResultType(self: *Semantizer, call: syn.FunctionCall, s: *Scope) SemErr!sg.Type {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "type_of expects '.value' argument",
                .{},
            );
            return error.Reported;
        }

        const svl = arg_node.content.struct_value_literal;
        if (svl.fields.len != 1 or !std.mem.eql(u8, svl.fields[0].name.string, "value")) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "type_of expects a single '.value' argument",
                .{},
            );
            return error.Reported;
        }

        const value_expr = svl.fields[0].value;
        const tv = try self.visitNode(value_expr.*, s);
        return tv.ty;
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

    fn resolveType(self: *Semantizer, t: syn.Type, s: *Scope) SemErr!sg.Type {
        return switch (t) {
            .type_name => |tn| blk: {
                const id = tn.string;
                if (std.mem.indexOfScalar(u8, id, '.')) |dot_idx| {
                    const module_name = id[0..dot_idx];
                    const type_name = id[dot_idx + 1 ..];
                    const module_dir = s.lookupModuleAlias(module_name) orelse break :blk error.UnknownType;
                    if (s.lookupTypeInModule(module_dir, type_name)) |td| {
                        if (!(try self.typeIsVisible(td, tn.location.file))) {
                            try self.addPrivateMemberDiag(tn.location, "type", type_name);
                            return error.Reported;
                        }
                        break :blk td.ty;
                    }
                    break :blk error.UnknownType;
                }
                if (typ.builtinFromName(id)) |bt|
                    break :blk .{ .builtin = bt };
                if (s.lookupAbstractInfo(id)) |_| {
                    if (s.lookupAbstractDefault(id)) |def_entry|
                        break :blk def_entry.ty;
                    break :blk error.AbstractNeedsDefault;
                }
                if (s.lookupType(id)) |td| {
                    if (!typeDeclIsReady(td)) break :blk error.UnknownType;
                    if (!(try self.typeIsVisible(td, tn.location.file))) {
                        try self.addPrivateMemberDiag(tn.location, "type", id);
                        return error.Reported;
                    }
                    break :blk td.ty;
                }
                break :blk error.UnknownType;
            },
            .generic_type_instantiation => |g| blk_g: {
                const base_name = g.base_name.string;
                if (try self.resolveSpecialGenericType(g, s, null)) |special_ty| break :blk_g special_ty;
                if (s.lookupAbstractInfo(base_name)) |info| {
                    for (info.param_names) |pname| {
                        var found = false;
                        for (g.args.fields) |fld| {
                            if (std.mem.eql(u8, fld.name.string, pname)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) break :blk_g error.UnknownType;
                    }
                    if (s.lookupAbstractDefault(base_name)) |def_entry|
                        break :blk_g def_entry.ty;
                    break :blk_g error.AbstractNeedsDefault;
                }

                const ty = self.instantiateGenericTypeNamed(base_name, g.args, s, null) catch |err| switch (err) {
                    error.SymbolNotFound => break :blk_g error.UnknownType,
                    else => return err,
                };
                break :blk_g ty;
            },
            .inferred_errable => error.InvalidType,
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
            .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteral(ct, s) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveType(ptr_info.child.*, s);
                const child = try self.allocator.create(sg.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
            .array_type => |arr_info| blk_arr: {
                const elem_ty = try self.resolveType(arr_info.element.*, s);
                break :blk_arr try self.makeArrayType(arr_info.length, elem_ty);
            },
        };
    }

    fn resolveTypePreservingAbstracts(self: *Semantizer, t: syn.Type, s: *Scope) SemErr!sg.Type {
        return switch (t) {
            .type_name => |tn| blk: {
                const id = tn.string;
                if (std.mem.indexOfScalar(u8, id, '.')) |dot_idx| {
                    const module_name = id[0..dot_idx];
                    const type_name = id[dot_idx + 1 ..];
                    const module_dir = s.lookupModuleAlias(module_name) orelse break :blk error.UnknownType;
                    if (s.lookupTypeInModule(module_dir, type_name)) |td| {
                        if (!(try self.typeIsVisible(td, tn.location.file))) {
                            try self.addPrivateMemberDiag(tn.location, "type", type_name);
                            return error.Reported;
                        }
                        break :blk td.ty;
                    }
                    break :blk error.UnknownType;
                }
                if (typ.builtinFromName(id)) |bt|
                    break :blk .{ .builtin = bt };
                if (s.lookupAbstractInfo(id)) |_| {
                    if (s.lookupType(id)) |td| break :blk td.ty;
                    break :blk error.UnknownType;
                }
                if (s.lookupType(id)) |td| {
                    if (!typeDeclIsReady(td)) break :blk error.UnknownType;
                    if (!(try self.typeIsVisible(td, tn.location.file))) {
                        try self.addPrivateMemberDiag(tn.location, "type", id);
                        return error.Reported;
                    }
                    break :blk td.ty;
                }
                break :blk error.UnknownType;
            },
            .generic_type_instantiation => |g| blk_g: {
                const base_name = g.base_name.string;
                if (try self.resolveSpecialGenericType(g, s, null)) |special_ty| break :blk_g special_ty;
                if (s.lookupAbstractInfo(base_name)) |_| {
                    if (s.lookupType(base_name)) |td| break :blk_g td.ty;
                    break :blk_g error.UnknownType;
                }

                const ty = self.instantiateGenericTypeNamed(base_name, g.args, s, null) catch |err| switch (err) {
                    error.SymbolNotFound => break :blk_g error.UnknownType,
                    else => return err,
                };
                break :blk_g ty;
            },
            .inferred_errable => error.InvalidType,
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
            .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteral(ct, s) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveTypePreservingAbstracts(ptr_info.child.*, s);
                const child = try self.allocator.create(sg.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
            .array_type => |arr_info| blk_arr: {
                const elem_ty = try self.resolveTypePreservingAbstracts(arr_info.element.*, s);
                break :blk_arr try self.makeArrayType(arr_info.length, elem_ty);
            },
        };
    }

    fn resolveTypeForSignaturePredeclaration(self: *Semantizer, t: syn.Type, s: *Scope) SemErr!sg.Type {
        return switch (t) {
            .type_name => |tn| blk: {
                const id = tn.string;
                if (std.mem.indexOfScalar(u8, id, '.')) |dot_idx| {
                    const module_name = id[0..dot_idx];
                    const type_name = id[dot_idx + 1 ..];
                    const module_dir = s.lookupModuleAlias(module_name) orelse break :blk error.UnknownType;
                    if (s.lookupTypeInModule(module_dir, type_name)) |td| {
                        if (!(try self.typeIsVisible(td, tn.location.file))) {
                            try self.addPrivateMemberDiag(tn.location, "type", type_name);
                            return error.Reported;
                        }
                        break :blk td.ty;
                    }
                    break :blk error.UnknownType;
                }
                if (typ.builtinFromName(id)) |bt| break :blk .{ .builtin = bt };
                if (s.lookupAbstractInfo(id)) |_| {
                    if (s.lookupType(id)) |td| break :blk td.ty;
                    break :blk error.UnknownType;
                }
                if (s.lookupType(id)) |td| {
                    if (!(try self.typeIsVisible(td, tn.location.file))) {
                        try self.addPrivateMemberDiag(tn.location, "type", id);
                        return error.Reported;
                    }
                    break :blk td.ty;
                }
                break :blk error.UnknownType;
            },
            .generic_type_instantiation => |g| blk_g: {
                const base_name = g.base_name.string;
                if (try self.resolveSpecialGenericType(g, s, null)) |special_ty| break :blk_g special_ty;
                if (s.lookupAbstractInfo(base_name)) |_| {
                    if (s.lookupType(base_name)) |td| break :blk_g td.ty;
                    break :blk_g error.UnknownType;
                }

                const ty = self.instantiateGenericTypeNamed(base_name, g.args, s, null) catch |err| switch (err) {
                    error.SymbolNotFound => break :blk_g error.UnknownType,
                    else => return err,
                };
                break :blk_g ty;
            },
            .inferred_errable => error.InvalidType,
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
            .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteral(ct, s) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveTypeForSignaturePredeclaration(ptr_info.child.*, s);
                const child = try self.allocator.create(sg.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
            .array_type => |arr_info| blk_arr: {
                const elem_ty = try self.resolveTypeForSignaturePredeclaration(arr_info.element.*, s);
                break :blk_arr try self.makeArrayType(arr_info.length, elem_ty);
            },
        };
    }

    fn resolveTypeWithSubst(
        self: *Semantizer,
        t: syn.Type,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        return switch (t) {
            .type_name => |tn| blk: {
                const id = tn.string;
                if (subst.types.get(id)) |mapped| break :blk mapped;
                break :blk try self.resolveType(t, s);
            },
            .generic_type_instantiation => |g| blk_g: {
                const base_name = g.base_name.string;
                if (try self.resolveSpecialGenericType(g, s, subst)) |special_ty| break :blk_g special_ty;
                if (s.lookupAbstractInfo(base_name)) |info| {
                    for (info.param_names) |pname| {
                        var found = false;
                        for (g.args.fields) |fld| {
                            if (std.mem.eql(u8, fld.name.string, pname)) {
                                found = true;
                                break;
                            }
                        }
                        if (!found) break :blk_g error.UnknownType;
                    }
                    if (s.lookupAbstractDefault(base_name)) |def_entry|
                        break :blk_g def_entry.ty;
                    break :blk_g error.AbstractNeedsDefault;
                }

                const ty = self.instantiateGenericTypeNamed(base_name, g.args, s, subst) catch |err| switch (err) {
                    error.SymbolNotFound => break :blk_g error.UnknownType,
                    else => return err,
                };
                break :blk_g ty;
            },
            .inferred_errable => error.InvalidType,
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteralWithSubst(st, s, subst) },
            .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteralWithSubst(ct, s, subst) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveTypeWithSubst(ptr_info.child.*, s, subst);
                const child = try self.allocator.create(sg.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
            .array_type => |arr_info| blk_arr: {
                const elem_ty = try self.resolveTypeWithSubst(arr_info.element.*, s, subst);
                break :blk_arr try self.makeArrayType(arr_info.length, elem_ty);
            },
        };
    }

    fn resolveTypeWithSubstPreservingAbstracts(
        self: *Semantizer,
        t: syn.Type,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!sg.Type {
        return switch (t) {
            .type_name => |tn| blk: {
                const id = tn.string;
                if (subst.types.get(id)) |mapped| break :blk mapped;
                break :blk try self.resolveTypePreservingAbstracts(t, s);
            },
            .generic_type_instantiation => |g| blk_g: {
                const base_name = g.base_name.string;
                if (try self.resolveSpecialGenericType(g, s, subst)) |special_ty| break :blk_g special_ty;
                if (s.lookupAbstractInfo(base_name)) |_| {
                    if (s.lookupType(base_name)) |td| break :blk_g td.ty;
                    break :blk_g error.UnknownType;
                }

                const ty = self.instantiateGenericTypeNamed(base_name, g.args, s, subst) catch |err| switch (err) {
                    error.SymbolNotFound => break :blk_g error.UnknownType,
                    else => return err,
                };
                break :blk_g ty;
            },
            .inferred_errable => error.InvalidType,
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteralWithSubst(st, s, subst) },
            .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteralWithSubst(ct, s, subst) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveTypeWithSubstPreservingAbstracts(ptr_info.child.*, s, subst);
                const child = try self.allocator.create(sg.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
            .array_type => |arr_info| blk_arr: {
                const elem_ty = try self.resolveTypeWithSubstPreservingAbstracts(arr_info.element.*, s, subst);
                break :blk_arr try self.makeArrayType(arr_info.length, elem_ty);
            },
        };
    }

    //──────────────────────────────────────────────────── HELPERS
    fn handleBuiltinTypeInfo(
        self: *Semantizer,
        kind: typ.BuiltinTypeInfoKind,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const target_ty = try self.extractTypeArgument(call, s);

        const value = switch (kind) {
            .size => typ.computeTypeSize(target_ty),
            .alignment => typ.computeTypeAlignment(target_ty),
        };

        const loc = call.input.*.location;
        if (value > std.math.maxInt(i64)) return error.InvalidType;
        return try typ.makeIntLiteral(self.allocator, loc, @intCast(value), .{ .builtin = .UIntNative });
    }

    fn handleLengthBuiltin(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const arg_node = call.input.*;
        const arg_loc = arg_node.location;

        var value_te: typ.TypedExpr = undefined;
        if (arg_node.content == .struct_value_literal) {
            const sv = arg_node.content.struct_value_literal;
            if (sv.fields.len == 1 and sv.positional_prefix_count == 1) {
                value_te = try self.visitNode(sv.fields[0].value.*, s);
            } else if (sv.fields.len != 1 or !std.mem.eql(u8, sv.fields[0].name.string, "value")) {
                return error.SymbolNotFound;
            } else {
                value_te = try self.visitNode(sv.fields[0].value.*, s);
            }
        } else {
            value_te = try self.visitNode(arg_node, s);
        }

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

    fn handleTypeOf(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "type_of expects '.value' argument",
                .{},
            );
            return error.Reported;
        }

        const svl = arg_node.content.struct_value_literal;
        if (svl.fields.len == 1 and svl.positional_prefix_count == 1) {
            const tv = try self.visitNode(svl.fields[0].value.*, s);
            const loc = call.input.*.location;
            return try typ.makeTypeLiteral(self.allocator, loc, tv.ty);
        }

        if (svl.fields.len != 1 or !std.mem.eql(u8, svl.fields[0].name.string, "value")) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "type_of expects a single '.value' argument",
                .{},
            );
            return error.Reported;
        }

        const tv = try self.visitNode(svl.fields[0].value.*, s);
        const loc = call.input.*.location;
        return try typ.makeTypeLiteral(self.allocator, loc, tv.ty);
    }

    fn handleIsBuiltin(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const arg_node = call.input.*;
        if (arg_node.content != .struct_value_literal) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const svl = arg_node.content.struct_value_literal;
        var value_field: ?syn.StructValueLiteralField = null;
        var variant_field: ?syn.StructValueLiteralField = null;

        for (svl.fields, 0..) |field, idx| {
            if (idx < svl.positional_prefix_count) {
                if (idx == 0) {
                    if (value_field != null) {
                        try self.addDuplicateIsBuiltinArgument(arg_node.location);
                        return error.Reported;
                    }
                    value_field = field;
                } else if (idx == 1) {
                    if (variant_field != null) {
                        try self.addDuplicateIsBuiltinArgument(arg_node.location);
                        return error.Reported;
                    }
                    variant_field = field;
                } else {
                    try self.diags.add(
                        field.name.location,
                        .semantic,
                        "is only accepts two positional arguments: value and variant",
                        .{},
                    );
                    return error.Reported;
                }
            } else if (std.mem.eql(u8, field.name.string, "value")) {
                if (value_field != null) {
                    try self.addDuplicateIsBuiltinArgument(field.name.location);
                    return error.Reported;
                }
                value_field = field;
            } else if (std.mem.eql(u8, field.name.string, "variant")) {
                if (variant_field != null) {
                    try self.addDuplicateIsBuiltinArgument(field.name.location);
                    return error.Reported;
                }
                variant_field = field;
            } else {
                try self.diags.add(
                    field.name.location,
                    .semantic,
                    "is only accepts '.value' and '.variant' arguments",
                    .{},
                );
                return error.Reported;
            }
        }

        if (value_field == null or variant_field == null) {
            try self.diags.add(
                arg_node.location,
                .semantic,
                "is expects '.value' and '.variant' arguments",
                .{},
            );
            return error.Reported;
        }

        const value_te = try self.visitNode(value_field.?.value.*, s);
        if (value_te.ty != .choice_type) {
            const desc = try self.formatTypeText(value_te.ty, s);
            defer desc.deinit();
            try self.diags.add(
                value_field.?.value.location,
                .semantic,
                "is expects '.value' to be a choice, found '{s}'",
                .{desc.bytes},
            );
            return error.Reported;
        }

        const variant_te = blk_variant: {
            const variant_node = variant_field.?.value.*;
            if (variant_node.content == .choice_literal) {
                const raw_variant = variant_node.content.choice_literal;
                if (raw_variant.payload == null) {
                    const choice_ty = value_te.ty.choice_type;
                    for (choice_ty.variants, 0..) |variant, idx| {
                        if (!std.mem.eql(u8, variant.name, raw_variant.name.string)) continue;

                        const typed = try self.allocator.create(sg.ChoiceLiteral);
                        typed.* = .{
                            .variant_name = raw_variant.name.string,
                            .choice_type = choice_ty,
                            .variant_index = @intCast(idx),
                            .payload = null,
                        };
                        const typed_node = try sg.makeSGNode(.{ .choice_literal = typed }, variant_node.location, self.allocator);
                        typed_node.sem_type = value_te.ty;
                        break :blk_variant typ.TypedExpr{ .node = typed_node, .ty = value_te.ty };
                    }

                    const choice_text = try self.formatTypeText(value_te.ty, s);
                    defer choice_text.deinit();
                    try self.diags.add(
                        variant_node.location,
                        .semantic,
                        "choice type '{s}' has no variant '..{s}'",
                        .{ choice_text.bytes, raw_variant.name.string },
                    );
                    return error.Reported;
                }
            }

            var coerced = try self.visitNode(variant_node, s);
            coerced = try typ.coerceExprToType(value_te.ty, coerced, variant_field.?.value, s, self.allocator, self.diags);
            break :blk_variant coerced;
        };

        if (!typ.typesExactlyEqual(value_te.ty, variant_te.ty)) {
            try self.diags.add(
                variant_field.?.value.location,
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

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, arg_node.location, self.allocator);
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

    // ─────────────────────────────────────────────────── Helpers reintento
    fn pushTopLevelForRetry(self: *Semantizer) !void {
        if (!self.defer_unknown_top_level) return;
        if (self.current_top_node) |ptr| {
            self.retry_enqueue_attempts += 1;
            for (self.pending_next.items) |pending| {
                if (pending == ptr) return;
            }
            try self.pending_next.append(ptr);
            self.retry_enqueue_unique += 1;
            switch (ptr.content) {
                .function_declaration, .test_declaration => self.retry_function_nodes += 1,
                .type_declaration => self.retry_type_nodes += 1,
                .symbol_declaration => self.retry_symbol_nodes += 1,
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
