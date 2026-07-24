COMPONENTS.Config = {
	Discord = {
		Server = "",
	},
	Groups = {
		Management = {
			Id = "Management",
			Name = "Management",
			Abv = "Management",
			Queue = {
				Priority = 100,
			},
			Permission = {
				Group = "admin", -- Can restart resources
				Level = 100,
			},
		},
		Dev = {
			Id = "Dev",
			Name = "Developer",
			Abv = "Dev",
			Queue = {
				Priority = 50,
			},
			Permission = {
				Group = "admin",
				Level = 100,
			},
		},
		Admin = {
			Id = "Admin",
			Name = "Admin",
			Abv = "Admin",
			Queue = {
				Priority = 50,
			},
			Permission = {
				Group = "staff",
				Level = 50,
			},
		},
		Operations = {
			Id = "Operations",
			Name = "Operations",
			Abv = "Operations",
			Queue = {
				Priority = 50,
			},
			Permission = {
				Group = "",
				Level = 0,
			},
		},
		Whitelisted = {
			Id = "Whitelisted",
			Name = "Whitelisted",
			Abv = "Whitelisted",
			Queue = {
				Priority = 0,
			},
			Permission = {
				Group = "",
				Level = 0,
			},
		},
	},
	Server = {
		ID = os.time(),
		Name = "Server Name",
		Access = GetConvar("sv_access_role", 0),
	},
}
