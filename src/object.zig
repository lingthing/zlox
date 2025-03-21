pub const ObjType = enum {
    obj_string,
};

pub const Obj = struct {
    type: ObjType,
    next: ?*Obj = null,

    pub fn asString(self: *Obj) *ObjString {
        return @as(*ObjString, @ptrCast(self));
    }
};

pub const ObjString = struct {
    obj: Obj,
    chars: []u8,

    pub fn asObj(self: *ObjString) *Obj {
        return @as(*Obj, @ptrCast(self));
    }
};

pub fn copyString(vm: *VM, chars: []const u8) ?*ObjString {
    const new_chars = vm.gpa.dupe(u8, chars) catch return null;

    return allocateString(vm, new_chars);
}

pub fn takeString(vm: *VM, chars: []const u8) ?*ObjString {
    return allocateString(vm, chars);
}

pub fn printObject(value: Value) void {
    const stdout = @import("utils.zig").getStdoutWriter();

    switch (value.objType()) {
        .obj_string => {
            stdout.print("{s}", .{value.asRawString()}) catch unreachable;
        },
    }
}

pub fn allocateObject(vm: *VM, obj_type: ObjType) ?*Obj {
    const unknown = vm.gpa.create(blk: {
        switch (obj_type) {
            .obj_string => break :blk ObjString,
        }
    }) catch return null;

    var object = unknown.asObj();
    object.type = obj_type;

    object.next = vm.objects;
    vm.objects = object;

    return object;
}

pub fn allocateString(vm: *VM, chars: []const u8) ?*ObjString {
    var object = allocateObject(vm, .obj_string) orelse return null;
    var string = object.asString();
    string.chars = @constCast(chars);

    return string;
}

pub fn freeObject(vm: *VM, obj: *Obj) void {
    switch (obj.type) {
        .obj_string => {
            const string = obj.asString();
            vm.gpa.free(string.chars);
            vm.gpa.destroy(string);
        },
    }
}

const std = @import("std");
const zloc = @import("zloc.zig");
const Value = zloc.Value;
const VM = zloc.VM;
