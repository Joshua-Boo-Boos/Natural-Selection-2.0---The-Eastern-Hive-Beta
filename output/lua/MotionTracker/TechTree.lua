function TechTree:AddNode(node)

    local nodeEntityId = node:GetTechId()
    
    -- assert(self.nodeList[nodeEntityId] == nil)
    
    self.nodeList[nodeEntityId] = node
    self.techIdList[#self.techIdList + 1] = nodeEntityId
    
end