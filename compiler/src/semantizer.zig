const std = @import("std");
const tok = @import("token.zig");
const syn = @import("syntax_tree.zig");
const sem = @import("semantic_graph.zig");
const sgp = @import("semantic_graph_print.zig"); // <-- NEW

const SemErr = error{
    SymbolAlreadyDefined,
    SymbolNotFound,
    ConstantReassignment,
    InvalidType,
    NotYetImplemented,
    OutOfMemory,
};

const TypedExpr = struct {
    node: *sem.SGNode,
    ty: sem.BuiltinType,
};

/// ──────────────────────────────────────────────────────────────────────────────
/// SEMANTIZER
/// ──────────────────────────────────────────────────────────────────────────────
pub const Semantizer = struct {
    allocator: *const std.mem.Allocator,
    st_nodes: []const *syn.STNode, // input
    root_nodes: std.ArrayList(*sem.SGNode), // output (top-level SG nodes)

    // ───── constructor ────────────────────────────────────────────────────────
    pub fn init(alloc: *const std.mem.Allocator, st_nodes: []const *syn.STNode) Semantizer {
        return .{
            .allocator = alloc,
            .st_nodes = st_nodes,
            .root_nodes = std.ArrayList(*sem.SGNode).init(alloc.*),
        };
    }

    /// Public API – drive the semantic analysis and obtain the SG roots.
    pub fn analyze(self: *Semantizer) SemErr!std.ArrayList(*sem.SGNode) {
        var global = try Scope.init(self.allocator, null);

        for (self.st_nodes) |st_ptr| {
            _ = try self.visitNode(st_ptr.*, &global);
        }

        return self.root_nodes;
    }

    /// Extra helper so that `build.zig` can dump the graph:
    pub fn printSG(self: *Semantizer) void { // <-- NEW
        std.debug.print("\nSEMANTIC GRAPH\n", .{});
        for (self.root_nodes.items) |n|
            sgp.printNode(n, 0);
    }

    // ========================================================================
    //  Visitors  (dispatcher)
    // ========================================================================
    fn visitNode(self: *Semantizer, n: syn.STNode, scope: *Scope) SemErr!TypedExpr {
        return switch (n.content) {
            .declaration => |d| self.handleDeclaration(d, n.location, scope),
            .assignment => |a| self.handleAssignment(a, n.location, scope),
            .identifier => |id| self.handleIdentifier(id, scope),
            .literal => |l| self.handleLiteral(l, scope),
            .binary_operation => |b| self.handleBinaryOperation(b, scope),
            .return_statement => |r| self.handleReturnStatement(r, scope),
            .if_statement => |ifs| self.handleIfStatement(ifs, scope),
            .code_block => |blk| self.handleCodeBlock(blk, scope),
            .function_call => |fc| self.handleFunctionCall(fc, n.location, scope),

            else => error.NotYetImplemented,
        };
    }

    // ========================================================================
    //  Handlers
    // ========================================================================

    // ------- literals -------------------------------------------------------
    fn handleLiteral(self: *Semantizer, lit: tok.Literal, scope: *Scope) SemErr!TypedExpr {
        var sg_val: sem.ValueLiteral = undefined;
        var ty: sem.BuiltinType = undefined;

        switch (lit) {
            .decimal_int_literal, .hexadecimal_int_literal, .octal_int_literal, .binary_int_literal => |txt| {
                const v = std.fmt.parseInt(i64, txt, 0) catch 0;
                sg_val = .{ .int_literal = v };
                ty = .Int32;
            },
            .regular_float_literal, .scientific_float_literal => |txt| {
                const f = std.fmt.parseFloat(f64, txt) catch 0.0;
                sg_val = .{ .float_literal = f };
                ty = .Float32;
            },
            else => return error.NotYetImplemented,
        }

        const lit_ptr = try self.allocator.create(sem.ValueLiteral);
        lit_ptr.* = sg_val;
        const sg_node_ptr = try self.makeNode(.{ .value_literal = lit_ptr.* }, scope);

        return .{ .node = sg_node_ptr, .ty = ty };
    }

    // ------- identifiers ----------------------------------------------------
    fn handleIdentifier(self: *Semantizer, name: []const u8, scope: *Scope) SemErr!TypedExpr {
        const binding = scope.lookupBinding(name) orelse return error.SymbolNotFound;
        const node = try self.makeNode(.{ .binding_use = binding }, null);
        return .{ .node = node, .ty = binding.ty.builtin };
    }

    // ------- blocks ---------------------------------------------------------
    fn handleCodeBlock(self: *Semantizer, blk: syn.CodeBlock, parent: *Scope) SemErr!TypedExpr {
        var child = try Scope.init(self.allocator, parent);

        for (blk.items) |item_ptr|
            _ = try self.visitNode(item_ptr.*, &child);

        const cb = try self.allocator.create(sem.CodeBlock);
        cb.* = .{
            .nodes = child.nodes,
            .ret_val = null,
        };

        const node = try self.makeNode(.{ .code_block = cb }, parent);
        return .{ .node = node, .ty = .Void }; // <- ".Void" is now legal
    }

    fn handleFunctionCall(self: *Semantizer, call: syn.FunctionCall, loc: tok.Location, scope: *Scope) SemErr!TypedExpr {
        _ = loc; // unused for now
        const fn_decl = scope.lookupFunction(call.callee) orelse return error.SymbolNotFound;

        const param_count = fn_decl.params.items.len;
        var sg_args = try self.allocator.alloc(sem.SGNode, param_count);
        var provided = try self.allocator.alloc(bool, param_count);
        defer self.allocator.free(provided);
        @memset(provided, false);

        for (call.args, 0..) |arg, idx_call| {
            var idx_param: usize = idx_call;
            if (arg.name) |n| {
                var found = false;
                for (fn_decl.params.items, 0..) |p, j| {
                    if (std.mem.eql(u8, p.name, n)) {
                        idx_param = j;
                        found = true;
                        break;
                    }
                }
                if (!found) return error.SymbolNotFound;
            }
            if (idx_param >= param_count or provided[idx_param])
                return error.InvalidType;

            const te = try self.visitNode(arg.value.*, scope);
            const param = fn_decl.params.items[idx_param];
            const expected = param.ty.builtin;
            if (te.ty != expected and !(expected == .Float32 and te.ty == .Int32))
                return error.InvalidType;
            sg_args[idx_param] = te.node.*;
            provided[idx_param] = true;
        }

        for (provided) |p|
            if (!p) return error.InvalidType; // missing argument

        const fc_ptr = try self.allocator.create(sem.FunctionCall);
        fc_ptr.* = .{
            .callee = fn_decl,
            .args = sg_args,
        };

        const node_ptr = try self.makeNode(.{ .function_call = fc_ptr }, scope);
        const ret_ty = fn_decl.return_type.?.builtin; // we only have Builtin for now

        return .{ .node = node_ptr, .ty = ret_ty };
    }

    fn handleDeclaration(self: *Semantizer, decl: syn.Declaration, loc: tok.Location, scope: *Scope) SemErr!TypedExpr {
        return if (decl.kind == .function)
            self.handleFunctionDeclaration(decl, loc, scope)
        else
            self.handleBindingDeclaration(decl, loc, scope);
    }

    fn handleBindingDeclaration(self: *Semantizer, decl: syn.Declaration, loc: tok.Location, scope: *Scope) SemErr!TypedExpr {
        if (scope.bindings.contains(decl.name)) return error.SymbolAlreadyDefined;

        // deducir tipo -----------------------------------------------------
        var builtin_ty: sem.BuiltinType = .Int32; // por defecto
        if (decl.type) |t|
            builtin_ty = try builtinFromName(t.name)
        else if (decl.value) |val_node| {
            const tmp = try self.visitNode(val_node.*, scope);
            builtin_ty = tmp.ty;
        }

        const binding_ptr = try self.allocator.create(sem.BindingDeclaration);
        binding_ptr.* = .{
            .name = decl.name,
            .mutability = decl.mutability,
            .ty = .{ .builtin = builtin_ty },
            .initialization = null, // se asigna más adelante si hay inicializador
        };

        try scope.bindings.put(decl.name, binding_ptr);

        const node_ptr = try self.makeNode(.{ .binding_declaration = binding_ptr }, scope);
        if (scope.parent == null) try self.root_nodes.append(node_ptr);

        // inicializador implícito
        if (decl.value) |v| {
            if (decl.mutability == .variable) {
                // Primer write de una variable: sigue siendo un assignment
                _ = try self.handleAssignment(.{ .name = decl.name, .value = v }, loc, scope);
            } else {
                const prev_len = scope.nodes.items.len;
                const rhs = try self.visitNode(v.*, scope);
                binding_ptr.initialization = rhs.node;
                // si la visita añadió el nodo como sentencia, lo quitamos
                if (scope.nodes.items.len > prev_len) {
                    _ = scope.nodes.pop();
                }
            }
        }

        return .{ .node = node_ptr, .ty = .Void };
    }

    // ---------- asignación -----------------------------------------------
    fn handleAssignment(self: *Semantizer, asg: syn.Assignment, loc: tok.Location, scope: *Scope) SemErr!TypedExpr {
        _ = loc;

        const binding = scope.lookupBinding(asg.name) orelse return error.SymbolNotFound;

        const rhs = try self.visitNode(asg.value.*, scope);

        if (rhs.ty != binding.ty.builtin and !(binding.ty.builtin == .Float32 and rhs.ty == .Int32))
            return error.InvalidType;

        const assign_ptr = try self.allocator.create(sem.Assignment);
        assign_ptr.* = .{
            .sym_id = binding,
            .value = rhs.node,
        };

        const is_first_write = (binding.initialization == null);

        // ─── Caso 1: CONST  →  la primera escritura es la inicialización
        if (is_first_write and binding.mutability == .constant) {
            // Guardamos solo la *expresión*, no el assignment
            binding.initialization = rhs.node;
            return .{ .node = rhs.node, .ty = .Void };
        }

        // ─── Caso 2: VAR (o reasignación)
        if (binding.mutability == .constant)
            return error.ConstantReassignment;

        // Todas las escrituras a var (incluida la primera) se materializan
        const node_ptr = try self.makeNode(.{ .binding_assignment = assign_ptr }, scope);
        try scope.nodes.append(node_ptr);

        return .{ .node = node_ptr, .ty = .Void };
    }

    // ---------- binaria (+, -, …) ----------------------------------------
    fn handleBinaryOperation(self: *Semantizer, bin: syn.BinaryOperation, scope: *Scope) SemErr!TypedExpr {
        const lhs = try self.visitNode(bin.left.*, scope);
        const rhs = try self.visitNode(bin.right.*, scope);

        var out_ty: sem.BuiltinType = .Int32;
        if (bin.operator == .equals or bin.operator == .not_equals) {
            out_ty = .Bool;
        } else if (lhs.ty == .Float32 or rhs.ty == .Float32) {
            out_ty = .Float32;
        }

        const bin_ptr = try self.allocator.create(sem.BinaryOperation);
        bin_ptr.* = .{
            .operator = bin.operator,
            .left = lhs.node,
            .right = rhs.node,
        };

        const node_ptr = try self.makeNode(.{ .binary_operation = bin_ptr.* }, scope);
        return .{ .node = node_ptr, .ty = out_ty };
    }

    fn handleIfStatement(self: *Semantizer, ifs: syn.IfStatement, scope: *Scope) SemErr!TypedExpr {
        const cond = try self.visitNode(ifs.condition.*, scope);
        const then_te = try self.visitNode(ifs.then_block.*, scope);
        if (then_te.node.* != .code_block) return error.InvalidType;

        var else_cb: ?*sem.CodeBlock = null;
        if (ifs.else_block) |eb| {
            const else_te = try self.visitNode(eb.*, scope);
            if (else_te.node.* != .code_block) return error.InvalidType;
            else_cb = else_te.node.*.code_block;
        }

        const if_ptr = try self.allocator.create(sem.IfStatement);
        if_ptr.* = .{
            .condition = cond.node,
            .then_block = then_te.node.*.code_block,
            .else_block = else_cb,
        };

        const node_ptr = try self.makeNode(.{ .if_statement = if_ptr }, scope);
        return .{ .node = node_ptr, .ty = .Void };
    }

    // ---------- función ---------------------------------------------------
    fn handleFunctionDeclaration(self: *Semantizer, decl: syn.Declaration, loc: tok.Location, parent: *Scope) SemErr!TypedExpr {
        _ = loc;
        if (parent.functions.contains(decl.name)) return error.SymbolAlreadyDefined;

        // 1) Crear alcance hijo para la función
        var child = try Scope.init(self.allocator, parent);

        // 2) Procesar parámetros y registrarlos en el scope hijo
        var params = std.ArrayList(*sem.BindingDeclaration).init(self.allocator.*);
        if (decl.args) |arg_list| {
            for (arg_list) |a| {
                var builtin_ty: sem.BuiltinType = .Int32;
                if (a.type) |t| builtin_ty = try builtinFromName(t.name);
                const bd_ptr = try self.allocator.create(sem.BindingDeclaration);
                bd_ptr.* = .{
                    .name = a.name,
                    .mutability = a.mutability,
                    .ty = .{ .builtin = builtin_ty },
                    .initialization = null,
                };
                try params.append(bd_ptr);
                try child.bindings.put(a.name, bd_ptr);
            }
        }

        const body_ptr = decl.value.?; // punto al STNode que es code_block

        // Visitamos ese STNode de tipo code_block; devolvemos TypedExpr
        const body_te = try self.visitNode(body_ptr.*, &child);
        const body_sg_node = body_te.node; // *SGNode de variante .code_block

        // 3) Creamos la FunctionDeclaration y apuntamos su `body` al CodeBlock del SGNode
        const func_ptr = try self.allocator.create(sem.FunctionDeclaration);
        const declared_rt = decl.type orelse return error.InvalidType;
        const builtin_rt = try builtinFromName(declared_rt.name);
        func_ptr.* = .{
            .name = decl.name,
            .params = params,
            .return_type = .{ .builtin = builtin_rt },
            .body = body_sg_node.*.code_block,
        };

        try parent.functions.put(decl.name, func_ptr);
        const node_ptr = try self.makeNode(.{ .function_declaration = func_ptr }, parent);
        if (parent.parent == null) try self.root_nodes.append(node_ptr);
        return .{ .node = node_ptr, .ty = .Void };
    }

    // ---------- return ----------------------------------------------------
    fn handleReturnStatement(self: *Semantizer, ret: syn.ReturnStatement, scope: *Scope) SemErr!TypedExpr {
        const expr_opt = if (ret.expression) |e| try self.visitNode(e.*, scope) else null;

        if (expr_opt) |te| scope.setReturnType(te.ty);

        const ret_ptr = try self.allocator.create(sem.ReturnStatement);
        ret_ptr.* = .{
            .expression = if (expr_opt) |te| te.node else null,
        };

        const node_ptr = try self.makeNode(.{ .return_statement = ret_ptr }, scope);
        return .{ .node = node_ptr, .ty = .Void };
    }

    // ========================================================================
    //  Helpers
    // ========================================================================
    fn makeNode(self: *Semantizer, val: sem.SGNode, scope: ?*Scope) SemErr!*sem.SGNode {
        const ptr = try self.allocator.create(sem.SGNode);
        ptr.* = val;
        if (scope) |s| try s.nodes.append(ptr);
        return ptr;
    }

    fn builtinFromName(name: []const u8) SemErr!sem.BuiltinType {
        return std.meta.stringToEnum(sem.BuiltinType, name) orelse error.InvalidType;
    }
};

