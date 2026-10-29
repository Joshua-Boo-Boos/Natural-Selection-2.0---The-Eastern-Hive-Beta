Script.Load("lua/GUIScript.lua")
Script.Load("lua/Utility.lua")

-- (2026-10-25) Rendered at 320x320 (was 80x80): the display texture is stretched over the gun's screen, so 80x80 made
-- the ammo text a blurry smear. Same layout and proportions, four times the resolution (BI9.lua GetUIDisplaySettings
-- must match). The text uses the 96 px font at 1.125 - the old 27 px font at 1.0 in 80 px, scaled up 4x.
local screenX = 320
local screenY = 320

-- Global state that can be externally set to adjust the display.
weaponClip     = 0
weaponAmmo     = 0
weaponAuxClip  = 0
globalTime     = 0

bulletDisplay  = nil

-- Local (was the global FontScaleVector, which other weapon displays could read or overwrite).
local kBI9FontScale = Vector(1.125, 1.125, 1)

class 'GUIbi9Display'

function GUIbi9Display:Initialize()

    self.weaponClip     = 0
    self.weaponAmmo     = 0
    self.weaponClipSize = 2
	self.globalTime = 0
    self.lowAmmoWarning = true
    
    self.flashInDelay = 1.2

    self.background = GUIManager:CreateGraphicItem()
    self.background:SetSize( Vector(screenX, screenY, 0) )
    self.background:SetPosition( Vector(0, 0, 0))    
    self.background:SetTexture("models/marine/bi9/bi9_display.dds")
	
	self.lowAmmoOverlay = GUIManager:CreateGraphicItem()
    self.lowAmmoOverlay:SetSize( Vector(screenX, screenY, 0) )
    self.lowAmmoOverlay:SetPosition( Vector(0, 0, 0))    
	self.background:AddChild(self.lowAmmoOverlay)
    
    self.clipText, self.clipTextBg = self:CreateItem(screenX*1.25/5, screenY/2)
    self.ammoText, self.ammoTextBg = self:CreateItem(screenX*3.75/5, screenY/2)
    
    local slash, slashBg = self:CreateItem(screenX/2, screenY/2)
    slash:SetText("/")
    slashBg:SetText("/")
    slash:SetFontName(Fonts.kAgencyFB_Huge)
    slashBg:SetFontName(Fonts.kAgencyFB_Huge)
    
    -- parent text items to the rotated background so they inherit rotation
    self.background:AddChild(self.clipTextBg)
    self.background:AddChild(self.clipText)
    self.background:AddChild(self.ammoTextBg)
    self.background:AddChild(self.ammoText)
    self.background:AddChild(slashBg)
    self.background:AddChild(slash)
    
    self.flashInOverlay = GUIManager:CreateGraphicItem()
    self.flashInOverlay:SetSize( Vector(screenX, screenY, 0) )
    self.flashInOverlay:SetPosition( Vector(0, 0, 0))    
    self.flashInOverlay:SetColor(Color(1,1,1,0.0))
    self.background:AddChild(self.flashInOverlay)
    
    -- Force an update so our initial state is correct.
    self:Update(0)

end

function GUIbi9Display:CreateItem(x, y)

    local textBg = GUIManager:CreateTextItem()
    textBg:SetFontName(Fonts.kAgencyFB_Huge)
	textBg:SetScale(kBI9FontScale)
    textBg:SetFontSize(10)
    textBg:SetTextAlignmentX(GUIItem.Align_Center)
    textBg:SetTextAlignmentY(GUIItem.Align_Center)
    textBg:SetPosition(Vector(x, y, 0))
    textBg:SetColor(Color(0.88, 0.98, 1, 0.25))

    -- Text displaying the amount of reserve ammo
    local text = GUIManager:CreateTextItem()
    text:SetFontName(Fonts.kAgencyFB_Huge)
    text:SetFontSize(10)
    text:SetScale(kBI9FontScale)
    text:SetTextAlignmentX(GUIItem.Align_Center)
    text:SetTextAlignmentY(GUIItem.Align_Center)
    text:SetPosition(Vector(x, y, 0))
    text:SetColor(Color(0.88, 0.98, 1))
    
    return text, textBg
    
end

function GUIbi9Display:Update(deltaTime)

    PROFILE("GUIbi9Display:Update")
    
    -- Update the ammo counter.
    
    local clipFormat = string.format("%d", self.weaponClip) 
    local ammoFormat = string.format("%02d", self.weaponAmmo)
    
    self.clipText:SetText( clipFormat )
    self.clipTextBg:SetText( clipFormat )
    
    self.ammoText:SetText( ammoFormat )
    self.ammoTextBg:SetText( ammoFormat )
    
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
    
    if self.weaponClip < 10 then
        pulseSpeed = 10
        alpha = (math.sin(self.globalTime * pulseSpeed) + 1) / 2
    elseif self.weaponClip == 0 then
        pulseSpeed = 40
        alpha = (math.sin(self.globalTime * pulseSpeed) + 1) / 2
    end
    
    if not self.lowAmmoWarning then alpha = 0 end
    
    self.lowAmmoOverlay:SetColor(Color(1, 0, 0, alpha * 0.5))

end

function GUIbi9Display:SetClip(weaponClip)
    self.weaponClip = weaponClip
end

function GUIbi9Display:SetClipSize(weaponClipSize)
    self.weaponClipSize = weaponClipSize
end

function GUIbi9Display:SetAmmo(weaponAmmo)
    self.weaponAmmo = weaponAmmo
end

function GUIbi9Display:SetGlobalTime(globalTime)
    self.globalTime = globalTime
end

function GUIbi9Display:SetLowAmmoWarning(lowAmmoWarning)
    self.lowAmmoWarning = ConditionalValue(lowAmmoWarning == "true", true, false)
end

-- Called by the player to update the components.
function Update(deltaTime)

    bulletDisplay:SetClip(weaponClip)
    bulletDisplay:SetAmmo(weaponAmmo)
	bulletDisplay:SetGlobalTime(globalTime)
	bulletDisplay:SetLowAmmoWarning(lowAmmoWarning)
    bulletDisplay:Update(deltaTime)
        
end

-- Initializes the player components.
function Initialize()

    GUI.SetSize( screenX, screenY )

    bulletDisplay = GUIbi9Display()
    bulletDisplay:Initialize()
	bulletDisplay:SetGlobalTime(globalTime)
    bulletDisplay:SetLowAmmoWarning(lowAmmoWarning)
    bulletDisplay:SetClipSize(33)

end

Initialize()
