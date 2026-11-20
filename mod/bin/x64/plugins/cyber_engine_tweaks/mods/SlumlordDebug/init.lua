-- SlumlordDebug: CET developer window for the Slumlord mod.
-- Opens with the CET overlay. Requires the Slumlord redscript files to be compiled.
--
-- Position capture: stand at a property's entrance, pick its id, press "Capture position"
-- (or bind the hotkey in CET > Bindings). Lines are appended to captured_positions.txt in
-- this folder, ready to paste into r6/scripts/Slumlord/Positions.reds.

local Debug = {
  overlayOpen = false,
  ids = {},
  names = {},
  selected = 0,       -- 0-based index for ImGui.Combo
  rank = 0,
  dump = "",
  status = "",
  captures = {},
}

local CAPTURE_FILE = "captured_positions.txt"
local RANKS = { "D", "C", "B", "A", "S" }

local function system()
  local container = Game.GetScriptableSystemsContainer()
  if not container then return nil end
  return container:Get(CName.new("Slumlord.SlumlordSystem"))
end

local function boss()
  return Game.GetScriptableSystemsContainer():Get(CName.new("Slumlord.SlumlordBoss"))
end

local function noclip()
  return Game.GetScriptableSystemsContainer():Get(CName.new("Slumlord.SlumlordNoclip"))
end

local function fight()
  return Game.GetScriptableSystemsContainer():Get(CName.new("Slumlord.SlumlordFight"))
end

local function finger()
  return Game.GetScriptableSystemsContainer():Get(CName.new("Slumlord.SlumlordFinger"))
end

local function setStatus(text)
  Debug.status = text
  print("[Slumlord] " .. text)
end

local function loadIds()
  local sys = system()
  if not sys then return false end
  local props = sys:GetProperties()
  if not props or #props == 0 then return false end
  Debug.ids, Debug.names = {}, {}
  for _, p in ipairs(props) do
    local id = Game.NameToString(p.id)
    table.insert(Debug.ids, id)
    table.insert(Debug.names, id .. "  (" .. p.displayName .. ")")
  end
  return true
end

local function selectedId()
  return Debug.ids[Debug.selected + 1]
end

local function refreshDump()
  local sys = system()
  if not sys then
    Debug.dump = "Slumlord system not found. Are the redscript files compiled? Is a save loaded?"
    return
  end
  Debug.dump = sys:Debug_Dump()
end

local function capturePosition()
  local player = Game.GetPlayer()
  if not player then
    setStatus("No player. Load a save first.")
    return
  end
  local id = selectedId()
  if not id then
    setStatus("No property selected.")
    return
  end
  local pos = player:GetWorldPosition()
  local yaw = player:GetWorldYaw()
  local line = string.format(
    '    if Equals(id, n"%s") { return new Vector4(%.2f, %.2f, %.2f, 1.0); } // yaw %.1f',
    id, pos.x, pos.y, pos.z, yaw)
  local file = io.open(CAPTURE_FILE, "a")
  if file then
    file:write(line, "\n")
    file:close()
  end
  table.insert(Debug.captures, 1, line)
  if #Debug.captures > 8 then table.remove(Debug.captures) end
  setStatus("Captured " .. id .. (file and "" or " (file write failed; copy from the list below)"))
end

-- Scene spots for Million Dollar Baby: stand where an actor or prop should be, facing the way it
-- should face, pick the spot, press "Capture spot". Lines go to captured_positions.txt.
-- Conversation Overtime (Las Palapas): the motel_ spots.
local SPOTS = { "knocker", "welder", "smoker", "talker", "oshima", "light",
                "motel_finger", "motel_goon_1", "motel_goon_2", "motel_goon_3", "motel_bike", "motel_finger_hide" }
Debug.spot = 0

local function captureSpot()
  local player = Game.GetPlayer()
  if not player then
    setStatus("No player. Load a save first.")
    return
  end
  local name = SPOTS[Debug.spot + 1]
  local pos = player:GetWorldPosition()
  local yaw = player:GetWorldYaw()
  local line = string.format('SPOT %s %.2f %.2f %.2f yaw %.1f', name, pos.x, pos.y, pos.z, yaw)
  local file = io.open(CAPTURE_FILE, "a")
  if file then
    file:write(line, "\n")
    file:close()
  end
  print("[Slumlord] " .. line)
  table.insert(Debug.captures, 1, line)
  if #Debug.captures > 8 then table.remove(Debug.captures) end
  setStatus("Captured spot " .. name)
