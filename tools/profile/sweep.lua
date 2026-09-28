local OUTP = os.getenv("OUT")
local maxf = tonumber(os.getenv("FRAMES") or "600")
local MODE = os.getenv("MODE") or "attract"
local INV = os.getenv("INV") == "1"
local LEVEL = os.getenv("LEVEL")
local ALPHA = tonumber(os.getenv("ALPHA") or "0")
local TOPUP = os.getenv("TOPUP") ~= "0"
local WIN = tonumber(os.getenv("WIN") or "0")
local SCORE = os.getenv("SCORE") == "1"
local TWO = os.getenv("TWO") == "1"
local LETTERS = os.getenv("LETTERS") == "1"
local NOFIRE = os.getenv("NOFIRE") == "1"
math.randomseed(tonumber(os.getenv("SEED") or "1"))
local f, setup = 0, false
local cpu, mem, P1, P2, curpc, spst
local dirs = {"P1 Up","P1 Down","P1 Left","P1 Right"}
local dirs2 = {"P2 Up","P2 Down","P2 Left","P2 Right"}
local curdir, hold = nil, 0
local lastalpha = 0
local taps = {}
-- aggregates
local code = {}          -- byte addr -> true (fetched as part of instruction)
local exec = {}          -- instruction start
local into7 = {}         -- key "src>dst" -> count
local romdata = {}       -- pc -> {lo,hi,n}
local ram = {}           -- E000 offset -> bits (1 r, 2 w)
local rampc = {}         -- pc -> {rlo,rhi,wlo,whi,n}
local vid = {}           -- "pc:rw" -> {lo,hi,n,vlo,vhi,qmask}
local io = {}            -- "pc:rw:addr" -> {n,vlo,vhi}
local minsp = 0xFFFF
local lastpc = -1
local inlua = false
local stackacc = {}
local romaddr = {}
local function setf(port, name, v) port.fields[name]:set_value(v) end
local function upd(t, k, a, v)
  local e = t[k]
  if not e then e = {lo=a, hi=a, n=0, vlo=v or 0, vhi=v or 0, q=0}; t[k] = e end
  if a < e.lo then e.lo = a end; if a > e.hi then e.hi = a end
  e.n = e.n + 1
  if v then if v < e.vlo then e.vlo = v end; if v > e.vhi then e.vhi = v end end
  return e
