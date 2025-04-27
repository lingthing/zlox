const std = @import("std");

var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
pub const gpa = gpa_instance.allocator();
var once_deinit = std.once(struct {
    fn deinit() void {
        _ = gpa_instance.deinit();
    }
}.deinit);

// You must call this function before exiting your program.
// And only once.
pub fn deinit() void {
    once_deinit.call();
}
