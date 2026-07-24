COMPONENTS.Fetch = {
    _required = { 'Player' },
    _name = 'core',
}

function COMPONENTS.Fetch.Player(self)
    return COMPONENTS.Player.LocalPlayer
end