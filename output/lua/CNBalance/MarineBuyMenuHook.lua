-- CNBalance/MarineBuyMenuHook.lua
-- Overrides Marine:BuyMenu() to branch to GUIPrototypeLabBuyMenu when the
-- interacted structure is a PrototypeLab, and GUIMarineBuyMenu for everything
-- else (Armory).
-- Loaded as a "post" hook on lua/Marine_Client.lua, which is where vanilla
-- Marine:BuyMenu is defined.  This override replaces that definition.

function Marine:BuyMenu(structure)

    -- Guard: not ready room, and must be the local player
    if self:GetTeamNumber() ~= 0 and Client.GetLocalPlayer() == self then

        if not self.buyMenu and
           not HelpScreen_GetHelpScreen():GetIsBeingDisplayed() and
           not GetMainMenu():GetVisible() then

            -- Choose GUI class based on structure type
            local className = (structure and structure:isa("PrototypeLab"))
                and "CNBalance/GUI/GUIPrototypeLabBuyMenu"
                or  "GUIMarineBuyMenu"

            self.buyMenu = GetGUIManager():CreateGUIScript(className)

            MarineUI_SetHostStructure(structure)

            if structure then
                self.buyMenu:SetHostStructure(structure)
            end

            self:TriggerEffects("marine_buy_menu_open")

        end

    end

end
