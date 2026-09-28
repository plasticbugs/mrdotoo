local done=false
emu.register_frame_done(function()
  if done then return end
  done=true
  local d=manager.machine.debugger
  d:command("dasm "..os.getenv("S").."/dasm.txt,0,0x8000")
  manager.machine:exit()
end)
