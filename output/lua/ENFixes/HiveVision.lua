-- Fix: HiveVision_SetEnabled / HiveVision_SyncCamera called by the render loop
-- before HiveVision_Initialize() has run (LoadComplete fires after the first
-- render frames during map loading). Both functions index HiveVision_camera
-- which is nil until Initialize runs, producing Script Error #5941.
local _orig_SetEnabled = HiveVision_SetEnabled
function HiveVision_SetEnabled(enabled)
    if not HiveVision_camera or not HiveVision_screenEffect then return end
    _orig_SetEnabled(enabled)
end

local _orig_SyncCamera = HiveVision_SyncCamera
function HiveVision_SyncCamera(camera, forCommander)
    if not HiveVision_camera or not HiveVision_screenEffect then return end
    _orig_SyncCamera(camera, forCommander)
end
