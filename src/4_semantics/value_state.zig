const tok = @import("../2_tokens/token.zig");

pub const Initializedness = enum {
    initialized,
    moved,
    deinitialized,
};

pub const State = struct {
    initializedness: Initializedness = .initialized,
    transition_location: ?tok.Location = null,
};
