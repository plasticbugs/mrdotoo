local done=false
emu.register_frame_done(function()
  if done then return end; done=true
  for tag,s in pairs(manager.machine.memory.shares) do print("share",tag,s.size) end
  manager.machine:exit()
end)
