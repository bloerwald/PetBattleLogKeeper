--[[

   This addon provides a way to keep pet battle logs for future viewing.

   To save a log after you leave battle:
      - Summon the window via slash command (/pblk) or key binding
      - Click the 'Save Battle' button (which is only enabled while a battle can be saved that's not saved already)

   To view previously saved logs:
      - Summon the window via slash command (/pblk) or key binding
      - Click a saved log entry at the top to view the log details in the lower pane.

   Caveats:
      - If you disconnect/reload during a battle, it will not be able to save that battle.
      - Links in the log are not clickable. (I maybe recommend dropping the EditBox method and going with
        a ScrollingMessageFrame with clickable links due to the mess inline textures make with cursor
        position. However, ScrollingMessageFrames have their own issues, notably the lack of an upper
        bound to scroll to. All my dealings with ScrollingMessageFrames end in frustration so I didn't
        bother sorry!)
      
   On the PetBattleLogKeeperLogs savedvariable:
      - Due to the potentially large amounts of data, its table structure is kept as flat as possible, but as complex as necessary.
      - The data format changed from the original format to contain a set of subtables.
          pets = The pets that took part in the battle
            [1] to [3]: speciesID of user (false if slot empty)
            [4] to [6]: speciesID of opponent (false if slot empty)
          meta = Metadata. This is where you should store new variables under normal circumstances
            [1]: timestamp (string)
            [2]: duration (number)
            [3]: number of rounds (number)
            [4]: result of battle (string): loc.LOG_OUTCOME_WIN loc.LOG_OUTCOME_LOSS or loc.LOG_OUTCOME_DRAW
            [5]: Match was forfeited by loser (bool)
          log = 
            [1] to end: each combat log message is its own line in the table
      - New battles are inserted in the top of the list, at first index.

]]

local ADDON_NAME, _ = ...
local HUMAN_READABLE_ADDON_NAME = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Title")

local saved -- becomes savedvariable PetBattleLogKeeperLog
local frame = PetBattleLogKeeper -- the frame defined in XML
frame.lastFight = {} -- table that contains the last battle, wiped in PET_BATTLE_OPENING_DONE
frame.logReady = nil -- true when a battle log is stored in lastFight and ready to be saved
frame.startTime = nil -- time when a battle began (to track duration)
frame.selectedLog = nil -- the index of the currently clicked/selected log
-- watch for player forfeiting a match (playerForfeit is nil'ed during PET_BATTLE_OPENING_START)
hooksecurefunc(C_PetBattles,"ForfeitGame",function() frame.playerForfeit=true end)

local loc = {
  SETTINGS_SECTION_FIGHTS = 'Fights',
  SETTINGS_SECTION_UI = 'Interface',
  AUTO_LOG_TEXT = 'Save battles automatically',
  AUTO_LOG_TOOLTIP = 'Automatically save logs for battles. You need to manually click "' .. frame.SaveButton:GetText() .. '" in the UI otherwise.',
  DONT_AUTO_LOG_PVE_TEXT = "Don't auto-save PVE",
  DONT_AUTO_LOG_PVE_TOOLTIP = "Don't save PVE battles automatically.",
  AUTO_OPEN_TEXT = "Open window after fight",
  AUTO_OPEN_TOOLTIP = 'Automatically open ' .. HUMAN_READABLE_ADDON_NAME .. ' window after pet battle ends.',
  AUTO_OPEN_CHOICE_ALWAYS = 'Always',
  AUTO_OPEN_CHOICE_ALWAYS_TOOLTIP = 'Open window after every pet battle.',
  AUTO_OPEN_CHOICE_NEVER = 'Never',
  AUTO_OPEN_CHOICE_NEVER_TOOLTIP = 'Never open window automatically.',
  AUTO_OPEN_CHOICE_UNSAVED = 'Unsaved fight',
  AUTO_OPEN_CHOICE_UNSAVED_TOOLTIP = 'Open window automatically, if there is an unsaved log.',
  DONT_SAVE_FULL_LOG_TEXT = "Don't save full log",
  DONT_SAVE_FULL_LOG_TOOLTIP = "This will save memory if you don't care about the log details and log a lot of battles. This does not modify existing saved battles.",
  TOGGLE_WINDOW = "Toggle Window",
  COPY_ALL_LOGS = "Copy All Logs",
  COPY_THIS_LOG = "Copy This Log",

  LOG_OUTCOME_WIN = 'Win',
  LOG_OUTCOME_LOSS = 'Loss',
  LOG_OUTCOME_DRAW = 'Draw',
  LOG_FULL_PLAYER_FORFEITS = 'Player forfeits.',
  LOG_FULL_OPPONENT_FORFEITS = 'Opponent forfeits.',
  LOG_YOUR_PETS = 'Your pets: %s',
  LOG_OPPONENT_PETS = 'Opponent: %s',
  LOG_FORFEIT_SUFFIX = " (Forfeit)",
  LOG_TYPE_PVP = 'PVP',
  LOG_TYPE_PVE = 'PVE',
  LOG_SUMMARY = 'This %s battle happened on %s, lasted %s over %d rounds, and resulted in a %s%s.', -- TYPE_x, timestamp, duration, rounds, LOG_OUTCOME_, LOG_FORFEIT_SUFFIX or ''

  LOG_BATTLE_HEADER = 'Battle %d:',
  LOG_RESULT = 'Result: %s',
  LOG_DURATION = 'Duration: %s',
  LOG_TOTAL_ROUNDS = 'Total Rounds: %s',
  LOG_TIMESTAMP = 'Timestamp: %s',
  LOG_NO_TIMESTAMP = 'No Timestamp',
  LOG_ROUNDS_TITLE = 'The Battle:',

  CONFIRM_DELETE = "Are you sure you want to delete this pet battle log?",
  HELP_TEXT = "After you leave a pet battle, click '" .. frame.SaveButton:GetText() .. "' to store the battle you just left. You can enable automatically saving battle logs in the settings.\n\nClicking any saved battle in the above list will display its log here.",
}

-- event dispatch. example: when PLAYER_LOGIN fires, if frame.PLAYER_LOGIN exists, run it as a function
frame:SetScript("OnEvent",function(self,event,...)
   if self[event] then
      self[event](self,...)
   end
end)
frame:RegisterEvent("PLAYER_LOGIN")

--[[ Bindings/Slash Command ]]

BINDING_HEADER_PETBATTLELOGKEEPER = HUMAN_READABLE_ADDON_NAME
BINDING_NAME_PETBATTLELOGKEEPER_TOGGLE = loc.TOGGLE_WINDOW

-- called from Bindings.xml and slash command below
function frame:Toggle()
   frame:SetShown(not frame:IsVisible())
   frame:UpdateUI()
end

SLASH_PETBATTLELOGKEEPER1 = "/pblk" -- perhaps not the most memorable slash command
SlashCmdList["PETBATTLELOGKEEPER"] = frame.Toggle

--[[ Events ]]

-- wait until savedvariabes are loaded before doing anything meaningful
function frame:PLAYER_LOGIN()

   -- setup savedvar if it doesn't exist
  PetBattleLogKeeperLogs = PetBattleLogKeeperLogs or {}
  saved = PetBattleLogKeeperLogs
  
  -- setup savedvar settings and values if they don't exist
  PetBattleLogKeeperSettings = PetBattleLogKeeperSettings or {}
  frame:SetupSettings()

  frame:WipeLastFight()
  frame.TitleText:SetText(HUMAN_READABLE_ADDON_NAME)

  -- setup scrollframe bits
  local scrollFrame = PetBattleLogKeeper.ListFrame.ScrollFrame
  -- HACK: scroll frame templates are bork using *both* spellings of the variable, so give it both variables.
  scrollFrame.scrollBar = scrollFrame.ScrollBar
  scrollFrame.update = frame.UpdateList -- function to run when list needs updated
  scrollFrame.scrollBar.doNotHide = true
  HybridScrollFrame_CreateButtons(scrollFrame,"PetBattleLogKeeperListButtonTemplate")

  -- start with displaying an empty log ("After you leave a pet battle, etc" help text)
  frame:DisplayLogByIndex()

  -- outside of a pet battle this is the only event registered
  frame:RegisterEvent("PET_BATTLE_OPENING_DONE")
  frame:RegisterEvent("PET_BATTLE_OPENING_START")
end

-- entering a pet battle
function frame:PET_BATTLE_OPENING_START()
	frame.playerForfeit = nil -- start watching for player forfeiting the match
  frame:SetShown(false) -- hide frame
end

-- fires after the camera is done swinging around and as the battle UI comes up
-- wipe the lastFight, note speciesID of participants and register for events to watch the battle
function frame:PET_BATTLE_OPENING_DONE()
   frame:WipeLastFight()
   
   frame.logReady = nil -- this won't become true until the log is fully formed
   -- indexes [1] to [6] are the pets' speciesIDs. If a pet isn't present, false used to keep an ordered list
   -- ordered lists allocate less memory than unordered lists.
   for owner=1,2 do
      for index=1,3 do
         tinsert(frame.lastFight["pets"],C_PetBattles.GetPetSpeciesID(owner,index) or false)
      end
   end
   tinsert(frame.lastFight["meta"],date()) -- timestamp [1]
   tinsert(frame.lastFight["meta"],0) -- duration placeholder [2]
   tinsert(frame.lastFight["meta"],0) -- round placeholder [3]
   tinsert(frame.lastFight["meta"],"") -- result placeholder [4]
   tinsert(frame.lastFight["meta"],false) -- forfeit placeholder [5]
   tinsert(frame.lastFight["meta"],false) -- isPvp placeholder [6]
   frame:RegisterEvent("PET_BATTLE_CLOSE") -- to track when battle ends
   frame:RegisterEvent("CHAT_MSG_PET_BATTLE_COMBAT_LOG") -- to track combat log entries
   frame:RegisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE") -- to track battle round
   frame:RegisterEvent("PET_BATTLE_FINAL_ROUND") -- to track result of battle
   frame.startTime = GetTime()
end

-- this event often fires twice at the end of a battle but only once when out of battle
function frame:PET_BATTLE_CLOSE()
   if not C_PetBattles.IsInBattle() then
      -- outside of battle, don't need these events registered
      frame:UnregisterEvent("PET_BATTLE_FINAL_ROUND")
      frame:UnregisterEvent("PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE")
      frame:UnregisterEvent("CHAT_MSG_PET_BATTLE_COMBAT_LOG")
      frame:UnregisterEvent("PET_BATTLE_CLOSE")

      frame.logReady = true
      frame:UpdateUI()

   end
end

-- every line in the pet battle combat tab is from a CHAT_MSG_PET_BATTLE_COMBAT_LOG
-- this will copy the line to the lastFight table
function frame:CHAT_MSG_PET_BATTLE_COMBAT_LOG(msg)
  if not PetBattleLogKeeperSettings.DontSaveFullLog then
    tinsert(frame.lastFight["log"],msg)
  end
end

-- when a round completes this fires with the round finished as the first argumnet
-- it's actually one less than the current round but works out to be the last fought round because
-- the game will advance to next round as it determines whether a battle is won
function frame:PET_BATTLE_PET_ROUND_PLAYBACK_COMPLETE(round)
   frame.lastFight["meta"][3] = round
end

-- this fires when the game is over; winner argument is 1 or 2 depending on who won, however
-- 2 always wins if either side forfeits, so we check if pets are alive to tell if it was a
-- regular loss or a forfeit
function frame:PET_BATTLE_FINAL_ROUND(winner)

  -- update duration with length of fight
  if type(frame.startTime)=="number" then
      frame.lastFight["meta"][2] = ceil(GetTime()-frame.startTime)
  end

  -- if the second player is an npc, this is a pve fight
  local isPvp = not C_PetBattles.IsPlayerNPC(2)
  frame.lastFight["meta"][6] = isPvp 

  if winner==1 then -- player won
    frame.lastFight["meta"][4] = loc.LOG_OUTCOME_WIN
  else -- player didn't win
    -- determine which sides have pets still alive
    local allyAlive,enemyAlive
    local numAlly = C_PetBattles.GetNumPets(1)
    local numEnemy = C_PetBattles.GetNumPets(2)
    for i=1,3 do
        local health = C_PetBattles.GetHealth(1,i)
        if health and health>0 and i<=numAlly then
          allyAlive = true
        end
        health = C_PetBattles.GetHealth(2,i)
        if health and health>0 and i<=numEnemy then
          enemyAlive = true
        end
    end
    if allyAlive and enemyAlive then -- both pets sides have a living pet, someone forfeit tsk tsk
    frame.lastFight["meta"][5] = true -- match was a forfeit
  if frame.playerForfeit then
    frame.lastFight["meta"][4] = loc.LOG_OUTCOME_LOSS -- player forfeit match in progress, mark as loss
    if not PetBattleLogKeeperSettings.DontSaveFullLog then
      tinsert(frame.lastFight["log"],loc.LOG_FULL_PLAYER_FORFEITS)
    end
  else
    frame.lastFight["meta"][4] = loc.LOG_OUTCOME_WIN -- opponent forfeit match in progress, mark as win
    if not PetBattleLogKeeperSettings.DontSaveFullLog then
      tinsert(frame.lastFight["log"],loc.LOG_FULL_OPPONENT_FORFEITS)
    end
  end
    elseif not allyAlive and not enemyAlive then -- pets on both sides are dead, it's a draw
        frame.lastFight["meta"][4] = loc.LOG_OUTCOME_DRAW
    else -- if player didn't win and all other causes exhausted, it was a loss :(
        frame.lastFight["meta"][4] = loc.LOG_OUTCOME_LOSS
    end
  end
  local doAutoLog = PetBattleLogKeeperSettings.AutoLog and (not PetBattleLogKeeperSettings.DontAutoLogPve or isPvp)
  if doAutoLog then
    tinsert(saved,1,CopyTable(frame.lastFight))
  end
  if (doAutoLog and PetBattleLogKeeperSettings.AutoOpenWindow > 0) or PetBattleLogKeeperSettings.AutoOpenWindow > 1 then
    frame:SetShown(true)
    frame:UpdateUI()
  end
end

--[[ UI Display Updates ]]

-- updates the top scrollframe and button status; call every time frame.logReady value changes or the frame is shown
function frame:UpdateUI()
   if frame:IsVisible() then -- only does stuff if frame is on screen
      frame:UpdateList()
      frame:UpdateButtons()
      -- if no log selected (or logs not being saved), hide the log frame and extend list to whole height
      if frame.LogFrame.ForceOpen then
         frame.LogFrame:Show()
         frame.ListFrame:SetPoint("BOTTOMRIGHT",-6,120)-- just show the summary
      elseif not frame.selectedLog then
          frame.LogFrame:Hide()
          frame.ListFrame:SetPoint("BOTTOMRIGHT",-6,26) -- stretch ListFrame to cover LogFrame
      elseif not PetBattleLogKeeperSettings.DontSaveFullLog then -- if a log selected and logs are being kept, show log frame
         frame.LogFrame:Show()
         frame.ListFrame:SetPoint("BOTTOMRIGHT",frame,"TOPRIGHT",-6,-152) -- bring ListFrame up to just four rows (change -152 to other values to give it more room)
      elseif PetBattleLogKeeperSettings.DontSaveFullLog then --if log selected and no logs are being kept, still show top rows
         frame.LogFrame:Show()
         frame.ListFrame:SetPoint("BOTTOMRIGHT",-6,120)-- just show the summary
      end

   end
end

local petInfoBySpecies = {
  __data = {},
  __meta = {
    __index = function(tab, key)
      if tab.__data[key] == nil then
        local name, icon = C_PetJournal.GetPetInfoBySpeciesID(key)
        tab.__data[key] = {["name"] = name, ["icon"] = icon}
      end
      return tab.__data[key]
    end
  }
}
setmetatable(petInfoBySpecies, petInfoBySpecies.__meta)

-- this runs when the HybridScrollFrame at the top of the window needs updated. this fills in pet icons,
-- log summaries and marks the selected log
function frame:UpdateList()
   local numData = #saved
   local scrollFrame = frame.ListFrame.ScrollFrame
   local offset = HybridScrollFrame_GetOffset(scrollFrame)
   local buttons = scrollFrame.buttons

   -- iterate over the displayed buttons
   for i=1,#buttons do
      local index = i+offset -- index is the index into saved (PetBattleLogKeeperLogs)
      local button = buttons[i]
      if index<=numData then -- if index is within available data
        button.index = index -- for later selecting
        -- update the 3 ally and 3 enemy pet icons
        for j=1,6 do
          local speciesID = saved[index]["pets"][j]
          if speciesID then -- no guarantee team has 3 pets, don't show missing ones
              button.Pets[j]:Show()
              button.Pets[j]:SetTexture(petInfoBySpecies[speciesID].icon)
          else
              button.Pets[j]:Hide()
          end
        end
         -- update the text portions of the list
         button.Timestamp:SetText(saved[index]["meta"][1])
         button.Duration:SetText(frame:GetDurationAsText(saved[index]["meta"][2]))
         button.Rounds:SetText(saved[index]["meta"][3])
         button.Result:SetText(frame:GetFullResult(saved[index]["meta"][4],saved[index]["meta"][5]))
         button.Pvp:SetText(frame:GetIsPvp(saved[index]["meta"][6]))
         -- finally show selected texture if this log entry is selected
         button.Selected:SetShown(frame.selectedLog==index)
         button:Show()
      else
         button:Hide()
      end
   end
   -- let client handle remaining scrollframe tasks
   frame:PostUpdateList()
end

-- the HybridScrollFrame_Update is broken out so it can be done separately during resizes
function frame:PostUpdateList()
   local scrollFrame = frame.ListFrame.ScrollFrame
   HybridScrollFrame_Update(scrollFrame,scrollFrame.buttonHeight*#saved,scrollFrame.buttonHeight)
end

-- updates the status of the buttons across the bottom of the frame
function frame:UpdateButtons()
   -- disable delete button if a valid log is not selected
   frame.DeleteButton:SetEnabled(saved[frame.selectedLog] and true)
   -- disable save button if a log isn't ready to save or the one ready to save isn't already saved
   frame.SaveButton:SetEnabled(frame.logReady and (not saved[1] or frame.lastFight["meta"][1]~=saved[1]["meta"][1]))

   frame.CopyLogsButton:SetText(saved[frame.selectedLog] and loc.COPY_THIS_LOG or loc.COPY_ALL_LOGS)
end

-- wipes all data from the last fight and reinitializes the subtables
function frame:WipeLastFight()
	wipe(frame.lastFight)
	for k,v in pairs({"meta", "pets", "log"}) do
		if type(frame.lastFight[v])~="table" then
			frame.lastFight[v] = {}
		end
	end
end

-- fills in the log editbox in the lower half of the window with the indexed log
function frame:DisplayLogByIndex(index)
   local editBox = frame.LogFrame.ScrollFrame.EditBox
   editBox:SetText("") -- wipe anything that previously in the editbox
   frame.LogFrame.ForceOpen = false

   local log = saved[index]
   
   if not log then -- if indexed log doesn't exist (probably 0 and there are no logs)
      -- display help text instead of a log
      editBox:Insert(loc.HELP_TEXT)
      frame.LogFrame.ForceOpen = true
   else -- if log exists, toss log into the editbox
      -- at start of display, list pets used and a long-form summary
      editBox:Insert(format(loc.LOG_YOUR_PETS .. "\n",frame:GetPetsAsText(log["pets"][1],log["pets"][2],log["pets"][3])))
      editBox:Insert(format(loc.LOG_OPPONENT_PETS .. "\n\n",frame:GetPetsAsText(log["pets"][4],log["pets"][5],log["pets"][6])))
      editBox:Insert(format(loc.LOG_SUMMARY .. "\n\n",
                            frame:GetIsPvp(log["meta"][6]),
                            log["meta"][1],
                            frame:GetDurationAsText(log["meta"][2]),
                            log["meta"][3],
                            log["meta"][4],
                            frame:GetIsForfeit(log["meta"][5])))

      -- then append each line of the saved log
      local fullLog = log["log"]
      for i=1,#fullLog do
         editBox:Insert(log["log"][i].."\n")
      end
   end

   frame.LogFrame.ScrollFrame:SetVerticalScroll(0) -- scroll to top
   frame:UpdateUI()
end

--gives full result
function frame:GetFullResult(result, forfeit)
  local isForfeit = frame:GetIsForfeit(forfeit)
  local value = result .. isForfeit
  return value
end

--translates isPvp boolean variable into text for log window
function frame:GetIsPvp(isPvp)
  return isPvp == true and loc.LOG_TYPE_PVP or loc.LOG_TYPE_PVE
end

--translates isForfeit variable into text for log window
function frame:GetIsForfeit(isForfeit)
  return isForfeit == true and loc.LOG_FORFEIT_SUFFIX or ""
end

-- takes a variable number of speciesIDs and returns a string of the pets' icons and names separated by commas
function frame:GetPetsAsText(...)
   local temp = {}
   for i=1,select("#",...) do
      local speciesID=select(i,...)
      if speciesID then
         local info = petInfoBySpecies[speciesID]
         tinsert(temp,format("\124T%s:14\124t %s",info.icon,info.name))
      end
   end
   return table.concat(temp,", ") or "<unknown>"
end
function frame:GetPetNamesAsText(...)
   local temp = {}
   for i=1,select("#",...) do
      local speciesID=select(i,...)
      if speciesID then
         tinsert(temp,petInfoBySpecies[speciesID].name)
      end
   end
   return table.concat(temp,", ") or "<unknown>"
end

-- takes a duration in seconds and returns it in the format 00m 0s or 00s
function frame:GetDurationAsText(duration)
   local minutes = floor(duration/60)
   local seconds = duration%60
   return minutes>0 and format("%dm %ds",minutes,seconds) or format("%ds",seconds)
end

--[[ Frame Controls ]]

-- when one of the log entries in the top list is clicked, it displays that entry's log
function frame:ListButtonOnClick()
   local index = self.index -- index stored during UpdateList
   if index==frame.selectedLog then -- if the already-selected log is clicked, unselect it
      frame.selectedLog = nil
      frame:DisplayLogByIndex() -- display empty log
      C_Timer.After(0,frame.PostUpdateList) -- and update position of upper scrollframe
   elseif saved[index] then
      frame.selectedLog = index
      frame:DisplayLogByIndex(index) -- display chosen log (also calls UpdateUI)

      -- wait a frame to let the log display and hitrects adjust; and then check if the selected log is hidden
      -- behind the log frame. If so, scroll the ListFrame so the selectedLog is near the bottom of the visible list
      C_Timer.After(0,function() -- note 'self'' isn't pssed here! letting parent function self run through closure
         if self:GetBottom()<frame.LogFrame:GetTop() then -- the selected log is about to be hidden by the appearing log frame
            frame:ScrollListToSelectedLog() -- scroll to the selected log
         end
      end)
      
   end
end

-- scrolls the ListFrame.ScrollFrame to the frame.selectedLog index, in case log frame hid it
function frame:ScrollListToSelectedLog()
   local index = frame.selectedLog
   if index then
      local scrollFrame = frame.ListFrame.ScrollFrame
      if scrollFrame.scrollBar:IsEnabled() then -- only need to bother scrolling if list is scrollable
         local buttons = scrollFrame.buttons
         -- the following will calculate an offset that puts the index about 7/8th down the visible list
         local height = math.max(0,floor(scrollFrame.buttonHeight*(index-((scrollFrame:GetHeight()/scrollFrame.buttonHeight))*7/8)))
         HybridScrollFrame_SetOffset(scrollFrame,height)
         scrollFrame.scrollBar:SetValue(height)
      else -- scrollFrame not scrollable, set scrollbar to top just to be tidy
         scrollFrame.scrollBar:SetValue(0)
      end
   end
end

-- when delete button is clicked, a popup will confirm if they want to delete
-- potential modification: if IsShiftKeyDown() then don't ask for confirmation
function frame:DeleteButtonOnClick()
   if not StaticPopupDialogs.PETBATTLELOGKEEPER_DELETE then
      StaticPopupDialogs.PETBATTLELOGKEEPER_DELETE = {
         button1=YES, button2=NO, timeout=30, hideOnEscape=1, whileDead=1,
         text=loc.CONFIRM_DELETE,
      }
   end
   -- lazy closure sorry!
   StaticPopupDialogs.PETBATTLELOGKEEPER_DELETE.OnAccept = function(self)
      tremove(saved,frame.selectedLog) -- remove the log
      frame.selectedLog = nil -- clear selected index (potential modification: keep index to display )
      frame:DisplayLogByIndex() -- update display to an empty log (The "After you leave a pet battle" bit)
   end
   StaticPopup_Show("PETBATTLELOGKEEPER_DELETE")
end

-- the save button is only enabled while there's a valid log to save (frame.logReady)
-- this inserts a copy of frame.lastFight to the top of the savedvar and displays it
function frame:SaveButtonOnClick()
   tinsert(saved,1,CopyTable(frame.lastFight))
   frame.selectedLog = 1
   frame:DisplayLogByIndex(1)
end

--[[ Frame Methods ]]

-- this is the MouseDown of the parent frame, to move the frame around
function frame:OnMouseDown()
   self:StartMoving()
end

-- MouseUp of parent frame, to stop moving it
function frame:OnMouseUp()
   self:StopMovingOrSizing()
end

-- OnSizeChanged fires when a frame is created and positioned from userplaced
-- We only care about this while the frame is being manually resized
function frame:OnSizeChanged(width,height)
   if self.isResizing then -- if this flag is set, it's being manually resized
      self:PostUpdateList() -- adjust list scrollframe for changing size (log/editbox scrollframe is ok to leave alone)
   end
end

-- OnMouseDown of ResizeGrip will begin sizing (min/max sizes defined near top of parent frame in the XML)
function frame.ResizeGrip:OnMouseDown()
   frame:StartSizing()
   frame.isResizing = true
end

-- OnMouseUp of ResizeGrip will stop sizing
function frame.ResizeGrip:OnMouseUp()
   frame.isResizing = nil
   frame:StopMovingOrSizing()
   frame:SetUserPlaced(true)
end

--[[ Settings ]]

function frame:SetupSettings()
  local category, layout = Settings.RegisterVerticalLayoutCategory(HUMAN_READABLE_ADDON_NAME)
  Settings.RegisterAddOnCategory(category)

  local CreateSetting = function(variable, varType, default, name)
    local globalDummyVariable = '_global_dummy_PetBattleLogKeeperSettings_' .. variable
    local setting = Settings.RegisterAddOnSetting(category, globalDummyVariable, variable, PetBattleLogKeeperSettings, varType, name, default)
    return setting
  end

  local ConfigureInitializer = function(initializer)
    initializer:AddSearchTags(HUMAN_READABLE_ADDON_NAME)
    initializer:AddSearchTags('pblk')
    return initializer
  end

  local AddBoolean = function(variable, default, name, tooltip)
    local setting = CreateSetting(variable, Settings.VarType.Boolean, default, name)
    local initializer = Settings.CreateCheckbox(category, setting, tooltip)
    return ConfigureInitializer(initializer)
  end

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(loc.SETTINGS_SECTION_FIGHTS));

  local autoLogInitializer = AddBoolean("AutoLog", Settings.Default.True, loc.AUTO_LOG_TEXT, loc.AUTO_LOG_TOOLTIP)

  local dontAutoLogPveInitializer = AddBoolean("DontAutoLogPve", Settings.Default.True, loc.DONT_AUTO_LOG_PVE_TEXT, loc.DONT_AUTO_LOG_PVE_TOOLTIP)
  dontAutoLogPveInitializer:SetParentInitializer(autoLogInitializer, function() return PetBattleLogKeeperSettings.AutoLog end)

  AddBoolean("DontSaveFullLog", Settings.Default.False, loc.DONT_SAVE_FULL_LOG_TEXT, loc.DONT_SAVE_FULL_LOG_TOOLTIP)

  layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(loc.SETTINGS_SECTION_UI));

  if type(PetBattleLogKeeperSettings.AutoOpenWindow) == 'boolean' then
    PetBattleLogKeeperSettings.AutoOpenWindow = PetBattleLogKeeperSettings.AutoOpenWindow and 1 or 0
  end

  local function AutoOpenOptions()
    local container = Settings.CreateControlTextContainer();
    container:Add(0, loc.AUTO_OPEN_CHOICE_NEVER, loc.AUTO_OPEN_CHOICE_NEVER_TOOLTIP);
    container:Add(1, loc.AUTO_OPEN_CHOICE_UNSAVED, loc.AUTO_OPEN_CHOICE_UNSAVED_TOOLTIP);
    container:Add(2, loc.AUTO_OPEN_CHOICE_ALWAYS, loc.AUTO_OPEN_CHOICE_ALWAYS_TOOLTIP);
    return container:GetData();
  end

  local settingAutoOpen = CreateSetting('AutoOpenWindow', Settings.VarType.Number, 0, loc.AUTO_OPEN_TEXT)
  ConfigureInitializer(Settings.CreateDropdown(category, settingAutoOpen, AutoOpenOptions, loc.AUTO_OPEN_TOOLTIP))
end

function frame:CopyLogsButtonOnClick()
    frame:ShowLogInEditBox(saved[frame.selectedLog])
end

function frame:ShowLogInEditBox(maybeLog)
   if not frame.EditBox then
       -- Create a ScrollFrame to hold the EditBox
       local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
       scrollFrame:SetSize(380, 400)
       scrollFrame:SetPoint("CENTER", frame, "CENTER")

       -- Create the EditBox inside the ScrollFrame
       local editBox = CreateFrame("EditBox", nil, scrollFrame, "BackdropTemplate")
       editBox:SetMultiLine(true)
       editBox:SetSize(370, 1000)  -- Set the height large enough to allow scrolling
       editBox:SetFontObject(ChatFontNormal)
       editBox:SetAutoFocus(true)
       editBox:SetTextInsets(15, 15, 15, 15)

       editBox:SetFrameStrata("DIALOG")
       editBox:SetFrameLevel(40)

       editBox:SetScript("OnEscapePressed", function(self)
           self:ClearFocus()  -- Lose focus when Esc is pressed
           frame.EditBox:Hide()
           frame.ScrollFrame:Hide()  -- Hide the ScrollFrame (and the scrollbar)
       end)

       -- Set the backdrop for the EditBox to add a background
       editBox:SetBackdrop({
           bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",  -- Background texture
           edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",    -- Border texture
           tile = true, tileSize = 32, edgeSize = 32,
           insets = { left = 8, right = 8, top = 8, bottom = 8 }
       })
       editBox:SetBackdropColor(0, 0, 0)  -- Black background
       editBox:SetBackdropBorderColor(1, 1, 1)  -- White border

       -- Link the EditBox to the ScrollFrame
       scrollFrame:SetScrollChild(editBox)

       -- Enable mouse wheel scrolling
       scrollFrame:EnableMouseWheel(true)
       scrollFrame:SetScript("OnMouseWheel", function(self, delta)
           local current = self:GetVerticalScroll()
           local maxScroll = self:GetVerticalScrollRange()
           local newScroll = math.min(maxScroll, math.max(0, current - (delta * 30)))
           self:SetVerticalScroll(newScroll)
       end)

       -- Save references for later use
       frame.EditBox = editBox
       frame.ScrollFrame = scrollFrame
   end

   -- Get the log text and display it in the EditBox
   frame.EditBox:SetText(maybeLog and frame:GetFormattedLog(maybeLog) or frame:GetFullLogText())
   frame.EditBox:Show()
   frame.ScrollFrame:Show()  -- Show ScrollFrame when displaying the log
   frame.EditBox:HighlightText()  -- Automatically highlight the text for easy copying
end

-- Get the full log as a string
function frame:GetFullLogText()
   local fullLogText = ""

   -- Concatenate all logs, or just the selected log, into a single string
   for i, log in ipairs(PetBattleLogKeeperLogs) do
       fullLogText = fullLogText .. format(loc.LOG_BATTLE_HEADER, i) .. "\n"
       fullLogText = fullLogText .. frame:GetFormattedLog(log) .. "\n"
   end

   return fullLogText
end

local function stripColorsAndTextures(s)
   local keepGoing = 1
   while keepGoing > 0
   do
      s, keepGoing = string.gsub(s,"|c%x%x%x%x%x%x%x%x(.-)|r","%1")
   end
   return string.gsub(s, "|T.-|t", "")
end

-- Helper function to format the log content
function frame:GetFormattedLog(log)
   local logContent = ""

   local timestamp = log.meta[1] or loc.LOG_NO_TIMESTAMP
   logContent = logContent .. format(loc.LOG_TIMESTAMP, timestamp) .. "\n"
   logContent = logContent .. format(loc.LOG_YOUR_PETS, frame:GetPetNamesAsText(log.pets[1], log.pets[2], log.pets[3])) .. "\n"
   logContent = logContent .. format(loc.LOG_OPPONENT_PETS, frame:GetPetNamesAsText(log.pets[4], log.pets[5], log.pets[6])) .. "\n"
   logContent = logContent .. format(loc.LOG_RESULT, frame:GetFullResult(log.meta[4], log.meta[5])) .. "\n"
   logContent = logContent .. format(loc.LOG_DURATION, frame:GetDurationAsText(log.meta[2])) .. "\n"
   logContent = logContent .. format(loc.LOG_TOTAL_ROUNDS, log.meta[3]) .. "\n"
   logContent = logContent .. "\n"
   logContent = logContent .. loc.LOG_ROUNDS_TITLE .. "\n"

   for _, entry in ipairs(log.log) do
      if entry:find(PET_BATTLE_COMBAT_LOG_NEW_ROUND) then
         logContent = logContent .. "\n"  -- Add a newline before the round
      end
      logContent = logContent .. stripColorsAndTextures(entry) .. "\n"
   end

   return logContent
end
