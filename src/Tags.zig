const std = @import("std");
const Data = @import("Data.zig");
const Tag = @This();

start: u32,
end: u32,

pub fn getTagName(data: []const u8, tag: Tag) []const u8 {
    if (data[tag.start] != '<') unreachable;
    var start: usize = tag.start + 1;
    while (true) : (start += 1) {
        switch (data[start]) {
            'a'...'z', 'A'...'Z' => break,
            ' ', '/' => {},
            else => unreachable,
        }
    }

    var end: usize = start;
    while (true) : (end += 1) {
        switch (data[end]) {
            '>', ' ' => break,
            '\'', '\"' => end = skipComment(usize, data, end),
            else => {},
        }
    }

    return data[start..end];
}

// test "Get Tag Name" {
//     const tags = [_][]const u8{ "<tag>", "</tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\">" };
//     const exp_names = [_][]const u8{ "tag", "tag", "type" };
//     for (tags, exp_names) |tag, exp_name| {
//         const tag_name = getTagName(tag, .{ .start = 0, .end = @truncate(tag.len) });
//         try std.testing.expectEqualStrings(exp_name, tag_name);
//     }
// }

pub fn tagNamesMatch(data: []const u8, tag1: Tag, tag2: Tag) bool {
    const tag1_name = getTagName(data, tag1);
    const tag2_name = getTagName(data, tag2);
    return std.mem.eql(u8, tag1_name, tag2_name);
}

// test "Tag Names Match" {
//     const data = [_][]const u8{ "<tag></tag>", "<type category=\"struct\" name=\"VkInstanceCreateInfo\"></type>" };
//     const tag1s = [_]Tag{ .{ .start = 0, .end = 4 }, .{ .start = 0, .end = 44 } };
//     const tag2s = [_]Tag{ .{ .start = 5, .end = 10 }, .{ .start = 52, .end = 58 } };
//     for (data, tag1s, tag2s) |datum, tag1, tag2| {
//         try std.testing.expect(tagNamesMatch(datum, tag1, tag2));
//     }
// }

fn skipComment(comptime T: type, data: []const u8, i: T) T {
    var j: T = i + 1;
    const char = data[i];
    while (true) : (j += 1) {
        if (data[j] == char) break;
    }
    return j;
}

pub fn getTagsV(data: Data) void { // !std.ArrayList(Tag) {
    const n_tags = getNumberOfTagsV(u16, data) catch unreachable;
    std.debug.print("# of Tags: {}\n", .{n_tags});

    var tags = std.ArrayList(Tag).initCapacity(data.allo, n_tags) catch unreachable;
    defer tags.deinit();

    // use simd + multiple threads to get all open tag positions
    // use simd + multiple threads to get all close tag positions
}

pub fn getNumberOfTagsV(comptime T: type, data: []const u8) !T {
    // Steps:
    // 0. T = comptime input, must be unsigned int
    // 1. count the number of < inside data = # of tags, skip "" or '' = # of openings
    // 2. count the number of > inside data = # of tags, skip "" or '' = # of closings
    // 3. assert # of openings = # of closings
    // 4. return # of tags

    const n_threads: T = 8;
    var n_opens = [_]T{0} ** n_threads;
    var n_closes = [_]T{0} ** n_threads;
    const len: T = @truncate(data.len);
    const step: T = len / n_threads;

    {
        // var event = std.Thread.ResetEvent{};
        inline for (0..n_threads) |i| {
            const start: T = @as(T, @truncate(i)) * step;
            const end: T = start + step;
            const thread = try std.Thread.spawn(.{}, getNumberOfTagsPerBlock, .{ T, data[start..end], &n_opens[i], &n_closes[i] });
            defer thread.join();
            // defer thread.detach();
        }
        // event.wait();
    }

    const V: type = @Vector(n_threads, T);
    const n_open: T = @reduce(.Add, @as(V, n_opens));
    const n_close: T = @reduce(.Add, @as(V, n_closes));
    std.debug.print("# of Opens: {}\n", .{n_open});
    std.debug.print("# of Closes: {}\n", .{n_close});
    // std.debug.assert(n_open == n_close);
    return n_open;
}

// test "Get Number of Tags V" {
//     const data: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//     const n_opens = try Tag.getNumberOfTagsV(u16, data);
//     try std.testing.expect(n_opens == 8);
// }

