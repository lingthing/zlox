const std = @import("std");
const zlox = @import("zlox.zig");
const debug = @import("debug.zig");
const VM = zlox.VM;
const Value = zlox.Value;
const Obj = zlox.Obj;
const Table = zlox.Table;
const Compiler = zlox.Compiler;

const GC_HEAP_GROW_FACTOR = 2;

pub fn collectGarbage(vm: *VM) void {
    const before: if (debug.DEBUG_LOG_GC) usize else void = undefined;
    if (debug.DEBUG_LOG_GC) {
        before = vm.bytes_allocated;
        std.debug.print("-- gc begin\n", .{});
    }

    markRoots(vm);
    traceReferences(vm);
    tableRemoveWhite(vm, &vm.strings);

    sweep(vm);

    vm.next_gc = vm.bytes_allocated * GC_HEAP_GROW_FACTOR;

    if (debug.DEBUG_LOG_GC) {
        std.debug.print("-- gc end\n", .{});
        std.debug.print("   collected {d} bytes (from {d} to {d}) next at {d}\n", .{
            before - vm.bytes_allocated,
            before,
            vm.bytes_allocated,
            vm.next_gc,
        });
    }
}

fn markRoots(vm: *VM) void {
    {
        var slot = vm.stack.ptr;
        while (@intFromPtr(slot) < @intFromPtr(vm.stack_top)) : (slot += 1) {
            markValue(vm, slot[0]);
        }
    }

    for (0..vm.frame_count) |i| {
        markObject(vm, vm.frames[i].closure.asObj());
    }

    {
        var it = vm.open_upvalues;
        while (it) |upvalue| : (it = upvalue.next) {
            markObject(vm, upvalue.asObj());
        }
    }

    markTable(vm, &vm.globals);
    markCompilerRoots(vm);
    if (vm.init_string) |init_string| {
        markObject(vm, init_string.asObj());
    }
}

fn markValue(vm: *VM, value: Value) void {
    if (value.isObj()) {
        markObject(vm, value.asObj());
    }
}

fn markObject(vm: *VM, object_or_null: ?*Obj) void {
    if (object_or_null == null) return;

    const object = object_or_null.?;
    if (object.is_marked) return;

    if (debug.DEBUG_LOG_GC) {
        std.debug.print("{s}@{x} mark ", .{
            object.type.toString(),
            @intFromPtr(object),
        });
        zlox.printValue(Value.initObj(object));
        std.debug.print("\n", .{});
    }

    object.is_marked = true;
    vm.gray_stack.append(object) catch @panic("OOM");
}

fn markTable(vm: *VM, table: *Table) void {
    for (0..table.capacity) |i| {
        const entry = table.entries[i];
        if (entry.key) |key| {
            markObject(vm, key.asObj());
        }
        markValue(vm, entry.value);
    }
}

fn markCompilerRoots(vm: *VM) void {
    var it = Compiler.current;
    while (it) |compiler| : (it = compiler.enclosing) {
        markObject(vm, compiler.function.asObj());
    }
}

fn markArray(vm: *VM, array: *zlox.ValueArray) void {
    for (array.items) |value| {
        markValue(vm, value);
    }
}

fn traceReferences(vm: *VM) void {
    while (vm.gray_stack.pop()) |object| {
        blackenObject(vm, object);
    }
}

fn tableRemoveWhite(vm: *VM, table: *Table) void {
    _ = vm;
    for (0..table.capacity) |i| {
        const entry = table.entries[i];
        if (entry.key) |key| {
            if (!key.obj.is_marked) {
                _ = table.delete(key);
            }
        }
    }
}

fn blackenObject(vm: *VM, object: *Obj) void {
    if (debug.DEBUG_LOG_GC) {
        std.debug.print("{s}@{x} blacken ", .{
            object.type.toString(),
            @intFromPtr(object),
        });
        zlox.printValue(Value.initObj(object));
        std.debug.print("\n", .{});
    }

    switch (object.type) {
        .obj_class => {
            const class = object.asClass();
            markObject(vm, class.name.asObj());
            markTable(vm, &class.methods);
        },
        .obj_instance => {
            const instance = object.asInstance();
            markObject(vm, instance.class.asObj());
            markTable(vm, &instance.fields);
        },
        .obj_bound_method => {
            const bound = object.asBoundMethod();
            markValue(vm, bound.receiver);
            markObject(vm, bound.method.asObj());
        },
        .obj_upvalue => {
            const upvalue = object.asUpvalue();
            markValue(vm, upvalue.closed);
        },
        .obj_function => {
            const function = object.asFunction();
            if (function.name) |name| {
                markObject(vm, name.asObj());
            }
            markArray(vm, &function.chunk.constants);
        },
        .obj_closure => {
            const closure = object.asClosure();
            markObject(vm, closure.function.asObj());
            for (0..closure.upvalue_count) |i| {
                if (closure.upvalues[i]) |upvalue| {
                    markObject(vm, upvalue.asObj());
                }
            }
        },
        .obj_native,
        .obj_string,
        => {},
    }
}

fn sweep(vm: *VM) void {
    var previous: ?*Obj = null;
    var it = vm.objects;
    while (it) |object| {
        if (object.is_marked) {
            object.is_marked = false;
            previous = object;
            it = object.next;
        } else {
            const unreached = object;
            it = object.next;
            if (previous != null) {
                previous.?.next = it;
            } else {
                vm.objects = it;
            }

            zlox.freeObject(vm, unreached);
        }
    }
}
