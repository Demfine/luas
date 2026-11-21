local TAB_ICON = "rbxassetid://10734975692"

local tab = menu.new_tab("Hat", TAB_ICON)
local sec = tab:new_section("Chinese hat", "Left")
local ui_on = sec:new_toggle("Enable hat", false)
local ui_color
local okc = pcall(function()
	ui_color = sec:new_colorpicker("Hat color", color(255, 255, 255))
end)
local ui_r, ui_g, ui_b
if not okc or not ui_color then
	ui_r = sec:new_slider("Hat red", 0, 255, 255, 0, "")
	ui_g = sec:new_slider("Hat green", 0, 255, 255, 0, "")
	ui_b = sec:new_slider("Hat blue", 0, 255, 255, 0, "")
	print("[hat] colorpicker unavailable: RGB sliders")
end
local ui_radius = sec:new_slider("Brim radius", 0.5, 2, 1.1, 2, " st")
local ui_height = sec:new_slider("Cone height", 0.2, 2, 0.9, 2, " st")
local ui_offset = sec:new_slider("Head offset", -1, 1, -0.4, 2, " st")
local ui_debug = sec:new_toggle("Debug log", false)

local SEG = 72
local THROTTLE = 64
local NEAR_D2 = 36
local FP_DIST = 2

local function make(kind, init)
	local ok, obj = pcall(Drawing.new, kind)
	if not ok or not obj then
		return nil
	end
	if pcall(init, obj) then
		return obj
	end
	pcall(function()
		obj:Destroy()
	end)
	return nil
end

local tris, lines = {}, {}
for i = 1, SEG do
	tris[i] = make("Triangle", function(t)
		t.Filled = true
		t.Transparency = 0.2
		t.Visible = false
		t.PointA = vector(0, 0)
		t.PointB = vector(0, 0)
		t.PointC = vector(0, 0)
	end)
	lines[i] = make("Line", function(l)
		l.Thickness = 1
		l.Transparency = 1
		l.Visible = false
		l:SetCoords(0, 0, 0, 0, false)
	end)
end
if not tris[1] then
	print("[hat] Triangle unavailable: rim outline only")
end
if not lines[1] then
	print("[hat] Line unavailable: facets only")
end

local said = {}
local function say_once(key, msg)
	if not said[key] then
		said[key] = true
		print(msg)
	end
end

local function hat_rgb()
	if not ui_color then
		return ui_r:get() / 255, ui_g:get() / 255, ui_b:get() / 255
	end
	local ok, v = pcall(function()
		return ui_color:get()
	end)
	if not ok or v == nil then
		return 1, 1, 1
	end
	local r, g, b
	if type(v) == "table" then
		r, g, b = v.r or v.R or v[1], v.g or v.G or v[2], v.b or v.B or v[3]
	else
		local okr, rr = pcall(function()
			return v.R
		end)
		if not okr then
			return 1, 1, 1
		end
		r, g, b = rr, v.G, v.B
	end
	if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then
		return 1, 1, 1
	end
	if r > 1 or g > 1 or b > 1 then
		r, g, b = r / 255, g / 255, b / 255
	end
	return r, g, b
end

local function get_ws()
	local ok, w = pcall(function()
		return workspace
	end)
	if ok and w then
		return w
	end
	local ok2, w2 = pcall(function()
		return game:GetService("Workspace")
	end)
	if ok2 and w2 then
		return w2
	end
	return nil
end

local function get_cam()
	local ws = get_ws()
	if not ws then
		return nil
	end
	local ok, cam = pcall(function()
		return ws.CurrentCamera
	end)
	if ok then
		return cam
	end
	return nil
end

local get_lp = entity.get_local_player or entity.local_player

-- Crown position: exact Head part first, then model bbox top, then helpers.
local head_cache, head_cache_src = nil, nil
local last_scan = -1000

local function part_pos(p)
	local ok, v = pcall(function()
		return p.Position
	end)
	if ok then
		return v
	end
	return nil
end

local function crown_of_head(hp)
	local pos = part_pos(hp)
	if not pos then
		return nil
	end
	local oks, size = pcall(function()
		return hp.Size
	end)
	return pos + Vector3.new(0, (oks and size.Y or 1) / 2, 0)
end

local function scan_head(root)
	local ws = get_ws()
	if not ws then
		return nil
	end
	local me = get_lp and get_lp()
	local okn, nm = pcall(function()
		return me.Name
	end)
	if okn and nm then
		local okm, model = pcall(function()
			return ws:FindFirstChild(nm, true)
		end)
		if okm and model then
			local okh, hp = pcall(function()
				return model:FindFirstChild("Head", true)
			end)
			if okh and hp then
				local pos = crown_of_head(hp)
				if pos then
					return pos, hp, "Head"
				end
			end
			local okb, bf, bs = pcall(function()
				return model:GetBoundingBox()
			end)
			if okb and bf and bs then
				return bf.Position + Vector3.new(0, bs.Y / 2, 0), nil, "bbox"
			end
		end
	end
	-- character may live in a folder or under another name: nearest Head part
	local best, best_d = nil, nil
	local okd, desc = pcall(function()
		return ws:GetDescendants()
	end)
	if okd and desc and root then
		for _, inst in ipairs(desc) do
			local okname, name = pcall(function()
				return inst.Name
			end)
			if okname and (name == "Head" or name == "head") then
				local pos = part_pos(inst)
				if pos and pos.Y > root.Y then
					local dx, dz = pos.X - root.X, pos.Z - root.Z
					local d = dx * dx + dz * dz
					if d < NEAR_D2 and (not best_d or d < best_d) then
						best, best_d = inst, d
					end
				end
			end
		end
	end
	if best then
		local pos = crown_of_head(best)
		if pos then
			return pos, best, "Head"
		end
	end
	return nil
