COMPONENTS.WaitList = {
	IsInQueue = function(self, id)
		local k = COMPONENTS.State:Get('flags', string.format("WaitList:%s", id))
		return k ~= nil and k.waiting
	end,
}
  