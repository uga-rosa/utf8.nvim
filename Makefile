.PHONY: integration lint test format

integration: lint test

lint:
	luacheck lua

test:
	vusted lua

format:
	stylua lua
