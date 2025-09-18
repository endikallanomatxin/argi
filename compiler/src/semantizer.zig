const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");
const sem = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig");
const diagnostic = @import("diagnostic.zig");

const SemErr = error{
    SymbolAlreadyDefined,
    SymbolNotFound,
    ConstantReassignment,
    InvalidType,
    UnknownType,
    AbstractNeedsDefault,
    MissingReturnValue,
    NotYetImplemented,
    OutOfMemory,
    OptionalUnwrap,
    AmbiguousOverload,
    Reported,
};

const TypedExpr = struct {
    node: *sem.SGNode,
    ty: sem.Type,
};

//──────────────────────────────────────────────────────────────────────────────
//  SEMANTIZER
//──────────────────────────────────────────────────────────────────────────────
pub const Semantizer = struct {
    allocator: *const std.mem.Allocator,
    st_nodes: []const *syn.STNode, // entrada
    root_list: std.ArrayList(*sem.SGNode), // buffer mut
    root_nodes: []const *sem.SGNode = &.{}, // slice final
    diags: *diagnostic.Diagnostics,

    pub fn init(
        alloc: *const std.mem.Allocator,
        st: []const *syn.STNode,
        diags: *diagnostic.Diagnostics,
    ) Semantizer {
        return .{
            .allocator = alloc,
            .st_nodes = st,
            .root_list = std.ArrayList(*sem.SGNode).init(alloc.*),
            .diags = diags,
        };
    }

    pub fn analyze(self: *Semantizer) SemErr![]const *sem.SGNode {
        var global = try Scope.init(self.allocator, null, null);

        for (self.st_nodes) |n|
            _ = self.visitNode(n.*, &global) catch |err| {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in node '{any}': {s}",
                    .{ n.content, @errorName(err) },
                );
            };

        // Final conformance verification for abstracts (top-level scope)
        try self.verifyAbstracts(&global);

        self.root_nodes = try self.root_list.toOwnedSlice();
        self.root_list.deinit();
        self.clearDeferred(&global);
        return self.root_nodes;
    }

    pub fn printSG(self: *Semantizer) void {
        std.debug.print("\nSEMANTIC GRAPH:\n", .{});
        for (self.root_nodes) |n| sgp.printNode(n, 0);
    }

    //────────────────────────────────────────────────────────────────── visitors
    fn visitNode(self: *Semantizer, n: syn.STNode, s: *Scope) SemErr!TypedExpr {
        return switch (n.content) {
            .symbol_declaration => |d| self.handleSymbolDecl(d, s, n.location) catch |err| blk: {
                switch (err) {
                    error.UnknownType => {
                        // Try to extract the written type name when available
                        if (d.type) |tp| {
                            if (tp == .type_name) {
                                try self.diags.add(
                                    n.location,
                                    .semantic,
                                    "unknown type '{s}' in declaration of '{s}'",
                                    .{ tp.type_name, d.name },
                                );
                                break :blk err;
                            }
                        }
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "unknown type in declaration of '{s}'",
                            .{d.name},
                        );
                    },
                    error.AbstractNeedsDefault => {
                        if (d.type) |tp2| {
                            if (tp2 == .type_name) {
                                try self.diags.add(
                                    n.location,
                                    .semantic,
                                    "cannot use abstract '{s}' as a type for a symbol. Use a concrete type or add a default concrete type to the abstract type ('{s} defaultsto <Type>')",
                                    .{ tp2.type_name, tp2.type_name },
                                );
                                break :blk err;
                            }
                        }
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "cannot use abstract type without a default (add 'defaultsto' or use a concrete type)",
                            .{},
                        );
                    },
                    else => {
                        try self.diags.add(
                            n.location,
                            .semantic,
                            "error in symbol declaration '{s}': {s}",
                            .{ d.name, @errorName(err) },
                        );
                    },
                }
                break :blk err;
            },

            .abstract_declaration => |ad| self.handleAbstractDecl(ad, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in abstract declaration '{s}': {s}",
                    .{ ad.name, @errorName(err) },
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
                    .{ rel.name, @errorName(err) },
                );
                break :blk err;
            },

            .type_declaration => |d| self.handleTypeDecl(d, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in type declaration '{s}': {s}",
                    .{ d.name, @errorName(err) },
                );
                break :blk err;
            },

            .function_declaration => |d| self.handleFuncDecl(d, s, n.location) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in function declaration '{s}': {s}",
                    .{ d.name, @errorName(err) },
                );
                break :blk err;
            },

            .assignment => |a| self.handleAssignment(a, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in assignment '{s}': {s}",
                    .{ a.name, @errorName(err) },
                );
                break :blk err;
            },

            .identifier => |id| self.handleIdentifier(id, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in identifier '{s}': {s}",
                    .{ id, @errorName(err) },
                );
                break :blk err;
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

            .struct_field_access => |sfa| self.handleStructFieldAccess(sfa, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in struct field access '{s}': {s}",
                    .{ sfa.field_name, @errorName(err) },
                );
                break :blk err;
            },

            .function_call => |fc| self.handleCall(fc, s) catch |err| blk: {
                if (err == error.Reported) break :blk err;
                if (err == error.AmbiguousOverload) {
                    // try to produce detailed candidates list
                    const tv_in = self.visitNode(fc.input.*, s) catch null;
                    var details: []const u8 = "";
                    if (tv_in) |te| if (te.ty == .struct_type) {
                        details = self.buildOverloadCandidatesString(fc.callee, te.ty, s) catch "";
                    };
                    try self.diags.add(
                        n.location,
                        .semantic,
                        "ambiguous call to '{s}'. Possible overloads:\n{s}",
                        .{ fc.callee, details },
                    );
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

            .code_block => |blk| self.handleCodeBlock(blk, s) catch |err| blk_ret: {
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

    //──────────────────────────────────────────────────── ABSTRACT DECLARATION
    fn handleAbstractDecl(
        self: *Semantizer,
        ad: syn.AbstractDeclaration,
        s: *Scope,
    ) SemErr!TypedExpr {
        // Register abstract as a nominal type placeholder (maps to Any for now)
        if (s.types.contains(ad.name)) return error.SymbolAlreadyDefined;

        const td = try self.allocator.create(sem.TypeDeclaration);
        td.* = .{ .name = ad.name, .ty = .{ .builtin = .Any } };
        try s.types.put(ad.name, td);

        // Store abstract info (resolved requirements) in scope
        var reqs = std.ArrayList(AbstractFunctionReqSem).init(self.allocator.*);
        for (ad.requires_functions) |rf| {
            // Build input struct resolving types; treat 'Self' specially
            var in_fields = std.ArrayList(sem.StructTypeField).init(self.allocator.*);
            var self_idxs = std.ArrayList(u32).init(self.allocator.*);
            for (rf.input.fields, 0..) |fld, i| {
                var ty: sem.Type = undefined;
                if (fld.type) |t| {
                    if (t == .type_name and std.mem.eql(u8, t.type_name, "Self")) {
                        ty = .{ .builtin = .Any }; // placeholder; we’ll match via index
                        try self_idxs.append(@intCast(i));
                    } else {
                        ty = try self.resolveType(t, s);
                    }
                } else ty = .{ .builtin = .Any };
                try in_fields.append(.{ .name = fld.name, .ty = ty, .default_value = null });
            }
            const in_struct = sem.StructType{ .fields = try in_fields.toOwnedSlice() };
            in_fields.deinit();

            const out_ptr = try self.structTypeFromLiteral(rf.output, s);

            try reqs.append(.{
                .name = rf.name,
                .input = in_struct,
                .output = out_ptr.*,
                .input_self_indices = try self_idxs.toOwnedSlice(),
            });
            self_idxs.deinit();
        }
        const info = try self.allocator.create(AbstractInfo);
        info.* = .{ .name = ad.name, .requirements = try reqs.toOwnedSlice() };
        reqs.deinit();
        try s.abstracts.put(ad.name, info);

        const n = try self.makeNode(undefined, .{ .type_declaration = td }, s);
        if (s.parent == null) try self.root_list.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    // For now, relations are recorded as no-ops to accept syntax without enforcing.
    fn handleAbstractCanBe(
        self: *Semantizer,
        rel: syn.AbstractCanBe,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!TypedExpr {
        const concrete_ty = try self.resolveType(rel.ty, s);

        // Defer conformance checks until call sites or a validation pass.

        if (s.abstract_impls.getPtr(rel.name)) |lst| {
            try lst.append(.{ .ty = concrete_ty, .location = loc });
        } else {
            var new_list = std.ArrayList(AbstractImplEntry).init(self.allocator.*);
            try new_list.append(.{ .ty = concrete_ty, .location = loc });
            try s.abstract_impls.put(rel.name, new_list);
        }

        const empty = try self.allocator.create(sem.CodeBlock);
        empty.* = .{ .nodes = &.{}, .ret_val = null };
        const n = try self.makeNode(undefined, .{ .code_block = empty }, s);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn handleAbstractDefault(
        self: *Semantizer,
        rel: syn.AbstractDefault,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!TypedExpr {
        const concrete_ty = try self.resolveType(rel.ty, s);
        try s.abstract_defaults.put(rel.name, .{ .ty = concrete_ty, .location = loc });
        const empty = try self.allocator.create(sem.CodeBlock);
        empty.* = .{ .nodes = &.{}, .ret_val = null };
        const n = try self.makeNode(undefined, .{ .code_block = empty }, s);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    fn lookupAbstractInfo(_: *Semantizer, s: *Scope, name: []const u8) ?*AbstractInfo {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.abstracts.get(name)) |info| return info;
        }
        return null;
    }

    fn ensureConformance(self: *Semantizer, info: *AbstractInfo, concrete: sem.Type, s: *Scope) !void {
        for (info.requirements) |rq| {
            if (!self.existsFunctionForRequirement(rq, concrete, s))
                return error.SymbolNotFound;
        }
    }

    fn existsFunctionForRequirement(self: *Semantizer, rq: AbstractFunctionReqSem, concrete: sem.Type, s: *Scope) bool {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(rq.name)) |lst| {
                for (lst.items) |cand| {
                    if (!self.funcInputMatchesRequirement(&cand.input, &rq.input, concrete, rq.input_self_indices))
                        continue;
                    // Also require exact output match (nominal)
                    if (cand.output.fields.len != rq.output.fields.len) continue;
                    var j: usize = 0;
                    var outputs_ok = true;
                    while (j < rq.output.fields.len) : (j += 1) {
                        const ro = rq.output.fields[j];
                        const co = cand.output.fields[j];
                        if (!typesExactlyEqual(ro.ty, co.ty)) {
                            outputs_ok = false;
                            break;
                        }
                    }
                    if (!outputs_ok) continue;
                    return true;
                }
            }
        }
        return false;
    }

    fn verifyAbstracts(self: *Semantizer, s: *Scope) !void {
        var any_error = false;
        var it = s.abstract_impls.iterator();
        while (it.next()) |entry| {
            const abs_name = entry.key_ptr.*;
            const impls = entry.value_ptr.*;
            const info = self.lookupAbstractInfo(s, abs_name) orelse continue;

            for (impls.items) |impl| {
                const conc = impl.ty;
                for (info.requirements) |rq| {
                    if (self.existsFunctionForRequirement(rq, conc, s)) continue;

                    // Build expected input with concrete substituted for Self
                    const exp_in = try self.buildExpectedInputWithConcrete(&rq, conc);
                    const in_ty: sem.Type = .{ .struct_type = exp_in };

                    // Produce candidates string
                    const candidates = self.buildOverloadCandidatesString(rq.name, in_ty, s) catch "";

                    // Build signature string
                    var buf = std.ArrayList(u8).init(self.allocator.*);
                    defer buf.deinit();
                    try buf.appendSlice(rq.name);
                    try buf.appendSlice(" (");
                    var i: usize = 0;
                    while (i < exp_in.fields.len) : (i += 1) {
                        const fld = exp_in.fields[i];
                        if (i != 0) try buf.appendSlice(", ");
                        try buf.appendSlice(".");
                        try buf.appendSlice(fld.name);
                        try buf.appendSlice(": ");
                        try self.appendTypePretty(&buf, fld.ty, s);
                    }
                    try buf.appendSlice(")");

                    // Report diagnostic at the 'canbe' site
                    if (candidates.len > 0) {
                        try self.diags.add(
                            impl.location,
                            .semantic,
                            "type does not implement abstract '{s}': missing function '{s}'. Possible overloads:\n{s}",
                            .{ abs_name, buf.items, candidates },
                        );
                    } else {
                        try self.diags.add(
                            impl.location,
                            .semantic,
                            "type does not implement abstract '{s}': missing function '{s}'.",
                            .{ abs_name, buf.items },
                        );
                    }
                    any_error = true;
                }
            }
        }

        // Also verify defaults conform to their abstracts
        var it_def = s.abstract_defaults.iterator();
        while (it_def.next()) |entry2| {
            const abs_name2 = entry2.key_ptr.*;
            const def_entry = entry2.value_ptr.*;
            const info2 = self.lookupAbstractInfo(s, abs_name2) orelse continue;
            const conc2 = def_entry.ty;
            for (info2.requirements) |rq2| {
                if (self.existsFunctionForRequirement(rq2, conc2, s)) continue;

                const exp_in2 = try self.buildExpectedInputWithConcrete(&rq2, conc2);
                const in_ty2: sem.Type = .{ .struct_type = exp_in2 };
                const candidates2 = self.buildOverloadCandidatesString(rq2.name, in_ty2, s) catch "";

                var buf2 = std.ArrayList(u8).init(self.allocator.*);
                defer buf2.deinit();
                try buf2.appendSlice(rq2.name);
                try buf2.appendSlice(" (");
                var j: usize = 0;
                while (j < exp_in2.fields.len) : (j += 1) {
                    const fld2 = exp_in2.fields[j];
                    if (j != 0) try buf2.appendSlice(", ");
                    try buf2.appendSlice(".");
                    try buf2.appendSlice(fld2.name);
                    try buf2.appendSlice(": ");
                    try self.appendTypePretty(&buf2, fld2.ty, s);
                }
                try buf2.appendSlice(")");

                if (candidates2.len > 0) {
                    try self.diags.add(
                        def_entry.location,
                        .semantic,
                        "default type does not implement abstract '{s}': missing function '{s}'. Possible overloads:\n{s}",
                        .{ abs_name2, buf2.items, candidates2 },
                    );
                } else {
                    try self.diags.add(
                        def_entry.location,
                        .semantic,
                        "default type does not implement abstract '{s}': missing function '{s}'.",
                        .{ abs_name2, buf2.items },
                    );
                }
                any_error = true;
            }
        }
        if (any_error) return error.SymbolNotFound;
    }

    fn buildExpectedInputWithConcrete(self: *Semantizer, rq: *const AbstractFunctionReqSem, concrete: sem.Type) !*sem.StructType {
        var fields = try self.allocator.alloc(sem.StructTypeField, rq.input.fields.len);
        for (rq.input.fields, 0..) |f, i| {
            const is_self = containsIndex(rq.input_self_indices, @intCast(i));
            fields[i] = .{ .name = f.name, .ty = if (is_self) concrete else f.ty, .default_value = null };
        }
        const st_ptr = try self.allocator.create(sem.StructType);
        st_ptr.* = .{ .fields = fields };
        return st_ptr;
    }

    fn funcInputMatchesRequirement(self: *Semantizer, cand_in: *const sem.StructType, req_in: *const sem.StructType, concrete: sem.Type, self_idxs: []const u32) bool {
        _ = self;
        if (cand_in.fields.len != req_in.fields.len) return false;
        var i: usize = 0;
        while (i < req_in.fields.len) : (i += 1) {
            const rf = req_in.fields[i];
            const cf = cand_in.fields[i];
            // Field names do not need to match for abstract requirements
            const expect_ty: sem.Type = if (containsIndex(self_idxs, @intCast(i))) concrete else rf.ty;
            if (!typesExactlyEqual(expect_ty, cf.ty)) return false;
        }
        return true;
    }

    fn containsIndex(list: []const u32, idx: u32) bool {
        for (list) |v| if (v == idx) return true;
        return false;
    }

    //─────────────────────────────────────────────────────────  LITERALS
    fn handleLiteral(self: *Semantizer, lit: tok.Literal) SemErr!TypedExpr {
        var sg: sem.ValueLiteral = undefined;
        var ty: sem.Type = .{ .builtin = .Int32 };

        switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt| {
                sg = .{ .int_literal = std.fmt.parseInt(i64, txt, 0) catch 0 };
            },
            .regular_float_literal, .scientific_float_literal => |txt| {
                ty = .{ .builtin = .Float32 };
                sg = .{ .float_literal = std.fmt.parseFloat(f64, txt) catch 0.0 };
            },
            .char_literal => |c| {
                ty = .{ .builtin = .Char };
                sg = .{ .char_literal = c };
            },
            .string_literal => |s| {
                const char_ty: sem.Type = .{ .builtin = .Char };
                const child = try self.allocator.create(sem.Type);
                child.* = char_ty;

                const sem_ptr = try self.allocator.create(sem.PointerType);
                sem_ptr.* = .{ .mutability = .read_only, .child = child };

                ty = .{ .pointer_type = sem_ptr };
                sg = .{ .string_literal = s };
            },
            .bool_literal => |b| {
                ty = .{ .builtin = .Bool };
                sg = .{ .bool_literal = b };
            },
        }

        const ptr = try self.allocator.create(sem.ValueLiteral);
        ptr.* = sg;
        const n = try self.makeNode(undefined, .{ .value_literal = ptr.* }, null);
        return .{ .node = n, .ty = ty };
    }

    //─────────────────────────────────────────────────────────  IDENTIFIER
    fn handleIdentifier(
        self: *Semantizer,
        name: []const u8,
        s: *Scope,
    ) SemErr!TypedExpr {
        const b = s.lookupBinding(name) orelse return error.SymbolNotFound;
        const n = try self.makeNode(undefined, .{ .binding_use = b }, null);
        return .{ .node = n, .ty = b.ty };
    }

    //─────────────────────────────────────────────────────────  CODE BLOCK
    fn handleCodeBlock(
        self: *Semantizer,
        blk: syn.CodeBlock,
        parent: *Scope,
    ) SemErr!TypedExpr {
        var child = try Scope.init(self.allocator, parent, null);

        for (blk.items) |st|
            _ = try self.visitNode(st.*, &child);

        var d_idx: usize = child.deferred.items.len;
        while (d_idx > 0) : (d_idx -= 1) {
            const group = child.deferred.items[d_idx - 1];
            for (group.nodes) |node| try child.nodes.append(node);
        }

        const slice = try child.nodes.toOwnedSlice();
        child.nodes.deinit();
        self.clearDeferred(&child);

        const cb = try self.allocator.create(sem.CodeBlock);
        cb.* = .{ .nodes = slice, .ret_val = null };

        const n = try self.makeNode(undefined, .{ .code_block = cb }, parent);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── SYMBOL DECLARATION
    fn handleSymbolDecl(
        self: *Semantizer,
        d: syn.SymbolDeclaration,
        s: *Scope,
        loc: tok.Location,
    ) SemErr!TypedExpr {
        if (s.bindings.contains(d.name))
            return error.SymbolAlreadyDefined;

        var ty: sem.Type = .{ .builtin = .Int32 };
        if (d.type) |t|
            ty = try self.resolveType(t, s)
        else if (d.value) |v|
            ty = (try self.visitNode(v.*, s)).ty;

        const bd = try self.allocator.create(sem.BindingDeclaration);
        bd.* = .{
            .name = d.name,
            .mutability = d.mutability,
            .ty = ty,
            .initialization = null,
        };

        try s.bindings.put(d.name, bd);
        const n = try self.makeNode(loc, .{ .binding_declaration = bd }, s);
        if (s.parent == null) try self.root_list.append(n);

        if (d.value) |v| bd.initialization = (try self.visitNode(v.*, s)).node;

        try self.maybeScheduleAutoDeinit(bd, loc, s);

        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── TYPE DECLARATION
    fn handleTypeDecl(
        self: *Semantizer,
        d: syn.TypeDeclaration,
        s: *Scope,
    ) SemErr!TypedExpr {
        const st_lit = d.value.*.content.struct_type_literal;
        if (d.generic_params.len > 0) {
            // Register as generic type template
            if (s.generic_types.getPtr(d.name)) |lst| {
                try lst.append(.{ .name = d.name, .location = d.value.location, .param_names = d.generic_params, .body = st_lit });
            } else {
                var new_list = std.ArrayList(GenericTypeTemplate).init(self.allocator.*);
                try new_list.append(.{ .name = d.name, .location = d.value.location, .param_names = d.generic_params, .body = st_lit });
                try s.generic_types.put(d.name, new_list);
            }
            // No concrete type emitted now
            const noop = try self.makeNode(d.value.location, .{ .code_block = blk: {
                const empty = try self.allocator.create(sem.CodeBlock);
                empty.* = .{ .nodes = &.{}, .ret_val = null };
                break :blk empty;
            } }, s);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        } else {
            const st_ptr = try self.structTypeFromLiteral(st_lit, s);
            const td = try self.allocator.create(sem.TypeDeclaration);
            td.* = .{ .name = d.name, .ty = .{ .struct_type = st_ptr } };
            try s.types.put(d.name, td);
            const n = try self.makeNode(undefined, .{ .type_declaration = td }, s);
            if (s.parent == null) try self.root_list.append(n);
            return .{ .node = n, .ty = .{ .builtin = .Any } };
        }
    }

    //──────────────────────────────────────────────────── FUNCTION DECLARATION
    fn handleFuncDecl(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
    ) SemErr!TypedExpr {
        // Register generic template and skip direct emission
        if (f.generic_params.len > 0) {
            if (p.generic_functions.getPtr(f.name)) |lst| {
                try lst.append(.{
                    .name = f.name,
                    .location = loc,
                    .param_names = f.generic_params,
                    .input = f.input,
                    .output = f.output,
                    .body = f.body,
                });
            } else {
                var new_list = std.ArrayList(GenericTemplate).init(self.allocator.*);
                try new_list.append(.{
                    .name = f.name,
                    .location = loc,
                    .param_names = f.generic_params,
                    .input = f.input,
                    .output = f.output,
                    .body = f.body,
                });
                try p.generic_functions.put(f.name, new_list);
            }
            // Return a no-op node for generic template
            const noop = try self.makeNode(loc, .{ .code_block = blk: {
                const empty = try self.allocator.create(sem.CodeBlock);
                empty.* = .{ .nodes = &.{}, .ret_val = null };
                break :blk empty;
            } }, p);
            return .{ .node = noop, .ty = .{ .builtin = .Any } };
        }

        var child = try Scope.init(self.allocator, p, null);

        // ── entrada
        var in_fields = std.ArrayList(sem.StructTypeField).init(self.allocator.*);
        for (f.input.fields) |fld| {
            const ty = try self.resolveType(fld.type.?, &child);
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, &child)).node
            else
                null;

            try in_fields.append(.{
                .name = fld.name,
                .ty = ty,
                .default_value = dvp,
            });

            const bd = try self.allocator.create(sem.BindingDeclaration);
            bd.* = .{
                .name = fld.name,
                .mutability = .variable,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name, bd);
        }
        const in_struct = sem.StructType{ .fields = try in_fields.toOwnedSlice() };
        in_fields.deinit();

        // ── salida
        var out_fields = std.ArrayList(sem.StructTypeField).init(self.allocator.*);
        for (f.output.fields) |fld| {
            const ty = try self.resolveType(fld.type.?, &child);
            const dvp = if (fld.default_value) |n|
                (try self.visitNode(n.*, &child)).node
            else
                null;

            try out_fields.append(.{
                .name = fld.name,
                .ty = ty,
                .default_value = dvp,
            });

            const bd = try self.allocator.create(sem.BindingDeclaration);
            bd.* = .{
                .name = fld.name,
                .mutability = .variable,
                .ty = ty,
                .initialization = dvp,
            };
            try child.bindings.put(fld.name, bd);
        }
        const out_struct = sem.StructType{ .fields = try out_fields.toOwnedSlice() };
        out_fields.deinit();

        // ── cuerpo
        var body_cb: ?*sem.CodeBlock = null;
        if (f.body) |body_node| {
            const body_te = try self.visitNode(body_node.*, &child);
            body_cb = body_te.node.content.code_block;
        }

        const fn_ptr = try self.allocator.create(sem.FunctionDeclaration);
        fn_ptr.* = .{
            .name = f.name,
            .location = loc,
            .input = in_struct,
            .output = out_struct,
            .body = body_cb,
        };

        // Register function into overload set for the name
        if (p.functions.getPtr(f.name)) |list_ptr| {
            // prevent exact duplicate signature (same input structure, strict equality)
            for (list_ptr.items) |existing| {
                if (typesExactlyEqual(.{ .struct_type = &existing.input }, .{ .struct_type = &fn_ptr.input }))
                    return error.SymbolAlreadyDefined;
            }
            try list_ptr.append(fn_ptr);
        } else {
            var lst = std.ArrayList(*sem.FunctionDeclaration).init(self.allocator.*);
            try lst.append(fn_ptr);
            try p.functions.put(f.name, lst);
        }
        self.clearDeferred(&child);
        const n = try self.makeNode(loc, .{ .function_declaration = fn_ptr }, p);
        if (p.parent == null) try self.root_list.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── ASSIGNMENT
    fn handleAssignment(
        self: *Semantizer,
        a: syn.Assignment,
        s: *Scope,
    ) SemErr!TypedExpr {
        const b = s.lookupBinding(a.name) orelse return error.SymbolNotFound;
        if (b.mutability == .constant and b.initialization != null)
            return error.ConstantReassignment;

        const rhs = try self.visitNode(a.value.*, s);

        const asg = try self.allocator.create(sem.Assignment);
        asg.* = .{ .sym_id = b, .value = rhs.node };

        const n = try self.makeNode(undefined, .{ .binding_assignment = asg }, s);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── STRUCT VALUE LITERAL
    fn handleStructValLit(
        self: *Semantizer,
        sl: syn.StructValueLiteral,
        s: *Scope,
    ) SemErr!TypedExpr {
        var fields_buf = std.ArrayList(sem.StructValueLiteralField).init(self.allocator.*);

        for (sl.fields) |f| {
            const tv = try self.visitNode(f.value.*, s);
            try fields_buf.append(.{ .name = f.name, .value = tv.node });
        }

        const fields = try fields_buf.toOwnedSlice();
        fields_buf.deinit();

        const st_ptr = try self.structTypeFromVal(sl, s);

        const lit = try self.allocator.create(sem.StructValueLiteral);
        lit.* = .{ .fields = fields, .ty = .{ .struct_type = st_ptr } };

        const n = try self.makeNode(undefined, .{ .struct_value_literal = lit }, null);
        return .{ .node = n, .ty = .{ .struct_type = st_ptr } };
    }

    fn handleStructTypeLit(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!TypedExpr {
        var val_fields = std.ArrayList(sem.StructValueLiteralField).init(self.allocator.*);
        var ty_fields = std.ArrayList(sem.StructTypeField).init(self.allocator.*);

        for (st.fields) |fld| {
            if (fld.default_value == null)
                return error.NotYetImplemented;

            const tv = try self.visitNode(fld.default_value.?.*, s);

            try val_fields.append(.{ .name = fld.name, .value = tv.node });
            try ty_fields.append(.{ .name = fld.name, .ty = tv.ty, .default_value = null });
        }

        const vals = try val_fields.toOwnedSlice();
        const tys = try ty_fields.toOwnedSlice();
        val_fields.deinit();
        ty_fields.deinit();

        const st_ptr = try self.allocator.create(sem.StructType);
        st_ptr.* = .{ .fields = tys };

        const lit_ptr = try self.allocator.create(sem.StructValueLiteral);
        lit_ptr.* = .{ .fields = vals, .ty = .{ .struct_type = st_ptr } };

        const node_ptr = try self.makeNode(undefined, .{ .struct_value_literal = lit_ptr }, null);
        return .{ .node = node_ptr, .ty = .{ .struct_type = st_ptr } };
    }

    //──────────────────────────────────────────────────── STRUCT FIELD ACCESS
    fn handleStructFieldAccess(
        self: *Semantizer,
        ma: syn.StructFieldAccess,
        s: *Scope,
    ) SemErr!TypedExpr {
        const base = try self.visitNode(ma.struct_value.*, s);

        if (base.ty != .struct_type) return error.InvalidType;
        const st = base.ty.struct_type;

        var idx: ?u32 = null;
        var fty: sem.Type = undefined;
        for (st.fields, 0..) |f, i| {
            if (std.mem.eql(u8, f.name, ma.field_name)) {
                idx = @intCast(i);
                fty = f.ty;
                break;
            }
        }
        if (idx == null) return error.SymbolNotFound;

        const fa = try self.allocator.create(sem.StructFieldAccess);
        fa.* = .{
            .struct_value = base.node,
            .field_name = ma.field_name,
            .field_index = idx.?,
        };

        const n = try self.makeNode(undefined, .{ .struct_field_access = fa }, null);
        return .{ .node = n, .ty = fty };
    }

    //────────────────────────────────────────────────────  AUX STRUCT TYPES
    fn structTypeFromLiteral(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!*sem.StructType {
        var buf = std.ArrayList(sem.StructTypeField).init(self.allocator.*);

        for (st.fields) |f| {
            const ty = try self.resolveType(f.type.?, s);
            const dvp = if (f.default_value) |n|
                (try self.visitNode(n.*, s)).node
            else
                null;

            try buf.append(.{ .name = f.name, .ty = ty, .default_value = dvp });
        }

        const slice = try buf.toOwnedSlice();
        buf.deinit();

        const ptr = try self.allocator.create(sem.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    fn structTypeFromLiteralWithSubst(
        self: *Semantizer,
        st: syn.StructTypeLiteral,
        s: *Scope,
        subst: *std.StringHashMap(sem.Type),
    ) SemErr!*sem.StructType {
        var buf = std.ArrayList(sem.StructTypeField).init(self.allocator.*);
        for (st.fields) |f| {
            const ty = try self.resolveTypeWithSubst(f.type.?, s, subst);
            const dvp = if (f.default_value) |n|
                (try self.visitNode(n.*, s)).node
            else
                null;
            try buf.append(.{ .name = f.name, .ty = ty, .default_value = dvp });
        }
        const slice = try buf.toOwnedSlice();
        buf.deinit();
        const ptr = try self.allocator.create(sem.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    fn structTypeFromVal(
        self: *Semantizer,
        sv: syn.StructValueLiteral,
        s: *Scope,
    ) SemErr!*sem.StructType {
        var buf = std.ArrayList(sem.StructTypeField).init(self.allocator.*);

        for (sv.fields) |f| {
            const tv = try self.visitNode(f.value.*, s);
            try buf.append(.{ .name = f.name, .ty = tv.ty, .default_value = null });
        }

        const slice = try buf.toOwnedSlice();
        buf.deinit();

        const ptr = try self.allocator.create(sem.StructType);
        ptr.* = .{ .fields = slice };
        return ptr;
    }

    //──────────────────────────────────────────────────── FUNCTION CALL
    fn handleCall(
        self: *Semantizer,
        call: syn.FunctionCall,
        s: *Scope,
    ) SemErr!TypedExpr {
        const tv_in = try self.visitNode(call.input.*, s);
        if (s.lookupType(call.callee)) |type_decl| {
            return self.handleTypeInitializer(call, tv_in, type_decl, s);
        }

        if (tv_in.ty != .struct_type) return error.InvalidType;

        var chosen: *sem.FunctionDeclaration = undefined;
        if (call.type_arguments_struct) |stargs| {
            chosen = try self.instantiateGenericNamed(call.callee, stargs, s);
        } else if (call.type_arguments) |targs| {
            chosen = try self.instantiateGeneric(call.callee, targs, s);
        } else {
            chosen = self.resolveOverload(call.callee, tv_in.ty, s) catch |err| switch (err) {
                error.SymbolNotFound => {
                    if (tv_in.ty == .struct_type) {
                        const actual_sig = try self.formatCallInput(tv_in.ty.struct_type, s);
                        const available = try self.collectFunctionSignatures(call.callee, s);
                        defer {
                            self.allocator.free(actual_sig);
                            self.allocator.free(available);
                        }
                        try self.diags.add(
                            call.input.*.location,
                            .semantic,
                            "no overload of '{s}' accepts arguments {s}. Available signatures:\n{s}",
                            .{ call.callee, actual_sig, available },
                        );
                    } else {
                        try self.diags.add(
                            call.input.*.location,
                            .semantic,
                            "no overload of '{s}' matches the provided arguments",
                            .{call.callee},
                        );
                    }
                    return error.Reported;
                },
                else => return err,
            };
        }

        const fc_ptr = try self.allocator.create(sem.FunctionCall);
        fc_ptr.* = .{ .callee = chosen, .input = tv_in.node };

        const n = try self.makeNode(undefined, .{ .function_call = fc_ptr }, s);

        const result_ty: sem.Type = if (chosen.isExtern())
            switch (chosen.output.fields.len) {
                0 => .{ .builtin = .Any },
                1 => chosen.output.fields[0].ty,
                else => .{ .struct_type = &chosen.output },
            }
        else if (chosen.output.fields.len == 0)
            .{ .builtin = .Any }
        else
            .{ .struct_type = &chosen.output };

        return .{ .node = n, .ty = result_ty };
    }

    fn handleTypeInitializer(
        self: *Semantizer,
        call: syn.FunctionCall,
        tv_in: TypedExpr,
        type_decl: *sem.TypeDeclaration,
        s: *Scope,
    ) SemErr!TypedExpr {
        if (tv_in.ty != .struct_type) {
            try self.diags.add(
                call.input.*.location,
                .semantic,
                "expected struct literal arguments when constructing type '{s}'",
                .{call.callee},
            );
            return error.Reported;
        }

        var init_fields = std.ArrayList(sem.StructTypeField).init(self.allocator.*);
        defer init_fields.deinit();

        const ptr_child = try self.allocator.create(sem.Type);
        ptr_child.* = type_decl.ty;

        const ptr_info = try self.allocator.create(sem.PointerType);
        ptr_info.* = .{ .mutability = .read_write, .child = ptr_child };

        try init_fields.append(.{ .name = "p", .ty = .{ .pointer_type = ptr_info }, .default_value = null });

        const user_struct = tv_in.ty.struct_type;
        for (user_struct.fields) |fld| {
            try init_fields.append(.{ .name = fld.name, .ty = fld.ty, .default_value = null });
        }

        const init_struct = try self.allocator.create(sem.StructType);
        init_struct.* = .{ .fields = try init_fields.toOwnedSlice() };

        const init_input_ty: sem.Type = .{ .struct_type = init_struct };

        const init_fn = self.resolveOverload("init", init_input_ty, s) catch |err| switch (err) {
            error.SymbolNotFound => {
                const actual_sig = try self.formatCallInput(user_struct, s);
                const available = try self.collectFunctionSignatures("init", s);
                defer {
                    self.allocator.free(actual_sig);
                    self.allocator.free(available);
                }
                try self.diags.add(
                    call.input.*.location,
                    .semantic,
                    "failed to initialize type '{s}': no 'init' overload accepts arguments {s}. Available overloads:\n{s}",
                    .{ call.callee, actual_sig, available },
                );
                return error.Reported;
            },
            error.AmbiguousOverload => {
                const candidates_result = self.buildOverloadCandidatesString("init", init_input_ty, s) catch null;
                const candidates = candidates_result orelse "";
                defer if (candidates_result) |owned| self.allocator.free(owned);
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

        const type_init = sem.TypeInitializer{
            .type_decl = type_decl,
            .init_fn = init_fn,
            .args = tv_in.node,
        };

        const init_node = try self.makeNode(undefined, .{ .type_initializer = type_init }, null);
        return .{ .node = init_node, .ty = type_decl.ty };
    }

    fn resolveOverload(_: *Semantizer, name: []const u8, in_ty: sem.Type, s: *Scope) SemErr!*sem.FunctionDeclaration {
        var best: ?*sem.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    const expected: sem.Type = .{ .struct_type = &cand.input };
                    if (!typesCompatible(expected, in_ty)) continue;

                    const score = specificityScore(expected, in_ty);
                    if (best == null or score < best_score) {
                        best = cand;
                        best_score = score;
                        ambiguous = false;
                    } else if (score == best_score) {
                        // ambiguous with same specificity
                        ambiguous = true;
                    }
                }
            }
        }
        if (best == null) return error.SymbolNotFound;
        if (ambiguous) return error.AmbiguousOverload;
        return best.?;
    }

    fn instantiateGenericNamed(
        self: *Semantizer,
        name: []const u8,
        stargs: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!*sem.FunctionDeclaration {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    var subst = std.StringHashMap(sem.Type).init(self.allocator.*);
                    defer subst.deinit();

                    var ok: bool = true;
                    for (tmpl.param_names) |pname| {
                        var found: bool = false;
                        for (stargs.fields) |fld| {
                            if (std.mem.eql(u8, fld.name, pname)) {
                                const resolved = try self.resolveTypeWithSubst(fld.type.?, s, &subst);
                                try subst.put(pname, resolved);
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

                    const in_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.input, s, &subst);
                    const out_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.output, s, &subst);

                    if (s.functions.getPtr(name)) |fns| {
                        for (fns.items) |cand| {
                            if (typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = in_struct_ptr }))
                                return cand;
                        }
                    }

                    var child = try Scope.init(self.allocator, s, null);
                    var it = subst.iterator();
                    while (it.next()) |entry| {
                        const td = try self.allocator.create(sem.TypeDeclaration);
                        td.* = .{ .name = entry.key_ptr.*, .ty = entry.value_ptr.* };
                        try child.types.put(entry.key_ptr.*, td);
                    }
                    for (in_struct_ptr.fields) |fld| {
                        const bd = try self.allocator.create(sem.BindingDeclaration);
                        bd.* = .{ .name = fld.name, .mutability = .variable, .ty = fld.ty, .initialization = null };
                        try child.bindings.put(fld.name, bd);
                    }
                    for (out_struct_ptr.fields) |fld| {
                        const bd = try self.allocator.create(sem.BindingDeclaration);
                        bd.* = .{ .name = fld.name, .mutability = .variable, .ty = fld.ty, .initialization = null };
                        try child.bindings.put(fld.name, bd);
                    }

                    var body_cb: ?*sem.CodeBlock = null;
                    if (tmpl.body) |body_node| {
                        const body_te = try self.visitNode(body_node.*, &child);
                        body_cb = body_te.node.content.code_block;
                    }

                    const fn_ptr = try self.allocator.create(sem.FunctionDeclaration);
                    fn_ptr.* = .{
                        .name = tmpl.name,
                        .location = tmpl.location,
                        .input = in_struct_ptr.*,
                        .output = out_struct_ptr.*,
                        .body = body_cb,
                    };
                    if (s.functions.getPtr(name)) |list_ptr2| {
                        try list_ptr2.append(fn_ptr);
                    } else {
                        var lst = std.ArrayList(*sem.FunctionDeclaration).init(self.allocator.*);
                        try lst.append(fn_ptr);
                        try s.functions.put(name, lst);
                    }
                    const n = try self.makeNode(tmpl.location, .{ .function_declaration = fn_ptr }, null);
                    try self.root_list.append(n);
                    self.clearDeferred(&child);
                    return fn_ptr;
                }
            }
        }
        return error.SymbolNotFound;
    }

    fn instantiateGeneric(
        self: *Semantizer,
        name: []const u8,
        type_args_syn: []const syn.Type,
        s: *Scope,
    ) SemErr!*sem.FunctionDeclaration {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    if (tmpl.param_names.len != type_args_syn.len) continue;

                    var subst = std.StringHashMap(sem.Type).init(self.allocator.*);
                    defer subst.deinit();
                    var i: usize = 0;
                    while (i < tmpl.param_names.len) : (i += 1) {
                        const resolved = try self.resolveTypeWithSubst(type_args_syn[i], s, &subst);
                        try subst.put(tmpl.param_names[i], resolved);
                    }

                    const in_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.input, s, &subst);
                    const out_struct_ptr = try self.structTypeFromLiteralWithSubst(tmpl.output, s, &subst);

                    // Check if already instantiated
                    if (s.functions.getPtr(name)) |fns| {
                        for (fns.items) |cand| {
                            if (typesExactlyEqual(.{ .struct_type = &cand.input }, .{ .struct_type = in_struct_ptr }))
                                return cand;
                        }
                    }

                    // Create child scope with type aliases
                    var child = try Scope.init(self.allocator, s, null);
                    var it = subst.iterator();
                    while (it.next()) |entry| {
                        const td = try self.allocator.create(sem.TypeDeclaration);
                        td.* = .{ .name = entry.key_ptr.*, .ty = entry.value_ptr.* };
                        try child.types.put(entry.key_ptr.*, td);
                    }

                    // Register params in child scope
                    for (in_struct_ptr.fields) |fld| {
                        const bd = try self.allocator.create(sem.BindingDeclaration);
                        bd.* = .{ .name = fld.name, .mutability = .variable, .ty = fld.ty, .initialization = null };
                        try child.bindings.put(fld.name, bd);
                    }
                    for (out_struct_ptr.fields) |fld| {
                        const bd = try self.allocator.create(sem.BindingDeclaration);
                        bd.* = .{ .name = fld.name, .mutability = .variable, .ty = fld.ty, .initialization = null };
                        try child.bindings.put(fld.name, bd);
                    }

                    var body_cb: ?*sem.CodeBlock = null;
                    if (tmpl.body) |body_node| {
                        const body_te = try self.visitNode(body_node.*, &child);
                        body_cb = body_te.node.content.code_block;
                    }

                    const fn_ptr = try self.allocator.create(sem.FunctionDeclaration);
                    fn_ptr.* = .{
                        .name = tmpl.name,
                        .location = tmpl.location,
                        .input = in_struct_ptr.*,
                        .output = out_struct_ptr.*,
                        .body = body_cb,
                    };

                    if (s.functions.getPtr(name)) |list_ptr2| {
                        try list_ptr2.append(fn_ptr);
                    } else {
                        var lst = std.ArrayList(*sem.FunctionDeclaration).init(self.allocator.*);
                        try lst.append(fn_ptr);
                        try s.functions.put(name, lst);
                    }
                    const n = try self.makeNode(tmpl.location, .{ .function_declaration = fn_ptr }, null);
                    // Always add instantiated functions at the root for codegen order
                    try self.root_list.append(n);
                    self.clearDeferred(&child);
                    return fn_ptr;
                }
            }
        }
        return error.SymbolNotFound;
    }

    fn instantiateGenericTypeNamed(
        self: *Semantizer,
        name: []const u8,
        stargs: syn.StructTypeLiteral,
        s: *Scope,
    ) SemErr!*sem.StructType {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.generic_types.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |tmpl| {
                    var subst = std.StringHashMap(sem.Type).init(self.allocator.*);
                    defer subst.deinit();

                    var ok: bool = true;
                    for (tmpl.param_names) |pname| {
                        var found: bool = false;
                        for (stargs.fields) |fld| {
                            if (std.mem.eql(u8, fld.name, pname)) {
                                const resolved = try self.resolveTypeWithSubst(fld.type.?, s, &subst);
                                try subst.put(pname, resolved);
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

                    const st_ptr = try self.structTypeFromLiteralWithSubst(tmpl.body, s, &subst);
                    return st_ptr;
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
    ) SemErr!TypedExpr {
        const lhs = try self.visitNode(bo.left.*, s);
        const rhs = try self.visitNode(bo.right.*, s);

        const bin = try self.allocator.create(sem.BinaryOperation);
        bin.* = .{ .operator = bo.operator, .left = lhs.node, .right = rhs.node };

        const n = try self.makeNode(undefined, .{ .binary_operation = bin.* }, s);
        return .{ .node = n, .ty = lhs.ty };
    }

    //──────────────────────────────────────────────────── COMPARISON
    fn handleComparison(
        self: *Semantizer,
        c: syn.Comparison,
        s: *Scope,
    ) SemErr!TypedExpr {
        const lhs = try self.visitNode(c.left.*, s);
        const rhs = try self.visitNode(c.right.*, s);

        const cmp_ptr = try self.allocator.create(sem.Comparison);
        cmp_ptr.* = .{
            .operator = c.operator,
            .left = lhs.node,
            .right = rhs.node,
        };

        const node_ptr = try self.makeNode(undefined, .{ .comparison = cmp_ptr.* }, s);
        return .{ .node = node_ptr, .ty = .{ .builtin = .Bool } };
    }

    //──────────────────────────────────────────────────── RETURN
    fn handleReturn(
        self: *Semantizer,
        r: syn.ReturnStatement,
        s: *Scope,
    ) SemErr!TypedExpr {
        const e = if (r.expression) |ex| (try self.visitNode(ex.*, s)) else null;

        const rs = try self.allocator.create(sem.ReturnStatement);
        rs.* = .{ .expression = if (e) |te| te.node else null };

        const n = try self.makeNode(undefined, .{ .return_statement = rs }, s);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── IF
    fn handleIf(
        self: *Semantizer,
        ifs: syn.IfStatement,
        s: *Scope,
    ) SemErr!TypedExpr {
        const start_len = s.nodes.items.len;

        const cond = try self.visitNode(ifs.condition.*, s);
        const then_te = try self.visitNode(ifs.then_block.*, s);

        const else_cb = if (ifs.else_block) |eb|
            (try self.visitNode(eb.*, s)).node.content.code_block
        else
            null;

        s.nodes.items.len = start_len;

        const if_ptr = try self.allocator.create(sem.IfStatement);
        if_ptr.* = .{
            .condition = cond.node,
            .then_block = then_te.node.content.code_block,
            .else_block = else_cb,
        };

        const n = try self.makeNode(undefined, .{ .if_statement = if_ptr }, s);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── ADDRESS OF
    fn handleAddressOf(
        self: *Semantizer,
        addr: syn.AddressOf,
        s: *Scope,
    ) SemErr!TypedExpr {
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

        const child = try self.allocator.create(sem.Type);
        child.* = te.ty;

        const ptr_ty = try self.allocator.create(sem.PointerType);
        ptr_ty.* = .{ .mutability = addr.mutability, .child = child };

        const out_ty: sem.Type = .{ .pointer_type = ptr_ty };

        const addr_node = try self.makeNode(undefined, .{ .address_of = te.node }, null);
        return .{ .node = addr_node, .ty = out_ty };
    }

    fn handleDefer(
        self: *Semantizer,
        expr: *syn.STNode,
        s: *Scope,
    ) SemErr!TypedExpr {
        const start_len = s.nodes.items.len;
        const te = try self.visitNode(expr.*, s);

        if (s.nodes.items.len > start_len) {
            const new_nodes = s.nodes.items[start_len..];
            try self.registerDefer(s, new_nodes);
            s.nodes.items.len = start_len;
        }

        return .{ .node = te.node, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── DEREFERENCE
    fn handleDereference(
        self: *Semantizer,
        inner: *syn.STNode,
        s: *Scope,
    ) SemErr!TypedExpr {
        const te = try self.visitNode(inner.*, s);

        if (te.ty != .pointer_type) {
            const ty_str = try self.formatType(te.ty, s);
            defer self.allocator.free(ty_str);
            try self.diags.add(
                inner.*.location,
                .semantic,
                "cannot dereference value of type '{s}'; expected a pointer",
                .{ty_str},
            );
            return error.Reported;
        }
        const ptr_info_ptr = te.ty.pointer_type;
        const ptr_info = ptr_info_ptr.*;
        const base_ty = ptr_info.child.*; // T

        const der_ptr = try self.allocator.create(sem.Dereference);
        der_ptr.* = .{ .pointer = te.node, .ty = base_ty, .pointer_type = ptr_info_ptr };

        const n = try self.makeNode(undefined, .{ .dereference = der_ptr.* }, null);
        return .{ .node = n, .ty = base_ty };
    }

    //────────────────────────────────────────────────── POINTER ASSIGNMENT
    fn handlePointerAssignment(
        self: *Semantizer,
        pa: syn.PointerAssignment,
        s: *Scope,
    ) SemErr!TypedExpr {
        const rhs = try self.visitNode(pa.value.*, s);

        if (pa.target.*.content != .dereference) return error.InvalidType;

        const tgt_te = try self.visitNode(pa.target.*, s);
        const deref_sg = tgt_te.node.content.dereference;

        if (deref_sg.pointer_type.*.mutability != .read_write) {
            const ptr_ty: sem.Type = .{ .pointer_type = deref_sg.pointer_type };
            const ptr_str = try self.formatType(ptr_ty, s);
            defer self.allocator.free(ptr_str);
            try self.diags.add(
                pa.target.*.location,
                .semantic,
                "cannot assign through pointer '{s}' because it is read-only; use '$&' when acquiring it",
                .{ptr_str},
            );
            return error.Reported;
        }

        if (!typesStructurallyEqual(deref_sg.ty, rhs.ty)) {
            const expected = try self.formatType(deref_sg.ty, s);
            const actual = try self.formatType(rhs.ty, s);
            defer {
                self.allocator.free(expected);
                self.allocator.free(actual);
            }
            try self.diags.add(
                pa.value.*.location,
                .semantic,
                "cannot assign value of type '{s}' to location of type '{s}'",
                .{ actual, expected },
            );
            return error.Reported;
        }

        const n = try self.makeNode(
            undefined,
            .{ .pointer_assignment = .{
                .pointer = deref_sg.pointer,
                .value = rhs.node,
            } },
            s,
        );
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── HELPERS
    fn makeNode(
        self: *Semantizer,
        loc: tok.Location,
        content: sem.Content,
        scope: ?*Scope,
    ) !*sem.SGNode {
        const n = try self.allocator.create(sem.SGNode);
        n.* = .{
            .location = loc, // de momento ‘undefined’ en la mayoría de llamadas
            .content = content,
        };
        if (scope) |s| try s.nodes.append(n);
        return n;
    }

    fn resolveType(self: *Semantizer, t: syn.Type, s: *Scope) !sem.Type {
        return switch (t) {
            .type_name => |id| blk: {
                if (builtinFromName(id)) |bt|
                    break :blk .{ .builtin = bt };
                // If it's an abstract, require a defaultsto to use as a type
                if (self.lookupAbstractInfo(s, id)) |_| {
                    if (self.lookupAbstractDefault(s, id)) |def_entry|
                        break :blk def_entry.ty
                    else
                        break :blk error.AbstractNeedsDefault;
                }
                if (s.lookupType(id)) |td|
                    break :blk td.ty;
                break :blk error.UnknownType;
            },
            .generic_type_instantiation => |g| blk_g: {
                const st_ptr = try self.instantiateGenericTypeNamed(g.base_name, g.args, s);
                break :blk_g .{ .struct_type = st_ptr };
            },
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveType(ptr_info.child.*, s);
                const child = try self.allocator.create(sem.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sem.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
        };
    }

    fn resolveTypeWithSubst(self: *Semantizer, t: syn.Type, s: *Scope, subst: *std.StringHashMap(sem.Type)) !sem.Type {
        return switch (t) {
            .type_name => |id| blk: {
                if (subst.get(id)) |mapped| break :blk mapped;
                break :blk try self.resolveType(t, s);
            },
            .generic_type_instantiation => |g| blk_g: {
                // For now, ignore outer substitutions for base_name; stargs are resolved inside
                const st_ptr = try self.instantiateGenericTypeNamed(g.base_name, g.args, s);
                break :blk_g .{ .struct_type = st_ptr };
            },
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteralWithSubst(st, s, subst) },
            .pointer_type => |ptr_info| blk: {
                const inner_ty = try self.resolveTypeWithSubst(ptr_info.child.*, s, subst);
                const child = try self.allocator.create(sem.Type);
                child.* = inner_ty;

                const sem_ptr = try self.allocator.create(sem.PointerType);
                sem_ptr.* = .{
                    .mutability = ptr_info.mutability,
                    .child = child,
                };

                break :blk .{ .pointer_type = sem_ptr };
            },
        };
    }

    fn lookupAbstractDefault(_: *Semantizer, s: *Scope, name: []const u8) ?AbstractDefaultEntry {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.abstract_defaults.get(name)) |def| return def;
        }
        return null;
    }

    fn builtinFromName(name: []const u8) ?sem.BuiltinType {
        return std.meta.stringToEnum(sem.BuiltinType, name);
    }

    fn buildOverloadCandidatesString(self: *Semantizer, name: []const u8, in_ty: sem.Type, s: *Scope) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator.*);
        var cur: ?*Scope = s;
        var first: bool = true;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    const expected: sem.Type = .{ .struct_type = &cand.input };
                    if (!typesCompatible(expected, in_ty)) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try self.appendFunctionSignature(&buf, cand, s);
                    try buf.appendSlice("  [file: ");
                    try buf.appendSlice(cand.location.file);
                    try buf.appendSlice(":");
                    try buf.appendSlice(std.fmt.allocPrint(self.allocator.*, "{d}:{d}", .{ cand.location.line, cand.location.column }) catch "");
                    try buf.appendSlice("]");
                }
            }
        }
        return try buf.toOwnedSlice();
    }

    fn appendFunctionSignature(self: *Semantizer, buf: *std.ArrayList(u8), f: *const sem.FunctionDeclaration, s: *Scope) !void {
        try buf.appendSlice(f.name);
        try buf.appendSlice(" (");
        var i: usize = 0;
        while (i < f.input.fields.len) : (i += 1) {
            const fld = f.input.fields[i];
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(fld.name);
            try buf.appendSlice(": ");
            try self.appendTypePretty(buf, fld.ty, s);
        }
        try buf.appendSlice(") -> (");
        i = 0;
        while (i < f.output.fields.len) : (i += 1) {
            const ofld = f.output.fields[i];
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(ofld.name);
            try buf.appendSlice(": ");
            try self.appendTypePretty(buf, ofld.ty, s);
        }
        try buf.appendSlice(")");
    }

    fn appendType(self: *Semantizer, buf: *std.ArrayList(u8), t: sem.Type) !void {
        switch (t) {
            .builtin => |bt| {
                const s = @tagName(bt);
                try buf.appendSlice(s);
            },
            .pointer_type => |ptr_info_ptr| {
                const ptr_info = ptr_info_ptr.*;
                const prefix = if (ptr_info.mutability == .read_write) "$&" else "&";
                try buf.appendSlice(prefix);
                try self.appendType(buf, ptr_info.child.*);
            },
            .struct_type => |st| {
                try buf.appendSlice("{");
                var i: usize = 0;
                while (i < st.fields.len) : (i += 1) {
                    const fld = st.fields[i];
                    if (i != 0) try buf.appendSlice(", ");
                    try buf.appendSlice(".");
                    try buf.appendSlice(fld.name);
                    try buf.appendSlice(": ");
                    try self.appendType(buf, fld.ty);
                }
                try buf.appendSlice("}");
            },
        }
    }

    fn appendTypePretty(self: *Semantizer, buf: *std.ArrayList(u8), t: sem.Type, s: *Scope) !void {
        if (self.typeNameFor(s, t)) |nm| {
            try buf.appendSlice(nm);
            return;
        }
        switch (t) {
            .builtin => |bt| {
                const sname = @tagName(bt);
                try buf.appendSlice(sname);
            },
            .pointer_type => |ptr_info_ptr| {
                const ptr_info = ptr_info_ptr.*;
                const prefix = if (ptr_info.mutability == .read_write) "$&" else "&";
                try buf.appendSlice(prefix);
                try self.appendTypePretty(buf, ptr_info.child.*, s);
            },
            .struct_type => |_| {
                // Fallback: avoid expanding anonymous structs in this context
                try buf.appendSlice("{...}");
            },
        }
    }

    fn formatType(self: *Semantizer, t: sem.Type, s: *Scope) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator.*);
        errdefer buf.deinit();
        try self.appendTypePretty(&buf, t, s);
        return try buf.toOwnedSlice();
    }

    fn formatCallInput(self: *Semantizer, st: *const sem.StructType, s: *Scope) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator.*);
        errdefer buf.deinit();

        try buf.appendSlice("(");
        var i: usize = 0;
        while (i < st.fields.len) : (i += 1) {
            const fld = st.fields[i];
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(fld.name);
            try buf.appendSlice(": ");
            try self.appendTypePretty(&buf, fld.ty, s);
        }
        try buf.appendSlice(")");

        return try buf.toOwnedSlice();
    }

    fn collectFunctionSignatures(self: *Semantizer, name: []const u8, s: *Scope) ![]u8 {
        var buf = std.ArrayList(u8).init(self.allocator.*);
        errdefer buf.deinit();

        var cur: ?*Scope = s;
        var first = true;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try self.appendFunctionSignature(&buf, cand, s);
                }
            }
        }

        if (first) {
            try buf.appendSlice("  (none)");
        }

        return try buf.toOwnedSlice();
    }

    fn typeNameFor(self: *Semantizer, s: *Scope, t: sem.Type) ?[]const u8 {
        _ = self;
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            var it = sc.types.iterator();
            while (it.next()) |entry| {
                const td = entry.value_ptr.*;
                if (typesExactlyEqual(td.ty, t)) return td.name;
            }
        }
        return null;
    }

    fn registerDefer(self: *Semantizer, s: *Scope, nodes: []const *sem.SGNode) !void {
        if (nodes.len == 0) return;
        const copy = try self.allocator.alloc(*sem.SGNode, nodes.len);
        std.mem.copyForwards(*sem.SGNode, copy, nodes);
        try s.deferred.append(.{ .nodes = copy });
    }

    fn clearDeferred(self: *Semantizer, s: *Scope) void {
        for (s.deferred.items) |group| self.allocator.free(group.nodes);
        s.deferred.deinit();
    }

    fn findDeinit(_: *Semantizer, ty: sem.Type, s: *Scope) ?*sem.FunctionDeclaration {
        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr("deinit")) |list_ptr| {
                for (list_ptr.items) |cand| {
                    if (cand.input.fields.len == 0) continue;
                    const first = cand.input.fields[0];
                    if (first.ty != .pointer_type) continue;
                    const ptr_info = first.ty.pointer_type.*;
                    if (ptr_info.mutability != .read_write) continue;
                    const pointee = ptr_info.child.*;
                    if (typesExactlyEqual(pointee, ty)) return cand;
                }
            }
        }
        return null;
    }

    fn maybeScheduleAutoDeinit(
        self: *Semantizer,
        binding: *sem.BindingDeclaration,
        loc: tok.Location,
        s: *Scope,
    ) !void {
        if (s.parent == null) return;
        const deinit_fn = self.findDeinit(binding.ty, s) orelse return;
        if (deinit_fn.input.fields.len != 1) return;

        const binding_use = try self.makeNode(loc, .{ .binding_use = binding }, null);

        const addr_node = try self.makeNode(loc, .{ .address_of = binding_use }, null);

        const arg_fields = try self.allocator.alloc(sem.StructValueLiteralField, 1);
        arg_fields[0] = .{ .name = deinit_fn.input.fields[0].name, .value = addr_node };

        const args_struct = try self.allocator.create(sem.StructValueLiteral);
        args_struct.* = .{
            .fields = arg_fields,
            .ty = .{ .struct_type = &deinit_fn.input },
        };

        const args_node = try self.makeNode(loc, .{ .struct_value_literal = args_struct }, null);

        const fc_ptr = try self.allocator.create(sem.FunctionCall);
        fc_ptr.* = .{ .callee = deinit_fn, .input = args_node };

        const call_node = try self.makeNode(loc, .{ .function_call = fc_ptr }, null);
        try self.registerDefer(s, &[_]*sem.SGNode{call_node});
    }
};

