const std = @import("std");
const darwin = @import("./darwin.zig");

pub fn main() !void {
    const windowList = try darwin.WindowList.init();
    defer windowList.deinit();

    const n = windowList.count();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const check = gpa.deinit();
        switch (check) {
            .ok => {},
            .leak => std.debug.print("leaked\n", .{}),
        }
    }

    var windows: []darwin.Window = undefined;
    windows = try allocator.alloc(darwin.Window, n);

    defer {
        for (windows) |w| {
            w.deinit() catch {
                std.debug.print("error deinit\n", .{});
            };
        }

        allocator.free(windows);
    }

    try windowList.makeWindows(allocator, windows, n);

    for (0..n) |k| {
        const w = windows[k];
        w.print();
    }
}
