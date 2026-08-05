-- GUITechMap (NS2.0-TEH Beta post-hook)
--
-- The alien "J-menu tech tree visual" (GUITechMap) builds each node icon from
-- the shared atlas via GetTextureCoordinatesForIcon(techId). Primal Scream has
-- no atlas slot of its own and was pointed at Umbra's slot, so it showed the
-- Umbra icon. CreateTechIcon is a local function in the vanilla file, so we
-- can't override it directly; instead we re-skin the Primal Scream node icon
-- after Update runs. The base Update already tints every node with the team
-- colour (kTechMapIconColors), so the custom icon is tinted orange like the
-- rest automatically -- we only swap the texture here.

local kPrimalScreamIconTexture = PrecacheAsset("ui/lerk/primal_scream.dds")
local kPrimalScreamIconSize = 464

-- Combat Engineers is the marine equivalent of the Primal Scream case above: a standalone dds with
-- no atlas cell of its own, pointed at the Combat Builder's slot as a fallback so it would otherwise
-- render the Combat Builder icon. Re-skinned here, in this file, for the same reason Primal Scream
-- is - this is the file that is an actual post-hook on lua/GUITechMap.lua, so GUITechMap is
-- guaranteed to exist and this override is guaranteed to be the last one applied. (It was previously
-- attempted from CNBalance/GUI/CombatEngineersIcon.lua, a post-hook on a DIFFERENT file
-- (GUICommanderButtons.lua) that pulled GUITechMap in via Script.Load and wrapped Initialize - which
-- depended on the relative load order of two unrelated hook targets and did not take effect.)
local kCombatEngineersIconTexture = PrecacheAsset("ui/combat_engineers/combat_engineers_icon.dds")
local kCombatEngineersIconSize = 100

local baseUpdate = GUITechMap.Update
function GUITechMap:Update(deltaTime)

    baseUpdate(self, deltaTime)

    if not self.techIcons then return end

    for i = 1, #self.techIcons do
        local techIcon = self.techIcons[i]

        if techIcon and techIcon.TechId == kTechId.CombatEngineers and techIcon.Icon
           and not techIcon._combatEngineersReskinned then

            -- Texture only: the base Update keeps tinting the icon with the node's status colour
            -- every frame, so the node still greys out / lights up on research exactly as before.
            -- No resize, unlike Primal Scream above - this artwork is authored as an icon that
            -- already fills its cell, so it matches the other nodes at the default size.
            techIcon.Icon:SetTexture(kCombatEngineersIconTexture)
            techIcon.Icon:SetTexturePixelCoordinates(0, 0, kCombatEngineersIconSize, kCombatEngineersIconSize)

            techIcon._combatEngineersReskinned = true

        end

        if techIcon and techIcon.TechId == kTechId.PrimalScream and techIcon.Icon
           and not techIcon._primalScreamReskinned then

            techIcon.Icon:SetTexture(kPrimalScreamIconTexture)
            techIcon.Icon:SetTexturePixelCoordinates(0, 0, kPrimalScreamIconSize, kPrimalScreamIconSize)

            -- The standalone dds has no internal padding like the atlas cells,
            -- so shrink it (and thin it slightly) and re-centre within its cell
            -- so it matches the size of the other tech-map icons. The base
            -- Update keeps tinting it with the node status colour (orange),
            -- so we only touch size/texture here. Done once via the flag.
            local curSize = techIcon.Icon:GetSize()
            local curPos = techIcon.Icon:GetPosition()
            local newW = curSize.x * 0.78 * 0.88
            local newH = curSize.y * 0.78 * (1 / 1.15)
            techIcon.Icon:SetSize(Vector(newW, newH, 0))
            techIcon.Icon:SetPosition(Vector(
                curPos.x + (curSize.x - newW) / 2,
                curPos.y + (curSize.y - newH) / 2,
                0))

            techIcon._primalScreamReskinned = true

        end
    end

end