//────────────────────────────────────────────────────────────────────── BUILDER SCOPE
// Generic function template used for monomorphization
const GenericTemplate = struct {
    name: []const u8,
    location: tok.Location,
    param_names: []const []const u8,
    input: syn.StructTypeLiteral,
    output: syn.StructTypeLiteral,
    body: ?*syn.STNode,
};

// Generic type template for monomorphization of named struct types
const GenericTypeTemplate = struct {
    name: []const u8,
    location: tok.Location,
    param_names: []const []const u8,
    body: syn.StructTypeLiteral,
};
// Abstract typing support
const AbstractFunctionReqSem = struct {
    name: []const u8,
    input: sem.StructType,
    output: sem.StructType,
    // indices of input fields whose type was 'Self'
    input_self_indices: []const u32,
};

const AbstractInfo = struct {
    name: []const u8,
    requirements: []const AbstractFunctionReqSem,
};
const AbstractImplEntry = struct {
    ty: sem.Type,
    location: tok.Location,
};
const AbstractDefaultEntry = struct {
    ty: sem.Type,
    location: tok.Location,
};

const DeferredGroup = struct {
    nodes: []const *sem.SGNode,
};
const Scope = struct {
    parent: ?*Scope,
    allocator: *const std.mem.Allocator,

    nodes: std.ArrayList(*sem.SGNode),
    bindings: std.StringHashMap(*sem.BindingDeclaration),
    functions: std.StringHashMap(std.ArrayList(*sem.FunctionDeclaration)),
    types: std.StringHashMap(*sem.TypeDeclaration),
    abstracts: std.StringHashMap(*AbstractInfo),
    abstract_impls: std.StringHashMap(std.ArrayList(AbstractImplEntry)),
    abstract_defaults: std.StringHashMap(AbstractDefaultEntry),
    generic_functions: std.StringHashMap(std.ArrayList(GenericTemplate)),
    generic_types: std.StringHashMap(std.ArrayList(GenericTypeTemplate)),
    deferred: std.ArrayList(DeferredGroup),

    current_fn: ?*sem.FunctionDeclaration,

    fn init(
        a: *const std.mem.Allocator,
        p: ?*Scope,
        fnc: ?*sem.FunctionDeclaration,
    ) !Scope {
        return .{
            .parent = p,
            .allocator = a,
            .nodes = std.ArrayList(*sem.SGNode).init(a.*),
            .bindings = std.StringHashMap(*sem.BindingDeclaration).init(a.*),
            .functions = std.StringHashMap(std.ArrayList(*sem.FunctionDeclaration)).init(a.*),
            .types = std.StringHashMap(*sem.TypeDeclaration).init(a.*),
            .abstracts = std.StringHashMap(*AbstractInfo).init(a.*),
            .abstract_impls = std.StringHashMap(std.ArrayList(AbstractImplEntry)).init(a.*),
            .abstract_defaults = std.StringHashMap(AbstractDefaultEntry).init(a.*),
            .generic_functions = std.StringHashMap(std.ArrayList(GenericTemplate)).init(a.*),
            .generic_types = std.StringHashMap(std.ArrayList(GenericTypeTemplate)).init(a.*),
            .deferred = std.ArrayList(DeferredGroup).init(a.*),
            .current_fn = fnc,
        };
    }

    fn lookupBinding(self: *Scope, n: []const u8) ?*sem.BindingDeclaration {
        if (self.bindings.get(n)) |b| return b;
        if (self.parent) |p| return p.lookupBinding(n);
        return null;
    }

    // Deprecated: use resolveOverload in Semantizer instead.
    fn lookupFunction(self: *Scope, n: []const u8) ?*sem.FunctionDeclaration {
        if (self.functions.getPtr(n)) |lst| {
            if (lst.items.len > 0) return lst.items[0];
        }
        if (self.parent) |p| return p.lookupFunction(n);
        return null;
    }

    fn lookupType(self: *Scope, n: []const u8) ?*sem.TypeDeclaration {
        if (self.types.get(n)) |t| return t;
        if (self.parent) |p| return p.lookupType(n);
        return null;
    }
};