end

local function guarded(label, fn)
  local ok, err = pcall(fn)
  if not ok then setStatus(label .. " failed: " .. tostring(err)) end
end

registerForEvent("onInit", function()
  print("[Slumlord] Debug window loaded. Open the CET overlay to use it.")
end)

registerForEvent("onOverlayOpen", function()
  Debug.overlayOpen = true
  guarded("Load ids", loadIds)
  guarded("Dump", refreshDump)
end)

registerForEvent("onOverlayClose", function()
  Debug.overlayOpen = false
end)

local function toggleNoclip()
  local on = noclip():Toggle()
  Debug.flying = on
  setStatus(on and "Noclip ON: move keys fly along the camera, Jump up, Crouch down, Sprint fast."
               or "Noclip OFF (invulnerable for 10 s).")
end

-- Noclip frames: Noclip.reds integrates and teleports; it is stepped from here every frame.
registerForEvent("onUpdate", function(dt)
  if Debug.flying then
    local ok = pcall(function() noclip():Step(dt) end)
    if not ok then Debug.flying = false end
  end
end)

registerHotkey("slumlord_noclip", "Toggle noclip", function()
  guarded("Noclip", toggleNoclip)
end)

registerHotkey("slumlord_capture", "Capture property position", function()
  guarded("Capture", capturePosition)
end)

