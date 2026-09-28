# Mr. Do! arcade port for ColecoVision + SGM
ROM      := build/mrdo.rom
SRC      := $(wildcard src/*.asm src/*.inc)
DATA     := build/font.bin build/arc_lo.bin build/arc_hi.bin build/tiles/sets.bin build/sprites/pat.bin build/sprites/pin.bin build/screens/banks.bin build/images/extra.bin build/tiles/hud.bin
DIS      ?= $(HOME)/work/do_disassemble
OPENMSX  ?= /Applications/openMSX.app/Contents/MacOS/openmsx

all: $(ROM)

build/font.bin: tools/gen_font.py
	python3 tools/gen_font.py > /dev/null

build/tiles/sets.bin: tools/gen_tiles.py build/sprites/pat.bin
	python3 tools/gen_tiles.py

build/tiles/hud.bin: tools/gen_hud.py tools/gen_tiles.py
	python3 tools/gen_hud.py

build/sprites/pat.bin build/sprites/pin.bin: tools/gen_sprites.py tools/gen_sprites_hack.py
	python3 tools/gen_sprites.py
	python3 tools/gen_sprites_hack.py

build/screens/banks.bin: tools/gen_screens.py tools/gen_tiles.py $(wildcard tools/data/screens/*.txt)
	python3 tools/gen_screens.py

build/codemap.json: tools/codemap.py tools/z80dis.py tools/data/ghidra_functions.txt
	python3 tools/codemap.py

build/arc_lo.bin build/arc_hi.bin: tools/patch_arcade.py build/codemap.json
	python3 tools/patch_arcade.py

$(ROM): $(SRC) $(DATA)
	sjasmplus --nologo --msg=war -Wno-fileorg --fullpath -Isrc -I. --sym=build/mrdo.sym --lst=build/mrdo.lst src/main.asm
	@test $$(wc -c < $(ROM)) -eq 524288 || (echo "ROM is not 512KB"; exit 1)
	@python3 tools/check_rom.py $(ROM)

build/arc_lo_validate.bin: tools/patch_arcade.py build/codemap.json
	python3 tools/patch_arcade.py --validate

build/mrdo_validate.rom: $(SRC) $(DATA) build/arc_lo_validate.bin
	sjasmplus --nologo --msg=war -Wno-fileorg --fullpath -Isrc -I. -DVALIDATE --sym=build/mrdo_validate.sym src/main.asm
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

build/images/extra.bin: tools/gen_images.py
	python3 tools/gen_images.py
