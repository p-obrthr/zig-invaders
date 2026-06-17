const std = @import("std");
const c = @cImport({
    @cInclude("raylib.h");
});

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    pub fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }
};

const Player = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,

    pub fn init(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{
            .position_x = x,
            .position_y = y,
            .width = w,
            .height = h,
            .speed = 5.0,
        };
    }

    pub fn update(self: *@This()) void {
        if (c.IsKeyDown(c.KEY_RIGHT) and self.position_x + self.width < @as(f32, @floatFromInt(c.GetScreenWidth()))) {
            self.position_x += self.speed;
        }
        if (c.IsKeyDown(c.KEY_LEFT) and self.position_x > 0) {
            self.position_x -= self.speed;
        }
    }

    pub fn draw(self: @This()) void {
        c.DrawRectangle(
            @intFromFloat(self.position_x),
            @intFromFloat(self.position_y),
            @intFromFloat(self.width),
            @intFromFloat(self.height),
            c.BLUE,
        );
    }
};

const Timer = struct {
    start_ms: u64,
    buffer: [32]u8,

    pub fn init() @This() {
        return .{
            .buffer = [_]u8{0} ** 32,
            .start_ms = get_now_ms(),
        };
    }

    fn get_now_ms() u64 {
        return @intFromFloat(c.GetTime() * 1000.0);
    }

    fn get_elapsed_ms(self: @This()) u64 {
        return get_now_ms() - self.start_ms;
    }

    pub fn get_time_text(self: *@This()) [:0]const u8 {
        const total_seconds = self.get_elapsed_ms() / 1000;

        const mins: u64 = total_seconds / 60;
        const secs: u64 = total_seconds % 60;

        return std.fmt.bufPrintZ(
            &self.buffer,
            "{d:0>2}:{d:0>2}",
            .{ mins, secs },
        ) catch unreachable;
    }

    pub fn draw(self: *@This(), screenWidth: i32) void {
        c.DrawText(self.get_time_text().ptr, screenWidth - 80, 20, 20, c.YELLOW);
    }
};

pub fn main() !void {
    const screenWidth: i32 = 800;
    const screenHeight: i32 = 600;

    const title = "Zig Invaders";

    c.InitWindow(screenWidth, screenHeight, title);
    defer c.CloseWindow();

    c.SetTargetFPS(60);

    const playerWidth: f32 = 50;
    const playerHeight: f32 = 30;

    var player = Player.init(
        @as(f32, @floatFromInt(screenWidth)) / 2 - playerWidth / 2,
        @as(f32, @floatFromInt(screenHeight)) - 60,
        playerWidth,
        playerHeight,
    );

    var timer = Timer.init();

    while (!c.WindowShouldClose()) {
        c.BeginDrawing();
        defer c.EndDrawing();

        c.ClearBackground(c.BLACK);

        player.update();
        player.draw();
        timer.draw(screenWidth);

        c.DrawText(title, 300, 250, 40, c.GREEN);
    }
}