registerForEvent("onDraw", function()
  if not Debug.overlayOpen then return end

  if ImGui.Begin("Slumlord Debug") then
    local flying = false
    local status = "?"
    pcall(function() flying = noclip():IsOn(); status = noclip():Status() end)
    Debug.flying = flying
    if ImGui.Button(flying and "Noclip: ON" or "Noclip: OFF") then guarded("Noclip", toggleNoclip) end
    ImGui.SameLine()
    ImGui.Text("(bind a key: CET > Bindings > Toggle noclip)")
    ImGui.Text("Noclip: " .. status)
    ImGui.Separator()
    -- Money and time
    if ImGui.Button("+ 100,000 eddies") then
      guarded("Add money", function() Game.AddToInventory("Items.money", 100000) end)
      setStatus("Added 100,000.")
    end
    ImGui.SameLine()
    if ImGui.Button("Force rent day") then
      guarded("Force rent day", function()
        local waiting = system():Debug_ForceRentDay()
        setStatus("Rent day forced. Waiting: " .. tostring(waiting))
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Collect") then
      guarded("Collect", function()
        setStatus("Collected " .. tostring(system():Collect()))
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Reset all") then
      guarded("Reset", function() system():Debug_ResetAll() end)
      setStatus("All Slumlord state reset on this save.")
    end

    ImGui.Separator()

    -- Property selection
    if #Debug.ids == 0 then
      ImGui.Text("No properties loaded.")
      ImGui.SameLine()
      if ImGui.Button("Reload ids") then guarded("Load ids", loadIds) end
    else
      Debug.selected = ImGui.Combo("Property", Debug.selected, Debug.names, #Debug.names)
      if ImGui.Button("Buy (pay)") then
        guarded("Buy", function()
          setStatus("Buy result: " .. tostring(system():Buy(CName.new(selectedId()))))
        end)
      end
      ImGui.SameLine()
      if ImGui.Button("Buy (free)") then
        guarded("Buy free", function()
          setStatus("Free buy: " .. tostring(system():Debug_BuyFree(CName.new(selectedId()))))
        end)
      end
      ImGui.SameLine()
      if ImGui.Button("Release") then
        guarded("Release", function()
          setStatus("Released: " .. tostring(system():Debug_Release(CName.new(selectedId()))))
        end)
      end
      ImGui.SameLine()
      if ImGui.Button("Capture position") then
        guarded("Capture", capturePosition)
      end

      ImGui.PushItemWidth(120)
      Debug.rank = ImGui.SliderInt("##rank", Debug.rank, 0, 4, RANKS[Debug.rank + 1])
      ImGui.PopItemWidth()
      ImGui.SameLine()
      if ImGui.Button("Set rank") then
        guarded("Set rank", function()
          system():Debug_SetRank(CName.new(selectedId()), Debug.rank)
          setStatus("Rank set to " .. RANKS[Debug.rank + 1])
        end)
      end
    end

    ImGui.Separator()
    ImGui.Text("Contractors (renovation)")
    if ImGui.Button("Unlock gig contractors") then
      guarded("Unlock contractors", function()
        system():Debug_UnlockContractors()
        setStatus("The Architect and Oshima are available")
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Reset job limits") then
      guarded("Reset jobs", function()
        system():Debug_ResetJobs()
        setStatus("Contractor jobs reset on every property")
      end)
    end

    ImGui.Separator()
    ImGui.Text("Watson boss: Oshima's call")
    if ImGui.Button("Ring now") then
      guarded("Ring", function()
        boss():Debug_RingNow()
        setStatus("Oshima call: " .. boss():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Reset call") then
      guarded("Reset call", function()
        boss():Debug_Reset()
        setStatus("Oshima call: " .. boss():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Call state") then
      guarded("Call state", function() setStatus("Oshima call: " .. boss():Debug_State()) end)
    end

    ImGui.Text("Watson boss: Million Dollar Baby (Karl's texts, Harbor Safehouse fight)")
    if ImGui.Button("Start texts") then
      guarded("Start texts", function()
        fight():Debug_StartTexts()
        setStatus("Million Dollar Baby: " .. fight():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Reset fight") then
      guarded("Reset fight", function()
        fight():Debug_Reset()
        setStatus("Million Dollar Baby: " .. fight():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Fight state") then
      guarded("Fight state", function() setStatus("Million Dollar Baby: " .. fight():Debug_State()) end)
    end
    ImGui.PushItemWidth(140)
    Debug.spot = ImGui.Combo("##spot", Debug.spot, SPOTS, #SPOTS)
    ImGui.PopItemWidth()
    ImGui.SameLine()
    if ImGui.Button("Capture spot") then guarded("Capture spot", captureSpot) end

    ImGui.Separator()
    ImGui.Text("Santo Domingo boss: Conversation Overtime (Quentin Finger)")
    if ImGui.Button("Ring threat") then
      guarded("Ring threat", function()
        boss():Debug_RingFinger(false)
        setStatus("Conversation Overtime: " .. finger():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Ring goad") then
      guarded("Ring goad", function()
        boss():Debug_RingFinger(true)
        setStatus("Conversation Overtime: " .. finger():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Start quest") then
      guarded("Start quest", function()
        finger():Debug_StartQuest()
        setStatus("Conversation Overtime: " .. finger():Debug_State())
      end)
    end
    if ImGui.Button("Lease broken now") then
      guarded("Lease broken", function() setStatus("Conversation Overtime: " .. finger():Debug_HarassNow()) end)
    end
    ImGui.SameLine()
    if ImGui.Button("Win (stand-in)") then
      guarded("Win", function()
        finger():Debug_Win()
        setStatus("Conversation Overtime: " .. finger():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Reset Conversation Overtime") then
      guarded("Reset Conversation Overtime", function()
        finger():Debug_Reset()
        setStatus("Conversation Overtime: " .. finger():Debug_State())
      end)
    end
    ImGui.SameLine()
    if ImGui.Button("Conversation Overtime state") then
      guarded("Conversation Overtime state", function() setStatus("Conversation Overtime: " .. finger():Debug_State()) end)
    end

    ImGui.Separator()
    if ImGui.Button("Refresh state") then guarded("Dump", refreshDump) end
    ImGui.SameLine()
    ImGui.Text(Debug.status)
    ImGui.InputTextMultiline("##dump", Debug.dump, 65535, 760, 300, ImGuiInputTextFlags.ReadOnly)

    if #Debug.captures > 0 then
      ImGui.Separator()
      ImGui.Text("Recent captures (also in " .. CAPTURE_FILE .. "):")
      for _, line in ipairs(Debug.captures) do
        ImGui.TextWrapped(line)
      end
    end
  end
  ImGui.End()
end)
