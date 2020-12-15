local _, PBLK = ...

PBLK_LABEL = 'Pet Battle Log Keeper'
PBLK_SUBTEXT = 'General settings for the Pet Battle Log Keeper addon.'
PBLK_AUTO_LOG_TEXT = 'Save logged battles automatically.'
PBLK_DONT_AUTO_LOG_PVE_TEXT = "Don't save PVE battles automatically."
PBLK_AUTO_OPEN_TEXT = "Open log window automatically for unsaved battles."
PBLK_DONT_SAVE_FULL_LOG_TEXT = "Don't save full log."
PBLK_DONT_SAVE_FULL_LOG_TOOLTIP = "This will save memory if you don't care about the log details and log a lot of battles."

local function PetBattleLogKeeperOptions_Okay()
  PBLK.Settings.AutoLog = PetBattleLogKeeperOptionsAutoLog:GetChecked()
  PBLK.Settings.DontAutoLogPve = PetBattleLogKeeperOptionsDontAutoLogPve:GetChecked()
  PBLK.Settings.AutoOpenWindow = PetBattleLogKeeperOptionsAutoOpenWindow:GetChecked()
  PBLK.Settings.DontSaveFullLog = PetBattleLogKeeperOptionsDontSaveFullLog:GetChecked()
end

local function PetBattleLogKeeperSettings_Refresh()
  PetBattleLogKeeperOptionsAutoLog:SetChecked(PBLK.Settings.AutoLog)
  PetBattleLogKeeperOptionsDontAutoLogPve:SetChecked(PBLK.Settings.DontAutoLogPve)
  PetBattleLogKeeperOptionsAutoOpenWindow:SetChecked(PBLK.Settings.AutoOpenWindow)
  PetBattleLogKeeperOptionsDontSaveFullLog:SetChecked(PBLK.Settings.DontSaveFullLog)
end

function PetBattleLogKeeperSettings_Default()
  for name, value in pairs(PBLK.Defaults) do
    PBLK.Settings[name] = value
  end
end

function PetBattleLogKeeperOptions_OnLoad(self)
  self.name = PBLK_LABEL
  self.okay = PetBattleLogKeeperOptions_Okay
  self.cancel = function() end
  self.refresh = PetBattleLogKeeperSettings_Refresh
  self.default = PetBattleLogKeeperSettings_Default

  InterfaceOptions_AddCategory(self)
end

function PetBattleLogKeeperOptionsAutoLog_OnLoad(self)
  self.Text:SetText(PBLK_AUTO_LOG_TEXT)
  self.SetValue = function() end
end

function PetBattleLogKeeperOptionsDontAutoLogPve_OnLoad(self)
  self.Text:SetText(PBLK_DONT_AUTO_LOG_PVE_TEXT)
  self.SetValue = function() end
end

function PetBattleLogKeeperOptionsAutoOpenWindow_OnLoad(self)
  self.Text:SetText(PBLK_AUTO_OPEN_TEXT)
  self.SetValue = function() end
end

function PetBattleLogKeeperOptionsDontSaveFullLog_OnLoad(self)
  self.Text:SetText(PBLK_DONT_SAVE_FULL_LOG_TEXT)
  self.tooltipText = PBLK_DONT_SAVE_FULL_LOG_TOOLTIP
  self.SetValue = function() end
end
