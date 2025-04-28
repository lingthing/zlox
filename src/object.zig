pub const ObjType = enum {
    obj_class,
    obj_instance,
    obj_closure,
    obj_function,
    obj_native,
    obj_string,
    obj_upvalue,

    pub fn toString(obj_type: ObjType) []const u8 {
        return switch (obj_type) {
            .obj_class => "ObjClass",
            .obj_instance => "ObjInstance",
            .obj_closure => "ObjClosure",
            .obj_function => "ObjFunction",
            .obj_native => "ObjNative",
            .obj_string => "ObjString",
            .obj_upvalue => "ObjUpvalue",
        };
    }
};

pub const Obj = struct {
    type: ObjType,
    is_marked: bool,
    next: ?*Obj = null,

    pub fn asClass(self: *Obj) *ObjClass {
        return @as(*ObjClass, @ptrCast(self));
    }

    pub fn asInstance(self: *Obj) *ObjInstance {
        return @as(*ObjInstance, @ptrCast(self));
    }

    pub fn asClosure(self: *Obj) *ObjClosure {
        return @as(*ObjClosure, @ptrCast(self));
    }

    pub fn asFunction(self: *Obj) *ObjFunction {
        return @as(*ObjFunction, @ptrCast(self));
    }

    pub fn asNative(self: *Obj) *ObjNative {
        return @as(*ObjNative, @ptrCast(self));
    }

    pub fn asString(self: *Obj) *ObjString {
        return @as(*ObjString, @ptrCast(self));
    }

    pub fn asUpvalue(self: *Obj) *ObjUpvalue {
        return @as(*ObjUpvalue, @ptrCast(self));
    }
};

