const std = @import("std");
const builtin = @import("builtin");
const rl = @import("raylib");

// Zig 0.16's default debug Io is std.Io.Threaded, which currently fails to compile for wasm32-emscripten. On emscripten route std.debug through a
// no-op Io and trap on panic; native keeps default behavior.
pub const std_options_debug_io: std.Io = if (builtin.os.tag == .emscripten)
    std.Io.failing
else
    std.Io.Threaded.global_single_threaded.io();
pub const panic = if (builtin.os.tag == .emscripten) std.debug.no_panic else std.debug.FullPanic(std.debug.defaultPanic);

extern fn emscripten_set_main_loop_arg(
    func: *const fn (?*anyopaque) callconv(.c) void,
    arg: ?*anyopaque,
    fps: c_int,
    simulate_infinite_loop: c_int,
) void;

const screenWidth: i32 = 800;
const screenHeight: i32 = 600;

const title = "Zig Invaders";

const maxBullets: i32 = 10;
const maxEnemyBullets: i32 = 20;
const maxBorders: i32 = 3;

const invaderStartRows: usize = 5;
const invaderStartCols: usize = 11;

var game: Game = undefined;

const Game = struct {
    allocator: std.mem.Allocator,
    view: View,

    fn init(allocator: std.mem.Allocator) !@This() {
        return .{
            .allocator = allocator,
            .view = View{
                .run = try Run.init(allocator, 1),
            },
        };
    }

    fn cycle(self: *@This()) !void {
        try self.update();
        self.draw();
    }

    fn update(self: *@This()) !void {
        switch (self.view) {
            inline else => |*s| {
                if (try s.update(self.allocator)) |new| {
                    self.view = new;
                }
            },
        }
    }

    fn draw(self: *@This()) void {
        switch (self.view) {
            inline else => |*s| s.draw(),
        }
    }
};

const View = union(enum) {
    run: Run,
    gameOver: GameOver,
    levelUp: LevelUp,
};

const Run = struct {
    level: u8,
    player: Player,
    bullets: Bullets,
    enemyBullets: EnemyBullets,
    invaders: Invaders,
    borders: Borders,
    timer: Timer,
    score: Score,

    fn init(allocator: std.mem.Allocator, level: u8) !@This() {
        return .{
            .level = level,
            .player = Player.init(),
            .bullets = Bullets.init(),
            .enemyBullets = EnemyBullets.init(),
            .invaders = try Invaders.init(allocator, level),
            .borders = Borders.init(),
            .timer = Timer.init(),
            .score = Score.init(),
        };
    }

    fn deinit(self: *@This()) void {
        self.invaders.deinit();
    }

    fn update(self: *@This(), _: std.mem.Allocator) !?View {
        self.player.update();
        self.bullets.update(self.player);

        self.enemyBullets.update();
        self.enemyBullets.shoot(self.invaders);
        self.invaders.update();

        const hitBullet = self.bullets.checkBorderAndHit(&self.invaders, self.borders);

        if (hitBullet > 0) {
            self.score.incrementByCount(hitBullet);
        }

        const hitEnemyBullet = self.enemyBullets.checkBorderAndHit(self.player, self.borders);

        if (hitEnemyBullet > 0 and self.player.getHittedAndReturnIsDead()) {
            self.deinit();

            return View{
                .gameOver = GameOver.init(self.score.total, self.timer.getTimeParts()),
            };
        }

        if (self.invaders.areAllDead()) {
            self.deinit();

            return View{
                .levelUp = LevelUp.init(
                    self.score.total,
                    self.timer.getTimeParts(),
                    self.level + 1,
                ),
            };
        }

        self.timer.update();

        return null;
    }

    fn draw(self: @This()) void {
        self.player.draw();
        self.bullets.draw();
        self.enemyBullets.draw();
        self.invaders.draw();
        self.borders.draw();
        self.timer.draw();
        self.drawStatus();
    }

    fn drawStatus(self: @This()) void {
        const scoreText: [:0]const u8 = rl.textFormat("Level: %d, Score: %d, Lives: %d", .{
            self.level,
            self.score.total,
            self.player.lives,
        });
        rl.drawText(scoreText, 20, screenHeight - 20, 20, rl.Color.white);
    }

    fn view(self: *@This()) void {
        self.View.update();
        self.View.draw();
    }
};

