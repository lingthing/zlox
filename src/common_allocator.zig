const std = @import("std");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
pub const gpa = gpa_instance.allocator();

var is_deinit = false;

// You must call this function before exiting your program.
// And only once.
pub fn deinit() void {
    if (is_deinit) return;
    _ = gpa_instance.deinit();
    is_deinit = true;
}
