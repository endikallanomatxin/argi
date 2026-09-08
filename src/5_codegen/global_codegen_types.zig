const std = @import("std");
const llvm = @import("llvm.zig");
const c = llvm.c;
const graph_mod = @import("../4_semantics/global_semantic_graph.zig");
const types = @import("../4_semantics/global_semantic_types.zig");
const primitives = @import("../4_semantics/semantic_primitives.zig");

pub const Error = error{ InvalidType, OutOfMemory };

pub const Lowerer = struct {
    allocator: std.mem.Allocator,
    graph: *const graph_mod.GlobalSemanticGraph,

    pub fn toLLVMType(self: *Lowerer, ty: graph_mod.GlobalTypeId) Error!llvm.c.LLVMTypeRef {
        return switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin => |builtin| self.builtinType(builtin),
            .pointer => |pointer| blk: {
                if (types.isBuiltin(self.graph, pointer.child, .Any))
                    break :blk c.LLVMPointerType(c.LLVMInt8Type(), 0);
                break :blk c.LLVMPointerType(try self.toLLVMType(pointer.child), 0);
            },
            .array => |array| c.LLVMArrayType(try self.toLLVMType(array.element), @intCast(array.length)),
            .declared => |decl| self.declaredType(decl),
            .structural => |shape| self.structType(shape.fields, shape.layout),
            .structural_choice => |shape| self.choiceType(shape.variants, shape.layout),
            .inferred_choice => |shape| self.choiceType(shape.variants, .regular),
            .generic => self.genericType(ty),
            .nullable, .inferred_errable => Error.InvalidType,
        };
    }

    fn builtinType(self: *Lowerer, builtin: primitives.BuiltinType) Error!llvm.c.LLVMTypeRef {
        _ = self;
        return switch (builtin) {
            .Void => c.LLVMStructType(null, 0, 0),
            .Int8, .UInt8, .Char => c.LLVMInt8Type(),
            .Int16, .UInt16 => c.LLVMInt16Type(),
            .Int32, .UInt32 => c.LLVMInt32Type(),
            .Int64, .UInt64 => c.LLVMInt64Type(),
            .UIntNative => switch (types.pointer_size_bytes) {
                2 => c.LLVMInt16Type(),
                4 => c.LLVMInt32Type(),
                8 => c.LLVMInt64Type(),
                else => Error.InvalidType,
            },
            .Float16 => c.LLVMHalfType(),
            .Float32 => c.LLVMFloatType(),
            .Float64 => c.LLVMDoubleType(),
            .Bool => c.LLVMInt1Type(),
            .Type => c.LLVMPointerType(c.LLVMInt8Type(), 0),
            .Any => c.LLVMInt8Type(),
        };
    }

    fn declaredType(self: *Lowerer, decl_id: graph_mod.GlobalDeclId) Error!llvm.c.LLVMTypeRef {
        const declaration = self.graph.declarations.items[@intFromEnum(decl_id)];
        if (declaration.struct_fields) |fields| return self.structType(fields, declaration.struct_layout);
        if (declaration.choice_variants) |variants| return self.choiceType(variants, declaration.choice_layout);
        return Error.InvalidType;
    }

    fn genericType(self: *Lowerer, ty: graph_mod.GlobalTypeId) Error!llvm.c.LLVMTypeRef {
        const instance = types.genericInstance(self.graph, ty) orelse return Error.InvalidType;
        return switch (instance.shape) {
            .structure => |shape| self.structType(shape.fields, shape.layout),
            .choice => |shape| self.choiceType(shape.variants, shape.layout),
            .array => |shape| c.LLVMArrayType(try self.toLLVMType(shape.element), @intCast(shape.length)),
            .alias => |target| self.toLLVMType(target),
        };
    }

    fn structType(self: *Lowerer, range: graph_mod.FieldRange, layout: primitives.StructLayout) Error!llvm.c.LLVMTypeRef {
        if (layout == .c_union) return self.unionType(range);
        if (range.len == 0) return c.LLVMStructType(null, 0, 0);
        const field_types = self.allocator.alloc(llvm.c.LLVMTypeRef, range.len) catch return Error.OutOfMemory;
        defer self.allocator.free(field_types);
        for (self.graph.fields.items[range.start..][0..range.len], 0..) |field, index|
            field_types[index] = try self.toLLVMType(types.effectiveFieldType(field));
        return c.LLVMStructType(field_types.ptr, @intCast(range.len), 0);
    }

    fn unionType(self: *Lowerer, range: graph_mod.FieldRange) Error!llvm.c.LLVMTypeRef {
        if (range.len == 0) return c.LLVMStructType(null, 0, 0);
        var best = self.graph.fields.items[range.start];
        var best_layout = types.layoutOf(self.graph, types.effectiveFieldType(best)) catch return Error.InvalidType;
        for (self.graph.fields.items[range.start + 1 ..][0 .. range.len - 1]) |field| {
            const layout = types.layoutOf(self.graph, types.effectiveFieldType(field)) catch return Error.InvalidType;
            if (layout.alignment > best_layout.alignment or (layout.alignment == best_layout.alignment and layout.size > best_layout.size)) {
                best = field;
                best_layout = layout;
            }
        }
        const total = types.layoutOfStructForCodegen(self.graph, range, .c_union) catch return Error.InvalidType;
        const storage_ty = try self.toLLVMType(types.effectiveFieldType(best));
        if (best_layout.size >= total.size) {
            var one = [_]llvm.c.LLVMTypeRef{storage_ty};
            return c.LLVMStructType(&one, 1, 0);
        }
        var fields = [_]llvm.c.LLVMTypeRef{
            storage_ty,
            c.LLVMArrayType(c.LLVMInt8Type(), @intCast(total.size - best_layout.size)),
        };
        return c.LLVMStructType(&fields, 2, 0);
    }

    fn choiceType(self: *Lowerer, range: graph_mod.VariantRange, layout: primitives.ChoiceLayout) Error!llvm.c.LLVMTypeRef {
        if (layout == .c_enum) return c.LLVMInt32Type();
        const count: usize = @as(usize, range.len) + 1;
        const fields = self.allocator.alloc(llvm.c.LLVMTypeRef, count) catch return Error.OutOfMemory;
        defer self.allocator.free(fields);
        fields[0] = c.LLVMInt32Type();
        for (self.graph.variants.items[range.start..][0..range.len], 0..) |variant, index| {
            fields[index + 1] = if (variant.payload_type) |payload|
                try self.toLLVMType(payload)
            else
                c.LLVMInt8Type();
        }
        return c.LLVMStructType(fields.ptr, @intCast(count), 0);
    }

    pub fn buildUnionFieldPointer(
        self: *Lowerer,
        builder: llvm.c.LLVMBuilderRef,
        union_ptr: llvm.c.LLVMValueRef,
        field_ty: graph_mod.GlobalTypeId,
        name: [*:0]const u8,
    ) Error!llvm.c.LLVMValueRef {
        const type_ref = try self.toLLVMType(field_ty);
        const bytes = c.LLVMBuildBitCast(builder, union_ptr, c.LLVMPointerType(c.LLVMInt8Type(), 0), "union.bytes.ptr");
        return c.LLVMBuildBitCast(builder, bytes, c.LLVMPointerType(type_ref, 0), name);
    }

    pub fn encodeType(self: *Lowerer, buffer: *std.array_list.Managed(u8), ty: graph_mod.GlobalTypeId) !void {
        switch (self.graph.types.items[@intFromEnum(ty)]) {
            .builtin => |builtin| try buffer.appendSlice(switch (builtin) {
                .Void => "void", .Int8 => "i8", .Int16 => "i16", .Int32 => "i32", .Int64 => "i64",
                .UIntNative => "unative", .UInt8 => "u8", .UInt16 => "u16", .UInt32 => "u32", .UInt64 => "u64",
                .Float16 => "f16", .Float32 => "f32", .Float64 => "f64", .Char => "char", .Bool => "bool",
                .Type => "type", .Any => "any",
            }),
            .pointer => |pointer| {
                try buffer.appendSlice(if (pointer.mutability == .read_only) "pro_" else "prw_");
                try self.encodeType(buffer, pointer.child);
            },
            .array => |array| {
                try buffer.writer().print("arr{d}_", .{array.length});
                try self.encodeType(buffer, array.element);
            },
            .declared => |decl| {
                try buffer.appendSlice("d");
                try buffer.writer().print("{d}_", .{@intFromEnum(decl)});
                try buffer.appendSlice(self.graph.text(self.graph.declarations.items[@intFromEnum(decl)].name));
            },
            .structural => |shape| {
                try buffer.appendSlice("s{");
                for (self.graph.fields.items[shape.fields.start..][0..shape.fields.len], 0..) |field, index| {
                    if (index != 0) try buffer.append(',');
                    try buffer.appendSlice(self.graph.text(field.name));
                    try buffer.append(':');
                    try self.encodeType(buffer, field.ty);
                }
                try buffer.append('}');
            },
            .structural_choice => try buffer.appendSlice("choice"),
            .inferred_choice => |shape| try buffer.writer().print("choice_i{d}", .{shape.identity}),
            .generic => |identity| {
                try buffer.writer().print("g{d}", .{@intFromEnum(identity.base)});
                for (self.graph.generic_arguments.items[identity.arguments.start..][0..identity.arguments.len]) |argument| switch (argument.value) {
                    .type => |value| {
                        try buffer.append('_');
                        try self.encodeType(buffer, value);
                    },
                    .comptime_int => |value| try buffer.writer().print("_n{d}", .{value}),
                };
            },
            .nullable, .inferred_errable => return Error.InvalidType,
        }
    }

    pub fn mangledFunctionName(self: *Lowerer, function_id: graph_mod.GlobalFunctionId) ![]u8 {
        const function = self.graph.functions.items[@intFromEnum(function_id)];
        const declaration = self.graph.declarations.items[@intFromEnum(function.declaration)];
        if (function.body == null and !function.flags.has_declared_body)
            return self.allocator.dupe(u8, self.graph.text(declaration.name));

        var buffer = std.array_list.Managed(u8).init(self.allocator);
        errdefer buffer.deinit();
        try buffer.appendSlice(self.graph.text(declaration.name));
        try buffer.writer().print("__f{d}__in_", .{@intFromEnum(function_id)});
        for (self.graph.fields.items[function.input.start..][0..function.input.len], 0..) |field, index| {
            if (index != 0) try buffer.append('_');
            try self.encodeType(&buffer, field.ty);
        }
        try buffer.appendSlice("__out_");
        for (self.graph.fields.items[function.output.start..][0..function.output.len], 0..) |field, index| {
            if (index != 0) try buffer.append('_');
            try self.encodeType(&buffer, field.ty);
        }
        return buffer.toOwnedSlice();
    }
};

test "global codegen type layer is independent from legacy semantic graph" {
    try std.testing.expect(@sizeOf(graph_mod.GlobalTypeId) == 4);
    try std.testing.expect(types.pointer_size_bytes == @sizeOf(*usize));
}
