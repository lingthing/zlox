const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;

pub const VM = struct {
    chunk: *Chunk,

    pub fn init() VM {
        return VM{
            .chunk = undefined,
        };
    }

    pub fn deinit(self: *VM) void {
        _ = self;
    }
};
