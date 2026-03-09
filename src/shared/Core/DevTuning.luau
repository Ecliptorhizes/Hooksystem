--[[
	DevTuning
	Lightweight runtime telemetry registry shared between scripts and the studio dev dashboard.

	API:
	- Register(key, meta): declare probe metadata / slider definition.
	- Report(key, value): push live value for dashboard.
	- SetOverrides(table): apply slider overrides from external source.
	- GetSliderValue(key): read effective slider value.
	- GetData(): snapshot values + schema.
]]

local values = {}
local schema = {}
local overrides = {}

local DevTuning = {}

function DevTuning.Register(key, meta)
	if type(key) ~= "string" or key == "" then
		return
	end
	if type(meta) ~= "table" then
		return
	end
	schema[key] = {
		unit = type(meta.unit) == "string" and meta.unit or nil,
		min = type(meta.min) == "number" and meta.min or nil,
		max = type(meta.max) == "number" and meta.max or nil,
		step = type(meta.step) == "number" and meta.step or nil,
		chart = meta.chart == true,
		label = type(meta.label) == "string" and meta.label or key,
		slider = meta.slider == true,
		default = type(meta.default) == "number" and meta.default or nil,
	}
end

function DevTuning.SetOverrides(tbl)
	if type(tbl) ~= "table" then
		return
	end
	overrides = tbl
end

function DevTuning.GetSliderValue(key)
	if type(key) ~= "string" or key == "" then
		return nil
	end
	if overrides[key] ~= nil and type(overrides[key]) == "number" then
		return overrides[key]
	end
	local meta = schema[key]
	if meta and meta.default ~= nil then
		return meta.default
	end
	return nil
end

function DevTuning.Report(key, value)
	if type(key) ~= "string" or key == "" then
		return
	end
	if key == "_schema" then
		return
	end
	local v = value
	if v == nil then
		return
	end
	if type(v) == "number" or type(v) == "string" or type(v) == "boolean" then
		values[key] = v
		if not schema[key] then
			schema[key] = {
				unit = nil,
				min = nil,
				max = nil,
				step = nil,
				chart = type(v) == "number",
				label = key,
			}
		end
	end
end

function DevTuning.GetData()
	return {
		values = table.clone(values),
		schema = table.clone(schema),
	}
end

return DevTuning
