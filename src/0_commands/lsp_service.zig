const std = @import("std");
const indexed = @import("indexed_lsp_service.zig");

pub const Severity = indexed.Severity;
pub const Position = indexed.Position;
pub const Range = indexed.Range;
pub const Diagnostic = indexed.Diagnostic;
pub const InlayHint = indexed.InlayHint;
pub const Hover = indexed.Hover;
pub const Definition = indexed.Definition;
pub const PrepareRename = indexed.PrepareRename;
pub const Location = indexed.Location;
pub const LocationsResult = indexed.LocationsResult;
pub const TextEdit = indexed.TextEdit;
pub const TextEditsResult = indexed.TextEditsResult;
pub const DiagnosticsResult = indexed.DiagnosticsResult;
pub const InlayHintsResult = indexed.InlayHintsResult;
pub const LanguageService = indexed.LanguageService;

/// Protocol helper retained at the old import boundary while editor semantics
/// are served exclusively by `indexed_lsp_service.zig`.
pub fn decodeFileUri(allocator: std.mem.Allocator, uri: []const u8) !?[]u8 {
    if (!std.mem.startsWith(u8, uri, "file://")) return null;
    const encoded = uri["file://".len..];
    var output = std.array_list.Managed(u8).init(allocator);
    errdefer output.deinit();

    var index: usize = 0;
    while (index < encoded.len) {
        if (encoded[index] == '%' and index + 2 < encoded.len) {
            const high = std.fmt.charToDigit(encoded[index + 1], 16) catch {
                try output.append(encoded[index]);
                index += 1;
                continue;
            };
            const low = std.fmt.charToDigit(encoded[index + 2], 16) catch {
                try output.append(encoded[index]);
                index += 1;
                continue;
            };
            try output.append(@intCast(high * 16 + low));
            index += 3;
        } else {
            try output.append(encoded[index]);
            index += 1;
        }
    }
    return try output.toOwnedSlice();
}

test "LSP service facade exposes only the indexed implementation" {
    try std.testing.expect(@sizeOf(Position) == @sizeOf(indexed.Position));
    try std.testing.expect(@sizeOf(LanguageService) == @sizeOf(indexed.LanguageService));
}
