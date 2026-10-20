# Mr. Do! for ColecoVision

Mr. Do!, the 1982 arcade game by Universal, made for the ColecoVision with the
Super Game Module. It runs the arcade game's own program, so the monsters, apples
and scoring behave as they do in the arcade. You see the full arcade playfield, and
the screen scrolls to follow Mr. Do.

**This is a preview.** In the busiest rounds the game runs slower than the arcade.

## What you need

- **Your own copy of the Mr. Do! arcade game** as used by the MAME arcade emulator.
  It is a file called **`mrdo.zip`**. This project can't give it to you.
- **A computer with a web browser:** a recent Chrome, Edge, Firefox or Safari.
- **Something to play it on**, either:
  - a ColecoVision with the **Super Game Module** and a flash cartridge that can
    run large ("MegaCart") games, or
  - the free **[openMSX](https://openmsx.org/)** emulator on your computer.

## Make the game file

This takes about a minute and you don't need to install anything.

1. Go to the **[Releases page](https://github.com/plasticbugs/mrdotoo/releases)**
   and download **`mrdo-cv-builder.html`**.
2. Find the downloaded file (usually in your *Downloads* folder) and double-click
   it. It opens in your web browser.
3. Click **Choose mrdo.zip…** and pick your `mrdo.zip`. You can also drag the
   file onto the page.
4. When the page says **"Your cartridge file is ready"**, click
   **Save mrdo_cv.rom**.

You now have **`mrdo_cv.rom`**, the game.

Everything happens on your own computer: your files are not uploaded anywhere, and
the page works without an internet connection.

## Play it

### On a ColecoVision

1. Copy `mrdo_cv.rom` to your flash cartridge, the same way you add any other game
   (for most carts, that means copying it onto the cart's SD card).
2. Make sure the **Super Game Module** is plugged in and switched on.
3. Start the game from your flash cartridge's menu.

### In the openMSX emulator

1. Open openMSX.
2. Choose the machine **ColecoVision with SGM**. Plain "ColecoVision" won't
   work, because the game needs the Super Game Module.
3. Insert `mrdo_cv.rom` as a cartridge. openMSX recognises the cartridge type by
   itself.

If you're comfortable with a command line, this does the same:
`openmsx -machine ColecoVision_SGM -carta mrdo_cv.rom`

### Controls

| Control | What it does |
|---|---|
| Joystick | Move Mr. Do |
| Left button | Throw the power ball |
| Keypad **#** | Insert a coin |
| Keypad **1** / **2** | Start a 1-player or 2-player game |
| Keypad **\*** | Open the options screen (only while the game is showing its demo and title screens) |

The options screen sets the number of lives (2 to 5) and how hard the game is
(1 to 4). It also sets whether the EXTRA letters and the SPECIAL diamond are easy
or hard to get. If **\*** and **#** seem to do each other's job
on your controller, just use the other key.

## If something goes wrong

**The page says "This isn't the right Mr. Do! file".**
The page needs the arcade version called **mrdo** (by Universal). Variants such as
*mrdot*, *mrdofix* or *mrlo* have a different program and won't work. Neither will
the ColecoVision, Atari or other home versions.

**The page says it "can't open" your file.**
Your file is packed as `.7z` or `.rar` instead of `.zip`. Unpack it first: on a
Mac, double-click it; on Windows, use the free [7-Zip](https://www.7-zip.org/).
Then choose all the files that came out of it at once.

**The page says your browser is too old.**
Update your browser, or open the page in a different one.

**The game shows "SUPER GAME MODULE REQUIRED".**
The Super Game Module isn't connected or switched on. In openMSX, you picked a
machine without it: choose **ColecoVision with SGM**.

**The flash cartridge won't start the game, or you only see a blank screen.**
Your flash cartridge has to support MegaCart games of 512 KB. Check its manual or
update its firmware.

## Other ways to make the game file

These do exactly the same thing as the web page and give an identical file.

**With Python 3** (for people who use a command line): download **`mrdo2cv.py`**
and **`mrdo_cv.bps`** from the Releases page into one folder. Then run:

```
python3 mrdo2cv.py path/to/mrdo.zip
```

On Windows, type `py` instead of `python3`. You can also give it your MAME roms
folder, or a folder of the loose files.

**With a BPS patcher** such as [RomPatcher.js](https://www.marcrobledo.com/RomPatcher.js/):

1. Join these four files from `mrdo.zip`, in this order, into one file
   (32 KB): `a4-01.bin`, `c4-02.bin`, `e4-03.bin`, `f4-04.bin`.
   - Mac or Linux: `cat a4-01.bin c4-02.bin e4-03.bin f4-04.bin > mrdo_main.bin`
   - Windows: `copy /b a4-01.bin+c4-02.bin+e4-03.bin+f4-04.bin mrdo_main.bin`
2. Apply `mrdo_cv.bps` to that file.

To check you have the right files, compare their checksums with this table:

| File | CRC32 | SHA-1 |
|---|---|---|
| a4-01.bin | `03dcfba2` | `c15e3d0c4225e0ca120bcd28aca39632575f8e11` |
| c4-02.bin | `0ecdd39c` | `c64b3363593911a676c647bf3dba8fe063fcb0de` |
| e4-03.bin | `358f5dc2` | `9fed1f5d1d04935d1b77687c8b2f3bfce970dc08` |
| f4-04.bin | `f4190cfc` | `24f5125d900f944294d4eda068b710c8f1c6d39f` |

Each release lists the checksum of the finished `mrdo_cv.rom`.

## For developers

The port runs the arcade's Z80 program at its original addresses in the Super Game
Module's RAM. It replaces the arcade's video and sound hardware with a ColecoVision
renderer and sound translator. The game logic is checked frame by frame against
MAME. [CLAUDE.md](CLAUDE.md) holds the design notes and build instructions.
Building from source needs the arcade disassembly tools, which are not in this repository.

`make release` builds the release files into `build/release/`. Releases never contain
the built ROM, only the patch, because the ROM includes the arcade's program.

---

Mr. Do! © 1982 Universal. This is an unofficial fan project and is not affiliated
with Universal. It contains no arcade ROM data.
