const std = @import("std");
const Data = @import("Data.zig");
const Tag = @import("Tags.zig");

pub fn main() !void {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(.ok == da.deinit());
    const allo = da.allocator();

    // const filename = "src/vk.xml";
    const filename = "src/vk_extern_struct.xml";
    const data = try Data.init(allo, filename);
    defer data.deinit();

    const n_tags = try Tag.getNumberOfTagsV(u16, data);
    const n_tags2 = try Tag.getNumberOfTags(u16, data);
    std.debug.assert(n_tags == n_tags2);

    // try writeTags(allo, data, "src/tags.zig", &tags);
    // printTags(data, &tags);

    // // Parse Elements
    // var elements = try getElements(allo, data, tags.items);
    // defer elements.deinit(allo);
    // defer {
    //     const children = elements.items(.children);
    //     for (children) |maybe_child| {
    //         if (maybe_child) |child| {
    //             var list: std.ArrayList(u16) = @as(*std.ArrayList(u16), @ptrFromInt(child)).*;
    //             list.deinit();
    //         }
    //     }
    // }
    //
    // for (elements.items(.start), elements.items(.end)) |start, end| {
    //     const sname = getTagName(data, tags.items[start]);
    //     const ename = getTagName(data, tags.items[end]);
    //     std.debug.print("{s}:{s}\n", .{ sname, ename });
    //     // std.debug.print("{s}:{s}, {}:{}\n", .{ sname, ename, element.start, element.end });
    // }

    // Extract Extern Struct Data

}

// const Element = struct {
//     start: u16, // position inside []const Tag
//     end: u16, // position inside []const Tag
//     parent: u16, // position to elements array - if position = itself in the array, it has no parent
//     children: ?usize = null, // *std.ArrayList(u16) = null, children = positions in elements array, ptr is held as an int that points to std.ArrayList (saves some memory)
// };
//
// fn getElements(
//     allo: std.mem.Allocator,
//     data: []const u8,
//     tags: []const Tag,
// ) !std.MultiArrayList(Element) {
//     var elements = std.MultiArrayList(Element){};
//     errdefer elements.deinit(allo);
//     try elements.ensureTotalCapacity(allo, tags.len / 2);
//
//     var i: u16 = 0;
//     while (i < tags.len) : (i += 1) {
//         const tag = tags[i];
//         const tag_type = getTagType(data, tag);
//         switch (tag_type) {
//             .close => {
//                 var j: u16 = @truncate(elements.len - 1);
//                 if (j == 0) unreachable;
//
//                 const starts = elements.items(.start);
//                 const ends = elements.items(.end);
//
//                 while (true) : (j -= 1) {
//                     if (starts[j] != ends[j]) continue;
//
//                     const tag2 = tags[starts[j]];
//                     const prev_tag_type = getTagType(data, tag2);
//                     switch (prev_tag_type) {
//                         .close => continue,
//                         .prolog => unreachable,
//                         .open => {},
//                     }
//
//                     if (!tagNamesMatch(data, tag, tag2)) continue;
//
//                     ends[j] = i;
//                     break;
//                 }
//                 ends[j] = i;
//             },
//             else => { // prolog or open
//                 elements.appendAssumeCapacity(.{
//                     .start = i,
//                     .end = i,
//                     .parent = i, // null = same space as a regular ptr, less space this way
//                 });
//             },
//         }
//     }
//
//     // Identify Children
//     const starts = elements.items(.start);
//     const ends = elements.items(.end);
//     const rents = elements.items(.parent);
//     const children = elements.items(.children);
//     const len = elements.len;
//
//     i = 1;
//     while (i < len) : (i += 1) {
//         var j: u16 = i - 1;
//         while (true) : (j -= 1) {
//             if (starts[j] < starts[i] and ends[j] > ends[i]) {
//                 rents[i] = j;
//
//                 if (children[j]) |child| {
//                     var list = @as(*std.ArrayList(u16), @ptrFromInt(child)).*;
//                     try list.append(i);
//                     break;
//                 } else {
//                     var list = std.ArrayList(u16).init(allo);
//                     try list.append(i);
//                     children[j] = @intFromPtr(&list);
//                     break;
//                 }
//             }
//
//             if (j == 0) break;
//         }
//     }
//
//     return elements;
// }
//
// test "Get Elements" {
//     const data: []const u8 = "<1><2></2></1>";
//     const exp_names = [_][]const u8{ "1", "2" };
//     const exp_elem_ends = [_]Tag{
//         .{ .start = 0, .end = data.len - 1 },
//         .{ .start = 3, .end = 9 },
//     };
//
//     const allo = std.testing.allocator;
//
//     const tags = try getTags(allo, data);
//     defer tags.deinit();
//
//     const elements: std.ArrayList(Element) = try getElements(allo, data, tags);
//     defer elements.deinit();
//
//     for (elements.items, exp_names, exp_elem_ends) |element, exp_name, exp_elem_end| {
//         const elem_name = getTagName(data, element.start);
//         try std.testing.expectEqualStrings(elem_name, exp_name);
//
//         const match = tagNamesMatch(data, element.start, element.end);
//         try std.testing.expect(match);
//
//         try std.testing.expect(tags.items[element.start].start == exp_elem_end.start);
//         try std.testing.expect(tags.items[element.end].end == exp_elem_end.end);
//     }
// }
//
// fn isModified(e: Element) bool {
//     return e.start != e.end;
// }
//
// const ElementTree = struct {
//     root: ?*Element,
// };

// Notes:
// Extern Struct:
// Look for tags that start w/ type
// Parse the data
