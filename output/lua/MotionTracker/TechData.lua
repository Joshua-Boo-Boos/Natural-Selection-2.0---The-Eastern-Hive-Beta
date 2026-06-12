local oldBuildTechData = BuildTechData
function BuildTechData()
    
    local techData = oldBuildTechData()
							
	table.insert(techData,{ 
	
            [kTechDataId] = kTechId.MotionTracker,
            [kTechDataMaxHealth] = kMarineWeaponHealth,
            [kTechDataTooltipInfo] = "Purchase the Motion Tracker, a non-lethal detection device. Hold primary to scan a forward cone and reveal Kharaa; its range, arc, wall-vision and cloak-piercing scale with Weapons Level. Recharges at an Armory.",
            [kTechDataPointValue] = kMotionTrackerPointValue,
            [kTechDataMapName] = MotionTracker.kMapName,
            [kTechDataDisplayName] = "Motion Tracker",
            [kTechDataModel] = MotionTracker.kModelName,
            [kTechDataCostKey] = kMotionTrackerCost,} )
	
	
	table.insert(techData,{

            [kTechDataId] = kTechId.MotionTrackerTech,
            [kTechDataCostKey] = kMotionTrackerTechResearchCost,
            [kTechDataResearchTimeKey] = kMotionTrackerTechResearchTime,
            [kTechDataDisplayName] = "RESEARCH_MotionTracker",
            [kTechDataTooltipInfo] = "Allows the Frontiersmen to purchase the Motion Tracker, a Kharaa detection device whose scanning power scales with Weapons Level.", } )
   
	table.insert(techData,{ 
	
            [kTechDataId] = kTechId.DropMotionTracker,
            [kTechDataMapName] = MotionTracker.kMapName,
            [kTechDataDisplayName] = "MotionTracker_DROP",
            [kTechIDShowEnables] = false,
            [kTechDataTooltipInfo] = "Allows the Frontiersmen Commander to materialise a Motion Tracker, a Kharaa detection device whose scanning power scales with Weapons Level.",
            [kTechDataModel] = MotionTracker.kModelName,
            [kTechDataCostKey] = kMotionTrackerCost,
            [kStructureAttachId] = { kTechId.Armory, kTechId.AdvancedArmory },
            [kStructureAttachRange] = kArmoryWeaponAttachRange,
            [kStructureAttachRequiresPower] = true, } )

    return techData

end
