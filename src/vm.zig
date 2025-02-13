const std = @import("std");
const zloc = @import("zloc.zig");
const Chunk = zloc.Chunk;
const Value = zloc.Value;
const OpCode = zloc.OpCode;
const utils = @import("utils.zig");
const debug = @import("debug.zig");

pub const InterpretResult = enum {
    ok,
    compile_error,
    runtime_error,
};

pub const STACK_SIZE = 256;

pub const VM = struct {
    gpa: std.mem.Allocator,
    chunk: *Chunk,
    ip: [*]u8,
    stack: []Value,
    stackTop: [*]Value,

    pub fn init(gpa: std.mem.Allocator) VM {
        var vm: VM = undefined;
        vm.gpa = gpa;
        vm.stack = gpa.alloc(Value, STACK_SIZE) catch unreachable;
        vm.resetStack();

        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.gpa.free(self.stack);
    }

    pub fn interpret(vm: *VM, chunk: *Chunk) InterpretResult {
        vm.chunk = chunk;
        vm.ip = chunk.code.items.ptr;

        return vm.run();
    }

    fn resetStack(vm: *VM) void {
        vm.stackTop = vm.stack.ptr;
    }

    fn readByte(vm: *VM) u8 {
        const byte = vm.ip[0];
        vm.ip += 1;

        return byte;
    }

    fn readConstant(vm: *VM) Value {
        return vm.chunk.constants.items[vm.readByte()];
    }

    fn push(vm: *VM, value: Value) void {
        vm.stackTop[0] = value;
        vm.stackTop += 1;
    }

    fn pop(vm: *VM) Value {
        vm.stackTop -= 1;

        return vm.stackTop[0];
    }

    fn top(vm: *VM) *Value {
        return @ptrCast(vm.stackTop - 1);
    }

    fn run(vm: *VM) InterpretResult {
        const stdout = utils.getStdoutWriter();
        while (true) {
            if (debug.DEBUG_TRACE_EXECUTION) {
                stdout.print("          ", .{}) catch unreachable;
                var slot = vm.stack.ptr;
                while (slot != vm.stackTop) : (slot += 1) {
                    stdout.print("[ ", .{}) catch unreachable;
                    zloc.printValue(slot[0]);
                    stdout.print(" ]", .{}) catch unreachable;
                }
                stdout.print("\n", .{}) catch unreachable;
                _ = debug.disassembleInstruction(vm.chunk, @intFromPtr(vm.ip) - @intFromPtr(vm.chunk.code.items.ptr));
            }

            const instruction = OpCode.from(vm.readByte());
            switch (instruction) {
                .op_constant => {
                    const constant = vm.readConstant();
                    vm.push(constant);
                },
                .op_add => {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(a + b);
                },
                .op_subtract => {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(a - b);
                },
                .op_multiply => {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(a * b);
                },
                .op_divide => {
                    const b = vm.pop();
                    const a = vm.pop();
                    vm.push(a / b);
                },
                .op_negate => {
                    // naive way
                    vm.push(-vm.pop());

                    // smart way
                    // const ptr = vm.top();
                    // ptr.* = -ptr.*;
                },
                .op_return => {
                    zloc.printValue(vm.pop());
                    stdout.print("\n", .{}) catch unreachable;
                    return .ok;
                },
            }
        }
    }
};
