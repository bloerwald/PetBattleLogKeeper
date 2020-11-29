--[[----------------------------------------------------------------------------

  LiteBag/UIOptions.lua

  Copyright 2015-2016 Mike Battersby

----------------------------------------------------------------------------]]--
local settings -- becomes savedvariable PetBattleLogKeeperSettings
local frame = PetBattleLogKeeperOptions -- the frame defined in XML

function PetBattleLogKeeperOptions_OnLoad(self)
    self.name = "Pet Battle Log Keeper" -- set name

    self.okay = function (self) PetBattleLogKeeperOptions_Close(); end; -- set closing function
    self.cancel = function (self)  PetBattleLogKeeperOptions_CancelOrLoad();  end; -- set cancel function

    -- Add the panel to the Interface Options
    InterfaceOptions_AddCategory(self)

end

function PetBattleLogKeeperOptions_OnShow(self)
    PetBattleLogKeeperSettings_UpdateUI()
end

function PetBattleLogKeeperOptions_Close()
  settings.AutoLog = PetBattleLogKeeperOptionsAutoLog:GetChecked()
  settings.DontAutoLogPve = PetBattleLogKeeperOptionsDontAutoLogPve:GetChecked()
  settings.AutoOpenWindow = PetBattleLogKeeperOptionsAutoOpenWindow:GetChecked()
  settings.DontSaveFullLog = PetBattleLogKeeperOptionsDontSaveFullLog:GetChecked()
end

function PetBattleLogKeeperOptions_CancelOrLoad()
    PetBattleLogKeeperSettings_UpdateUI()
end

function PetBattleLogKeeperSettings_UpdateUI()
    -- setup savedvar settings and values if they don't exist
    PetBattleLogKeeperSettings = PetBattleLogKeeperSettings or {}
    settings = PetBattleLogKeeperSettings
    PetBattleLogKeeperOptionsAutoLog:SetChecked(settings.AutoLog)
    PetBattleLogKeeperOptionsDontAutoLogPve:SetChecked(settings.DontAutoLogPve)
    PetBattleLogKeeperOptionsAutoOpenWindow:SetChecked(settings.AutoOpenWindow)
    PetBattleLogKeeperOptionsDontSaveFullLog:SetChecked(settings.DontSaveFullLog)
end


--text setup
function PetBattleLogKeeperOptionsAutoLog_OnLoad(self)
    self.Text:SetText("Save logged battles automatically.")
end

function PetBattleLogKeeperOptionsDontAutoLogPve_OnLoad(self)
    self.Text:SetText("Don't save PVE battles automatically.")
end

function PetBattleLogKeeperOptionsAutoOpenWindow_OnLoad(self)
    self.Text:SetText("Open log window automatically for unsaved battles.")
end

function PetBattleLogKeeperOptionsDontSaveFullLog_OnLoad(self)
    self.Text:SetText("Don't save full log. This will save memory if you don't care about the log details\n\nand log a lot of battles.")
end