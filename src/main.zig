const std = @import("std");
const Io = std.Io;
const net = Io.net;
const Allocator = std.mem.Allocator;
const http = std.http;

const LabzServer = struct {
    address: net.IpAddress,
    io: Io,
    gpa: std.mem.Allocator,

    tcp_server: ?net.Server,

    pub const Options = struct { gpa: Allocator, io: Io, address: net.IpAddress };

    pub fn init(opts: Options) LabzServer {
        return .{
            .tcp_server = null,

            .io = opts.io,
            .gpa = opts.gpa,
            .address = opts.address,
        };
    }

    pub fn start(self: *LabzServer) !void {
        std.debug.assert(self.tcp_server == null);
        self.tcp_server = self.address.listen(self.io, .{ .reuse_address = true }) catch |err| {
            return err;
        };

        try self.serve();
        // const res = self.io.concurrent(serve, .{self}) catch |err| {
        //     std.debug.print("unable to spawn web server thread {t}", .{err});
        //     self.tcp_server.?.deinit(self.io);
        //     self.tcp_server = null;
        //     return err;
        // };
        // _ = res;
    }

    fn serve(self: *LabzServer) !void {
        while (true) {
            const stream = self.tcp_server.?.accept(self.io) catch |err| {
                std.debug.print("{any}\n", .{err});
                return err;
            };

            const res = self.io.concurrent(handleConnection, .{ self, stream }) catch |err| {
                std.debug.print("unable to spawn connection thread: {t}", .{err});
                stream.close(self.io);
                continue;
            };

            _ = res;
        }
    }

    fn handleConnection(self: *LabzServer, stream: net.Stream) void {
        const io = self.io;
        defer {
            var copy = stream;
            copy.close(io);
        }

        var send_buffer: [4096]u8 = undefined;
        var recv_buffer: [4096]u8 = undefined;

        var connection_reader = stream.reader(io, &recv_buffer);
        var connection_writer = stream.writer(io, &send_buffer);

        var server: http.Server = .init(&connection_reader.interface, &connection_writer.interface);

        while (server.reader.state == .ready) {
            var request = server.receiveHead() catch |err| switch (err) {
                error.HttpConnectionClosing => return,
                else => return std.debug.print("Failed to receive http request: {t}", .{err}),
            };

            const response = .{
                .status = "ok",
            };

            const json = std.json.Stringify.valueAlloc(self.gpa, response, .{}) catch |err| switch (err) {
                error.OutOfMemory => return std.debug.print("Failed to serialize json\n", .{}),
            };

            responseJson(&request, .ok, json) catch |err| {
                return std.debug.print("Failed to respond http request: {t} \n", .{err});
            };
        }
    }

    fn responseJson(request: *http.Server.Request, status: http.Status, body: []const u8) !void {
        try request.respond(body, .{ .status = status, .extra_headers = &.{.{
            .name = "content-type",
            .value = "application/json",
        }} });
    }
};

pub fn main(init: std.process.Init) !void {
    const address = try net.IpAddress.parse("127.0.0.1", 1121);
    var server = LabzServer.init(.{ .address = address, .gpa = init.gpa, .io = init.io });
    try server.start();
}
