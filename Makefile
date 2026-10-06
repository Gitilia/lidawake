PREFIX ?= /usr/local
BIN := lidawake

.PHONY: build test install clean

build: $(BIN)

$(BIN): main.swift
	swiftc -warnings-as-errors -O -o $(BIN) main.swift

test: build
	bash scripts/test.sh

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)

clean:
	rm -f $(BIN)
