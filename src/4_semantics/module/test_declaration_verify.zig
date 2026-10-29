const std = @import("std");
const entry_interface = @import("../entry_interface.zig");
const diagnostics_mod = @import("../../1_base/diagnostic.zig");
const source_db = @import("../../1_base/source_db.zig");
const syn = @import("../../3_syntax/syntax_tree.zig");

pub fn validate(
    files: []const syn.FileSyntaxTree,
    db: *const source_db.SourceDb,
    diagnostics: *diagnostics_mod.Diagnostics,
    include_tests: bool,
    selected_test_name: ?[]const u8,
) !void {
    if (!include_tests) return;
    var had_error = false;

    for (files) |*file| {
        for (file.roots) |node| {
            const test_decl = file.testDeclaration(node) orelse continue;
            const function = test_decl.function;
            const name = file.tokenText(db, function.name_token);
            if (selected_test_name) |wanted| if (!std.mem.eql(u8, name, wanted)) continue;
            if (!try validateOne(file, db, diagnostics, node, function)) had_error = true;
        }
    }

    if (had_error) return error.Reported;
}

fn validateOne(
    file: *const syn.FileSyntaxTree,
    db: *const source_db.SourceDb,
    diagnostics: *diagnostics_mod.Diagnostics,
    node: syn.NodeIndex,
    function: syn.FunctionDeclaration,
) !bool {
    const loc = file.location(node);
    const output = file.structTypeLiteral(function.output) orelse return false;

    if (function.is_once) {
        try diagnostics.add(loc, .semantic, "tests cannot be marked once", .{});
        return false;
    }
    if (function.generic_params.len != 0 or function.generic_params_struct != null) {
        try diagnostics.add(loc, .semantic, "tests do not support generic parameters in v1", .{});
        return false;
    }
    if (function.body == null) {
        try diagnostics.add(loc, .semantic, "tests must define a body", .{});
        return false;
    }
    _ = entry_interface.classifyInput(file, db.get(file.file_id).source, function.input, .program) catch {
        try diagnostics.add(loc, .semantic, "{s}", .{entry_interface.test_input_message});
        return false;
    };

    if (output.fields.len != 1) {
        try diagnostics.add(loc, .semantic, "tests must return exactly '-> !()' in v1", .{});
        return false;
    }
    const result_field = file.structTypeField(output.fields[0]) orelse return false;
    if (!result_field.inferred_result and !std.mem.eql(u8, file.tokenText(db, result_field.name_token), "result")) {
        try diagnostics.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
        return false;
    }
    const result_type_node = result_field.type_node orelse {
        try diagnostics.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
        return false;
    };
    switch (file.syntaxType(result_type_node) orelse return false) {
        .inferred_errable => |inner| switch (file.syntaxType(inner) orelse return false) {
            .struct_literal => |structure| if (structure.fields.len != 0) {
                try diagnostics.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
                return false;
            },
            else => {
                try diagnostics.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
                return false;
            },
        },
        else => {
            try diagnostics.add(file.tokenLocation(result_field.name_token), .semantic, "tests must return exactly '-> !()' in v1", .{});
            return false;
        },
    }
    return true;
}
