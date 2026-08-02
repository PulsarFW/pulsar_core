COMPONENTS.Sequence = {
	Get = function(self, key)
		return MySQL.insert.await(
			"INSERT INTO sequence (id, sequence) VALUES (?, LAST_INSERT_ID(1)) ON DUPLICATE KEY UPDATE sequence = LAST_INSERT_ID(sequence + 1)",
			{ key }
		)
	end,
}