//──────────────────────────────────────────────────────────── TYPE EQUALITY HELPER
fn typesStructurallyEqual(a: sem.Type, b: sem.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },

        .struct_type => |ast| switch (b) {
            .builtin => false,

            .struct_type => |bst| blk: {
                // Keep for legacy: structural comparison of anonymous structs
                if (ast.fields.len != bst.fields.len) break :blk false;
                var i: usize = 0;
                while (i < ast.fields.len) : (i += 1) {
                    const fa = ast.fields[i];
                    const fb = bst.fields[i];
                    if (!std.mem.eql(u8, fa.name, fb.name)) break :blk false;
                    if (!typesStructurallyEqual(fa.ty, fb.ty)) break :blk false;
                }
                break :blk true;
            },

            .pointer_type => false,
        },

        .pointer_type => |apt_ptr| switch (b) {
            .pointer_type => |bpt_ptr| blk: {
                const apt = apt_ptr.*;
                const bpt = bpt_ptr.*;

                if (apt.mutability != bpt.mutability)
                    break :blk false;

                const sub_a = apt.child.*;
                const sub_b = bpt.child.*;

                if (isAny(sub_a) or isAny(sub_b)) break :blk true;

                break :blk typesStructurallyEqual(sub_a, sub_b);
            },
            else => false,
        },
    };
}

