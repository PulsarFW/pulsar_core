COMPONENTS.Execute = {
	_name = "core",
	Client = function(self, source, component, method, ...)
		TriggerClientEvent("Execute:Client:Component", source, component, method, ...)
	end,
}