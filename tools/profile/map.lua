local done=false
emu.register_frame_done(function()
  if done then return end; done=true
  local sp=manager.machine.devices[":maincpu"].spaces["program"]
  for _,e in ipairs(sp.map.entries) do
    print(string.format("%04X-%04X r=%s w=%s %s %s", e.address_start, e.address_end, e.read.handlertype, e.write.handlertype, e.read.tag or "", e.write.tag or ""))
  end
  local cpu=manager.machine.devices[":maincpu"]
  print("clock", cpu.clock)
  manager.machine:exit()
end)
