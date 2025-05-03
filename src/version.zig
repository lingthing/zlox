pub const VERSION = blk: {
    const res = std.fmt.comptimePrint("zlox {d}.{d}.{d}", .{ VERSION_MAJOR, VERSION_MINOR, VERSION_PATCH });

    break :blk res;
};
pub const VERSION_MAJOR = 0;
pub const VERSION_MINOR = 1;
pub const VERSION_PATCH = 0;

const std = @import("std");
