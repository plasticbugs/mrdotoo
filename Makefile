# Mr. Do! arcade port for ColecoVision + SGM
ROM      := build/mrdo.rom
SRC      := $(wildcard src/*.asm src/*.inc)
DATA     := build/font.bin build/arc_lo.bin build/arc_hi.bin
DIS      ?= $(HOME)/work/do_disassemble
OPENMSX  ?= /Applications/openMSX.app/Contents/MacOS/openmsx

all: $(ROM)

build/font.bin: tools/gen_font.py
	python3 tools/gen_font.py > /dev/null

build/codemap.json: tools/codemap.py tools/z80dis.py tools/data/ghidra_functions.txt
	python3 tools/codemap.py

build/arc_lo.bin build/arc_hi.bin: tools/patch_arcade.py build/codemap.json
	python3 tools/patch_arcade.py

$(ROM): $(SRC) $(DATA)
	sjasmplus --nologo --msg=war -Wno-fileorg --fullpath -Isrc --sym=build/mrdo.sym --lst=build/mrdo.lst src/main.asm
	@test $$(wc -c < $(ROM)) -eq 131072 || (echo "ROM is not 128KB"; exit 1)
	@python3 tools/check_rom.py $(ROM)

build/arc_lo_validate.bin: tools/patch_arcade.py build/codemap.json
	python3 tools/patch_arcade.py --validate

build/mrdo_validate.rom: $(SRC) $(DATA) build/arc_lo_validate.bin
	sjasmplus --nologo --msg=war -Wno-fileorg --fullpath -Isrc -DVALIDATE --sym=build/mrdo_validate.sym src/main.asm
	@python3 tools/check_rom.py build/mrdo_validate.rom

validate: build/mrdo_validate.rom
	tools/diff/run_diff.sh $(or $(FRAMES),3000) $(or $(SEED),1)

run: $(ROM)
	$(OPENMSX) -machine ColecoVision_SGM -carta $(ROM) -romtype ColecoMegaCart

test: $(ROM)
	tools/test_boot.sh

clean:
	rm -rf build

.PHONY: all run test validate clean
