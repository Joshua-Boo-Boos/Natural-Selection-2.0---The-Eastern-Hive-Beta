Script.Load("lua/GUIScript.lua")
Script.Load("lua/Utility.lua")

local screenX = 512
local screenY = 80

-- Global state that can be externally set to adjust the display.
injectorType     = "REGEN"
-- weaponAmmo     = 0
-- weaponAuxClip  = 0
globalTime     = 0

bulletDisplay  = nil

FontScaleVector = Vector(1.75, 0.85, 1) * 2.75

class 'GUICombatInjectorDisplay'

function GUICombatInjectorDisplay:Initialize()

    self.injectorType     = "REGEN"
    -- self.weaponAmmo     = 0
    -- self.weaponClipSize = 4
	self.globalTime = 0
    self.lowAmmoWarning = true
    
    self.flashInDelay = 1.2

    self.background = GUIManager:CreateGraphicItem()
    self.background:SetSize( Vector(screenX, screenY, 0) )
    self.background:SetPosition( Vector(0, 0, 0))    
    self.background:SetTexture("models/marine/CombatInjector/injector_display.dds")
	
	self.lowAmmoOverlay = GUIManager:CreateGraphicItem()
    self.lowAmmoOverlay:SetSize( Vector(screenX, screenY, 0) )
    self.lowAmmoOverlay:SetPosition( Vector(0, 0, 0))
	self.background:AddChild(self.lowAmmoOverlay)

    self.injectorTypeText, self.injectorTypeTextBg = self:CreateItem(screenX/2, screenY/2)
    
    -- parent text items to the rotated background so they inherit rotation
    self.background:AddChild(self.injectorTypeTextBg)
    self.background:AddChild(self.injectorTypeText)
    
    self.flashInOverlay = GUIManager:CreateGraphicItem()
    self.flashInOverlay:SetSize( Vector(screenX, screenY, 0) )
    self.flashInOverlay:SetPosition( Vector(0, 0, 0))    
    self.flashInOverlay:SetColor(Color(1,1,1,0.0))
    self.background:AddChild(self.flashInOverlay)
    
    -- Force an update so our initial state is correct.
    self:Update(0)

end

function GUICombatInjectorDisplay:CreateItem(x, y)

    local textBg = GUIManager:CreateTextItem()
    textBg:SetFontName(Fonts.kAgencyFB_Small)
	textBg:SetScale(FontScaleVector)
    textBg:SetFontSize(10)
    textBg:SetTextAlignmentX(GUIItem.Align_Center)
    textBg:SetTextAlignmentY(GUIItem.Align_Center)
    textBg:SetPosition(Vector(x, y, 0))
    textBg:SetColor(Color(0.88, 0.98, 1, 0.25))

    -- Text displaying the amount of reserve ammo
    local text = GUIManager:CreateTextItem()
    text:SetFontName(Fonts.kAgencyFB_Small)
    text:SetFontSize(10)
    text:SetScale(FontScaleVector)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Center)
    text:SetPosition(Vector(x, y, 0))
    text:SetColor(Color(0.88, 0.98, 1))
    
    return text, textBg
    
end

function GUICombatInjectorDisplay:Update(deltaTime)

    PROFILE("GUICombatInjectorDisplay:Update")
    
    -- Update the ammo counter.
    
    self.injectorTypeText:SetText( self.injectorType )
    self.injectorTypeTextBg:SetText( self.injectorType )

    if self.injectorType == "REGEN" then
        self.injectorTypeText:SetColor(Color(0, 1, 0, 1))
        self.injectorTypeTextBg:SetColor(Color(0, 1, 0, 1))
    elseif self.injectorType == "ANTIDOTE" then
        self.injectorTypeText:SetColor(Color(1, 1, 0, 1))
        self.injectorTypeTextBg:SetColor(Color(1, 1, 0, 1))
    elseif self.injectorType == "CAT-PACK" then
        self.injectorTypeText:SetColor(Color(0, 1, 1, 1))
        self.injectorTypeTextBg:SetColor(Color(0, 1, 1, 1))
    elseif self.injectorType == "DEFENSE+" then
        self.injectorTypeText:SetColor(Color(1, 0, 1, 1))
        self.injectorTypeTextBg:SetColor(Color(1, 0, 1, 1))
    end
    
    if self.flashInDelay > 0 then
    
        self.flashInDelay = Clamp(self.flashInDelay - deltaTime, 0, 5)
        
        if self.flashInDelay == 0 then
            self.flashInOverlay:SetColor(Color(1,1,1,0.7))
        end
    
    else
    
        local flashInAlpha = self.flashInOverlay:GetColor().a    
        if flashInAlpha > 0 then
        
            local alphaPerSecond = .5        
            flashInAlpha = Clamp(flashInAlpha - alphaPerSecond * deltaTime, 0, 1)
            self.flashInOverlay:SetColor(Color(1, 1, 1, flashInAlpha))
            
        end
    
    end
	
	local alpha = 0
    local pulseSpeed = 5
    
    -- if self.weaponClip < 10 then
    --     pulseSpeed = 10
    --     alpha = (math.sin(self.globalTime * pulseSpeed) + 1) / 2
    -- elseif self.weaponClip == 0 then
    --     pulseSpeed = 40
    --     alpha = (math.sin(self.globalTime * pulseSpeed) + 1) / 2
    -- end
    
    if not self.lowAmmoWarning then alpha = 0 end
    
    self.lowAmmoOverlay:SetColor(Color(1, 0, 0, alpha * 0.5))

end

function GUICombatInjectorDisplay:SetInjectorType(injectorType)
    self.injectorType = injectorType
end

function GUICombatInjectorDisplay:SetGlobalTime(globalTime)
    self.globalTime = globalTime
end

function GUICombatInjectorDisplay:SetLowAmmoWarning(lowAmmoWarning)
    self.lowAmmoWarning = ConditionalValue(lowAmmoWarning == "true", true, false)
end

-- Called by the player to update the components.
function Update(deltaTime)

    bulletDisplay:SetInjectorType(injectorType)
	bulletDisplay:SetGlobalTime(globalTime)
	bulletDisplay:SetLowAmmoWarning(lowAmmoWarning)
    bulletDisplay:Update(deltaTime)
        
end

-- Initializes the player components.
function Initialize()

    GUI.SetSize( screenX, screenY )

    bulletDisplay = GUICombatInjectorDisplay()
    bulletDisplay:Initialize()
	bulletDisplay:SetGlobalTime(globalTime)
    bulletDisplay:SetLowAmmoWarning(lowAmmoWarning)
    bulletDisplay:SetInjectorType(injectorType)

end

Initialize()
