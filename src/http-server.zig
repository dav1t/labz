const std = @import("std");
const Io = std.Io;
const net = Io.net;
const http = std.http;
const Allocator = std.mem.Allocator;

pub const LabzServer = struct {
    address: net.IpAddress,
    io: Io,
    gpa: std.mem.Allocator,

    tcp_server: ?net.Server,
    router: ?Router,
    handler_context: HandlerContext,

    pub const HandlerContext = struct { allocator: std.mem.Allocator };

    const Route = struct {
        handler: *const fn (context: *HandlerContext, request: *http.Server.Request) anyerror!void,
        target: []const u8,
        method: std.http.Method,

        pub fn init(target: []const u8, handler: *const fn (context: *HandlerContext, request: *http.Server.Request) anyerror!void, method: http.Method) Route {
            return .{ .target = target, .handler = handler, .method = method };
        }
    };

    const Router = struct {
        routes: std.StringHashMap(Route),

        pub fn init(server: *LabzServer) Router {
            return .{ .routes = .init(server.gpa) };
        }

        pub fn get(self: *Router, path: []const u8, handler: *const fn (context: *HandlerContext, request: *http.Server.Request) anyerror!void) !void {
            const r: Route = .init(path, handler, http.Method.GET);

            try self.routes.put(path, r);
        }

        pub fn deinit(self: *Router) void {
            self.routes.deinit();
        }
    };

    pub const Options = struct { gpa: Allocator, io: Io, address: net.IpAddress };

    pub fn init(opts: Options) LabzServer {
        return .{ .tcp_server = null, .router = null, .io = opts.io, .gpa = opts.gpa, .address = opts.address, .handler_context = .{ .allocator = opts.gpa } };
    }

    // We can Add some options here for routes
    pub fn initRouter(self: *LabzServer) *Router {
        self.router = .init(self);

        return &self.router.?;
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

            // Here with errors we can swithc to proper global response
            self.route(&request) catch |err| {
                std.debug.print("failed to route: {t}\n", .{err});
            };
        }
    }

    fn route(self: *LabzServer, request: *http.Server.Request) !void {
        const router = self.router orelse {
            std.debug.print("Router not initialized\n", .{});
            return;
        };

        const target = request.head.target;

        const r = router.routes.get(target) orelse {
            std.debug.print("Route not found: {s}\n", .{target});
            try responseJson(request, .not_found, "{}");
            return;
        };

        try r.handler(&self.handler_context, request);
    }

    pub fn responseJson(request: *http.Server.Request, status: http.Status, body: []const u8) !void {
        try request.respond(body, .{ .status = status, .extra_headers = &.{.{
            .name = "content-type",
            .value = "application/json",
        }} });
    }

    pub fn deinit(self: *LabzServer) void {
        self.router.?.deinit();
    }
};
