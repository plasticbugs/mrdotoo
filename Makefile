# Mr. Do! arcade port for ColecoVision + SGM
ROM      := build/mrdo.rom
SRC      := $(wildcard src/*.asm src/*.inc)
DATA     := build/font.bin
OPENMSX  ?= /Applications/openMSX.app/Contents/MacOS/openmsx

all: $(ROM)

build/font.bin: tools/gen_font.py
	python3 tools/gen_font.py > /dev/null

$(ROM): $(SRC) $(DATA)
	sjasmplus --nologo --msg=war -Wno-fileorg --fullpath -Isrc --sym=build/mrdo.sym --lst=build/mrdo.lst src/main.asm
	@test $$(wc -c < $(ROM)) -eq 131072 || (echo "ROM is not 128KB"; exit 1)

run: $(ROM)
	$(OPENMSX) -machine ColecoVision_SGM -carta $(ROM) -romtype ColecoMegaCart

test: $(ROM)
	tools/test_boot.sh

clean:
	rm -rf build

.PHONY: all run test clean