fn isAny(t: sem.Type) bool {
    return switch (t) {
        .builtin => |bt| bt == .Any,
        else => false,
    };
}

fn pointerMutabilityCompatible(expected: syn.PointerMutability, actual: syn.PointerMutability) bool {
    return switch (expected) {
        .read_only => true,
        .read_write => actual == .read_write,
    };
}

fn typesCompatible(expected: sem.Type, actual: sem.Type) bool {
    return switch (expected) {
        .builtin => |eb| switch (actual) {
            .builtin => |ab| eb == ab,
            else => false,
        },
        .struct_type => |est| switch (actual) {
            .struct_type => |ast| blk: {
                if (est.fields.len != ast.fields.len) break :blk false;
                var i: usize = 0;
                while (i < est.fields.len) : (i += 1) {
                    const ef = est.fields[i];
                    const af = ast.fields[i];
                    if (!typesCompatible(ef.ty, af.ty)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .pointer_type => |ept_ptr| switch (actual) {
            .pointer_type => |apt_ptr| blk: {
                const ept = ept_ptr.*;
                const apt = apt_ptr.*;

                if (!pointerMutabilityCompatible(ept.mutability, apt.mutability))
                    break :blk false;

                const expected_child = ept.child.*;
                const actual_child = apt.child.*;

                if (isAny(expected_child) or isAny(actual_child))
                    break :blk true;

                break :blk typesCompatible(expected_child, actual_child);
            },
            else => false,
        },
    };
}

// Strict type equality: no wildcards; pointer subtypes must match exactly.
fn typesExactlyEqual(a: sem.Type, b: sem.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },
        .struct_type => |ast| switch (b) {
            .struct_type => |bst| ast == bst, // nominal: same named type instance
            else => false,
        },
        .pointer_type => |apt_ptr| switch (b) {
            .pointer_type => |bpt_ptr| blk: {
                const apt = apt_ptr.*;
                const bpt = bpt_ptr.*;
                if (apt.mutability != bpt.mutability) break :blk false;
                break :blk typesExactlyEqual(apt.child.*, bpt.child.*);
            },
            else => false,
        },
    };
}

// Lower score = more specific. Assumes typesStructurallyEqual(expected, actual) already true.
fn specificityScore(expected: sem.Type, actual: sem.Type) u32 {
    return switch (expected) {
        .builtin => 0,
        .struct_type => |est| blk: {
            var sum: u32 = 0;
            const ast = actual.struct_type;
            var i: usize = 0;
            while (i < est.fields.len) : (i += 1) {
                const fe = est.fields[i];
                const fa = ast.fields[i];
                sum += specificityScore(fe.ty, fa.ty);
            }
            break :blk sum;
        },
        .pointer_type => |ept_ptr| blk2: {
            const apt_ptr = actual.pointer_type;
            const ept = ept_ptr.*;
            const apt = apt_ptr.*;

            if (ept.mutability != apt.mutability)
                break :blk2 5;

            const expected_child = ept.child.*;
            const actual_child = apt.child.*;

            if (isAny(expected_child) or isAny(actual_child))
                break :blk2 1;

            break :blk2 specificityScore(expected_child, actual_child);
        },
    };
}
