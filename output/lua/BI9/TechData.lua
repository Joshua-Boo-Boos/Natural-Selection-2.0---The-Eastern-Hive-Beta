local oldBuildTechData = BuildTechData
function BuildTechData()

    local techData = oldBuildTechData()

    table.insert(techData, {
            [kTechDataId] = kTechId.bi9,
            [kTechDataMaxHealth] = kMarineWeaponHealth,
            [kTechDataTooltipInfo] = "The Brazier Industries 9. A fully automatic machine pistol, perfect for close quarters combat against all Kharaa threats. A free, permanent secondary weapon that replaces the Pistol or Revolver.",
            [kTechDataPointValue] = kbi9PointValue,
            [kTechDataMapName] = bi9.kMapName,
            [kTechDataDisplayName] = "Brazier Industries 9",
            [kTechDataModel] = bi9.kModelName,
            [kTechDataDamageType] = kbi9DamageType,
            [kTechDataCostKey] = kbi9Cost, } )

    return techData

end
