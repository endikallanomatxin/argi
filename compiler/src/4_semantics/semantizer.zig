const std = @import("std");
const tok = @import("../2_tokens/token.zig");
const syn = @import("../3_syntax/syntax_tree.zig");
const sg = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("../1_base/diagnostic.zig");
const source_files = @import("../1_base/source_files.zig");

const typ = @import("types.zig");
const abs = @import("abstracts.zig");
const gen = @import("generics.zig");

const Scope = @import("scope.zig").Scope;
const SemErr = @import("errors.zig").SemErr;

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
    name: []const u8,
    mode: CallAccessMode,
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
    allocator: *const std.mem.Allocator,
    st_nodes: []const *syn.STNode, // entrada
    root_list: std.array_list.Managed(*sg.SGNode), // buffer mut
    root_nodes: []const *sg.SGNode = &.{}, // slice final
    diags: *diagnostic.Diagnostics,

    // ── Reintentos top-level
    pending_now: std.array_list.Managed(*const syn.STNode),
    pending_next: std.array_list.Managed(*const syn.STNode),
    defer_unknown_top_level: bool = false,
    current_top_node: ?*const syn.STNode = null,
    max_retry_rounds: u32 = 8,
    synthetic_name_counter: u32 = 0,

    pub fn init(
        alloc: *const std.mem.Allocator,
        st: []const *syn.STNode,
        diags: *diagnostic.Diagnostics,
    ) Semantizer {
        return .{
            .allocator = alloc,
            .st_nodes = st,
            .root_list = std.array_list.Managed(*sg.SGNode).init(alloc.*),
            .diags = diags,
            .pending_now = std.array_list.Managed(*const syn.STNode).init(alloc.*),
            .pending_next = std.array_list.Managed(*const syn.STNode).init(alloc.*),
        };
    }

    pub fn analyze(self: *Semantizer) SemErr![]const *sg.SGNode {
        var global = try Scope.init(self.allocator, null, null);

        // 1) Pasada inicial: difiere los UnknownType top-level
        self.defer_unknown_top_level = true;
        for (self.st_nodes) |n| {
            self.current_top_node = n;
            _ = self.visitNode(n.*, &global) catch {};
        }
        self.current_top_node = null;

        // 2) Rondas de reintento: solo lo pendiente
        var round: u32 = 0;
        while (self.pending_next.items.len > 0 and round < self.max_retry_rounds) {
            // swap pending_next -> pending_now
            const tmp = self.pending_now;
            self.pending_now = self.pending_next;
            self.pending_next = tmp;
            self.pending_next.items.len = 0;

            var progressed = false;
            for (self.pending_now.items) |pn| {
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

        // 3) Último pase: ya NO diferir => emitir diags de lo que quede
        self.defer_unknown_top_level = false;
        if (self.pending_next.items.len > 0) {
            for (self.pending_next.items) |pn| {
                self.current_top_node = pn;
                _ = self.visitNode(pn.*, &global) catch {};
            }
            self.current_top_node = null;
            self.pending_next.items.len = 0;
        }

        // Final conformance verification for abstracts (top-level scope)
        try abs.verifyAbstracts(&global, self.allocator, self.diags);

        self.root_nodes = try self.root_list.toOwnedSlice();
        self.root_list.deinit();
        self.clearDeferred(&global);
        return self.root_nodes;
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
            .address_of => |addr| syntaxNodeContainsPipePlaceholder(addr.value),
            .binary_operation => |bo| syntaxNodeContainsPipePlaceholder(bo.left) or syntaxNodeContainsPipePlaceholder(bo.right),
            .comparison => |cmp| syntaxNodeContainsPipePlaceholder(cmp.left) or syntaxNodeContainsPipePlaceholder(cmp.right),
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
                fty = f.ty;
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
                .{ desc.bytes, variant_name.string },
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

        try self.diags.add(
            loc,
            .semantic,
            "choice has no variant '..{s}'",
            .{variant_name.string},
        );
        return error.Reported;
    }

    fn handlePipeAddressOf(
        self: *Semantizer,
        inner: typ.TypedExpr,
        mutability: syn.PointerMutability,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (inner.node.content != .binding_use) {
            try self.diags.add(
                loc,
                .semantic,
                "cannot take the address of this expression; only named variables are addressable",
                .{},
            );
            return error.Reported;
        }

        const binding = inner.node.content.binding_use;
        if (mutability == .read_write and binding.mutability != .variable) {
            try self.diags.add(
                loc,
                .semantic,
                "binding '{s}' is immutable; declare it with '::' or take '&{s}' instead of '$&{s}'",
                .{ binding.name, binding.name, binding.name },
            );
            return error.Reported;
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

            .abstract_canbe => |rel| self.handleAbstractCanBe(rel, s, n.location) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in abstract canbe for '{s}': {s}",
                    .{ rel.name, @errorName(err) },
                );
                break :blk err;
            },

            .abstract_defaultsto => |rel| self.handleAbstractDefault(rel, s, n.location) catch |err| blk: {
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

            .function_declaration => |d| self.handleFuncDecl(d, s, n.location) catch |err| blk: {
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

            .literal => |l| self.handleLiteral(l) catch |err| blk: {
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
                    "choice type literals are only valid inside type declarations",
                    .{},
                );
                break :blk error.Reported;
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

            .binary_operation => |bo| self.handleBinOp(bo, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in binary operation '{any}': {s}",
                    .{ bo.operator, @errorName(err) },
                );
                break :blk err;
            },

            .comparison => |c| self.handleComparison(c, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in comparison '{any}': {s}",
                    .{ c.operator, @errorName(err) },
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

            .if_statement => |ifs| self.handleIf(ifs, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in if statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .for_statement => |f| self.handleFor(f, s, n.location) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in for statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .while_statement => |w| self.handleWhile(w, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in while statement: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .match_statement => |m| self.handleMatch(m, s) catch |err| blk: {
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

    fn typeIsVisible(self: *Semantizer, td: *const sg.TypeDeclaration, requester_file: []const u8) !bool {
        if (!isPrivateName(td.name)) return true;
        return try self.isSameModule(requester_file, td.origin_file);
    }

    fn functionIsVisible(self: *Semantizer, fd: *const sg.FunctionDeclaration, requester_file: []const u8) !bool {
        if (!isPrivateName(fd.name)) return true;
        return try self.isSameModule(requester_file, fd.location.file);
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
        // Register abstract as a nominal semantic type.
        if (s.types.contains(ad.name.string)) return error.SymbolAlreadyDefined;

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

        const info = try self.allocator.create(abs.AbstractInfo);
        info.* = .{
            .name = ad.name.string,
            .requirements = try reqs.toOwnedSlice(),
            .param_names = generic_params,
        };
        reqs.deinit();

        const abs_ty = try self.allocator.create(sg.AbstractType);
        abs_ty.* = .{ .name = ad.name.string };
        const td = try self.allocator.create(sg.TypeDeclaration);
        td.* = .{ .name = ad.name.string, .origin_file = ad.name.location.file, .ty = .{ .abstract_type = abs_ty } };
        try s.types.put(ad.name.string, td);
        try s.abstracts.put(ad.name.string, info);

        const n = try sg.makeSGNode(.{ .type_declaration = td }, undefined, self.allocator);
        try s.nodes.append(n);
        if (s.parent == null) try self.root_list.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    // For now, relations are recorded as no-ops to accept syntax without enforcing.
    fn handleAbstractCanBe(
        self: *Semantizer,
        rel: syn.AbstractCanBe,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (rel.generic_params_struct != null or rel.generic_params.len != 0 or rel.ty == .generic_type_instantiation) {
            var params_buf = std.array_list.Managed(gen.GenericParam).init(self.allocator.*);
            defer params_buf.deinit();

            if (rel.generic_params_struct != null or rel.generic_params.len != 0) {
                const params_struct = try self.genericParamsStructOrNames(rel.generic_params_struct, rel.generic_params, loc);
                const explicit_params = try self.genericParamDefsFromSyntax(params_struct, s);
                for (explicit_params) |param| try params_buf.append(param);
            }

            try self.collectHiddenCanBeParamsFromType(rel.ty, &params_buf, s);
            const params = try params_buf.toOwnedSlice();
            try s.appendAbstractImplTemplate(rel.name, .{
                .params = params,
                .ty = rel.ty,
                .location = loc,
            });

            const n = try self.makeNoopNode(loc);
            try s.nodes.append(n);
            return .{ .node = n, .ty = .{ .builtin = .Any } };
        }

        const concrete_ty = try self.resolveType(rel.ty, s);

        // Defer conformance checks until call sites or a validation pass.

        try s.appendAbstractImpl(rel.name, .{ .ty = concrete_ty, .location = loc });

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
    fn handleLiteral(self: *Semantizer, lit: tok.Literal) SemErr!typ.TypedExpr {
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
            .string_literal => |s| {
                const char_ty: sg.Type = .{ .builtin = .Char };
                const child = try self.allocator.create(sg.Type);
                child.* = char_ty;

                const sem_ptr = try self.allocator.create(sg.PointerType);
                sem_ptr.* = .{ .mutability = .read_only, .child = child };

                ty = .{ .pointer_type = sem_ptr };
                value_literal = .{ .string_literal = s };
            },
            .bool_literal => |b| {
                ty = .{ .builtin = .Bool };
                value_literal = .{ .bool_literal = b };
            },
        }

        const ptr = try self.allocator.create(sg.ValueLiteral);
        ptr.* = value_literal;
        const n = try sg.makeSGNode(.{ .value_literal = ptr.* }, undefined, self.allocator);
        return .{ .node = n, .ty = ty };
    }

    fn handleChoiceLiteral(self: *Semantizer, lit: syn.ChoiceLiteral, s: *Scope) SemErr!typ.TypedExpr {
        var payload: ?*const sg.SGNode = null;
        if (lit.payload) |payload_node| {
            var payload_te = try self.visitNode(payload_node.*, s);
            payload_te = try typ.ensureValuePositionAllowed(payload_te, payload_node.location, s, self.allocator, self.diags);
            payload_te.node.sem_type = payload_te.ty;
            payload = payload_te.node;
        }

        const node = try self.allocator.create(sg.ChoiceLiteral);
        node.* = .{
            .variant_name = lit.name.string,
            .choice_type = undefined,
            .variant_index = 0,
            .payload = payload,
        };
        const n = try sg.makeSGNode(.{ .choice_literal = node }, lit.name.location, self.allocator);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
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
                const n = try sg.makeSGNode(.{ .binding_use = b }, undefined, self.allocator);
                return .{ .node = n, .ty = b.ty };
            }
            try self.diags.add(
                loc,
                .semantic,
                "binding '{s}' was moved and cannot be used again before reinitialization (moved at {s}:{d}:{d})",
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

        const b = s.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(b, loc.file))) {
            try self.addPrivateMemberDiag(loc, "value", name);
            return error.Reported;
        }
        const n = try sg.makeSGNode(.{ .binding_use = b }, undefined, self.allocator);
        return .{ .node = n, .ty = b.ty };
    }

    fn handleMove(
        self: *Semantizer,
        inner: *const syn.STNode,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (inner.content != .identifier) {
            try self.diags.add(
                loc,
                .semantic,
                "move currently only supports named bindings",
                .{},
            );
            return error.Reported;
        }

        const name = inner.content.identifier;
        const binding = s.lookupBinding(name) orelse return error.SymbolNotFound;
        if (!(try self.bindingIsVisible(binding, loc.file))) {
            try self.addPrivateMemberDiag(loc, "value", name);
            return error.Reported;
        }
        try s.markBindingMoved(binding.name, loc);

        const binding_use = try sg.makeSGNode(.{ .binding_use = binding }, inner.location, self.allocator);
        const node = try sg.makeSGNode(.{ .move_value = binding_use }, loc, self.allocator);
        node.sem_type = binding.ty;
        return .{ .node = node, .ty = binding.ty };
    }

    //─────────────────────────────────────────────────────────  CODE BLOCK
    fn handleCodeBlock(
        self: *Semantizer,
        blk: syn.CodeBlock,
        parent: *Scope,
    ) SemErr!typ.TypedExpr {
        var child = try Scope.init(self.allocator, parent, null);

        for (blk.items) |st| {
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

        const n = try sg.makeSGNode(.{ .code_block = cb }, undefined, self.allocator);
        try parent.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── SYMBOL DECLARATION
    fn handleSymbolDecl(
        self: *Semantizer,
        d: syn.SymbolDeclaration,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!typ.TypedExpr {
        if (s.bindings.contains(d.name.string))
            return error.SymbolAlreadyDefined;
        if (s.lookupModuleAlias(d.name.string) != null)
            return error.SymbolAlreadyDefined;

        if (d.value) |v| {
            if (v.*.content == .import_statement) {
                const resolved = source_files.resolveImportDir(self.allocator, loc.file, v.*.content.import_statement.path) catch {
                    try self.diags.add(
                        v.*.location,
                        .semantic,
                        "failed to resolve import '{s}'",
                        .{v.*.content.import_statement.path},
                    );
                    return error.Reported;
                };
                try s.module_aliases.put(d.name.string, resolved);
                return try typ.makeTypeLiteral(self.allocator, loc, .{ .builtin = .Any });
            }
        }

        var init_node: ?*syn.STNode = null;
        var init_te_opt: ?typ.TypedExpr = null;
        if (d.value) |v| {
            init_node = v;
            init_te_opt = try self.visitNode(v.*, s);
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
            init_te_opt = try typ.ensureValuePositionAllowed(init_te, init_node.?.location, s, self.allocator, self.diags);
        }

        const bd = try self.allocator.create(sg.BindingDeclaration);
        bd.* = .{
            .name = d.name.string,
            .origin_file = loc.file,
            .mutability = d.mutability,
            .ty = ty,
            .initialization = null,
        };

        try s.bindings.put(d.name.string, bd);
        s.clearBindingMoved(d.name.string);
        const n = try sg.makeSGNode(.{ .binding_declaration = bd }, loc, self.allocator);
        try s.nodes.append(n);
        if (s.parent == null) try self.root_list.append(n);

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
            // Register as generic type template
            try s.appendGenericTypeTemplate(d.name.string, .{
                .name = d.name.string,
                .location = d.value.location,
                .params = try self.genericParamDefsFromSyntax(params_struct, s),
                .body = d.value,
            });
            // No concrete type emitted now
            const noop = try self.makeNoopNode(d.value.location);
            try s.nodes.append(noop);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        } else {
            return switch (d.value.*.content) {
                .struct_type_literal => |st_lit| blk_struct: {
                    var td: *sg.TypeDeclaration = undefined;
                    if (s.types.get(d.name.string)) |existing| {
                        td = existing;
                    } else {
                        const stub = try self.allocator.create(sg.StructType);
                        stub.* = .{ .fields = &.{} };
                        td = try self.allocator.create(sg.TypeDeclaration);
                        td.* = .{ .name = d.name.string, .origin_file = d.value.location.file, .ty = .{ .struct_type = stub } };
                        try s.types.put(d.name.string, td);
                        const n0 = try sg.makeSGNode(.{ .type_declaration = td }, d.value.location, self.allocator);
                        try s.nodes.append(n0);
                        if (s.parent == null) try self.root_list.append(n0);
                    }

                    const st_ptr = try self.structTypeFromLiteral(st_lit, s);
                    const dst_const = td.ty.struct_type;
                    const dst: *sg.StructType = @constCast(dst_const);
                    dst.fields = st_ptr.fields;
                    if (dst.generic_identity == null) {
                        const identity = try self.allocator.create(sg.GenericTypeIdentity);
                        identity.* = .{
                            .base_name = d.name.string,
                            .arg_names = &.{},
                            .arg_values = &.{},
                        };
                        dst.generic_identity = identity;
                    }
                    const noop = try self.makeNoopNode(d.value.location);
                    break :blk_struct .{ .node = noop, .ty = .{ .builtin = .Any } };
                },
                .choice_type_literal => |ct_lit| blk_choice: {
                    if (s.types.contains(d.name.string))
                        return error.SymbolAlreadyDefined;

                    var variants = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
                    for (ct_lit.variants, 0..) |variant, idx| {
                        const payload_type = if (variant.payload_type) |pt| sg.Type{ .struct_type = try self.structTypeFromLiteral(pt, s) } else null;
                        try variants.append(.{
                            .name = variant.name.string,
                            .value = @intCast(idx),
                            .payload_type = payload_type,
                        });
                    }

                    const choice_ptr = try self.allocator.create(sg.ChoiceType);
                    choice_ptr.* = .{ .variants = try variants.toOwnedSlice() };
                    variants.deinit();

                    const td = try self.allocator.create(sg.TypeDeclaration);
                    td.* = .{
                        .name = d.name.string,
                        .origin_file = d.value.location.file,
                        .ty = .{ .choice_type = choice_ptr },
                    };
                    try s.types.put(d.name.string, td);

                    const n0 = try sg.makeSGNode(.{ .type_declaration = td }, d.value.location, self.allocator);
                    try s.nodes.append(n0);
                    if (s.parent == null) try self.root_list.append(n0);

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
    ) SemErr!typ.TypedExpr {
        // Register generic template and skip direct emission
        if (f.generic_params.len > 0) {
            const params_struct = try self.genericParamsStructOrNames(
                f.generic_params_struct,
                f.generic_params,
                f.name.location,
            );
            try p.appendGenericFunctionTemplate(f.name.string, .{
                .name = f.name.string,
                .location = loc,
                .params = try self.genericParamDefsFromSyntax(params_struct, p),
                .param_abstract_constraints = try self.allocEmptyAbstractConstraintSlice(f.generic_params.len),
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

        var child = try Scope.init(self.allocator, p, null);
        // ── entrada
        var in_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        for (f.input.fields) |fld| {
            const ty = try self.resolveType(fld.type.?, &child);
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, &child)).node
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
                .origin_file = loc.file,
                .mutability = .constant,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name.string, bd);
        }
        const in_struct = sg.StructType{ .fields = try in_fields.toOwnedSlice() };
        in_fields.deinit();

        // ── salida
        var out_fields = std.array_list.Managed(sg.StructTypeField).init(self.allocator.*);
        for (f.output.fields) |fld| {
            const ty = try self.resolveType(fld.type.?, &child);
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, &child)).node
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
                .origin_file = loc.file,
                .mutability = .variable,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name.string, bd);
        }
        const out_struct = sg.StructType{ .fields = try out_fields.toOwnedSlice() };
        out_fields.deinit();

        // ── cuerpo
        var body_cb: ?*sg.CodeBlock = null;
        if (f.body) |body_node| {
            const body_te = try self.visitNode(body_node.*, &child);
            body_cb = body_te.node.content.code_block;
        }

        const fn_ptr = try self.allocator.create(sg.FunctionDeclaration);
        fn_ptr.* = .{
            .name = f.name.string,
            .location = loc,
            .input = in_struct,
            .output = out_struct,
            .body = body_cb,
        };

        // Register function into overload set for the name
        if (p.functions.getPtr(f.name.string)) |list_ptr| {
            // prevent exact duplicate signature (same input structure, strict equality)
            for (list_ptr.items) |existing| {
                if (typ.typesExactlyEqual(.{ .struct_type = &existing.input }, .{ .struct_type = &fn_ptr.input }))
                    return error.SymbolAlreadyDefined;
            }
        }
        try p.appendFunction(f.name.string, fn_ptr);
        self.clearDeferred(&child);
        const n = try sg.makeSGNode(.{ .function_declaration = fn_ptr }, loc, self.allocator);
        try p.nodes.append(n);
        if (p.parent == null) try self.root_list.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn allocEmptyAbstractConstraintSlice(self: *Semantizer, len: usize) ![]const ?[]const u8 {
        const slice = try self.allocator.alloc(?[]const u8, len);
        for (slice, 0..) |_, i| slice[i] = null;
        return slice;
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
        var params = try self.allocator.alloc(gen.GenericParam, params_struct.fields.len);
        for (params_struct.fields, 0..) |field, idx| {
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

            params[idx] = .{
                .name = field.name.string,
                .kind = .comptime_int,
                .value_type = try self.resolveType(field_ty, s),
            };
        }
        return params;
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

    fn collectHiddenCanBeParamsFromType(
        self: *Semantizer,
        ty: syn.Type,
        params: *std.array_list.Managed(gen.GenericParam),
        s: *Scope,
    ) !void {
        switch (ty) {
            .pointer_type => |ptr_info| try self.collectHiddenCanBeParamsFromType(ptr_info.child.*, params, s),
            .array_type => |arr_info| try self.collectHiddenCanBeParamsFromType(arr_info.element.*, params, s),
            .struct_type_literal => |st| {
                for (st.fields) |field| {
                    if (field.type) |field_ty| {
                        try self.collectHiddenCanBeParamsFromType(field_ty, params, s);
                    }
                    if (field.default_value) |value_expr| {
                        try self.collectHiddenComptimeParamsFromValueExpr(value_expr, params, s);
                    }
                }
            },
            .generic_type_instantiation => |g| {
                for (g.args.fields) |field| {
                    if (field.type) |field_ty| {
                        try self.collectHiddenCanBeParamsFromType(field_ty, params, s);
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
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt|
                std.fmt.parseInt(i64, txt, 0) catch null,
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

        const elem_ptr = try self.allocator.create(sg.Type);
        elem_ptr.* = element_ty;

        const sem_arr = try self.allocator.create(sg.ArrayType);
        sem_arr.* = .{
            .length = @intCast(length),
            .element_type = elem_ptr,
        };
        return .{ .array_type = sem_arr };
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
        };
    }

    fn outputUsesAbstractWithoutDefault(self: *Semantizer, ty: syn.Type, s: *Scope) bool {
        return switch (ty) {
            .type_name => |tn| {
                if (s.lookupAbstractInfo(tn.string) != null and s.lookupAbstractDefault(tn.string) == null) return true;
                return false;
            },
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
                        if (p.lookupAbstractInfo(tn.string) != null and p.lookupAbstractDefault(tn.string) == null) {
                            has_abstract_input = true;
                            const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                            try hidden_param_names.append(hidden_name);
                            try hidden_constraints.append(tn.string);
                            rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, tn.string);
                        }
                    },
                    .generic_type_instantiation => |g| {
                        if (p.lookupAbstractInfo(g.base_name.string) != null and p.lookupAbstractDefault(g.base_name.string) == null) {
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
                                if (p.lookupAbstractInfo(child_name) != null and p.lookupAbstractDefault(child_name) == null) {
                                    has_abstract_input = true;
                                    const hidden_name = try std.fmt.allocPrint(self.allocator.*, "__abstract_param_{d}", .{hidden_param_names.items.len});
                                    try hidden_param_names.append(hidden_name);
                                    try hidden_constraints.append(child_name);
                                    rewritten_input_fields[i].type = try self.rewriteAbstractTypeForTemplate(field_ty, hidden_name, child_name);
                                }
                            },
                            .generic_type_instantiation => |g| {
                                const child_name = g.base_name.string;
                                if (p.lookupAbstractInfo(child_name) != null and p.lookupAbstractDefault(child_name) == null) {
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
        if (b.mutability == .constant and b.initialization != null)
            return error.ConstantReassignment;

        var rhs = try self.visitNode(a.value.*, s);
        rhs = try typ.coerceExprToType(b.ty, rhs, a.value, s, self.allocator, self.diags);
        rhs = try typ.ensureValuePositionAllowed(rhs, a.value.location, s, self.allocator, self.diags);
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

        s.clearBindingMoved(b.name);

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
            tv = try typ.ensureValuePositionAllowed(tv, f.value.location, s, self.allocator, self.diags);
            try fields_buf.append(.{ .name = f.name.string, .value = tv.node });
        }

        const fields = try fields_buf.toOwnedSlice();
        fields_buf.deinit();

        const st_ptr = try self.structTypeFromVal(sl, s);

        const lit = try self.allocator.create(sg.StructValueLiteral);
        lit.* = .{
            .fields = fields,
            .ty = .{ .struct_type = st_ptr },
            .dispatch_prefix_positional_count = 0,
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

        if (base.ty == .array_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                ma.struct_value.*.location,
                .semantic,
                "type '{s}' has no field '.{s}'",
                .{ desc.bytes, ma.field_name.string },
            );
            return error.Reported;
        }

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
        const st = base.ty.struct_type;

        var idx: ?u32 = null;
        var fty: sg.Type = undefined;
        for (st.fields, 0..) |f, i| {
            if (std.mem.eql(u8, f.name, ma.field_name.string)) {
                idx = @intCast(i);
                fty = f.ty;
                break;
            }
        }
        if (idx == null) return error.FieldsNotFound;

        const fa = try self.allocator.create(sg.StructFieldAccess);
        fa.* = .{
            .struct_value = base.node,
            .field_name = ma.field_name.string,
            .field_index = idx.?,
        };

        const n = try sg.makeSGNode(.{ .struct_field_access = fa }, undefined, self.allocator);
        return .{ .node = n, .ty = fty };
    }

    fn handleChoicePayloadAccess(
        self: *Semantizer,
        acc: syn.ChoicePayloadAccess,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const base = try self.visitNode(acc.choice_value.*, s);
        if (base.ty != .choice_type) {
            const desc = try self.formatTypeText(base.ty, s);
            defer desc.deinit();
            try self.diags.add(
                acc.choice_value.*.location,
                .semantic,
                "cannot access choice payload '..{s}' on value of type '{s}'",
                .{ desc.bytes, acc.variant_name.string },
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

        try self.diags.add(
            acc.variant_name.location,
            .semantic,
            "choice has no variant '..{s}'",
            .{acc.variant_name.string},
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
            try self.diags.add(
                loc,
                .semantic,
                "module has no value '.{s}'",
                .{field_name},
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

        var idx = try self.visitNode(ia.index.*, s);

        const ro_self = try typ.ensureReadOnlyPointer(ia.value, base, self.allocator, self.diags);

        const name = "operator get[]";
        const empty_args = syn.StructTypeLiteral{ .fields = &.{} };
        var input_te = try self.buildCallInput(&[_]CallArg{
            .{ .name = "self", .expr = ro_self },
            .{ .name = "index", .expr = idx },
        });

        var chosen: ?*sg.FunctionDeclaration = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
            error.SymbolNotFound => null,
            else => return err,
        };

        if (chosen == null) {
            chosen = self.resolveVisibleOverload(name, input_te, s, ia.value.*.location) catch |err| switch (err) {
                error.SymbolNotFound => null,
                error.AmbiguousOverload => {
                    try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, ia.value.*.location);
                    return error.Reported;
                },
                else => return err,
            };
        }

        if (chosen == null and !typ.typesExactlyEqual(idx.ty, native_uint_ty)) {
            idx = try typ.coerceExprToType(native_uint_ty, idx, ia.index, s, self.allocator, self.diags);
            input_te = try self.buildCallInput(&[_]CallArg{
                .{ .name = "self", .expr = ro_self },
                .{ .name = "index", .expr = idx },
            });

            chosen = self.instantiateGenericNamed(name, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (chosen == null) {
                chosen = self.resolveVisibleOverload(name, input_te, s, ia.value.*.location) catch |err| switch (err) {
                    error.SymbolNotFound => null,
                    error.AmbiguousOverload => {
                        try self.addAmbiguousFunctionDiagnostic(name, input_te.ty, s, ia.value.*.location);
                        return error.Reported;
                    },
                    else => return err,
                };
            }
        }

        const chosen_fn = chosen orelse {
            try self.addMissingFunctionDiagnostic(name, input_te.ty, s, ia.value.*.location);
            return error.Reported;
        };
        input_te = try self.coerceCallInputToExpected(&chosen_fn.input, input_te, ia.index, s);

        const call_ptr = try self.allocator.create(sg.FunctionCall);
        call_ptr.* = .{ .callee = chosen_fn, .input = input_te.node };

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, undefined, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = typ.functionReturnType(chosen_fn) };
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

        const node = try sg.makeSGNode(.{ .function_call = call_ptr }, undefined, self.allocator);
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
        for (st.fields) |f| {
            const ty = try self.resolveType(f.type.?, s);
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
            const ty = try self.resolveTypeWithSubst(f.type.?, s, subst);
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

    pub fn choiceTypeFromLiteralWithSubst(
        self: *Semantizer,
        ct: syn.ChoiceTypeLiteral,
        s: *Scope,
        subst: *const GenericSubst,
    ) SemErr!*sg.ChoiceType {
        var variants = std.array_list.Managed(sg.ChoiceVariant).init(self.allocator.*);
        for (ct.variants, 0..) |variant, idx| {
            const payload_type = if (variant.payload_type) |pt|
                sg.Type{ .struct_type = try self.structTypeFromLiteralWithSubst(pt, s, subst) }
            else
                null;
            try variants.append(.{
                .name = variant.name.string,
                .value = @intCast(idx),
                .payload_type = payload_type,
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

        const tv_in = try self.visitNode(call.input.*, s);
        try self.checkCallBindingExclusivity(call.callee, tv_in, call.input.*.location);
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

        const chosen = try self.resolveRegularCallCallee(call, tv_in, s, call.input.*.location);
        const coerced_input = try self.coerceCallInputToExpected(&chosen.input, tv_in, call.input, s);
        try self.checkCallBindingExclusivity(call.callee, coerced_input, call.input.*.location);

        const fc_ptr = try self.allocator.create(sg.FunctionCall);
        fc_ptr.* = .{ .callee = chosen, .input = coerced_input.node };

        const n = try sg.makeSGNode(.{ .function_call = fc_ptr }, undefined, self.allocator);

        const result_ty = typ.functionReturnType(chosen);

        return .{ .node = n, .ty = result_ty };
    }

    fn extractCallBindingAccess(
        self: *Semantizer,
        field_value: *const sg.SGNode,
        field_ty: sg.Type,
    ) ?CallBindingAccess {
        _ = self;
        return switch (field_value.content) {
            .binding_use => |binding| .{ .name = binding.name, .mode = .value },
            .address_of => |inner| blk: {
                if (inner.content != .binding_use) break :blk null;
                if (field_ty != .pointer_type) break :blk null;

                const mode: CallAccessMode = switch (field_ty.pointer_type.mutability) {
                    .read_only => .read,
                    .read_write => .write,
                };
                break :blk .{ .name = inner.content.binding_use.name, .mode = mode };
            },
            else => null,
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
                if (!std.mem.eql(u8, left.name, right.name)) continue;
                if (!callModesConflict(left.mode, right.mode)) continue;

                try self.diags.add(
                    loc,
                    .semantic,
                    "binding '{s}' cannot be passed as '{s}' and '{s}' in the same call to '{s}'",
                    .{ left.name, modeText(left.mode), modeText(right.mode), callee_name },
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
            if (std.mem.eql(u8, field.name, "value")) {
                value_idx = idx;
            } else if (std.mem.eql(u8, field.name, "variant")) {
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

                    try self.diags.add(
                        loc,
                        .semantic,
                        "choice has no variant '..{s}'",
                        .{raw_variant.variant_name},
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

    fn resolveRegularCallCallee(
        self: *Semantizer,
        call: syn.FunctionCall,
        input_te: typ.TypedExpr,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!*sg.FunctionDeclaration {
        var chosen: *sg.FunctionDeclaration = undefined;
        if (call.type_arguments_struct) |stargs| {
            chosen = try self.instantiateGenericNamed(call.callee, stargs, input_te, s, .regular);
        } else if (call.type_arguments) |targs| {
            chosen = try self.instantiateGeneric(call.callee, targs, input_te, s, .regular);
        } else {
            const empty_args = syn.StructTypeLiteral{ .fields = &.{} };
            const inferred = self.instantiateGenericNamed(call.callee, empty_args, input_te, s, .regular) catch |err| switch (err) {
                error.SymbolNotFound => null,
                else => return err,
            };

            if (inferred) |instantiated| {
                chosen = instantiated;
            } else {
                if (call.module_qualifier) |module_name| {
                    chosen = try self.resolveQualifiedOverload(module_name, call.callee, input_te, s, loc);
                } else {
                    chosen = self.resolveVisibleOverload(call.callee, input_te, s, loc) catch |err| switch (err) {
                        error.SymbolNotFound => blk: {
                            const abstract_inferred = self.instantiateGenericNamed(call.callee, empty_args, input_te, s, .abstract_contract) catch |inner_err| switch (inner_err) {
                                error.SymbolNotFound => null,
                                else => return inner_err,
                            };
                            if (abstract_inferred) |instantiated_abstract| break :blk instantiated_abstract;
                            if (self.defer_unknown_top_level and self.current_top_node != null) {
                                if (!(try self.hasVisibleFunctionNamed(call.callee, s, loc))) {
                                    return error.SymbolNotFound;
                                }
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
            }
        }
        return chosen;
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

        return switch (expected) {
            .builtin => |bt| typ.canLiteralCoerceToBuiltin(bt, actual),
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

    fn coerceCallFieldExpr(
        self: *Semantizer,
        expected: sg.Type,
        actual: typ.TypedExpr,
        expr_node: *const syn.STNode,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        if (typ.typesCompatible(expected, actual.ty)) return actual;

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
        const fields = try self.allocator.alloc(sg.StructValueLiteralField, init_struct.fields.len);

        const fake_binding = try self.allocator.create(sg.BindingDeclaration);
        fake_binding.* = .{
            .name = "__init_target",
            .origin_file = loc.file,
            .mutability = .variable,
            .ty = init_struct.fields[0].ty,
            .initialization = null,
        };
        const fake_binding_use = try sg.makeSGNode(.{ .binding_use = fake_binding }, loc, self.allocator);
        fields[0] = .{ .name = init_struct.fields[0].name, .value = fake_binding_use };

        const user_value = tv_in.node.content.struct_value_literal;
        for (user_value.fields, 0..) |field, idx| {
            fields[idx + 1] = .{ .name = field.name, .value = field.value };
        }

        const struct_value = try self.allocator.create(sg.StructValueLiteral);
        struct_value.* = .{
            .fields = fields,
            .ty = init_input_ty,
            .dispatch_prefix_positional_count = 1,
        };

        const node = try sg.makeSGNode(.{ .struct_value_literal = struct_value }, loc, self.allocator);
        _ = constructed_ty;
        return .{ .node = node, .ty = init_input_ty };
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
                    "pipe right-hand side must use named arguments",
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

            var field_names = std.array_list.Managed([]const u8).init(self.allocator.*);
            defer field_names.deinit();
            var evaluated_args = std.array_list.Managed(typ.TypedExpr).init(self.allocator.*);
            defer evaluated_args.deinit();

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
                try field_names.append(field.name.string);
                try evaluated_args.append(try self.evalPipeArg(field.value, left_te, s));
            }

            var input_te = try self.buildNamedPipeInput(field_names.items, evaluated_args.items);

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
            try self.checkCallBindingExclusivity(call.callee, input_te, loc);

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

                    const score = abs.specificityScore(.{ .struct_type = &cand.input }, input_te.ty);
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

        if (best == null) {
            try self.addMissingModuleFunctionDiagnostic(module_name, module_dir, fn_name, input_te.ty, s, loc);
            return error.Reported;
        }
        if (ambiguous) {
            try self.diags.add(
                loc,
                .semantic,
                "module-qualified call '{s}.{s}' is ambiguous",
                .{ module_name, fn_name },
            );
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

                    const score = abs.specificityScore(.{ .struct_type = &cand.input }, input_te.ty);
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
        }

        if (first) try buf.appendSlice("  (none)");
        return try buf.toOwnedSlice();
    }

    fn addMissingFunctionDiagnostic(
        self: *Semantizer,
        fn_name: []const u8,
        input_ty: sg.Type,
        s: *Scope,
        loc: tok.Location,
    ) !void {
        if (!(try self.hasVisibleFunctionNamed(fn_name, s, loc))) {
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
            if (fld.type) |ty_node| {
                if (self.typeUsesParam(ty_node, param_name)) return fld.name.string;
            }
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
        if (input_ty != .struct_type) return false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(fn_name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != .abstract_contract) continue;

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
        const empty_args = syn.StructTypeLiteral{ .fields = &.{} };

        const inferred_init = self.instantiateGenericNamed("init", empty_args, init_input_te, s, .regular) catch |err| switch (err) {
            error.SymbolNotFound => null,
            else => return err,
        };

        const init_fn = inferred_init orelse self.resolveVisibleOverload("init", init_input_te, s, call.input.*.location) catch |err| switch (err) {
            error.SymbolNotFound => {
                if (!(try self.hasVisibleFunctionNamed("init", s, call.input.*.location))) {
                    try self.diags.add(
                        call.input.*.location,
                        .semantic,
                        "failed to initialize type '{s}': no function named 'init' exists",
                        .{call.callee},
                    );
                    return error.Reported;
                }
                const sigs = try self.collectVisibleSignatureText("init", user_struct, s, call.input.*.location);
                defer sigs.deinit();
                try self.diags.add(
                    call.input.*.location,
                    .semantic,
                    "failed to initialize type '{s}': no 'init' overload accepts arguments {s}. Available overloads:\n{s}",
                    .{ call.callee, sigs.actual.bytes, sigs.available.bytes },
                );
                return error.Reported;
            },
            error.AmbiguousOverload => {
                const candidates_result = self.buildOverloadCandidatesText("init", init_input_ty, s) catch null;
                const candidates = if (candidates_result) |owned| owned.bytes else "";
                defer if (candidates_result) |owned| owned.deinit();
                try self.diags.add(
                    call.input.*.location,
                    .semantic,
                    "failed to initialize type '{s}': matching 'init' overloads are ambiguous. Candidates:\n{s}",
                    .{ call.callee, candidates },
                );
                return error.Reported;
            },
            else => return err,
        };

        const expected_user_fields = try self.allocator.alloc(sg.StructTypeField, tv_in.ty.struct_type.fields.len);
        for (tv_in.ty.struct_type.fields, 0..) |_, idx| {
            expected_user_fields[idx] = init_fn.input.fields[idx + 1];
        }
        const expected_user_struct = try self.allocator.create(sg.StructType);
        expected_user_struct.* = .{ .fields = expected_user_fields };
        const coerced_args = try self.coerceCallInputToExpected(expected_user_struct, tv_in, call.input, s);

        const type_init = sg.TypeInitializer{
            .type_decl = type_decl,
            .init_fn = init_fn,
            .args = coerced_args.node,
        };

        const init_node = try sg.makeSGNode(.{ .type_initializer = type_init }, undefined, self.allocator);
        return .{ .node = init_node, .ty = type_decl.ty };
    }

    fn typeUsesParam(self: *Semantizer, ty: syn.Type, param: []const u8) bool {
        return switch (ty) {
            .type_name => std.mem.eql(u8, ty.type_name.string, param),
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
            .generic_type_instantiation => |g| {
                if (std.mem.eql(u8, g.base_name.string, "Array")) {
                    if (actual_ty != .array_type) return null;
                    for (g.args.fields) |arg_field| {
                        if (!std.mem.eql(u8, arg_field.name.string, "t")) continue;
                        if (arg_field.type) |arg_ty| {
                            if (!self.typeUsesParam(arg_ty, param_name)) continue;
                            return self.extractTypeArgumentFromActual(arg_ty, actual_ty.array_type.element_type.*, param_name, s);
                        }
                    }
                    return null;
                }
                const tmpl_ptr = s.lookupGenericTypeTemplate(g.base_name.string, g.args.fields.len) orelse null;
                if (tmpl_ptr != null and actual_ty == .struct_type) {
                    const actual_struct = actual_ty.struct_type;
                    if (actual_struct.generic_identity) |identity| {
                        if (std.mem.eql(u8, identity.base_name, g.base_name.string)) {
                            for (g.args.fields) |arg_field| {
                                if (arg_field.type) |arg_ty| {
                                    if (!self.typeUsesParam(arg_ty, param_name)) continue;
                                    var idx: usize = 0;
                                    while (idx < identity.arg_names.len) : (idx += 1) {
                                        if (std.mem.eql(u8, identity.arg_names[idx], arg_field.name.string)) {
                                            switch (identity.arg_values[idx]) {
                                                .type => |arg_ty_value| return arg_ty_value,
                                                else => {},
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            },
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
            .generic_type_instantiation => |g| {
                if (std.mem.eql(u8, g.base_name.string, "Array")) {
                    if (actual_ty != .array_type) return null;
                    for (g.args.fields) |arg_field| {
                        if (!std.mem.eql(u8, arg_field.name.string, "n")) continue;
                        if (arg_field.default_value) |value_expr| {
                            if (valueExprUsesParam(value_expr, param_name)) return @intCast(actual_ty.array_type.length);
                        }
                    }
                    return null;
                }

                const tmpl_ptr = s.lookupGenericTypeTemplate(g.base_name.string, g.args.fields.len) orelse null;
                if (tmpl_ptr != null and actual_ty == .struct_type) {
                    const actual_struct = actual_ty.struct_type;
                    if (actual_struct.generic_identity) |identity| {
                        if (std.mem.eql(u8, identity.base_name, g.base_name.string)) {
                            for (g.args.fields) |arg_field| {
                                if (arg_field.default_value) |value_expr| {
                                    if (!valueExprUsesParam(value_expr, param_name)) continue;
                                    var idx: usize = 0;
                                    while (idx < identity.arg_names.len) : (idx += 1) {
                                        if (std.mem.eql(u8, identity.arg_names[idx], arg_field.name.string)) {
                                            switch (identity.arg_values[idx]) {
                                                .comptime_int => |value| return value,
                                                else => {},
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
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
        for (tmpl.input.fields) |fld| {
            if (fld.type) |ty_node| {
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
            if (fld.type) |ty_node| {
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
            const expected_field_ty = if (expected_field.type) |ty_node|
                try self.resolveTypeWithSubst(ty_node, s, subst)
            else
                return false;
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
                    const first_ptr = switch (first_field.type orelse continue) {
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
    ) !?*sg.StructType {
        if (actual_ty != .struct_type) return null;
        const actual = actual_ty.struct_type;

        const expected_fields = expected_ptr.fields;
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
                } else if (typ.typesCompatible(exp_field.ty, actual_ty_field)) {
                    final_ty = actual_ty_field;
                    changed = true;
                } else {
                    return null;
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
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != allowed_kind) continue;
                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();

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
                            if (self.inferGenericArgFromCall(tmpl, param, call_input.ty, s, &subst)) |inferred| {
                                try self.putGenericArg(&subst, param, inferred);
                                found = true;
                            }
                        }
                        if (!found) {
                            ok = false;
                            break;
                        }
                    }
                    if (!ok) continue;
                    if (!self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) continue;
                    if (try self.instantiateGenericTemplate(name, tmpl, call_input, s, &subst)) |instantiated| {
                        return instantiated;
                    }
                }
            }
        }
        return error.SymbolNotFound;
    }

    fn instantiateGeneric(
        self: *Semantizer,
        name: []const u8,
        type_args_syn: []const syn.Type,
        call_input: typ.TypedExpr,
        s: *Scope,
        allowed_kind: gen.GenericDispatchKind,
    ) SemErr!*sg.FunctionDeclaration {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.dispatch_kind != allowed_kind) continue;
                    if (tmpl.params.len != type_args_syn.len) continue;

                    var subst = GenericSubst.init(self.allocator);
                    defer subst.deinit();
                    var i: usize = 0;
                    while (i < tmpl.params.len) : (i += 1) {
                        if (tmpl.params[i].kind != .type) continue;
                        const resolved = try self.resolveTypeWithSubst(type_args_syn[i], s, &subst);
                        try subst.types.put(tmpl.params[i].name, resolved);
                    }
                    if (!self.substSatisfiesAbstractConstraints(tmpl, &subst, s)) continue;
                    if (try self.instantiateGenericTemplate(name, tmpl, call_input, s, &subst)) |instantiated| {
                        return instantiated;
                    }
                }
            }
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
        const out_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.output, s, subst);

        if (try self.refinedStructTypeWithActual(in_struct_ptr, call_input.ty)) |refined| {
            in_struct_ptr = refined;
        }
        if (!self.callInputMatchesDispatch(in_struct_ptr, call_input, s)) return null;

        if (s.functions.getPtr(name)) |fns| {
            for (fns.items) |cand| {
                if (typ.typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = in_struct_ptr })) {
                    return cand;
                }
            }
        }

        var child = try Scope.init(self.allocator, s, null);
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

        for (in_struct_ptr.fields) |fld| {
            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{ .name = fld.name, .origin_file = tmpl.location.file, .mutability = .variable, .ty = fld.ty, .initialization = null };
            try child.bindings.put(fld.name, bd);
        }
        for (out_struct_ptr.fields) |fld| {
            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{ .name = fld.name, .origin_file = tmpl.location.file, .mutability = .variable, .ty = fld.ty, .initialization = null };
            try child.bindings.put(fld.name, bd);
        }

        var body_cb: ?*sg.CodeBlock = null;
        if (tmpl.body) |body_node| {
            const body_te = try self.visitNode(body_node.*, &child);
            body_cb = body_te.node.content.code_block;
        }

        const fn_ptr = try self.allocator.create(sg.FunctionDeclaration);
        fn_ptr.* = .{
            .name = tmpl.name,
            .location = tmpl.location,
            .input = in_struct_ptr.*,
            .output = out_struct_ptr.*,
            .body = body_cb,
        };

        try s.appendFunction(name, fn_ptr);
        const node = try sg.makeSGNode(.{ .function_declaration = fn_ptr }, tmpl.location, self.allocator);
        try self.root_list.append(node);
        self.clearDeferred(&child);
        return fn_ptr;
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
                            st_ptr.generic_identity = identity;
                            break :blk_struct .{ .struct_type = st_ptr };
                        },
                        .choice_type_literal => |ct| .{ .choice_type = try self.choiceTypeFromLiteralWithSubst(ct, s, &subst) },
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
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var lhs = try self.visitNode(bo.left.*, s);
        var rhs = try self.visitNode(bo.right.*, s);

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

        const n = try sg.makeSGNode(.{ .binary_operation = bin.* }, undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = lhs.ty };
    }

    //──────────────────────────────────────────────────── COMPARISON
    fn handleComparison(
        self: *Semantizer,
        c: syn.Comparison,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var lhs = try self.visitNode(c.left.*, s);
        var rhs = try self.visitNode(c.right.*, s);

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

        const node = try sg.makeSGNode(.{ .comparison = cmp_ptr.* }, undefined, self.allocator);
        try s.nodes.append(node);
        return .{ .node = node, .ty = .{ .builtin = .Bool } };
    }

    //──────────────────────────────────────────────────── RETURN
    fn handleReturn(
        self: *Semantizer,
        r: syn.ReturnStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        var e = if (r.expression) |ex| (try self.visitNode(ex.*, s)) else null;
        if (r.expression) |ex| {
            if (e) |te| e = try typ.ensureValuePositionAllowed(te, ex.location, s, self.allocator, self.diags);
        }

        const rs = try self.allocator.create(sg.ReturnStatement);
        rs.* = .{ .expression = if (e) |te| te.node else null };

        const n = try sg.makeSGNode(.{ .return_statement = rs }, undefined, self.allocator);
        try s.nodes.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── IF
    fn handleIf(
        self: *Semantizer,
        ifs: syn.IfStatement,
        s: *Scope,
    ) SemErr!typ.TypedExpr {
        const start_len = s.nodes.items.len;

        const cond = try self.visitNode(ifs.condition.*, s);
        const then_te = try self.visitNode(ifs.then_block.*, s);

        const else_cb = if (ifs.else_block) |eb|
            (try self.visitNode(eb.*, s)).node.content.code_block
        else
            null;

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
        const iterable_copyable = typ.isTypeCopyable(iterable_ty, s);
        const iterable_name = try self.makeSyntheticName("iterable");
        const iterator_name = try self.makeSyntheticName("iterator");

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

        if (!abs.typeImplementsAbstract("Iterable", iterable_ty, s)) {
            const iterable_ty_text = try self.formatTypeText(iterable_ty, s);
            defer iterable_ty_text.deinit();
            try self.diags.add(
                loc,
                .semantic,
                "for expects a type implementing abstract 'Iterable', got '{s}'",
                .{iterable_ty_text.bytes},
            );
            return error.Reported;
        }

        const iterable_addr = try self.makeSynNode(.{ .address_of = .{
            .value = iterable_ident,
            .mutability = .read_only,
        } }, loc);

        const to_iterator_fields = try self.allocator.alloc(syn.StructValueLiteralField, 1);
        to_iterator_fields[0] = .{
            .name = .{ .string = "value", .location = loc },
            .value = iterable_addr,
        };
        const to_iterator_arg = try self.makeSynNode(.{ .struct_value_literal = .{
            .fields = to_iterator_fields,
        } }, loc);
        const to_iterator_call = try self.makeSynNode(.{ .function_call = .{
            .callee = "to_iterator",
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
            iterator_check_scope_storage = try Scope.init(self.allocator, s, null);
            const tmp_binding = try self.allocator.create(sg.BindingDeclaration);
            tmp_binding.* = .{
                .name = iterable_name,
                .origin_file = loc.file,
                .mutability = .constant,
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
                "for expects 'to_iterator(.value = &...)' to return a type implementing abstract 'Iterator', got '{s}'",
                .{iterator_ty.bytes},
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
            .callee = "next",
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
        const value_te = try self.visitNode(m.value.*, s);
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
                try self.diags.add(
                    case_syn.variant_name.location,
                    .semantic,
                    "choice has no variant '..{s}'",
                    .{case_syn.variant_name.string},
                );
                return error.Reported;
            }

            const case_body = try self.handleMatchCaseBody(value_te.node, found_idx.?, payload_ty, case_syn, s);

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
        choice_value: *const sg.SGNode,
        variant_index: u32,
        payload_ty: ?sg.Type,
        case_syn: syn.MatchCase,
        parent: *Scope,
    ) SemErr!*const sg.CodeBlock {
        var child = try Scope.init(self.allocator, parent, null);

        if (case_syn.payload_binding) |binding_name| {
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
                .choice_value = choice_value,
                .variant_index = variant_index,
                .payload_type = resolved_payload_ty,
            };
            const access_node = try sg.makeSGNode(.{ .choice_payload_access = access }, binding_name.location, self.allocator);
            access_node.sem_type = resolved_payload_ty;

            const bd = try self.allocator.create(sg.BindingDeclaration);
            bd.* = .{
                .name = binding_name.string,
                .origin_file = binding_name.location.file,
                .mutability = .constant,
                .ty = resolved_payload_ty,
                .initialization = access_node,
            };

            try child.bindings.put(binding_name.string, bd);
            const decl_node = try sg.makeSGNode(.{ .binding_declaration = bd }, binding_name.location, self.allocator);
            try child.nodes.append(decl_node);
            try self.maybeScheduleAutoDeinit(bd, binding_name.location, &child);
        } else if (payload_ty != null) {
            // payload exists but binding is optional
        }

        const body_cb = case_syn.body.content.code_block;
        for (body_cb.items) |st|
            _ = try self.visitNode(st.*, &child);

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
        const te = try self.visitNode(addr.value.*, s);

        if (te.node.content != .binding_use) {
            try self.diags.add(
                addr.value.*.location,
                .semantic,
                "cannot take the address of this expression; only named variables are addressable",
                .{},
            );
            return error.Reported;
        }

        const binding = te.node.content.binding_use;
        if (addr.mutability == .read_write and binding.mutability != .variable) {
            try self.diags.add(
                addr.value.*.location,
                .semantic,
                "binding '{s}' is immutable; declare it with '::' or take '&{s}' instead of '$&{s}'",
                .{ binding.name, binding.name, binding.name },
            );
            return error.Reported;
        }

        const child = try self.allocator.create(sg.Type);
        child.* = te.ty;

        const ptr_ty = try self.allocator.create(sg.PointerType);
        ptr_ty.* = .{ .mutability = addr.mutability, .child = child };

        const out_ty: sg.Type = .{ .pointer_type = ptr_ty };

        const addr_node = try sg.makeSGNode(.{ .address_of = te.node }, undefined, self.allocator);
        addr_node.sem_type = out_ty;
        return .{ .node = addr_node, .ty = out_ty };
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

        return .{ .node = n, .ty = base_ty };
    }

    //────────────────────────────────────────────────── POINTER ASSIGNMENT
    const CallArg = struct {
        name: []const u8,
        expr: typ.TypedExpr,
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

            const struct_type = ptr_info.child.*.struct_type;
            if (sf.field_index >= struct_type.fields.len) return error.SymbolNotFound;
            const field_info = struct_type.fields[sf.field_index];

            rhs = try typ.coerceExprToType(field_info.ty, rhs, pa.value, s, self.allocator, self.diags);
            if (!typ.typesExactlyEqual(field_info.ty, rhs.ty)) {
                const pair = try self.formatTypePairText(field_info.ty, rhs.ty, s);
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
                .field_type = field_info.ty,
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

        if (!((source_is_ptr and target_is_native_uint) or (source_is_native_uint and target_is_ptr))) {
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

        const elem_ty_ptr = try self.allocator.create(sg.Type);
        elem_ty_ptr.* = first_ty;

        const arr_info = try self.allocator.create(sg.ArrayType);
        arr_info.* = .{
            .length = ll.elements.len,
            .element_type = elem_ty_ptr,
        };
        return arr_info;
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
                if (std.mem.eql(u8, base_name, "Array")) {
                    break :blk_g try self.resolveArrayTypeFromGenericArgs(g.base_name.location, g.args, s, null);
                }
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
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
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
                const elem_ptr = try self.allocator.create(sg.Type);
                elem_ptr.* = elem_ty;

                const sem_arr = try self.allocator.create(sg.ArrayType);
                sem_arr.* = .{
                    .length = arr_info.length,
                    .element_type = elem_ptr,
                };

                break :blk_arr .{ .array_type = sem_arr };
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
                if (std.mem.eql(u8, base_name, "Array")) {
                    break :blk_g try self.resolveArrayTypeFromGenericArgs(g.base_name.location, g.args, s, subst);
                }
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
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteralWithSubst(st, s, subst) },
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
                const elem_ptr = try self.allocator.create(sg.Type);
                elem_ptr.* = elem_ty;

                const sem_arr = try self.allocator.create(sg.ArrayType);
                sem_arr.* = .{
                    .length = arr_info.length,
                    .element_type = elem_ptr,
                };

                break :blk_arr .{ .array_type = sem_arr };
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
            if (sv.fields.len != 1 or !std.mem.eql(u8, sv.fields[0].name.string, "value")) {
                try self.diags.add(
                    arg_loc,
                    .semantic,
                    "length expects a single '.value' argument when using named parameters",
                    .{},
                );
                return error.Reported;
            }
            value_te = try self.visitNode(sv.fields[0].value.*, s);
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

        for (svl.fields) |field| {
            if (std.mem.eql(u8, field.name.string, "value")) {
                value_field = field;
            } else if (std.mem.eql(u8, field.name.string, "variant")) {
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

                    try self.diags.add(
                        variant_node.location,
                        .semantic,
                        "choice has no variant '..{s}'",
                        .{raw_variant.name.string},
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
        const deinit_fn = s.findDeinit(binding.ty) orelse return;
        const auto_ptr = try self.allocator.create(sg.AutoDeinitBinding);
        auto_ptr.* = .{ .binding = binding, .deinit_fn = deinit_fn };

        const call_node = try sg.makeSGNode(.{ .auto_deinit_binding = auto_ptr }, loc, self.allocator);
        try self.registerDefer(s, &[_]*sg.SGNode{ call_node });
    }

    // ─────────────────────────────────────────────────── Helpers reintento
    fn pushTopLevelForRetry(self: *Semantizer) !void {
        if (!self.defer_unknown_top_level) return;
        if (self.current_top_node) |ptr| {
            try self.pending_next.append(ptr);
        }
    }
};

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
