# tests/Makefile — host (macOS) unit tests for access_group.c.
#
# Targets:
#   make test    Build and run unit tests
#   make clean   Remove the test binary

CC      ?= clang
CFLAGS  := -Wall -Wextra -Wno-deprecated-declarations -O0 -g
LDFLAGS := -framework CoreFoundation -framework Security
SRCS    := test_access_group.c ../access_group.c

.PHONY: test clean

test: test-runner
	./test-runner

test-runner: $(SRCS) ../access_group.h
	$(CC) $(CFLAGS) $(SRCS) $(LDFLAGS) -o $@

clean:
	rm -f test-runner