const Scope = struct {
    parent: ?*Scope,
    nodes: std.ArrayList(*sem.SGNode),

    bindings: std.StringHashMap(*sem.BindingDeclaration),
    functions: std.StringHashMap(*sem.FunctionDeclaration),
    types: std.StringHashMap(*sem.TypeDeclaration),

    inferredReturnType: ?sem.BuiltinType = null,

    fn init(alloc: *const std.mem.Allocator, parent: ?*Scope) SemErr!Scope {
        return .{
            .parent = parent,
            .nodes = std.ArrayList(*sem.SGNode).init(alloc.*),
            .bindings = std.StringHashMap(*sem.BindingDeclaration).init(alloc.*),
            .functions = std.StringHashMap(*sem.FunctionDeclaration).init(alloc.*),
            .types = std.StringHashMap(*sem.TypeDeclaration).init(alloc.*),
        };
    }

    fn lookupBinding(self: *Scope, name: []const u8) ?*sem.BindingDeclaration {
        if (self.bindings.get(name)) |b| return b;
        if (self.parent) |p| return p.lookupBinding(name);
        return null;
    }

    fn lookupFunction(self: *Scope, name: []const u8) ?*sem.FunctionDeclaration {
        if (self.functions.get(name)) |f| return f;
        if (self.parent) |p| return p.lookupFunction(name);
        return null;
    }

    fn setReturnType(self: *Scope, ty: sem.BuiltinType) void {
        if (self.inferredReturnType) |cur| {
            if (cur == .Float32 and ty == .Int32) return;
            if (cur == .Int32 and ty == .Float32) self.inferredReturnType = .Float32;
        } else {
            self.inferredReturnType = ty;
        }
    }
};
