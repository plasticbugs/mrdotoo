-- Cutscene recorder (for tools/capture_screen.py scene:PREFIX:f0-f1): per video
-- frame dump bg/fg video RAM ($8000-$8FFF), sprite RAM share (256B), work RAM
-- $E000-$EFFF; log scroll writes to PREFIX.scroll.
-- Env: OUT (prefix), FRAMES, SCEN (attract|vg|w|dia|ext|over), POKEF (frame of
--      the poke that ends the round into the scene), LETTER (0-4: the EXTRA
--      letter the alpha monster wears, $E017), SNAPEVERY, SNAPFROM, SNAPTO
-- Run MAME with SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy -video none -sound none.
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local out = os.getenv("OUT")
local rec = io.open(out .. ".bin", "wb")
local slog = io.open(out .. ".scroll", "w")
local maxf = tonumber(os.getenv("FRAMES") or "3000")
local scen = os.getenv("SCEN") or "attract"
local pokef = tonumber(os.getenv("POKEF") or "1200")
local snapev = tonumber(os.getenv("SNAPEVERY") or "0")
local snapfrom = tonumber(os.getenv("SNAPFROM") or "0")
local snapto = tonumber(os.getenv("SNAPTO") or "999999")
math.randomseed(tonumber(os.getenv("SEED") or "1"))
local f = 0
local P1, P2
local want_p1, want_p2 = 0xFF, 0xFF
local P1BIT = {["P1 Left"]=0, ["P1 Down"]=1, ["P1 Right"]=2, ["P1 Up"]=3,
               ["P1 Button 1"]=4, ["1 Player Start"]=5, ["2 Players Start"]=6}
local function setf(name, v)
  if name == "Coin 1" then
    want_p2 = (v == 1) and (want_p2 & ~0x40) or (want_p2 | 0x40)
  else
    local b = 1 << P1BIT[name]
    want_p1 = (v == 1) and (want_p1 & ~b) or (want_p1 | b)
  end
  want_p1 = want_p1 & 0xFF; want_p2 = want_p2 & 0xFF
end
local taps = {}
local spr
local function install()
  spr = manager.machine.memory.shares[":spriteram"]
  taps[1] = mem:install_write_tap(0xF000, 0xFFFF, "scroll", function(off, data, mask)
    slog:write(string.format("%d %04x %02x %04x\n", f, off, data & 0xFF, cpu.state["CURPC"].value))
    return data
  end)
  taps[2] = mem:install_read_tap(0xA000, 0xA001, "inp", function(off, data, mask)
    if off == 0xA000 then data = (data & 0xFF00) | want_p1 end
    if off == 0xA001 then data = (data & 0xFF00) | want_p2 end
    return data
  end)
  if os.getenv("INVULN") then
    -- invincibility: breakpoints from tools/profile (skip death paths)
  end
end
local dirs = {"P1 Up", "P1 Down", "P1 Left", "P1 Right"}
local cur, hold = nil, 0
local done = false
emu.register_frame_done(function()
  if done then return end
  f = f + 1
  if f == 1 then install() end
  if f > 1 then
    rec:write(mem:read_range(0x8000, 0x8FFF, 8))
    local s = {}
    for i = 0, 255 do s[#s+1] = string.char(spr:read_u8(i)) end
    rec:write(table.concat(s))
    rec:write(mem:read_range(0xE000, 0xEFFF, 8))
  end
  if snapev > 0 and f >= snapfrom and f <= snapto and (f - snapfrom) % snapev == 0 then
    manager.machine.video:snapshot()
    slog:write(string.format("SNAP %d\n", f))
  end
  if f >= maxf then
    rec:close(); slog:close(); done = true
    manager.machine:exit(); return
  end
  if scen ~= "attract" then
    if f == 600 then setf("Coin 1", 1) elseif f == 606 then setf("Coin 1", 0) end
    if f == 700 then setf("1 Player Start", 1) elseif f == 706 then setf("1 Player Start", 0) end
    if f == tonumber(os.getenv("IDLEAFTER") or "-1") then want_p1 = 0xFF end
    if f > 800 and scen ~= "idle" and f < tonumber(os.getenv("IDLEAFTER") or "999999") then
      hold = hold - 1
      if hold <= 0 then
        if cur then setf(cur, 0) end
        cur = dirs[math.random(4)]; setf(cur, 1); hold = math.random(10, 60)
      end
      setf("P1 Button 1", (f % 40 < 3) and 1 or 0)
    end
    if f == pokef then
      if scen == "vg" then mem:write_u8(0xE09B, 0x03)
      elseif scen == "w" then mem:write_u8(0xE09B, 0x10)
      elseif scen == "dia" then mem:write_u8(0xE09B, 0x01)
      elseif scen == "ext" then mem:write_u8(0xE09B, 0x01)
      end
      local reason = ({vg=2, w=2, dia=3, ext=4})[scen]
      if reason then
        mem:write_u8(0xE0C7, reason)
        local fl = 0x80
        if scen == "dia" then fl = 0xA0 elseif scen == "ext" then fl = 0x88 end
        mem:write_u8(0xE1B6, mem:read_u8(0xE1B6) | fl)
      end
      if scen == "over" then
        mem:write_u8(0xE097, 1)
        mem:write_u8(0xE098, 0x05); mem:write_u8(0xE099, 0x00); mem:write_u8(0xE09A, 0x00)
      end
      if os.getenv("LETTER") then mem:write_u8(0xE017, tonumber(os.getenv("LETTER"))) end
      slog:write(string.format("POKE %d %s\n", f, scen))
    end
  end
end)
