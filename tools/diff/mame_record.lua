-- Record the arcade reference run for the lockstep RAM diff.
-- For every vblank handler (sync point: the handler's single read of ROM
-- $0156 at $00E9, identical RAM state to $00D5) write work RAM $E000-$EFFF,
-- and log the input port values each handler reads.
-- Env: OUT (file prefix), FRAMES (handlers to record), SEED (play RNG).
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local ram = io.open(os.getenv("OUT") .. ".ram", "wb")
local inl = io.open(os.getenv("OUT") .. ".inp", "w")
local maxh = tonumber(os.getenv("FRAMES") or "3000")
math.randomseed(tonumber(os.getenv("SEED") or "1"))
local n = 0                     -- snapshots taken = handlers past their sync point
local last = {}
local P1, P2
-- Inputs are injected by the read tap itself: the scripted player picks the
-- P1/P2 bytes ($A000/$A001, active low) each frame, and they are latched at
-- the next handler start (its read of $E001 at $00C4). MAME's own input
-- system only updates once per frame, which can land mid-handler.
local want_p1, want_p2 = 0xFF, 0xFF
local cur_p1, cur_p2 = 0xFF, 0xFF
local P1BIT = {["P1 Left"]=0, ["P1 Down"]=1, ["P1 Right"]=2, ["P1 Up"]=3,
               ["P1 Button 1"]=4, ["1 Player Start"]=5, ["2 Players Start"]=6}
local function setf(port, name, v)
  if name == "Coin 1" then
    want_p2 = (v == 1) and (want_p2 & ~0x40) or (want_p2 | 0x40)
  else
    local b = 1 << P1BIT[name]
    want_p1 = (v == 1) and (want_p1 & ~b) or (want_p1 | b)
  end
  want_p1 = want_p1 & 0xFF; want_p2 = want_p2 & 0xFF
end

local taps = {}
local finished = false
-- Validation mode (must match tools/patch_arcade.py VALIDATE_PATCHES): the
-- pathfinder runs with the vblank held off; hooks at $0010/$0018 re-enable it.
local function validate_patches()
  local rom = manager.machine.memory.regions[":maincpu"]
  local p = {[0x013B]=0x00, [0x0144]=0x00, [0x0150]=0x00, [0x014C]=0xDF, [0x0154]=0xD7,
             [0x0010]=0x33, [0x0011]=0x33, [0x0012]=0xFB, [0x0013]=0x18, [0x0014]=0xFE,
             [0x0018]=0x33, [0x0019]=0x33, [0x001A]=0xFB, [0x001B]=0xC9}
  for a, v in pairs(p) do rom:write_u8(a, v) end
end

