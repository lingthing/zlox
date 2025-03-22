pub const Entry = struct {
    key: ?*ObjString,
    value: Value,
};

pub const Table = struct {
    count: usize,
    capacity: usize,
    entries: [*]Entry,

    const TABLE_MAX_LOAD = 0.75;

    pub fn init() Table {
        return .{
            .count = 0,
            .capacity = 0,
            .entries = undefined,
        };
    }

    pub fn deinit(table: *Table) void {
        if (table.entries == undefined) return;
        // TODO: 换更好的方式
        const gpa = @import("common_allocator.zig").gpa;
        gpa.free(table.entries[0..table.capacity]);
        table.* = init();
    }

    fn findEntry(entries: [*]Entry, capacity: usize, key: *ObjString) *Entry {
        var index = key.hash % capacity;
        var tombstone: ?*Entry = null;
        while (true) {
            const entry = &entries[index];
            if (entry.key == null) {
                if (entry.value.isNil()) {
                    return if (tombstone != null) tombstone.? else entry;
                } else {
                    if (tombstone == null) tombstone = entry;
                }
            } else if (entry.key == key) {
                return entry;
            }

            index = (index + 1) % capacity;
        }
    }

    fn adjustCapacity(table: *Table, capacity: usize) void {
        // TODO: 改成一种更好的方式
        const gpa = @import("common_allocator.zig").gpa;
        var entries = gpa.alloc(Entry, capacity) catch {
            // handle oom
            unreachable;
        };
        // zig 0.13.0 不支持这种写法
        // for (entries) |entry| {
        //     entry.key = null;
        //     entry.value = Value.initNil();
        // }
        for (0..capacity) |i| {
            entries[i].key = null;
            entries[i].value = Value.initNil();
        }

        table.count = 0;
        for (0..table.capacity) |i| {
            const entry = &table.entries[i];
            if (entry.key) |key| {
                var dest = findEntry(entries.ptr, capacity, key);
                dest.key = key;
                dest.value = entry.value;

                table.count += 1;
            }
        }

        if (table.entries != undefined) {
            gpa.free(table.entries[0..table.capacity]);
        }

        table.entries = entries.ptr;
        table.capacity = capacity;
    }

    pub fn set(table: *Table, key: *ObjString, value: Value) bool {
        if (table.count + 1 > @as(usize, @intFromFloat((@as(f64, @floatFromInt(table.capacity)) * TABLE_MAX_LOAD)))) {
            const capacity = if (table.capacity < 8) @as(usize, 8) else table.capacity * 2;
            table.adjustCapacity(capacity);
        }

        var entry = findEntry(table.entries, table.capacity, key);
        const is_new_key = entry.key == null;
        if (is_new_key and entry.value.isNil()) table.count += 1;

        entry.key = key;
        entry.value = value;

        return is_new_key;
    }

    pub fn addAll(to: *Table, from: *Table) void {
        for (0..from.capacity) |i| {
            const entry = &from.entries[i];
            if (entry.key) |key| {
                to.set(key, entry.value);
            }
        }
    }

    pub fn findString(table: *Table, chars: []const u8, hash: u32) ?*ObjString {
        if (table.count == 0) return null;

        var index = hash % table.capacity;
        while (true) {
            const entry = &table.entries[index];
            if (entry.key == null) {
                if (entry.value.isNil()) return null;
            } else if (entry.key.?.chars.len == chars.len and
                entry.key.?.hash == hash and
                std.mem.eql(u8, entry.key.?.chars, chars))
            {
                return entry.key;
            }

            index = (index + 1) % table.capacity;
        }
    }

    pub fn get(table: *Table, key: *ObjString, value: *Value) bool {
        if (table.count == 0) return false;

        const entry = findEntry(table.entries, table.capacity, key);
        if (entry.key == null) return false;

        value.* = entry.value;

        return true;
    }

    pub fn delete(table: *Table, key: *ObjString) bool {
        if (table.count == 0) return false;

        var entry = findEntry(table.entries, table.capacity, key);
        if (entry.key == null) return false;

        // place a tombstone in the entry
        entry.key = null;
        entry.value = Value.initBool(true);

        return true;
    }
};

const std = @import("std");
const zloc = @import("zloc.zig");
const ObjString = zloc.ObjString;
const Value = zloc.Value;
