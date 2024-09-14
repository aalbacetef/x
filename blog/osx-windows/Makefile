
build:
	zig build


test:
	zig build test


run: build
	./zig-out/bin/osx-windows


clean:
	rm -rf zig-out 
	rm -rf .zig-cache

.PHONY: build test run clean