fn getNumberOfTagsPerBlock(comptime T: type, data: []const u8, n_open_ptr: *T, n_close_ptr: *T) void {
    var i: T = 0;
    const len = data.len;

    var n_open: T = n_open_ptr.*;
    var n_close: T = n_open_ptr.*;

    const V_len: T = 64;
    const V: type = @Vector(V_len, u8);

    const open_char: V = @splat('<');
    const close_char: V = @splat('>');

    const squote: V = @splat('\'');
    const dquote: V = @splat('\"');

    var is_single_carry: bool = false;
    var is_double_carry: bool = false;

    while (i + V_len < len) : (i += V_len) {
        const v = @as(V, data[i..][0..V_len].*);

        var o: u64 = @as(u64, @bitCast(v == open_char));
        var c: u64 = @as(u64, @bitCast(v == close_char));

        // create masks
        const s: u64 = @as(u64, @bitCast(v == squote));
        const s_mask = turnOnBitsBW2Bits(u64, s, is_single_carry);
        is_single_carry = s_mask.carry;

        const d: u64 = @as(u64, @bitCast(v == dquote));
        const d_mask = turnOnBitsBW2Bits(u64, s, is_double_carry);
        is_double_carry = d_mask.carry;

        o = o & ~s & ~d;
        c = c & ~s & ~d;

        n_open += @as(T, @popCount(o));
        n_close += @as(T, @popCount(c));
    }

    if (i + 1 < len) {
        var bit = [_]u8{0} ** V_len;
        @memcpy(bit[0 .. len - i], data[i..][0 .. len - i]);
        const v: V = bit;

        const o: u64 = @bitCast(v == open_char);
        n_open += @as(T, @popCount(o));

        const c: u64 = @bitCast(v == close_char);
        n_close += @as(T, @popCount(c));
    }

    n_open_ptr.* = n_open;
    n_close_ptr.* = n_close;
}

// test "Get Number of Tags Per Block" {
//     const T: type = u16;
//     var n_open: T = 0;
//     var n_close: T = 0;
//     const data: []const u8 = "<member><basic>Hello World</basic><name>Jeff</name><type>VkStructureType</type></member>";
//     getNumberOfTagsPerBlock(T, data, &n_open, &n_close);
//     try std.testing.expect(n_open == n_close);
// }

pub fn getNumberOfTags(comptime T: type, data: Data) !T {
    var n_opens: T = 0;
    var n_closes: T = 0;

    var i: T = 0;
    while (i < data.data.len) : (i += 1) {
        const ch = data.data[i];
        switch (ch) {
            '<' => n_opens += 1,
            '>' => n_closes += 1,
            '\'', '\"' => i = skipComment(T, data.data, i),
            else => {},
        }
    }
    std.debug.assert(n_opens == n_closes);
    return n_opens;
}

pub fn getTags(
    allo: std.mem.Allocator,
    data: []const u8,
) !std.ArrayList(Tag) {
    var tags = std.ArrayList(Tag).initCapacity(allo, 1_024) catch unreachable;

    var found_prolog: bool = false;
    var found_open: bool = false;

    var i: usize = 0;
    var j: usize = 0;

    while (true) : (i += 1) {
        if (i == data.len) break;
        switch (data[i]) {
            '<' => {
                if (found_open) std.log.err("On open, did not end previous tag: position: {}\n", .{i});
                const tag_type: TagType = getTagType(data, .{ .start = @truncate(i), .end = undefined });

                switch (tag_type) {
                    .prolog => {
                        if (found_prolog) std.log.err("On prolog, found more than 1: position: {}\n", .{i});
                        found_prolog = true;
                    },
                    else => {},
                }

                try tags.append(.{
                    .start = @truncate(i),
                    .end = undefined,
                });
                found_open = true;
            },
            '>' => {
                if (!found_open) std.log.err("On close, did not end previous tag: positon: {}\n", .{i});
                tags.items[j].end = @truncate(i);
                if (tags.items[j].end < tags.items[j].start) std.log.err("Tag: {} has end < start\n", .{i});
                found_open = false;
                j += 1;
            },
            '\'', '\"' => {
                i = skipComment(data, i);
            },
            else => {},
        }
    }

    return tags;
}

