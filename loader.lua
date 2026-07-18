if getgenv and getgenv().NH_LOADER_RUNNING then return end
if getgenv then getgenv().NH_LOADER_RUNNING = true end

local function main()
	local BASE      = "https://nighthub-keys.nighthubv1.workers.dev"
	local KEY_FILE  = "nighthub_key.txt"
	local DISCORD   = "https://discord.gg/ZaSw7uAvU"      -- Join Discord button
	local GETKEY    = "free keys are not supported until fixed"      -- Get Free Key button

	local Players = game:GetService("Players")
	local HttpService = game:GetService("HttpService")
	local LP = Players.LocalPlayer
	while not LP do task.wait(); LP = Players.LocalPlayer end

	--========================== ACCOUNT BINDING ==========================--
	-- Keys bind to Roblox ACCOUNTS, not devices. A key admits up to its seat count
	-- (1-10 accounts); once an account uses it, it counts toward that limit until
	-- the owner resets the key. USER = the player's UserId; NAME is just for the
	-- owner's admin list.
	local USER = tostring(LP.UserId)
	local NAME = LP.Name

	--========================== HTTP ==========================--
	-- Resolve the HTTP request function once, defensively. After obfuscation the
	-- global lookups still work, but wrapping them in rawget/pcall avoids issues
	-- with executors that sandbox the environment.
	local function getRequestFn()
		local ok, fn = pcall(function()
			return (syn and syn.request)
				or (http and http.request)
				or http_request
				or request
				or (fluxus and fluxus.request)
		end)
		if ok then return fn end
		return nil
	end

	local function httpPOST(url, bodyTable)
		local reqFn = getRequestFn()
		local body = HttpService:JSONEncode(bodyTable)
		if reqFn then
			local ok, res = pcall(reqFn, {
				Url = url, Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = body,
			})
			if ok and res and res.Body then
				local ok2, decoded = pcall(function() return HttpService:JSONDecode(res.Body) end)
				if ok2 then return decoded end
			end
			return nil
		end
		-- last resort: PostAsync (some executors allow it)
		local ok, res = pcall(function()
			return HttpService:PostAsync(url, body, Enum.HttpContentType.ApplicationJson)
		end)
		if ok then
			local ok2, decoded = pcall(function() return HttpService:JSONDecode(res) end)
			if ok2 then return decoded end
		end
		return nil
	end

	local function urlEnc(s)
		return (tostring(s):gsub("[^%w%-_%.~]", function(c)
			return string.format("%%%02X", string.byte(c))
		end))
	end

	-- Validate against the server. Returns ok(bool), reason/keyType(string).
	-- On success, stash the verified key info where the hub's Key Info tab reads it.
	local function validate(key)
		local res = httpPOST(BASE .. "/api/validate", { key = key, user = USER, name = NAME })
		if not res then return false, "Could not reach key server." end
		if res.ok then
			pcall(function()
				getgenv().NH_KEY_INFO = {
					key       = key,
					keyType   = res.keyType,
					expiresAt = res.expiresAt,   -- unix seconds, or nil = Lifetime
					base      = BASE,
					user      = USER,
					name      = NAME,
					checkedAt = os.time(),
				}
			end)
			return true, res.keyType or "OK"
		end
		return false, res.reason or "Invalid key."
	end

	-- Fetch + run the hub (only called after a successful validate).
	local function launchHub(key)
		local url = ("%s/loader?key=%s&user=%s&name=%s"):format(
			BASE, urlEnc(key), urlEnc(USER), urlEnc(NAME))
		local ok, src = pcall(function() return game:HttpGet(url) end)
		if not ok or type(src) ~= "string" or src == "" then
			return false, "Failed to download hub."
		end
		-- Resolve loadstring defensively: some executors expose it only via getgenv.
		local ls = loadstring or (getgenv and getgenv().loadstring)
		if type(ls) ~= "function" then
			return false, "Executor has no loadstring."
		end
		local fn, err = ls(src)
		if not fn then return false, "Hub compile error: " .. tostring(err) end
		local ranOk, runErr = pcall(fn)
		if not ranOk then return false, "Hub runtime error: " .. tostring(runErr) end
		return true
	end

	--========================== SAVED KEY ==========================--
	local function readSavedKey()
		if not readfile or not isfile then return nil end
		local exists = false
		pcall(function() exists = isfile(KEY_FILE) end)
		if not exists then return nil end
		local ok, raw = pcall(readfile, KEY_FILE)
		if ok and type(raw) == "string" then
			raw = raw:gsub("%s+", "")
			if raw ~= "" then return raw end
		end
		return nil
	end
	local function saveKey(key)
		if writefile then pcall(writefile, KEY_FILE, key) end
	end

	--========================== SILENT AUTO-LOGIN ==========================--
	do
		local saved = readSavedKey()
		if saved then
			local ok = validate(saved)
			if ok then
				local didLaunch = launchHub(saved)
				if didLaunch then return end   -- returns from main(), not the chunk
			end
		end
	end

	--========================== KEY GATE UI ==========================--
	local doneGate, launched = false, false

	local gui = Instance.new("ScreenGui")
	gui.Name = "NHKeyGate"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 99999
	local okParent = pcall(function()
		gui.Parent = (gethui and gethui()) or game:GetService("CoreGui")
	end)
	if not okParent then gui.Parent = LP:WaitForChild("PlayerGui") end

	local panel = Instance.new("Frame")
	panel.Size             = UDim2.fromOffset(360, 280)
	panel.Position         = UDim2.new(0.5, -180, 0.5, -140)
	panel.BackgroundColor3 = Color3.fromRGB(17, 17, 21)
	panel.BorderSizePixel  = 0
	panel.Parent           = gui
	local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 10); pc.Parent = panel
	local ps = Instance.new("UIStroke");  ps.Color = Color3.fromRGB(80, 160, 255); ps.Thickness = 1.5; ps.Parent = panel

	local function mkLabel(txt, y, size, color, bold)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size     = UDim2.new(1, -30, 0, 22)
		l.Position = UDim2.new(0, 15, 0, y)
		l.Font     = bold and Enum.Font.GothamBold or Enum.Font.Gotham
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Text = txt
		l.Parent = panel
		return l
	end
	mkLabel("NIGHTHUB", 12, 20, Color3.fromRGB(200, 220, 255), true)
	mkLabel("enter your key to continue", 38, 13, Color3.fromRGB(150, 150, 160))

	local box = Instance.new("TextBox")
	box.Size             = UDim2.new(1, -30, 0, 34)
	box.Position         = UDim2.new(0, 15, 0, 70)
	box.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	box.BorderSizePixel  = 0
	box.Font             = Enum.Font.Code
	box.TextSize         = 14
	box.TextColor3       = Color3.fromRGB(230, 230, 240)
	box.PlaceholderText  = "NH-X-XXXXX-XXXXX-XXXXX-XXXXX"
	box.PlaceholderColor3 = Color3.fromRGB(90, 90, 100)
	box.ClearTextOnFocus = false
	box.Text = ""
	box.Parent = panel
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(0, 6); bc.Parent = box

	local status = mkLabel("", 108, 13, Color3.fromRGB(255, 120, 120))

	local function mkButton(txt, y, color)
		local b = Instance.new("TextButton")
		b.Size             = UDim2.new(1, -30, 0, 32)
		b.Position         = UDim2.new(0, 15, 0, y)
		b.BackgroundColor3 = color
		b.BorderSizePixel  = 0
		b.Font             = Enum.Font.GothamSemibold
		b.TextSize         = 14
		b.TextColor3       = Color3.fromRGB(235, 240, 255)
		b.Text             = txt
		b.Parent           = panel
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = b
		return b
	end
	local loginBtn   = mkButton("Login",        134, Color3.fromRGB(45, 90, 160))
	local freeBtn    = mkButton("Get Free Key",  172, Color3.fromRGB(38, 38, 46))
	local discordBtn = mkButton("Join Discord",  210, Color3.fromRGB(38, 38, 46))

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.fromOffset(24, 24)
	closeBtn.Position         = UDim2.new(1, -32, 0, 8)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = 16
	closeBtn.TextColor3       = Color3.fromRGB(160, 160, 170)
	closeBtn.Text             = "X"
	closeBtn.Parent           = panel

	mkLabel("Keys bind to your Roblox account on first login.", 250, 12, Color3.fromRGB(110, 110, 120))

	loginBtn.MouseButton1Click:Connect(function()
		local key = box.Text:gsub("%s+", ""):upper()
		if key == "" then
			status.TextColor3 = Color3.fromRGB(255, 120, 120)
			status.Text = "Please enter a key."
			return
		end
		status.TextColor3 = Color3.fromRGB(150, 200, 255)
		status.Text = "Checking key..."
		local ok, res = validate(key)
		if not ok then
			status.TextColor3 = Color3.fromRGB(255, 120, 120)
			status.Text = tostring(res)
			return
		end
		status.TextColor3 = Color3.fromRGB(120, 255, 140)
		status.Text = "Key accepted - " .. tostring(res) .. ". Loading..."
		saveKey(key)
		local good, err = launchHub(key)
		if good then
			launched = true
			doneGate = true
		else
			status.TextColor3 = Color3.fromRGB(255, 120, 120)
			status.Text = tostring(err)
		end
	end)
	freeBtn.MouseButton1Click:Connect(function()
		local copied = setclipboard and pcall(setclipboard, GETKEY)
		status.TextColor3 = Color3.fromRGB(150, 200, 255)
		status.Text = copied and "Link copied - get your key there." or ("Get a key: " .. GETKEY)
	end)
	discordBtn.MouseButton1Click:Connect(function()
		local copied = setclipboard and pcall(setclipboard, DISCORD)
		status.TextColor3 = Color3.fromRGB(150, 200, 255)
		status.Text = copied and "Discord link copied." or DISCORD
	end)
	closeBtn.MouseButton1Click:Connect(function() doneGate = true end)

	repeat task.wait(0.1) until doneGate or not gui.Parent
	pcall(function() gui:Destroy() end)
end

--========================== ENTRY POINT ==========================--
-- Run main() under pcall so a partial failure never leaves the loader "stuck",
-- and always clear the re-entry guard afterward.
local ok, err = pcall(main)
if getgenv then getgenv().NH_LOADER_RUNNING = nil end
if not ok then
	warn("[NightHub] Loader error: " .. tostring(err))
end
