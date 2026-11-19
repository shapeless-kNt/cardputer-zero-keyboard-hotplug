CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -Werror -std=gnu11
TARGET = build/libkeyboard-hotplug.so

all: $(TARGET)

$(TARGET): src/keyboard-hotplug.c
	mkdir -p build
	$(CC) $(CFLAGS) -shared -fPIC -o $@ $< -ldl

check: all
	bash -n install.sh uninstall.sh tests/check.sh
	bash tests/check.sh

clean:
	rm -rf build

.PHONY: all check clean
