const std = @import("std");
const fs = std.fs;
const mem = std.mem;
const version = @import("version.zig");
const debug = @import("debug.zig");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;
const VM = zloc.VM;

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_instance.deinit();
    const gpa = gpa_instance.allocator();

    var vm = VM.init();
    defer vm.deinit();

    var chunk = Chunk.init(gpa);
    defer chunk.deinit();

    const constant: u8 = @intCast(chunk.addConstant(5.6));
    chunk.write(OpCode.op_constant.u8(), 12);
    chunk.write(constant, 12);
    chunk.write(OpCode.op_return.u8(), 12);
    debug.disassembleChunk(&chunk, "main");

    // const argv = try std.process.argsAlloc(gpa);
    // defer std.process.argsFree(gpa, argv);
    // if (argv.len < 2) {
    //     std.debug.print("Usage: zloc <file>\n", .{});
    //     return;
    // }

    // if (mem.eql(u8, argv[1], "--help")) {
    //     std.debug.print("Usage: zloc <file>\n", .{});
    // } else if (mem.eql(u8, argv[1], "--version")) {
    //     std.debug.print("{s}\n", .{version.VERSION});
    // } else {}
}
