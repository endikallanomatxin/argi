const c = @import("llvm.zig").c;

// Argi's private calling convention. C imports/exports use their target-specific
// ABI instead. Definitions, ordinary calls and virtual calls share this plan;
// internal parameters must never be inserted independently at a call site.
pub const Signature = struct {
    function_type: c.LLVMTypeRef,
    input_type: c.LLVMTypeRef,
    output_type: c.LLVMTypeRef,
    indirect_output: bool,

    pub fn init(input_type: c.LLVMTypeRef, output_type: c.LLVMTypeRef, indirect_output: bool) Signature {
        var parameters = [_]c.LLVMTypeRef{ c.LLVMPointerType(output_type, 0), input_type };
        return .{
            .function_type = if (indirect_output)
                c.LLVMFunctionType(c.LLVMVoidType(), &parameters, 2, 0)
            else
                c.LLVMFunctionType(output_type, &parameters[1], 1, 0),
            .input_type = input_type,
            .output_type = output_type,
            .indirect_output = indirect_output,
        };
    }

    pub fn input(self: Signature, function: c.LLVMValueRef) c.LLVMValueRef {
        return c.LLVMGetParam(function, if (self.indirect_output) 1 else 0);
    }

    pub fn outputStorage(self: Signature, function: c.LLVMValueRef) ?c.LLVMValueRef {
        return if (self.indirect_output) c.LLVMGetParam(function, 0) else null;
    }

    pub fn returnValue(self: Signature, builder: c.LLVMBuilderRef, function: c.LLVMValueRef, value: c.LLVMValueRef) !void {
        if (c.LLVMTypeOf(value) != self.output_type) return error.InvalidArgiReturnValue;
        if (self.outputStorage(function)) |storage| {
            _ = c.LLVMBuildStore(builder, value, storage);
            _ = c.LLVMBuildRetVoid(builder);
        } else _ = c.LLVMBuildRet(builder, value);
    }

    // The caller owns output-storage policy: ordinary expressions allocate a
    // temporary, while large-value forwarding supplies its checked destination.
    // An indirect call returns no SSA aggregate to load or repack unnecessarily.
    pub fn call(self: Signature, builder: c.LLVMBuilderRef, callee: c.LLVMValueRef, argument: c.LLVMValueRef, destination: ?c.LLVMValueRef, name: [:0]const u8) !?c.LLVMValueRef {
        if (c.LLVMTypeOf(argument) != self.input_type) return error.InvalidArgiCallInput;
        if (self.indirect_output) {
            const storage = destination orelse return error.MissingArgiOutputStorage;
            if (c.LLVMGetTypeKind(c.LLVMTypeOf(storage)) != c.LLVMPointerTypeKind) return error.InvalidArgiOutputStorage;
            var args = [_]c.LLVMValueRef{ storage, argument };
            _ = c.LLVMBuildCall2(builder, self.function_type, callee, &args, 2, "");
            return null;
        }
        if (destination != null) return error.UnexpectedArgiOutputStorage;
        var args = [_]c.LLVMValueRef{argument};
        return c.LLVMBuildCall2(builder, self.function_type, callee, &args, 1, name.ptr);
    }
};

test "Argi ABI verifies calls and definitions with both result conventions" {
    const std = @import("std");
    const module = c.LLVMModuleCreateWithName("argi_abi_test");
    defer c.LLVMDisposeModule(module);
    const builder = c.LLVMCreateBuilder();
    defer c.LLVMDisposeBuilder(builder);
    var input_fields = [_]c.LLVMTypeRef{c.LLVMInt32Type()};
    const input_type = c.LLVMStructType(&input_fields, 1, 0);
    for ([_]bool{ false, true }) |indirect| {
        var output_fields = [_]c.LLVMTypeRef{if (indirect) c.LLVMArrayType(c.LLVMInt32Type(), 40) else c.LLVMInt32Type()};
        const output_type = c.LLVMStructType(&output_fields, 1, 0);
        const signature = Signature.init(input_type, output_type, indirect);
        const callee = c.LLVMAddFunction(module, if (indirect) "indirect_callee" else "direct_callee", signature.function_type);
        c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(callee, "entry"));
        try std.testing.expectEqual(input_type, c.LLVMTypeOf(signature.input(callee)));
        try std.testing.expectError(error.InvalidArgiReturnValue, signature.returnValue(builder, callee, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0)));
        try signature.returnValue(builder, callee, c.LLVMConstNull(output_type));

        const caller = c.LLVMAddFunction(module, if (indirect) "indirect_caller" else "direct_caller", signature.function_type);
        c.LLVMPositionBuilderAtEnd(builder, c.LLVMAppendBasicBlock(caller, "entry"));
        const destination = signature.outputStorage(caller);
        const result = try signature.call(builder, callee, signature.input(caller), destination, "result");
        if (indirect) {
            try std.testing.expect(result == null);
            try std.testing.expectError(error.MissingArgiOutputStorage, signature.call(builder, callee, signature.input(caller), null, ""));
            try std.testing.expectError(error.InvalidArgiOutputStorage, signature.call(builder, callee, signature.input(caller), c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), ""));
            _ = c.LLVMBuildRetVoid(builder);
        } else {
            try std.testing.expect(result != null);
            try std.testing.expectError(error.UnexpectedArgiOutputStorage, signature.call(builder, callee, signature.input(caller), c.LLVMConstNull(c.LLVMPointerType(output_type, 0)), ""));
            _ = c.LLVMBuildRet(builder, result.?);
        }
        try std.testing.expectError(error.InvalidArgiCallInput, signature.call(builder, callee, c.LLVMConstInt(c.LLVMInt32Type(), 0, 0), destination, ""));
    }
    var message: [*c]u8 = null;
    defer if (message != null) c.LLVMDisposeMessage(message);
    const invalid = c.LLVMVerifyModule(module, c.LLVMReturnStatusAction, &message);
    if (invalid != 0) std.debug.print("{s}\n", .{message});
    try std.testing.expectEqual(@as(c_int, 0), invalid);
}
