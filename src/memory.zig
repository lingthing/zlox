const std = @import("std");
const zloc = @import("zloc.zig");
const debug = @import("debug.zig");
const VM = zloc.VM;

pub const MemoryManager = struct {
    vm: *VM,
    child_allocator: std.mem.Allocator,

    pub fn init(vm: *VM, child_allocator: std.mem.Allocator) MemoryManager {
        return .{
            .vm = vm,
            .child_allocator = child_allocator,
        };
    }

    pub fn deinit(self: *MemoryManager) void {
        _ = self;
    }

    pub fn allocator(self: *MemoryManager) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));
        if (debug.DEBUG_STRESS_GC) {
            zloc.collectGarbage(mm.vm);
        }

        if (mm.vm.bytes_allocated > mm.vm.next_gc) {
            zloc.collectGarbage(mm.vm);
        }

        mm.vm.bytes_allocated += len;

        return mm.child_allocator.rawAlloc(len, alignment, ret_addr);
    }

    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));

        if (memory.len <= new_len) {
            mm.vm.bytes_allocated += new_len - memory.len;
        } else {
            mm.vm.bytes_allocated -= memory.len - new_len;
        }

        return mm.child_allocator.rawResize(memory, alignment, new_len, ret_addr);
    }

    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));

        // TODO: This is a hack to get around the fact that remap is not implemented
        // TODO: I haven't studied remapes.it's probably going to be a problem, but it's going to be updated until 0.14
        if (memory.len <= new_len) {
            mm.vm.bytes_allocated += new_len - memory.len;
        } else {
            mm.vm.bytes_allocated -= memory.len - new_len;
        }

        return mm.child_allocator.rawRemap(memory, alignment, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret_addr: usize) void {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));

        mm.vm.bytes_allocated -= memory.len;

        return mm.child_allocator.rawFree(memory, alignment, ret_addr);
    }
};
