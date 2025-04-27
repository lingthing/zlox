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
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));
        if (debug.DEBUG_STRESS_GC) {
            zloc.collectGarbage(mm.vm);
        }

        if (mm.vm.bytes_allocated > mm.vm.next_gc) {
            zloc.collectGarbage(mm.vm);
        }

        mm.vm.bytes_allocated += len;

        return mm.child_allocator.rawAlloc(len, ptr_align, ret_addr);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));

        if (buf.len <= new_len) {
            mm.vm.bytes_allocated += new_len - buf.len;
        } else {
            mm.vm.bytes_allocated -= buf.len - new_len;
        }

        return mm.child_allocator.rawResize(buf, buf_align, new_len, ret_addr);
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
        const mm: *MemoryManager = @ptrCast(@alignCast(ctx));

        mm.vm.bytes_allocated -= buf.len;

        return mm.child_allocator.rawFree(buf, buf_align, ret_addr);
    }
};
