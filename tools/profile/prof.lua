local out = io.open(os.getenv("OUT"), "w")
local maxf = tonumber(os.getenv("FRAMES") or "600")
local f = 0
local nlog = 0
local setup = false
local dbg
emu.register_frame_done(function()
  if not setup then
    setup = true
    dbg = manager.machine.debugger
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
  out:write("F ", f, "\n")
  if f >= maxf then out:close(); manager.machine:exit() end
end)
