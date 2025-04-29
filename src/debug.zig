const builtin = @import("builtin");
const utils = @import("utils.zig");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const OpCode = zloc.OpCode;

pub const DEBUG_PRINT_CODE = true and builtin.mode == .Debug;
pub const DEBUG_TRACE_EXECUTION = false and builtin.mode == .Debug;
pub const DEBUG_STRESS_GC = false;
pub const DEBUG_LOG_GC = false and builtin.mode == .Debug;

pub fn disassembleChunk(chunk: *Chunk, name: []const u8) void {
    const stdout = utils.getStdoutWriter();
    stdout.print("== {s} ==\n", .{name}) catch unreachable;

    var offset: usize = 0;
    while (offset < chunk.count()) {
        offset = disassembleInstruction(chunk, offset);
    }
    stdout.print("\n", .{}) catch unreachable;
}

pub fn disassembleInstruction(chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    stdout.print("{:0>4} ", .{offset}) catch unreachable;

    if (offset > 0 and chunk.getLine(offset) == chunk.getLine(offset - 1)) {
        stdout.print("{c:>4} ", .{'|'}) catch unreachable;
    } else {
        stdout.print("{:>4} ", .{chunk.getLine(offset)}) catch unreachable;
    }

    const instruction = OpCode.from(chunk.getByte(offset));
    switch (instruction) {
        .op_nil,
        .op_true,
        .op_false,
        .op_pop,
        .op_equal,
        .op_greater,
        .op_less,
        .op_add,
        .op_subtract,
        .op_multiply,
        .op_divide,
        .op_not,
        .op_negate,
        .op_print,
        .op_close_upvalue,
        .op_return,
        .op_inherit,
        => {
            return simpleInstruction(instruction.toString(), offset);
        },
        .op_constant,
        .op_get_global,
        .op_define_global,
        .op_set_global,
        .op_get_property,
        .op_set_property,
        .op_get_super,
        .op_class,
        .op_method,
        => {
            return constantInstruction(instruction.toString(), chunk, offset);
        },
        .op_get_local,
        .op_set_local,
        .op_get_upvalue,
        .op_set_upvalue,
        .op_call,
        => {
            return byteInstruction(instruction.toString(), chunk, offset);
        },
        .op_jump,
        .op_jump_if_false,
        => {
            return jumpInstruction(instruction.toString(), 1, chunk, offset);
        },
        .op_loop,
        => {
            return jumpInstruction(instruction.toString(), -1, chunk, offset);
        },
        .op_closure => {
            return closureInstruction(instruction.toString(), chunk, offset);
        },
        .op_invoke,
        .op_super_invoke,
        => {
            return invokeInstruction(instruction.toString(), chunk, offset);
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
    const constant: u8 = chunk.getByte(offset + 1);
    stdout.print("{s:<16} {d:>4} '", .{ name, constant }) catch unreachable;
    zloc.printValue(chunk.constants.items[constant]);
    stdout.print("'\n", .{}) catch unreachable;

    return offset + 2;
}

fn closureInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    const constant: u8 = chunk.getByte(offset + 1);
    stdout.print("{s:<16} {d:>4} ", .{ name, constant }) catch unreachable;
    zloc.printValue(chunk.constants.items[constant]);
    stdout.print("\n", .{}) catch unreachable;

    const function = chunk.getConstant(constant).asFunction();
    var new_offset = offset + 2;
    for (0..function.upvalue_count) |_| {
        const is_local = chunk.getByte(new_offset) == 1;
        const index = chunk.getByte(new_offset + 1);
        stdout.print("{d:0>4}      |                     {s} {d}\n", .{
            new_offset,
            if (is_local) "local" else "upvalue",
            index,
        }) catch unreachable;

        new_offset += 2;
    }

    return new_offset;
}

fn byteInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    const slot = chunk.getByte(offset + 1);
    stdout.print("{s:<16} {d:>4}\n", .{ name, slot }) catch unreachable;

    return offset + 2;
}

fn jumpInstruction(name: []const u8, sign: i8, chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    const jump = @as(u16, @as(u16, chunk.getByte(offset + 1)) << 8 | chunk.getByte(offset + 2));
    stdout.print("{s:<16} {d:>4} -> {d}\n", .{
        name,
        offset,
        @as(isize, @intCast(offset)) + 3 + sign * @as(isize, @intCast(jump)),
    }) catch unreachable;

    return offset + 3;
}

fn invokeInstruction(name: []const u8, chunk: *Chunk, offset: usize) usize {
    const stdout = utils.getStdoutWriter();
    const constant = chunk.getByte(offset + 1);
    const arg_count = chunk.getByte(offset + 2);
    stdout.print("{s:<16} ({d} args) {d:>4} '", .{ name, arg_count, constant }) catch unreachable;
    zloc.printValue(chunk.getConstant(constant));
    stdout.print("'\n", .{}) catch unreachable;

    return offset + 3;
}
