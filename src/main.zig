const std = @import("std");
const http = std.http;
const net = std.Io.net;
const LabzServer = @import("http-server.zig").LabzServer;

fn getRame(context: *LabzServer.HandlerContext, request: *http.Server.Request) !void {
    const response = .{
        .status = "ok",
    };

    const json = std.json.Stringify.valueAlloc(context.allocator, response, .{}) catch |err| switch (err) {
        error.OutOfMemory => return std.debug.print("Failed to serialize json\n", .{}),
    };
    defer context.allocator.free(json);

    LabzServer.responseJson(request, .ok, json) catch |err| {
        return std.debug.print("Failed to respond http request: {t} \n", .{err});
    };
}

pub fn main(init: std.process.Init) !void {
    const address = try net.IpAddress.parse("127.0.0.1", 1121);
    var server = LabzServer.init(.{ .address = address, .gpa = init.gpa, .io = init.io });
    defer server.deinit();
    var router = server.initRouter();

    try router.get("/test", getRame);
    try server.start();
}
