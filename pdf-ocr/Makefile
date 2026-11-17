PREFIX ?= $(HOME)/.local
BIN := bin/pdf-ocr

$(BIN): Sources/pdf-ocr.swift
	@mkdir -p bin .build/module-cache
	swiftc -O -module-cache-path .build/module-cache $< -o $@

.PHONY: install clean
install: $(BIN)
	install -d $(PREFIX)/bin
	install -m 755 $(BIN) $(PREFIX)/bin/pdf-ocr

clean:
	rm -rf bin .build
