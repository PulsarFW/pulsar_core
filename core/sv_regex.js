const REGEX = {
	_protected: true,
	_required: ['Test'],
	_name: 'core',
	Test: (t, regex, testString, regexOptions) => {
		return new RegExp(regex, regexOptions).test(testString);
	},
};

AddEventHandler('Proxy:Shared:RegisterReady', () => {
	exports['pulsar_core'].RegisterComponent('Regex', REGEX);
});