pub fn getTagType(data: []const u8, tag: Tag) TagType {
    return switch (data[tag.start + 1]) {
        '?' => .prolog,
        '/' => .close,
        'a'...'z', 'A'...'Z' => .open,
        else => unreachable,
    };
}

// test "Get Tag Type" {
//     const names = [_][]const u8{ "<name>", "</name>", "<?xml>" };
//     const values = [_]TagType{ .open, .close, .prolog };
//     for (names, values) |name, value| {
//         const tag_type = getTagType(name, .{ .start = 0, .end = @truncate(name.len) });
//         try std.testing.expect(tag_type == value);
//     }
// }

pub fn writeTags(
    allo: std.mem.Allocator,
    data: []const u8,
    filename: []const u8,
    tags: *const std.ArrayList(Tag),
) !void {
    const file = try std.fs.cwd().createFile(filename, .{});
    defer file.close();

    for (tags.items) |tag| {
        const line = try std.fmt.allocPrint(allo, "{s}\n", .{data[tag.start .. tag.end + 1]});
        defer allo.free(line);
        _ = file.write(line) catch unreachable;
    }
}

pub inline fn printTag(data: []const u8, tag: Tag) void {
    std.debug.print("{s}\n", .{data[tag.start .. tag.end + 1]});
}

pub fn printTags(data: []const u8, tags: []const Tag) void {
    for (tags) |tag| {
        printTag(data, tag);
    }
}

pub const TagType = enum {
    prolog,
    open,
    close,
};

fn turnOnBitsBW2Bits(
    comptime T: type,
    value: T,
    prev_carry: bool,
) struct { mask: T, carry: bool } {
    switch (@typeInfo(T)) {
        .int => |int| switch (int.signedness) {
            .signed => @compileError("T must be an unsigned int"),
            else => {},
        },
        else => @compileError("T must be an unsigned int"),
    }

    var temp: T = @bitReverse(value);
    var mask: T = value;

    const bits_as_u16 = @typeInfo(T).int.bits;
    const max_bit: T = if (@typeInfo(@TypeOf(bits_as_u16)).int.bits > bits_as_u16) @truncate(bits_as_u16) else bits_as_u16;

    if (prev_carry) {
        const first_bit = @ctz(temp);
        temp ^= @as(T, 1) << @truncate(first_bit);
        for (0..first_bit) |i| {
            mask |= @as(T, 1) << @truncate(max_bit - i - 1);
        }
    }
    // std.debug.print("Mask Prev: {b}\n", .{mask});

    var carry: bool = false;
    while (temp > 0) {
        const first_bit = @ctz(temp);
        temp ^= @as(T, 1) << @truncate(first_bit);

        const second_bit = @ctz(temp);
        if (second_bit == max_bit) {
            carry = true;
        } else {
            temp ^= @as(T, 1) << @truncate(second_bit);
        }

        for (first_bit..second_bit) |i| {
            mask |= @as(T, 1) << @truncate(max_bit - i - 1);
        }
    }
    // std.debug.print("Mask Curr: {b}\n", .{mask});

    return .{
        .mask = mask,
        .carry = carry,
    };
}

test "Create Mask" {
    const T: type = u8;
    const input_masks = [_]T{ 8, 66, 66, 74, 0, 255, 255 };
    const input_carries = [_]bool{ false, false, true, true, true, false, true };
    const expected_masks = [_]T{ 15, 126, 195, 206, 255, 255, 255 };
    const expected_carries = [_]bool{ true, false, true, false, true, false, true };

    for (input_masks, input_carries, expected_masks, expected_carries, 0..) |imask, icarry, emask, ecarry, i| {
        _ = i;
        // std.debug.print("\nTest {}: {}\n", .{ i, imask });
        const mask, const carry = blk: {
            const mask = turnOnBitsBW2Bits(T, imask, icarry);
            break :blk .{ mask.mask, mask.carry };
        };
        // std.debug.print("\nMasks: {b}->{b}: {b}\n", .{ @as(T, imask), @as(T, emask), @as(T, mask) });
        // std.debug.print("Carry: {}->{}: {}\n", .{ icarry, ecarry, carry });
        try std.testing.expect(mask == emask and carry == ecarry);
    }

    try std.testing.expect(true);
}