pub const ObjClass = struct {
    obj: Obj,
    name: *ObjString,

    pub fn asObj(self: *ObjClass) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjInstance = struct {
    obj: Obj,
    class: *ObjClass,
    fields: Table,

    pub fn asObj(self: *ObjInstance) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjClosure = struct {
    obj: Obj,
    function: *ObjFunction,
    upvalues: [*]?*ObjUpvalue,
    upvalue_count: usize,

    pub fn asObj(self: *ObjClosure) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjFunction = struct {
    obj: Obj,
    arity: usize,
    upvalue_count: usize,
    chunk: Chunk,
    name: ?*ObjString,

    pub fn asObj(self: *ObjFunction) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const NativeFn = *const fn (args: []Value) Value;

pub const ObjNative = struct {
    obj: Obj,
    function: NativeFn,

    pub fn asObj(self: *ObjNative) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjString = struct {
    obj: Obj,
    chars: []u8,
    hash: u32,

    pub fn asObj(self: *ObjString) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub const ObjUpvalue = struct {
    obj: Obj,
    location: *Value,
    closed: Value,
    next: ?*ObjUpvalue,

    pub fn asObj(self: *ObjUpvalue) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub fn copyString(vm: *VM, chars: []const u8) ?*ObjString {
    const hash = hashString(chars);
    const interned = vm.strings.findString(chars, hash);
    if (interned != null) {
        return interned;
    }

    const new_chars = vm.allocator.dupe(u8, chars) catch return null;

    return allocateString(vm, new_chars, hash);
}

pub fn takeString(vm: *VM, chars: []const u8) ?*ObjString {
    const hash = hashString(chars);
    const interned = vm.strings.findString(chars, hash);
    if (interned != null) {
        vm.allocator.free(chars);

        return interned;
    }

    return allocateString(vm, chars, hash);
}

pub fn printObject(value: Value) void {
    const stdout = utils.getStdoutWriter();

    switch (value.objType()) {
        .obj_class => {
            stdout.print("{s}", .{value.asClass().name.chars}) catch unreachable;
        },
        .obj_instance => {
            stdout.print("{s} instance", .{value.asInstance().class.name.chars}) catch unreachable;
        },
        .obj_closure => {
            printFunction(value.asClosure().function);
        },
        .obj_function => {
            printFunction(value.asFunction());
        },
        .obj_native => {
            stdout.print("<native fn>", .{}) catch unreachable;
        },
        .obj_string => {
            stdout.print("{s}", .{value.asRawString()}) catch unreachable;
        },
        .obj_upvalue => {
            stdout.print("upvalue", .{}) catch unreachable;
        },
    }
}

fn printFunction(function: *ObjFunction) void {
    const stdout = utils.getStdoutWriter();
    if (function.name == null) {
        stdout.print("<script>", .{}) catch unreachable;
        return;
    }

    if (function.name) |name| {
        stdout.print("<fn {s}>", .{name.chars}) catch unreachable;
    } else {
        stdout.print("<fn <null>>", .{}) catch unreachable;
    }
}

pub fn allocateObject(vm: *VM, comptime obj_type: ObjType) ?*Obj {
    const unknown = vm.allocator.create(comptime blk: {
        switch (obj_type) {
            .obj_class => break :blk ObjClass,
            .obj_instance => break :blk ObjInstance,
            .obj_closure => break :blk ObjClosure,
            .obj_function => break :blk ObjFunction,
            .obj_native => break :blk ObjNative,
            .obj_string => break :blk ObjString,
            .obj_upvalue => break :blk ObjUpvalue,
        }
    }) catch return null;

    var object = unknown.asObj();
    object.type = obj_type;
    object.is_marked = false;

    object.next = vm.objects;
    vm.objects = object;

    if (debug.DEBUG_LOG_GC) {
        std.debug.print("{s}@{x} allocate {d} byte(s)\n", .{
            object.type.toString(),
            @intFromPtr(unknown),
            @sizeOf(@TypeOf(unknown.*)),
        });
    }

    return object;
}

pub fn allocateString(vm: *VM, chars: []const u8, hash: u32) ?*ObjString {
    var object = allocateObject(vm, .obj_string) orelse return null;
    var string = object.asString();
    string.chars = @constCast(chars);
    string.hash = hash;

    vm.push(Value.initObj(string));
    _ = vm.strings.set(string, Value.initNil());
    _ = vm.pop();

    return string;
}

pub fn freeObject(vm: *VM, obj: *Obj) void {
    if (debug.DEBUG_LOG_GC) {
        std.debug.print("{s}@{x} free\n", .{
            obj.type.toString(),
            @intFromPtr(obj),
        });
    }

    switch (obj.type) {
        .obj_class => {
            const class = obj.asClass();
            vm.allocator.destroy(class);
        },
        .obj_instance => {
            const instance = obj.asInstance();
            instance.fields.deinit();
            vm.allocator.destroy(instance);
        },
        .obj_closure => {
            const closure = obj.asClosure();
            vm.allocator.free(closure.upvalues[0..closure.upvalue_count]);
            vm.allocator.destroy(closure);
        },
        .obj_function => {
            const function = obj.asFunction();
            function.chunk.deinit();
            vm.allocator.destroy(function);
        },
        .obj_native => {
            const native = obj.asNative();
            vm.allocator.destroy(native);
        },
        .obj_string => {
            const string = obj.asString();
            vm.allocator.free(string.chars);
            vm.allocator.destroy(string);
        },
        .obj_upvalue => {
            const upvalue = obj.asUpvalue();
            vm.allocator.destroy(upvalue);
        },
    }
}

fn hashString(keys: []const u8) u32 {
    var hash: u32 = 2166136261;
    for (keys) |c| {
        hash ^= c;
        hash = @as(u32, @truncate(@as(u64, hash) * 16777619));
    }

    return hash;
}

pub fn newFunction(vm: *VM) ?*ObjFunction {
    const object = allocateObject(vm, .obj_function) orelse return null;
    const function = object.asFunction();
    function.arity = 0;
    function.upvalue_count = 0;
    function.chunk = Chunk.init(vm.allocator);
    function.name = null;

    return function;
}

pub fn newNative(vm: *VM, function: NativeFn) ?*ObjNative {
    const object = allocateObject(vm, .obj_native) orelse return null;
    const native = object.asNative();
    native.function = function;

    return native;
}

pub fn newClosure(vm: *VM, function: *ObjFunction) ?*ObjClosure {
    var upvalues = vm.allocator.alloc(?*ObjUpvalue, function.upvalue_count) catch return null;
    for (0..function.upvalue_count) |i| {
        upvalues[i] = null;
    }

    const object: *Obj = allocateObject(vm, .obj_closure) orelse {
        vm.allocator.free(upvalues);

        return null;
    };
    const closure = object.asClosure();
    closure.function = function;
    closure.upvalues = upvalues.ptr;
    closure.upvalue_count = function.upvalue_count;

    return closure;
}

pub fn newUpvalue(vm: *VM, slot: *Value) ?*ObjUpvalue {
    const object = allocateObject(vm, .obj_upvalue) orelse return null;
    const upvalue = object.asUpvalue();
    upvalue.location = slot;
    upvalue.closed = Value.initNil();
    upvalue.next = null;

    return upvalue;
}

pub fn newClass(vm: *VM, name: *ObjString) ?*ObjClass {
    const object = allocateObject(vm, .obj_class) orelse return null;
    const class = object.asClass();
    class.name = name;

    return class;
}

pub fn newInstance(vm: *VM, class: *ObjClass) ?*ObjInstance {
    const object = allocateObject(vm, .obj_instance) orelse return null;
    const instance = object.asInstance();
    instance.class = class;
    instance.fields = Table.init();

    return instance;
}

const std = @import("std");
const zloc = @import("zloc.zig");
const debug = @import("debug.zig");
const utils = @import("utils.zig");
const Value = zloc.Value;
const Chunk = zloc.Chunk;
const VM = zloc.VM;
const Table = zloc.Table;
