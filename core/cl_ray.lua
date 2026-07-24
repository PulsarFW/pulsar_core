COMPONENTS.ShapeTest = {
    _protected = true,
    _name = 'core',
}

COMPONENTS.ShapeTest = {
    Ray = {
        EntityHit = function(self, startCoords, endCoords, flags, ignoreEntity, ignoreFlags)
            local rayHandle = StartExpensiveSynchronousShapeTestLosProbe(startCoords.x, startCoords.y, startCoords.z, endCoords.x, endCoords.y, endCoords.z, flags or 17, ignoreEntity or PlayerPedId(), ignoreFlags or 7)
            local _, hit, _, _, entityHit = GetShapeTestResult(rayHandle)
            return hit == 1 and entityHit or false
        end
    }
}

