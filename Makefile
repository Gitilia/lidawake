PREFIX ?= /usr/local
BIN := lidawake
UNAME_S := $(shell uname -s)

.PHONY: build test install clean

ifeq ($(UNAME_S),Darwin)

build: $(BIN)

$(BIN): main.swift
	swiftc -warnings-as-errors -O -o $(BIN) main.swift

test: build
	bash scripts/test.sh
	bash scripts/test-linux.sh

install: build
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/$(BIN)

else ifeq ($(UNAME_S),Linux)

build:
	@echo "Linux lidawake is scripts/lidawake (no compiler step)"

test:
	bash scripts/test-linux.sh

install:
	install -d $(PREFIX)/bin
	install -m 755 scripts/lidawake $(PREFIX)/bin/$(BIN)

else

build test install:
	$(error lidawake supports Darwin and Linux only)

endif

clean:
	rm -f $(BIN)
