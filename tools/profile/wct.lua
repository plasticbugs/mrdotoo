local out = io.open(os.getenv("OUT"), "w")
local maxf = tonumber(os.getenv("FRAMES") or "600")
local MODE = os.getenv("MODE") or "attract"   -- attract | random | idle
local INV = os.getenv("INV") == "1"
local LEVEL = os.getenv("LEVEL")               -- binary level counter (0-based), hex string for debugger
local ALPHA = tonumber(os.getenv("ALPHA") or "0") -- frames between alpha-trigger pokes (0=off)
math.randomseed(tonumber(os.getenv("SEED") or "1"))
local f, nlog, setup = 0, 0, false
local dbg, mem, P1, P2, spr
local dirs = {"P1 Up","P1 Down","P1 Left","P1 Right"}
local curdir, hold = nil, 0
local lastalpha = 0
local function setf(port, name, v) port.fields[name]:set_value(v) end
emu.register_frame_done(function()
  if not setup then
    setup = true
    dbg = manager.machine.debugger
    mem = manager.machine.devices[":maincpu"].spaces["program"]
    spr = manager.machine.memory.shares[":spriteram"]
    P1 = manager.machine.ioport.ports[":P1"]; P2 = manager.machine.ioport.ports[":P2"]
    dbg:command('bpset 00B8,1,{printf "I %d %X",totalcycles,w@sp; temp2=0; g}')
    dbg:command('bpset 00AC,temp2==0,{printf "D %d",totalcycles; temp2=1; g}')
    dbg:command('bpset 0154,temp2==0,{printf "D %d",totalcycles; temp2=1; g}')
    dbg:command('bpset 0138,1,{printf "P0 %d",totalcycles; g}')
    dbg:command('bpset 0141,1,{printf "P1 %d",totalcycles; g}')
    dbg:command('bpset 014D,1,{printf "P2 %d",totalcycles; g}')
    dbg:command('bpset 0136,1,{printf "E %d",totalcycles; g}')
    if INV then
      for _,a in ipairs({"32A6","44B0","4B94"}) do dbg:command('bpset '..a..',1,{f=f&fe; g}') end
    end
    if LEVEL then
      dbg:command('bpset 1A76,1,{b@e09f='..LEVEL..'; g}')
    end
    dbg:command('g')
  end
  f = f + 1
  local TS=tonumber(os.getenv('TRACE_START') or '0')
  if TS>0 and f==TS then dbg:command('trace '..os.getenv('TRACE_FILE')..',maincpu,noloop,{tracelog "C%d ",totalcycles}') end
  if TS>0 and f==TS+tonumber(os.getenv('TRACE_FRAMES')) then dbg:command('trace off') ; out:close(); manager.machine:exit() end
  local log = dbg.consolelog
  for i = nlog + 1, #log do out:write(log[i], "\n") end
  nlog = #log
  local nmon = 0
  for k = 0, 7 do if mem:read_u8(0xE21A + k*0x15) >= 0x80 then nmon = nmon + 1 end end
  local alpha = mem:read_u8(0xE2C2) >= 0x80 and 1 or 0
  local nch = 0
  for _,a in ipairs({0xE2D3,0xE2E2,0xE2F1}) do if mem:read_u8(a) >= 0x80 then nch = nch + 1 end end
  local lives = mem:read_u8(0xE097)
  local score = string.format("%02X%02X%02X", mem:read_u8(0xE098), mem:read_u8(0xE099), mem:read_u8(0xE09A))
  local g0 = mem:read_u8(0xE000)
  -- object slots (apples etc): 12 x 7B at E0C8, byte0 state
  local objs = {}
  for k = 0, 11 do local b = mem:read_u8(0xE0C8 + k*7); if b >= 0x80 then objs[#objs+1] = string.format("%02X", b) end end
  out:write(string.format("F %d %d %d %d %d %s %02X %02X %02X %02X %02X %s\n", f, nmon, alpha, nch, lives, score, g0, mem:read_u8(0xE001), mem:read_u8(0xE09F), mem:read_u8(0xE2C2), mem:read_u8(0xE0B2), table.concat(objs, ",")))
  -- sprite RAM census: entries with byte1 != 0 are drawn (MAME mrdo draw rule; upload zeroes byte1 of unused slots)
  local ent = {}
  for k = 0, 63 do
    local y = spr:read_u8(k*4+1)
    if y ~= 0 then
      ent[#ent+1] = string.format("%02X%02X%02X%02X", spr:read_u8(k*4), y, spr:read_u8(k*4+2), spr:read_u8(k*4+3))
    end
  end
  out:write("S ", mem:read_u8(0xE311), " ", table.concat(ent, " "), "\n")
  if MODE ~= "attract" then
    if f == 600 then setf(P2,"Coin 1",1) elseif f == 606 then setf(P2,"Coin 1",0) end
    if f == 700 then setf(P1,"1 Player Start",1) elseif f == 706 then setf(P1,"1 Player Start",0) end
    if f > 900 then
      if f % 30 == 0 and lives < 3 and lives > 0 then mem:write_u8(0xE097, 3) end
      if ALPHA > 0 and (g0 & 0xC0) == 0xC0 and nch == 0 and f - lastalpha >= ALPHA then
        mem:write_u8(0xE0B2, mem:read_u8(0xE0B2) | 3); lastalpha = f
        out:write("A ", f, "\n")
      end
      if MODE == "random" then
        hold = hold - 1
        if hold <= 0 then
          if curdir then setf(P1, curdir, 0) end
          curdir = dirs[math.random(4)]; hold = math.random(8, 50)
          setf(P1, curdir, 1)
        end
        if os.getenv("NOFIRE") ~= "1" then setf(P1, "P1 Button 1", (f % 40 < 3) and 1 or 0) end
      end
    end
  end
  if f >= maxf then out:close(); manager.machine:exit() end
end)