const LevelUp = struct {
    score: i32,
    time: [8:0]u8,
    nextLevel: u8,

    fn init(score: i32, timeParts: struct { u64, u64 }, nextLevel: u8) @This() {
        var buffer: [8:0]u8 = std.mem.zeroes([8:0]u8);

        writeDisplayTimeIntoBuffer(&buffer, timeParts);
        return .{
            .nextLevel = nextLevel,
            .score = score,
            .time = buffer,
        };
    }

    fn update(self: @This(), allocator: std.mem.Allocator) !?View {
        if (rl.isKeyPressed(.enter)) {
            return View{ .run = try Run.init(allocator, self.nextLevel) };
        }
        return null;
    }

    fn draw(self: @This()) void {
        rl.drawText("Congratulations", 270, 250, 40, rl.Color.green);
        const scoreText = rl.textFormat(
            "You completed level %d with score of: %d and time: %s",
            .{
                self.nextLevel - 1,
                self.score,
                &self.time,
            },
        );
        rl.drawText(scoreText, 100, 310, 30, rl.Color.white);
    }
};

const GameOver = struct {
    score: i32,
    time: [8:0]u8,

    fn init(score: i32, timeParts: struct { u64, u64 }) @This() {
        var buffer: [8:0]u8 = std.mem.zeroes([8:0]u8);

        writeDisplayTimeIntoBuffer(&buffer, timeParts);
        return .{
            .score = score,
            .time = buffer,
        };
    }

    fn update(_: @This(), allocator: std.mem.Allocator) !?View {
        if (rl.isKeyPressed(.enter)) {
            return View{ .run = try Run.init(allocator, 1) };
        }
        return null;
    }

    fn draw(self: @This()) void {
        rl.drawText("GAME OVER", 270, 250, 40, rl.Color.red);
        const scoreText = rl.textFormat(
            "Final Score: %d with time Time: %s",
            .{
                self.score,
                &self.time,
            },
        );
        rl.drawText(scoreText, 100, 310, 30, rl.Color.white);
    }
};

const Rectangle = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,

    fn intersects(self: Rectangle, other: Rectangle) bool {
        return self.x < other.x + other.width and
            self.x + self.width > other.x and
            self.y < other.y + other.height and
            self.y + self.height > other.y;
    }

    fn intersectsAny(self: Rectangle, others: []const Rectangle) bool {
        for (others) |other| {
            if (self.intersects(other)) {
                return true;
            }
        }
        return false;
    }
};

const Score = struct {
    total: i32,
    value: i32,

    fn init() Score {
        return .{
            .total = 0,
            .value = 10,
        };
    }

    fn incrementByCount(self: *@This(), count: i32) void {
        self.total += self.value * count;
    }
};

