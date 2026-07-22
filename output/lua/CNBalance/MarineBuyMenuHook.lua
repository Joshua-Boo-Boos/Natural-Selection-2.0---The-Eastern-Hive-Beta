-- CNBalance/MarineBuyMenuHook.lua
-- Overrides Marine:BuyMenu() to open GUIPrototypeLabBuyMenu when the interacted
-- structure is a PrototypeLab, and the normal GUIMarineBuyMenu otherwise (Armory).
-- Loaded as a "post" hook on lua/Marine_Client.lua (where vanilla Marine:BuyMenu is).

function Marine:BuyMenu(structure)

    -- Not ready room, and must be the local player.
    if self:GetTeamNumber() ~= 0 and Client.GetLocalPlayer() == self then

        if not self.buyMenu and
           not HelpScreen_GetHelpScreen():GetIsBeingDisplayed() and
           not GetMainMenu():GetVisible() then

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
