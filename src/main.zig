const std = @import("std");
const fs = std.fs;
const mem = std.mem;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    if (argv.len < 2) {
        std.debug.print("Usage: zloc <file or directory>\n", .{});
        return;
    }

    if (mem.eql(u8, argv[1], "--help")) {
        std.debug.print("Usage: zloc <file or directory>\n", .{});
    } else if (mem.eql(u8, argv[1], "--version")) {
        std.debug.print("zloc 0.1.0\n", .{});
    } else {
        const dir = fs.cwd().openDir(argv[1], .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => {
                std.debug.print("Cannot find {s}: No such file or directory\n", .{argv[1]});
                return;
            },
            else => return err,
        };

        var walker = try dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next()) |entry| {
            if (entry.kind != .file) continue;
            if (mem.endsWith(u8, entry.path, ".zig")) {
                std.debug.print("{s}\n", .{entry.path});
            }
        }
    }
}