const Player = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    lives: i32,

    fn init() @This() {
        const playerWidth: f32 = 50;
        const playerHeight: f32 = 30;

        return .{
            .position_x = @as(f32, @floatFromInt(screenWidth)) / 2 - playerWidth / 2,
            .position_y = @as(f32, @floatFromInt(screenHeight)) - 60,
            .width = playerWidth,
            .height = playerHeight,
            .speed = 5.0,
            .lives = 3,
        };
    }

    fn update(self: *@This()) void {
        if (rl.isKeyDown(.right) and self.position_x + self.width < @as(f32, @floatFromInt(rl.getScreenWidth()))) {
            self.position_x += self.speed;
        }
        if (rl.isKeyDown(.left) and self.position_x > 0) {
            self.position_x -= self.speed;
        }
    }

    fn getHittedAndReturnIsDead(self: *@This()) bool {
        self.decrementLive();
        self.reduceSize();

        if (self.lives == 0) {
            return true;
        }
        return false;
    }

    fn reduceSize(self: *@This()) void {
        self.width = self.width * 0.66;
        self.height = self.height * 0.66;
    }

    fn decrementLive(self: *@This()) void {
        self.lives -= 1;
    }

    fn draw(self: @This()) void {
        rl.drawRectangle(
            @intFromFloat(self.position_x),
            @intFromFloat(self.position_y),
            @intFromFloat(self.width),
            @intFromFloat(self.height),
            rl.Color.blue,
        );
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const Bullets = struct {
    bullets: [maxBullets]Bullet,

    fn init() @This() {
        var bullets: [maxBullets]Bullet = undefined;
        for (&bullets) |*bullet| {
            bullet.* = Bullet.init();
        }

        return .{ .bullets = bullets };
    }

    fn update(self: *@This(), player: Player) void {
        if (rl.isKeyPressed(.space)) {
            for (&self.bullets) |*bullet| {
                if (bullet.spawn(player)) {
                    break;
                }
            }
        }

        for (&self.bullets) |*bullet| {
            bullet.update();
        }
    }

    fn draw(self: @This()) void {
        for (self.bullets) |bullet| {
            bullet.draw();
        }
    }

    fn checkBorderAndHit(self: *@This(), invaders: *Invaders, borders: Borders) i32 {
        var hit: i32 = 0;

        for (&self.bullets) |*bullet| {
            if (!bullet.active) {
                continue;
            }

            const bulletRect = bullet.getRect();

            if (bulletRect.intersectsAny(&borders.getRects())) {
                bullet.active = false;
                continue;
            }

            for (invaders.invaders) |row| {
                for (row) |*invader| {
                    if (invader.active and bulletRect.intersects(invader.getRect())) {
                        invader.active = false;
                        bullet.active = false;
                        hit += 1;
                        break;
                    }
                }
            }
        }

        return hit;
    }
};

const Bullet = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    pub fn init() @This() {
        return .{
            .position_x = 0,
            .position_y = 0,
            .width = 4.0,
            .height = 10.0,
            .speed = 10.0,
            .active = false,
        };
    }

    fn spawn(self: *@This(), player: Player) bool {
        if (!self.active) {
            self.position_x = player.position_x + player.width / 2 - self.width / 2;
            self.position_y = player.position_y;
            self.active = true;
            return true;
        }
        return false;
    }

    fn update(self: *@This()) void {
        if (self.active) {
            self.position_y -= self.speed;
            if (self.position_y < 0) {
                self.active = false;
            }
        }
    }

    fn draw(self: @This()) void {
        if (self.active) {
            rl.drawRectangle(
                @intFromFloat(self.position_x),
                @intFromFloat(self.position_y),
                @intFromFloat(self.width),
                @intFromFloat(self.height),
                rl.Color.red,
            );
        }
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const Invaders = struct {
    allocator: std.mem.Allocator,
    invaders: [][]Invader,
    speed: f32,
    moveDelay: i32,
    direction: f32,
    moveTimer: i32,
    dropDistance: f32,

    fn init(allocator: std.mem.Allocator, level: u8) !@This() {
        const invadersRowsLevel: usize = invaderStartRows + @as(usize, level) - 1;
        const invadersColsLevel: usize = invaderStartCols + @as(usize, level) - 1;

        var invaders = try allocator.alloc([]Invader, invadersRowsLevel);
        errdefer allocator.free(invaders);

        var allocatedRows: usize = 0;
        errdefer {
            for (0..allocatedRows) |i| {
                allocator.free(invaders[i]);
            }
        }

        while (allocatedRows < invadersRowsLevel) : (allocatedRows += 1) {
            invaders[allocatedRows] = try allocator.alloc(Invader, invadersColsLevel);
        }

        const invadersWidth: f32 = 640.0;
        const invadersHeight: f32 = 190.0;

        const spaceX: f32 = 20.0;
        const spaceY: f32 = 10.0;

        const totalSpaceX = spaceX * @as(f32, @floatFromInt(invadersColsLevel - 1));
        const totalSpaceY = spaceY * @as(f32, @floatFromInt(invadersRowsLevel - 1));

        const invaderWidth =
            (invadersWidth - totalSpaceX) / @as(f32, @floatFromInt(invadersColsLevel));

        const invaderHeight =
            (invadersHeight - totalSpaceY) / @as(f32, @floatFromInt(invadersRowsLevel));

        const startX: f32 = 100.0;
        const startY: f32 = 50.0;

        for (0..invadersRowsLevel) |i| {
            for (0..invadersColsLevel) |j| {
                const x =
                    startX +
                    @as(f32, @floatFromInt(j)) *
                        (spaceX + invaderWidth);

                const y =
                    startY +
                    @as(f32, @floatFromInt(i)) *
                        (spaceY + invaderHeight);

                invaders[i][j] = Invader.init(
                    x,
                    y,
                    invaderWidth,
                    invaderHeight,
                );
            }
        }

        return .{
            .allocator = allocator,
            .invaders = invaders,
            .speed = 5.0,
            .moveDelay = 30,
            .direction = 1.0,
            .moveTimer = 0,
            .dropDistance = 20.0,
        };
    }

    fn deinit(self: *@This()) void {
        for (self.invaders) |row| {
            self.allocator.free(row);
        }

        self.allocator.free(self.invaders);
    }

    fn update(self: *@This()) void {
        self.moveTimer += 1;
        if (self.moveTimer >= self.moveDelay) {
            self.moveTimer = 0;

            var hitEdge = false;

            for (self.invaders) |row| {
                for (row) |invader| {
                    if (invader.active) {
                        const nextX = invader.position_x + (self.speed * self.direction);
                        if (nextX < 0 or nextX + invader.width > @as(f32, @floatFromInt(screenWidth))) {
                            hitEdge = true;
                            break;
                        }
                    }
                }
                if (hitEdge) {
                    break;
                }
            }

            if (hitEdge) {
                self.direction *= -1.0;
                for (self.invaders) |row| {
                    for (row) |*invader| {
                        invader.update(0, self.dropDistance);
                    }
                }
            } else {
                for (self.invaders) |row| {
                    for (row) |*invader| {
                        invader.update(self.speed * self.direction, 0);
                    }
                }
            }
        }
    }

    fn draw(self: @This()) void {
        for (self.invaders) |row| {
            for (row) |invader| {
                invader.draw();
            }
        }
    }

    fn areAllDead(self: @This()) bool {
        for (self.invaders) |row| {
            for (row) |invader| {
                if (invader.active) {
                    return false;
                }
            }
        }

        return true;
    }
};

const Invader = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    fn init(
        position_x: f32,
        position_y: f32,
        width: f32,
        height: f32,
    ) @This() {
        return .{
            .position_x = position_x,
            .position_y = position_y,
            .width = width,
            .height = height,
            .speed = 5.0,
            .active = true,
        };
    }

    fn update(self: *@This(), dx: f32, dy: f32) void {
        self.position_x += dx;
        self.position_y += dy;
    }

    fn draw(self: @This()) void {
        if (self.active) {
            rl.drawRectangle(
                @intFromFloat(self.position_x),
                @intFromFloat(self.position_y),
                @intFromFloat(self.width),
                @intFromFloat(self.height),
                rl.Color.green,
            );
        }
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const EnemyBullets = struct {
    enemyBullets: [maxEnemyBullets]EnemyBullet,
    enemyShootDelay: i32,
    enemyShootChance: i32,
    enemyShootTimer: i32,

    fn init() @This() {
        var enemyBullets: [maxEnemyBullets]EnemyBullet = undefined;

        for (&enemyBullets) |*enemyBullet| {
            enemyBullet.* = EnemyBullet.init();
        }

        return .{
            .enemyBullets = enemyBullets,
            .enemyShootDelay = 60,
            .enemyShootChance = 5,
            .enemyShootTimer = 0,
        };
    }

    fn update(self: *@This()) void {
        for (&self.enemyBullets) |*bullet| {
            bullet.update();
        }
    }

    fn checkBorderAndHit(self: *@This(), player: Player, borders: Borders) i32 {
        var hit: i32 = 0;

        for (&self.enemyBullets) |*bullet| {
            if (bullet.active) {
                var bulletRect = bullet.getRect();

                if (bulletRect.intersects(player.getRect())) {
                    hit = hit + 1;
                    bullet.active = false;
                    continue;
                }

                if (bulletRect.intersectsAny(&borders.getRects())) {
                    bullet.active = false;
                }
            }
        }

        return hit;
    }

    fn shoot(self: *@This(), invaders: Invaders) void {
        self.enemyShootTimer += 1;
        if (self.enemyShootTimer >= self.enemyShootDelay) {
            self.enemyShootTimer = 0;
            for (invaders.invaders) |row| {
                for (row) |invader| {
                    if (invader.active and rl.getRandomValue(0, 100) < self.enemyShootChance) {
                        for (&self.enemyBullets) |*bullet| {
                            if (!bullet.active) {
                                bullet.position_x = invader.position_x + invader.width / 2 - bullet.width / 2;
                                bullet.position_y = invader.position_y + invader.height;
                                bullet.active = true;
                                break;
                            }
                        }
                        break;
                    }
                }
            }
        }
    }

    fn draw(self: @This()) void {
        for (self.enemyBullets) |bullet| {
            bullet.draw();
        }
    }
};

const EnemyBullet = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,
    speed: f32,
    active: bool,

    fn init() @This() {
        return .{
            .position_x = 0,
            .position_y = 0,
            .width = 4.0,
            .height = 10.0,
            .speed = 5.0,
            .active = false,
        };
    }

    fn update(self: *@This()) void {
        if (self.active) {
            self.position_y += self.speed;
            if (self.position_y > @as(f32, @floatFromInt(screenHeight))) {
                self.active = false;
            }
        }
    }

    fn draw(self: @This()) void {
        if (self.active) {
            rl.drawRectangle(
                @intFromFloat(self.position_x),
                @intFromFloat(self.position_y),
                @intFromFloat(self.width),
                @intFromFloat(self.height),
                rl.Color.yellow,
            );
        }
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const Borders = struct {
    borders: [maxBorders]Border,

    fn init() @This() {
        var borders: [maxBorders]Border = undefined;

        const borderHeight: f32 = 30;
        const covered: f32 = 0.25 * @as(f32, @floatFromInt(screenWidth));
        const borderWidth: f32 = covered / maxBorders;
        const space: f32 = (@as(f32, @floatFromInt(screenWidth)) - covered);
        const spaceWidth: f32 = space / (maxBorders + 1);

        for (&borders, 0..) |*border, i| {
            const x: f32 = @as(f32, @floatFromInt(i)) * borderWidth + (@as(f32, @floatFromInt(i)) + 1) * spaceWidth;
            border.* = Border.init(x, 450, borderWidth, borderHeight);
        }

        return .{ .borders = borders };
    }

    fn draw(self: @This()) void {
        for (self.borders) |border| {
            border.draw();
        }
    }

    fn getRects(self: @This()) [maxBorders]Rectangle {
        var rects: [maxBorders]Rectangle = undefined;

        for (self.borders, 0..) |border, i| {
            rects[i] = border.getRect();
        }

        return rects;
    }
};

const Border = struct {
    position_x: f32,
    position_y: f32,
    width: f32,
    height: f32,

    pub fn init(x: f32, y: f32, w: f32, h: f32) @This() {
        return .{
            .position_x = x,
            .position_y = y,
            .width = w,
            .height = h,
        };
    }

    fn draw(self: @This()) void {
        rl.drawRectangle(
            @intFromFloat(self.position_x),
            @intFromFloat(self.position_y),
            @intFromFloat(self.width),
            @intFromFloat(self.height),
            rl.Color.brown,
        );
    }

    fn getRect(self: @This()) Rectangle {
        return .{
            .x = self.position_x,
            .y = self.position_y,
            .width = self.width,
            .height = self.height,
        };
    }
};

const Timer = struct {
    start_ms: u64,
    displayBuffer: [8:0]u8,

    fn init() @This() {
        return .{
            .start_ms = getNowMs(),
            .displayBuffer = std.mem.zeroes([8:0]u8),
        };
    }

    fn getNowMs() u64 {
        return @intFromFloat(rl.getTime() * 1000.0);
    }

    fn getElapsedMs(self: @This()) u64 {
        return getNowMs() - self.start_ms;
    }

    fn getTimeParts(self: @This()) struct { u64, u64 } {
        const total = self.getElapsedMs() / 1000;
        return .{ total / 60, total % 60 };
    }

    fn update(self: *Timer) void {
        const time = self.getTimeParts();
        writeDisplayTimeIntoBuffer(&self.displayBuffer, time);
    }

    fn draw(self: Timer) void {
        rl.drawText(&self.displayBuffer, screenWidth - 80, 20, 20, rl.Color.yellow);
    }
};

fn writeDisplayTimeIntoBuffer(buffer: *[8:0]u8, time: struct { u64, u64 }) void {
    _ = std.fmt.bufPrintZ(
        buffer,
        "{d:0>2}:{d:0>2}",
        .{ time[0], time[1] },
    ) catch {};
}

fn updateDrawFrame(arg: ?*anyopaque) callconv(.c) void {
    rl.beginDrawing();
    defer rl.endDrawing();
    rl.clearBackground(rl.Color.black);

    const game_ptr: *Game = @ptrCast(@alignCast(arg.?));

    game_ptr.cycle() catch |err| {
        std.debug.print("Game error: {}\n", .{err});
    };
}

pub fn main() !void {
    rl.initWindow(800, 600, title);
    defer rl.closeWindow();

    rl.setTargetFPS(60);

    var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    game = try Game.init(allocator);

    if (builtin.os.tag == .emscripten) {
        emscripten_set_main_loop_arg(updateDrawFrame, &game, 0, 1);
    } else {
        while (!rl.windowShouldClose()) {
            updateDrawFrame(&game);
        }
    }
}
