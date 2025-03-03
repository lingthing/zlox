const builtin = @import("builtin");
const utils = @import("utils.zig");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;

pub const DEBUG_PRINT_CODE = true and builtin.mode == .Debug;
pub const DEBUG_TRACE_EXECUTION = true and builtin.mode == .Debug;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    const stdout = utils.getStdoutWriter();
    stdout.print("== {s} ==\n", .{name}) catch unreachable;

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    stdout.print("{:0>4} ", .{offset}) catch unreachable;

    if (offset > 0 and chunk.lines.items[offset] == chunk.lines.items[offset - 1]) {
        stdout.print("{c:>4} ", .{'|'}) catch unreachable;
    } else {
        stdout.print("{:>4} ", .{chunk.lines.items[offset]}) catch unreachable;
    }

    const instruction = OpCode.from(chunk.get(offset));
    switch (instruction) {
        .op_constant => {
            return constantInstruction(instruction.toString(), chunk, offset);
        },
        .op_add,
        .op_subtract,
        .op_multiply,
        .op_divide,
        => {
            return simpleInstruction(instruction.toString(), offset);
        },
        .op_negate => {
            return simpleInstruction(instruction.toString(), offset);
        },
        .op_return => {
            return simpleInstruction(instruction.toString(), offset);
        },
    }

    return offset + 1;
}

fn simpleInstruction(name: []const u8, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    stdout.print("{s}\n", .{name}) catch unreachable;
    return offset + 1;
}

fn constantInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    const constant: u8 = chunk.get(offset + 1);
    stdout.print("{s:<16} {d:>4} '", .{ name, constant }) catch unreachable;
    zloc.printValue(chunk.constants.items[constant]);
    stdout.print("'\n", .{}) catch unreachable;

    return offset + 2;
}
