local done=false
emu.register_frame_done(function()
  if done then return end; done=true
  for tag,p in pairs(manager.machine.ioport.ports) do
    for name,f in pairs(p.fields) do print(tag, name, string.format("%02X",f.mask), f.defvalue) end
  end
  manager.machine:exit()
end)