end
local function dump()
  local o = io.open and nil
  local fh = assert(_G.io.open(OUTP, "w"))
  local function kv(t, fn) local parts = {}; for k, v in pairs(t) do parts[#parts+1] = fn(k, v) end; return table.concat(parts, ",") end
  fh:write("{")
  fh:write('"exec":[', kv(exec, function(k) return tostring(k) end), '],')
  fh:write('"code":[', kv(code, function(k) return tostring(k) end), '],')
  fh:write('"into7":{', kv(into7, function(k, v) return '"'..k..'":'..v end), '},')
  fh:write('"romdata":{', kv(romdata, function(k, e) return string.format('"%d":[%d,%d,%d]', k, e.lo, e.hi, e.n) end), '},')
  fh:write('"ram":{', kv(ram, function(k, v) return string.format('"%d":%d', k, v) end), '},')
  fh:write('"rampc":{', kv(rampc, function(k, e) return string.format('"%s":[%d,%d,%d,%d,%d]', k, e.lo, e.hi, e.n, e.vlo, e.vhi) end), '},')
  fh:write('"vid":{', kv(vid, function(k, e) return string.format('"%s":[%d,%d,%d,%d,%d,%d]', k, e.lo, e.hi, e.n, e.vlo, e.vhi, e.q) end), '},')
  fh:write('"io":{', kv(io, function(k, e) return string.format('"%s":[%d,%d,%d]', k, e.n, e.vlo, e.vhi) end), '},')
  fh:write('"stackpc":{', kv(stackacc, function(k, v) return '"'..k..'":'..v end), '},')
  fh:write('"romaddr":{', kv(romaddr, function(k, t) local p = {}; for a in pairs(t) do p[#p+1] = tostring(a) end; return '"'..k..'":['..table.concat(p, ',')..']' end), '},')
  fh:write('"minsp":', minsp, ',"frames":', f, '}')
  fh:close()
end
emu.register_frame_done(function()
  if not setup then
    setup = true
    cpu = manager.machine.devices[":maincpu"]
    mem = cpu.spaces["program"]
    curpc = cpu.state["CURPC"]; spst = cpu.state["SP"]
    P1 = manager.machine.ioport.ports[":P1"]; P2 = manager.machine.ioport.ports[":P2"]
    if os.getenv("COCKTAIL") == "1" then manager.machine.ioport.ports[":DSW1"].fields["Cabinet"]:set_value(0) end
    local dbg = manager.machine.debugger
    if dbg then
      if INV then for _,a in ipairs({"32A6","44B0","4B94"}) do dbg:command('bpset '..a..',1,{f=f&fe; g}') end end
      if LEVEL then dbg:command('bpset 1A76,1,{b@e09f='..LEVEL..'; g}') end
      dbg:command('g')
    end
    taps[#taps+1] = mem:install_read_tap(0x0000, 0x7fff, "r0", function(off, data, mask)
      if inlua then return end
      local pc = curpc.value
      local d = off - pc
      if d >= 0 and d <= 3 then
        code[off] = true
        if d == 0 then
          exec[pc] = true
          if off >= 0x7000 and (lastpc < 0x7000 or lastpc > 0x7fff) and lastpc >= 0 then
            local k = lastpc..">"..off; into7[k] = (into7[k] or 0) + 1
          end
          lastpc = pc
        end
      else
        upd(romdata, pc, off)
        local t = romaddr[pc]; if not t then t = {}; romaddr[pc] = t end; t[off] = true
      end
    end)
    taps[#taps+1] = mem:install_read_tap(0xe000, 0xefff, "re", function(off, data, mask)
      if inlua then return end
      local pc = curpc.value
      if pc == 0x0080 then return end
      local o = off - 0xe000; ram[o] = (ram[o] or 0) | 1
      local s = spst.value
      if off >= s - 2 and off <= s + 1 then stackacc[pc] = (stackacc[pc] or 0) + 1 else upd(rampc, pc..":r", off) end
    end)
    taps[#taps+1] = mem:install_write_tap(0xe000, 0xefff, "we", function(off, data, mask)
      if inlua then return end
      local pc = curpc.value
      if pc == 0x0080 then return end
      local o = off - 0xe000; ram[o] = (ram[o] or 0) | 2
      local s = spst.value
      if off >= s - 2 and off <= s + 1 then
        stackacc[pc] = (stackacc[pc] or 0) + 1
        if s >= 0xe000 and s < minsp then minsp = s end
      else upd(rampc, pc..":w", off, data & 0xff) end
    end)
    local function vtap(rw)
      return function(off, data, mask)
      if inlua then return end
        local e = upd(vid, curpc.value..":"..rw, off, rw == "w" and (data & 0xff) or nil)
        e.q = e.q | (1 << ((off - 0x8000) >> 10))
      end
    end
    taps[#taps+1] = mem:install_read_tap(0x8000, 0x8fff, "rv", vtap("r"))
    taps[#taps+1] = mem:install_write_tap(0x8000, 0x8fff, "wv", vtap("w"))
    local function iot(rw)
      return function(off, data, mask)
      if inlua then return end
        upd(io, curpc.value..":"..rw..":"..off, off, data & 0xff)
      end
    end
    for _, r in ipairs({{0x9000,0x97ff},{0x9800,0x9fff},{0xa000,0xdfff},{0xf000,0xffff}}) do
      taps[#taps+1] = mem:install_read_tap(r[1], r[2], "ri", iot("r"))
      taps[#taps+1] = mem:install_write_tap(r[1], r[2], "wi", iot("w"))
    end
  end
  inlua = true
  f = f + 1
  local nch = 0
  for _,a in ipairs({0xE2D3,0xE2E2,0xE2F1}) do if mem:read_u8(a) >= 0x80 then nch = nch + 1 end end
  local lives = mem:read_u8(0xE097)
  local g0 = mem:read_u8(0xE000)
  if MODE ~= "attract" then
    local ncoin = TWO and 2 or 1
    for c = 0, ncoin-1 do
      if f == 600 + c*20 then setf(P2,"Coin 1",1) elseif f == 606 + c*20 then setf(P2,"Coin 1",0) end
    end
    local sb = TWO and "2 Players Start" or "1 Player Start"
    if f == 700 then setf(P1, sb, 1) elseif f == 706 then setf(P1, sb, 0) end
    if f > 900 then
      if TOPUP and f % 30 == 0 and lives < 3 and lives > 0 then mem:write_u8(0xE097, 3) end
      if SCORE and f == 1500 then mem:write_u8(0xE098, 0x05) end
      if WIN > 0 and f % WIN == 0 and (g0 & 0xC0) == 0xC0 then
        mem:write_u8(0xE0C7, 2); mem:write_u8(0xE1B6, mem:read_u8(0xE1B6) | 0x80)
      end
      if ALPHA > 0 and (g0 & 0xC0) == 0xC0 and nch == 0 and f - lastalpha >= ALPHA then
        if LETTERS then mem:write_u8(0xE0AD, 0x0F) end
        mem:write_u8(0xE0B2, mem:read_u8(0xE0B2) | 3); lastalpha = f
      end
      if MODE == "random" then
        hold = hold - 1
        if hold <= 0 then
          if curdir then setf(P1, curdir, 0); setf(P2, curdir:gsub("P1","P2"), 0) end
          curdir = dirs[math.random(4)]; hold = math.random(8, 50)
          setf(P1, curdir, 1); setf(P2, curdir:gsub("P1","P2"), 1)
        end
        if not NOFIRE then
          local b = (f % 40 < 3) and 1 or 0
          setf(P1, "P1 Button 1", b); setf(P2, "P2 Button 1", b)
        end
      end
    end
  end
  if f >= maxf then dump(); manager.machine:exit() end
  inlua = false
end)
