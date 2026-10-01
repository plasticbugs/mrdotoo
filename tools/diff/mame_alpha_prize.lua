-- MAME: a lone letter monster killed, then the center prize collected
-- DELAY frames later (tools/diff/mame_alpha_prize.sh records it). The
-- arcade's alpha_monster_update ($4353) clears the prize's session request
-- ($E0B2 bit 0, the prize stores 3) on every update while the dying monster
-- is still active, and bit 1 when it ends: a prize taken during the death
-- animation (~0.65 s) starts no session.
-- Env: DELAY (frames from the kill to the prize), END (frames to run).
local cpu = manager.machine.devices[":maincpu"]
local mem = cpu.spaces["program"]
local rom = manager.machine.memory.regions[":maincpu"]
local delay = tonumber(os.getenv("DELAY") or "12")
local endf = tonumber(os.getenv("END") or "900")
local p1, p2 = 0xFF, 0xFF
local f = 0
local stage, t_kill = 0, 0
local log = io.open(os.getenv("LOG") or "/dev/null", "w")
local function say(s) log:write(string.format("%5d %s\n", f, s)); log:flush() end

local taps = {}
local function inst()           -- (installed at the first frame: at load the
  taps[1] = mem:install_read_tap(0xA000, 0xA003, "inp", function(off, data, mask)   -- map is not up)
    if off == 0xA000 then data = (data & 0xFF00) | p1 end
    if off == 0xA001 then data = (data & 0xFF00) | p2 end
    return data
  end)
end

local function prize_present()
  for k = 0, 11 do
    if (mem:read_u8(0xE300 + 7 * k) & 0x78) == 0x68 then return true end
  end
  return false
end

emu.register_frame_done(function()
  f = f + 1
  if f == 2 then inst() end
  if f == 1 then for _, a in ipairs({0x32A6, 0x44B0, 0x4B94}) do rom:write_u8(a, 0x18) end end  -- invincible
  if f == 600 then p2 = 0xBF elseif f == 606 then p2 = 0xFF end          -- coin
  if f == 700 then p1 = 0xDF elseif f == 706 then p1 = 0xFF end          -- 1 player start
  if stage == 0 and f > 1500 and (mem:read_u8(0xE000) & 0x80) ~= 0 then
    stage = 1; say("prize on the field; a lone letter monster comes out")
    mem:write_u8(0xE0B2, mem:read_u8(0xE0B2) | 1)
  elseif stage == 1 and f > 0 and (mem:read_u8(0xE2C2) & 0xF0) == 0xE0 and mem:read_u8(0xE2C7) == 0x10 then
    stage = 2; t_kill = f + 150
  elseif stage == 2 and f == t_kill then
    stage = 3; say("letter monster hit (ball)")
    mem:write_u8(0xE2C2, mem:read_u8(0xE2C2) | 8)
  elseif stage == 3 and f == t_kill + delay then
    stage = 4; say(string.format("Mr. Do onto the prize (%d frames after the kill)", delay))
  end
  if stage == 4 and (mem:read_u8(0xE000) & 8) == 0 and f < t_kill + delay + 30 then
    mem:write_u8(0xE1C6, 0x78); mem:write_u8(0xE1C8, 0x80)    -- (held until the arcade collects it)
  elseif stage == 4 then
    stage = 5; say(string.format("prize collected: E000=%02x E0B2=%02x", mem:read_u8(0xE000), mem:read_u8(0xE0B2)))
  end
  if stage >= 3 and f % 6 == 0 then
    say(string.format("E0B2=%02x letter monster=%02x E000=%02x", mem:read_u8(0xE0B2), mem:read_u8(0xE2C2), mem:read_u8(0xE000)))
  end
  if f >= endf or (stage == 5 and f > t_kill + delay + 360) then manager.machine:exit() end
end)
