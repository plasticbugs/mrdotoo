local out = io.open(os.getenv("OUT"), "w")
local maxf = tonumber(os.getenv("FRAMES") or "600")
local PLAY = os.getenv("PLAY") == "1"
local seed = tonumber(os.getenv("SEED") or "1")
math.randomseed(seed)
local f, nlog, setup = 0, 0, false
local dbg, mem, P1, P2
local dirs = {"P1 Up","P1 Down","P1 Left","P1 Right"}
local curdir, hold = nil, 0
local function setf(port, name, v) port.fields[name]:set_value(v) end
emu.register_frame_done(function()
  if not setup then
    setup = true
    dbg = manager.machine.debugger
    mem = manager.machine.devices[":maincpu"].spaces["program"]
    P1 = manager.machine.ioport.ports[":P1"]; P2 = manager.machine.ioport.ports[":P2"]
    dbg:command('bpset 00B8,1,{printf "I %d %X",totalcycles,w@sp; temp2=0; g}')
    dbg:command('bpset 00AC,temp2==0,{printf "D %d",totalcycles; temp2=1; g}')
    dbg:command('bpset 0154,temp2==0,{printf "D %d",totalcycles; temp2=1; g}')
    dbg:command('bpset 0138,1,{printf "P0 %d",totalcycles; g}')
    dbg:command('bpset 0141,1,{printf "P1 %d",totalcycles; g}')
    dbg:command('bpset 014D,1,{printf "P2 %d",totalcycles; g}')
    dbg:command('bpset 0136,1,{printf "E %d",totalcycles; g}')
    dbg:command('g')
  end
  f = f + 1
  local log = dbg.consolelog
  for i = nlog + 1, #log do out:write(log[i], "\n") end
  nlog = #log
  -- state
  local nmon = 0
  for k = 0, 7 do if mem:read_u8(0xE21A + k*0x15) >= 0x80 then nmon = nmon + 1 end end
  local alpha = mem:read_u8(0xE2C2) >= 0x80 and 1 or 0
  local nch = 0
  for _,a in ipairs({0xE2D3,0xE2E2,0xE2F1}) do if mem:read_u8(a) >= 0x80 then nch = nch + 1 end end
  local lives = mem:read_u8(0xE097)
  local score = string.format("%02X%02X%02X", mem:read_u8(0xE098), mem:read_u8(0xE099), mem:read_u8(0xE09A))
  out:write(string.format("F %d %d %d %d %d %s %02X %02X\n", f, nmon, alpha, nch, lives, score, mem:read_u8(0xE000), mem:read_u8(0xE001)))
  if PLAY then
    if f == 600 then setf(P2,"Coin 1",1) elseif f == 606 then setf(P2,"Coin 1",0) end
    if f == 700 then setf(P1,"1 Player Start",1) elseif f == 706 then setf(P1,"1 Player Start",0) end
    if f > 900 then
      if f % 30 == 0 and lives < 3 and lives > 0 then mem:write_u8(0xE097, 3) end
      hold = hold - 1
      if hold <= 0 then
        if curdir then setf(P1, curdir, 0) end
        curdir = dirs[math.random(4)]; hold = math.random(8, 50)
        setf(P1, curdir, 1)
      end
      setf(P1, "P1 Button 1", (f % 40 < 3) and 1 or 0)
    end
  end
  if f >= maxf then out:close(); manager.machine:exit() end
end)
