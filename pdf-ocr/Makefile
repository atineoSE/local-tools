PREFIX ?= $(HOME)/.local
BIN := bin/pdf-ocr

.PHONY: build install clean
build:
	swift build -c release
	@mkdir -p bin
	ln -sf ../.build/release/pdf-ocr $(BIN)

# A symlink, not a copy: pdf-ocr follows it back to this folder to find names.txt.
install: build
	install -d $(PREFIX)/bin
	ln -sf $(CURDIR)/.build/release/pdf-ocr $(PREFIX)/bin/pdf-ocr

clean:
	rm -rf bin .build
