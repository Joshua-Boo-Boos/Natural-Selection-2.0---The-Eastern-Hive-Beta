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

local baseUpdate = GUITechMap.Update
function GUITechMap:Update(deltaTime)

    baseUpdate(self, deltaTime)

    if not self.techIcons then return end

    for i = 1, #self.techIcons do
        local techIcon = self.techIcons[i]
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
