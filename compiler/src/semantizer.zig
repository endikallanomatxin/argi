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
    MissingReturnValue,
    NotYetImplemented,
    OutOfMemory,
    OptionalUnwrap,
    AmbiguousOverload,
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

        self.root_nodes = try self.root_list.toOwnedSlice();
        self.root_list.deinit();
        return self.root_nodes;
    }

    pub fn printSG(self: *Semantizer) void {
        std.debug.print("\nSEMANTIC GRAPH:\n", .{});
        for (self.root_nodes) |n| sgp.printNode(n, 0);
    }

    //────────────────────────────────────────────────────────────────── visitors
    fn visitNode(self: *Semantizer, n: syn.STNode, s: *Scope) SemErr!TypedExpr {
        return switch (n.content) {
            .symbol_declaration => |d| self.handleSymbolDecl(d, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error en la declaración del símbolo '{s}': {s}",
                    .{ d.name, @errorName(err) },
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
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in address-of operation: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .dereference => |p| self.handleDereference(p, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in dereference operation: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },

            .pointer_assignment => |pa| self.handlePointerAssignment(pa, s) catch |err| blk: {
                try self.diags.add(
                    n.location,
                    .semantic,
                    "error in pointer assignment: {s}",
                    .{@errorName(err)},
                );
                break :blk err;
            },
        };
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
                const ptr = try self.allocator.create(sem.Type);
                ptr.* = char_ty;

                ty = .{ .pointer_type = ptr };
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

        const slice = try child.nodes.toOwnedSlice();
        child.nodes.deinit();

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
        const n = try self.makeNode(undefined, .{ .binding_declaration = bd }, s);
        if (s.parent == null) try self.root_list.append(n);

        if (d.value) |v| bd.initialization = (try self.visitNode(v.*, s)).node;

        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── TYPE DECLARATION
    fn handleTypeDecl(
        self: *Semantizer,
        d: syn.TypeDeclaration,
        s: *Scope,
    ) SemErr!TypedExpr {
        const st_lit = d.value.*.content.struct_type_literal;
        const st_ptr = try self.structTypeFromLiteral(st_lit, s);

        const td = try self.allocator.create(sem.TypeDeclaration);
        td.* = .{ .name = d.name, .ty = .{ .struct_type = st_ptr } };

        try s.types.put(d.name, td);
        const n = try self.makeNode(undefined, .{ .type_declaration = td }, s);
        if (s.parent == null) try self.root_list.append(n);
        return .{ .node = n, .ty = .{ .builtin = .Any } };
    }

    //──────────────────────────────────────────────────── FUNCTION DECLARATION
    fn handleFuncDecl(
        self: *Semantizer,
        f: syn.FunctionDeclaration,
        p: *Scope,
        loc: tok.Location,
    ) SemErr!TypedExpr {
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
        if (tv_in.ty != .struct_type) return error.InvalidType;

        const chosen = try self.resolveOverload(call.callee, tv_in.ty, s);

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

    fn resolveOverload(_: *Semantizer, name: []const u8, in_ty: sem.Type, s: *Scope) SemErr!*sem.FunctionDeclaration {
        var best: ?*sem.FunctionDeclaration = null;
        var best_score: u32 = std.math.maxInt(u32);
        var ambiguous = false;

        var cur: ?*Scope = s;
        while (cur) |sc| : (cur = sc.parent) {
            if (sc.functions.getPtr(name)) |list_ptr| {
                for (list_ptr.items) |cand| {
                    const expected: sem.Type = .{ .struct_type = &cand.input };
                    if (!typesStructurallyEqual(expected, in_ty)) continue;

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
        inner: *syn.STNode,
        s: *Scope,
    ) SemErr!TypedExpr {
        const te = try self.visitNode(inner.*, s);

        if (te.node.content != .binding_use)
            return error.InvalidType;

        const ptr_ty = try self.allocator.create(sem.Type);
        ptr_ty.* = te.ty;

        const out_ty: sem.Type = .{ .pointer_type = ptr_ty };

        const addr_node = try self.makeNode(undefined, .{ .address_of = te.node }, null);
        return .{ .node = addr_node, .ty = out_ty };
    }

    //──────────────────────────────────────────────────── DEREFERENCE
    fn handleDereference(
        self: *Semantizer,
        inner: *syn.STNode,
        s: *Scope,
    ) SemErr!TypedExpr {
        const te = try self.visitNode(inner.*, s);

        if (te.ty != .pointer_type) return error.InvalidType;
        const base_ty = te.ty.pointer_type.*; // T

        const der_ptr = try self.allocator.create(sem.Dereference);
        der_ptr.* = .{ .pointer = te.node, .ty = base_ty };

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

        if (!typesStructurallyEqual(deref_sg.ty, rhs.ty))
            return error.InvalidType;

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
                if (s.lookupType(id)) |td|
                    break :blk td.ty;
                break :blk error.InvalidType;
            },
            .struct_type_literal => |st| .{ .struct_type = try self.structTypeFromLiteral(st, s) },
            .pointer_type => |inner| blk: {
                const inner_ty = try self.resolveType(inner.*, s);
                const ptr = try self.allocator.create(sem.Type);
                ptr.* = inner_ty;
                break :blk .{ .pointer_type = ptr };
            },
        };
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
                    if (!typesStructurallyEqual(expected, in_ty)) continue;
                    if (!first) try buf.appendSlice("\n");
                    first = false;
                    try buf.appendSlice("  - ");
                    try self.appendFunctionSignature(&buf, cand);
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

    fn appendFunctionSignature(self: *Semantizer, buf: *std.ArrayList(u8), f: *const sem.FunctionDeclaration) !void {
        try buf.appendSlice(f.name);
        try buf.appendSlice(" (");
        var i: usize = 0;
        while (i < f.input.fields.len) : (i += 1) {
            const fld = f.input.fields[i];
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(fld.name);
            try buf.appendSlice(": ");
            try self.appendType(buf, fld.ty);
        }
        try buf.appendSlice(") -> (");
        i = 0;
        while (i < f.output.fields.len) : (i += 1) {
            const ofld = f.output.fields[i];
            if (i != 0) try buf.appendSlice(", ");
            try buf.appendSlice(".");
            try buf.appendSlice(ofld.name);
            try buf.appendSlice(": ");
            try self.appendType(buf, ofld.ty);
        }
        try buf.appendSlice(")");
    }

    fn appendType(self: *Semantizer, buf: *std.ArrayList(u8), t: sem.Type) !void {
        switch (t) {
            .builtin => |bt| {
                const s = @tagName(bt);
                try buf.appendSlice(s);
            },
            .pointer_type => |sub| {
                try buf.appendSlice("&");
                try self.appendType(buf, sub.*);
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
};

//────────────────────────────────────────────────────────────────────── BUILDER SCOPE
const Scope = struct {
    parent: ?*Scope,

    nodes: std.ArrayList(*sem.SGNode),
    bindings: std.StringHashMap(*sem.BindingDeclaration),
    functions: std.StringHashMap(std.ArrayList(*sem.FunctionDeclaration)),
    types: std.StringHashMap(*sem.TypeDeclaration),

    current_fn: ?*sem.FunctionDeclaration,

    fn init(
        a: *const std.mem.Allocator,
        p: ?*Scope,
        fnc: ?*sem.FunctionDeclaration,
    ) !Scope {
        return .{
            .parent = p,
            .nodes = std.ArrayList(*sem.SGNode).init(a.*),
            .bindings = std.StringHashMap(*sem.BindingDeclaration).init(a.*),
            .functions = std.StringHashMap(std.ArrayList(*sem.FunctionDeclaration)).init(a.*),
            .types = std.StringHashMap(*sem.TypeDeclaration).init(a.*),
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

        .pointer_type => |apt| switch (b) {
            .pointer_type => |bpt| blk: {
                const sub_a = apt.*;
                const sub_b = bpt.*;

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

// Strict type equality: no wildcards; pointer subtypes must match exactly.
fn typesExactlyEqual(a: sem.Type, b: sem.Type) bool {
    return switch (a) {
        .builtin => |ab| switch (b) {
            .builtin => |bb| ab == bb,
            else => false,
        },
        .struct_type => |ast| switch (b) {
            .struct_type => |bst| blk: {
                if (ast.fields.len != bst.fields.len) break :blk false;
                var i: usize = 0;
                while (i < ast.fields.len) : (i += 1) {
                    const fa = ast.fields[i];
                    const fb = bst.fields[i];
                    if (!std.mem.eql(u8, fa.name, fb.name)) break :blk false;
                    if (!typesExactlyEqual(fa.ty, fb.ty)) break :blk false;
                }
                break :blk true;
            },
            else => false,
        },
        .pointer_type => |apt| switch (b) {
            .pointer_type => |bpt| typesExactlyEqual(apt.*, bpt.*),
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
        .pointer_type => |ept| blk2: {
            const apt = actual.pointer_type;
            if (isAny(ept.*) or isAny(apt.*)) break :blk2 1;
            break :blk2 specificityScore(ept.*, apt.*);
        },
    };
}