local function install()
  validate_patches()
  taps[1] = mem:install_read_tap(0x0156, 0x0156, "snap", function(off, data, mask)
    if finished or cpu.state["CURPC"].value ~= 0x00E9 then return data end
    ram:write(mem:read_range(0xE000, 0xEFFF, 8)); ram:write(mem:read_range(0x8000, 0x8FFF, 8))
    n = n + 1
    -- optional: SNAP=h1,h2,... saves a screenshot at those handlers
    local snaps = os.getenv("SNAP")
    if snaps then
      for v in string.gmatch(snaps, "%d+") do
        if tonumber(v) == n then manager.machine.video:snapshot() end
      end
    end
    if n >= maxh then finished = true end
    return data
  end)
  taps[2] = mem:install_read_tap(0xA000, 0xA003, "inp", inp_tap)
  taps[5] = mem:install_read_tap(0xE001, 0xE001, "hstart", function(off, data, mask)
    if cpu.state["CURPC"].value == 0x00C4 then
      local it = tonumber(os.getenv("ITRACE") or "-1")
      -- SCEN (vg|w|dia|ext) + POKEH=h: end the round into that scene at the
      -- start of handler h (tools/diff/cv_replay.tcl does the same)
      if os.getenv("SCEN") and n == tonumber(os.getenv("POKEH") or "-1") then
        local sc = os.getenv("SCEN")
        local lv = ({vg=0x03, w=0x10, dia=0x01, ext=0x01})[sc]
        local why = ({vg=2, w=2, dia=3, ext=4})[sc]
        local fl = ({vg=0x80, w=0x80, dia=0xA0, ext=0x88})[sc]
        mem:write_u8(0xE09B, lv); mem:write_u8(0xE0C7, why)
        mem:write_u8(0xE1B6, mem:read_u8(0xE1B6) | fl)
      end

      cur_p1, cur_p2 = want_p1, want_p2
    end
    return data
  end)
  -- optional: ROMW=1 logs every write into ROM addresses ($0000-$7FFF),
  -- which the arcade board ignores but the port's RAM copy would not
  if os.getenv("ROMW") then
    taps[6] = mem:install_write_tap(0x0000, 0x7FFF, "romw", function(off, data, mask)
      print(string.format("ROMW h=%d pc=%04x %04x<-%02x", n, cpu.state["CURPC"].value, off, data & 0xFF))
      return data
    end)
  end
  -- optional: RTRACE=h logs fg-tile reads during handler h (after its sync)
  local rt = tonumber(os.getenv("RTRACE") or "-1")
  if rt >= 0 then
    taps[4] = mem:install_read_tap(0x8C00, 0x8FFF, "rtrace", function(off, data, mask)
      if n == rt + 1 then
        print(string.format("RT pc=%04x %04x=%02x", cpu.state["CURPC"].value, off, data & 0xFF))
      end
      return data
    end)
  end
  -- optional: WATCH=hexaddr logs every write there with PC and handler
  local w = os.getenv("WATCH")
  if w then
    local wa = tonumber(w, 16)
    taps[3] = mem:install_write_tap(wa, wa, "watch", function(off, data, mask)
      local sp = cpu.state["SP"].value
      print(string.format("WATCH h=%d pc=%04x %04x<-%02x (sp) %04x %04x", n, cpu.state["CURPC"].value, off, data & 0xFF,
        mem:read_u16(sp), mem:read_u16(sp + 2)))
      return data
    end)
  end
end

function inp_tap(off, data, mask)
  local pc = cpu.state["CURPC"].value
  if off == 0xA000 then data = (data & 0xFF00) | cur_p1 end
  if off == 0xA001 then data = (data & 0xFF00) | cur_p2 end
  -- reads before the sync point (coin poll, $01A6-$01F9) belong to the handler
  -- about to be snapshotted; later reads belong to the last snapshotted one
  local h = (pc >= 0x01A6 and pc < 0x01FA) and n or n - 1
  local port = off - 0xA000
  local it = tonumber(os.getenv("ITRACE") or "-1")
  if it >= 0 and n >= it and n <= it + 3 and port == 0 then
    print(string.format("IT n=%d pc=%04x v=%02x", n, pc, data & 0xFF))
  end
  local v = data & 0xFF
  local key = port
  if last[key] ~= v or last[key .. "h"] ~= h then
    inl:write(string.format("%d %d %d %04x\n", h, port, v, pc))
    last[key] = v; last[key .. "h"] = h
  end
  return data
end

-- Scripted play: coin, start, then random joystick with fire every 40 frames.
local f = 0
local dirs = {"P1 Up", "P1 Down", "P1 Left", "P1 Right"}
local cur, hold = nil, 0
emu.register_frame_done(function()
  f = f + 1
  if f == 1 then
    P1 = manager.machine.ioport.ports[":P1"]; P2 = manager.machine.ioport.ports[":P2"]
    install()
  end
  if finished then
    ram:close(); inl:close(); finished = nil
    manager.machine:exit()
    return
  end
  if finished == nil then return end
  if not os.getenv("NOCOIN") then   -- NOCOIN: leave the attract sequence running
    if f == 600 then setf(P2, "Coin 1", 1) elseif f == 606 then setf(P2, "Coin 1", 0) end
  end
  if not os.getenv("NOSTART") then
    if f == 700 then setf(P1, "1 Player Start", 1) elseif f == 706 then setf(P1, "1 Player Start", 0) end
  end
  if os.getenv("ALPHA") and f > 1500 and f % 2400 == 0 then
    mem:write_u8(0xE0B2, mem:read_u8(0xE0B2) | 3)
  end
  if f > 800 and not os.getenv("NOSTART") then
    hold = hold - 1
    if hold <= 0 then
      if cur then setf(P1, cur, 0) end
      cur = dirs[math.random(4)]; setf(P1, cur, 1); hold = math.random(10, 60)
    end
    setf(P1, "P1 Button 1", (f % 40 < 3) and 1 or 0)
  end
end)
