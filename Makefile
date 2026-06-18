run:
	zig build run

build: 
	zig build

build-web:
	zig build web -Dtarget=wasm32-emscripten

run-web:
	zig build run -Dtarget=wasm32-emscripten