end

local function crown()
	local me = get_lp and get_lp()
	if not me then
		return nil, "nil player (get_local_player gone?)"
	end
	-- visual only: no is_alive gate, a broken/dead flag must not hide the hat
	local okr, root = pcall(entity.get_player_position, me)
	if not okr then
		root = nil
	end
	if head_cache then
		local okpar, par = pcall(function()
			return head_cache.Parent
		end)
		local pos = part_pos(head_cache)
		local near = true
		if pos and root then
			local dx, dz = pos.X - root.X, pos.Z - root.Z
			near = dx * dx + dz * dz < NEAR_D2
		end
		if okpar and par and pos and near then
			return crown_of_head(head_cache), head_cache_src
		end
		head_cache = nil
	end
	local tick = globals.tickcount()
	if tick - last_scan >= THROTTLE then
		last_scan = tick
		local pos, hp, src = scan_head(root)
		if pos then
			head_cache, head_cache_src = hp, src
			return pos, src
		end
	end
	local ok2, head = pcall(entity.get_player_hitbox_position, me, "head")
	if ok2 and head then
		return head + Vector3.new(0, 0.5, 0), "hitbox"
	end
	if root then
		return root + Vector3.new(0, 2, 0), "root+2"
	end
	return nil, "no position source"
end

local drawn = false
local last_debug = 0

local function hide()
	if not drawn then
		return
	end
	drawn = false
	for i = 1, SEG do
		if tris[i] then
			tris[i].Visible = false
		end
		if lines[i] then
			lines[i].Visible = false
		end
	end
end

local w2s = render and (render.world_to_screen or render.WorldToScreen or render.w2s) or nil

local function draw_hat()
	if not w2s then
		say_once("w2s", "[hat] no world_to_screen API in this build")
		return
	end
	if not ui_on:get() then
		hide()
		return
	end
	local pos, src = crown()
	if not pos then
		hide()
		say_once("no_head", "[hat] no head position: " .. src)
		return
	end
	said.no_head = nil
	pos = pos + Vector3.new(0, ui_offset:get(), 0)
	local R, H = ui_radius:get(), ui_height:get()
	local camPos, camLook = nil, nil
	local cam = get_cam()
	if cam then
		local okc, cf = pcall(function()
			return cam.CFrame
		end)
		if okc and cf then
			camPos, camLook = cf.Position, cf.LookVector
			-- first person: camera sits inside the head
			if (pos - camPos).Magnitude < FP_DIST then
				hide()
				return
			end
		end
	end
	local apexPos = pos + Vector3.new(0, H, 0)
	if camLook and (apexPos - camPos):Dot(camLook) <= 0 then
		hide()
		return
	end
	local ax, ay, onA = w2s(apexPos)
	if not onA then
		hide()
		return
	end
	local sx, sy, on = {}, {}, {}
	for i = 1, SEG do
		local a = math.rad((i - 1) * (360 / SEG))
		local p = pos + Vector3.new(math.sin(a) * R, 0, math.cos(a) * R)
		local x, y, ok = w2s(p)
		if ok and camLook then
			ok = (p - camPos):Dot(camLook) > 0
		end
		sx[i], sy[i], on[i] = x, y, ok
	end
	local br, bg, bb = hat_rgb()
	local visible = 0
	for i = 1, SEG do
		local j = i % SEG + 1
		local t, l = tris[i], lines[i]
		if on[i] and on[j] then
			local c = Color3.fromRGB(br * 255, bg * 255, bb * 255)
			if t then
				t.PointA = vector(sx[i], sy[i])
				t.PointB = vector(sx[j], sy[j])
				t.PointC = vector(ax, ay)
				t.Color = c
				t.Visible = true
			end
			if l then
				l.Color = c
				l:SetCoords(sx[i], sy[i], sx[j], sy[j], true)
			end
			visible += 1
		else
			if t then
				t.Visible = false
			end
			if l then
				l.Visible = false
			end
		end
	end
	drawn = true
	if ui_debug:get() then
		local tick = globals.tickcount()
		if tick - last_debug >= THROTTLE then
			last_debug = tick
			print(`[hat] src {src} facets {visible}/{SEG}`)
		end
	end
end

client.set_event_callback("paint", function()
	local ok, err = pcall(draw_hat)
	if not ok then
		say_once("paint", "[hat] paint error: " .. tostring(err))
	end
end)

client.set_event_callback("shutdown", function()
	for i = 1, SEG do
		if tris[i] then
			tris[i]:Destroy()
		end
		if lines[i] then
			lines[i]:Destroy()
		end
	end
end)

print("[hat] loaded (cone facets)")