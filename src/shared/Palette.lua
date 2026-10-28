-- Mundial War · readable, non-neon colours (RGB 0..255). Shared so the server can
-- pick colours that differ from nearby nations and the client can paint them.
local Palette = {}

Palette.Water = { 46, 92, 138 }
Palette.WaterCoast = { 62, 112, 158 }
Palette.Neutral = { 214, 208, 192 }
Palette.NeutralPolar = { 228, 230, 228 }
Palette.NeutralCoast = { 198, 192, 176 }
Palette.CountryLine = { 188, 181, 163 }

Palette.Nations = {
	{ 66, 120, 196 }, { 196, 72, 68 }, { 72, 160, 92 }, { 222, 178, 60 }, { 142, 92, 182 },
	{ 46, 166, 168 }, { 218, 120, 50 }, { 190, 88, 150 }, { 120, 152, 52 }, { 96, 96, 168 },
	{ 168, 116, 76 }, { 70, 132, 120 }, { 206, 96, 112 }, { 148, 168, 214 }, { 112, 70, 60 },
	{ 230, 150, 140 }, { 86, 180, 220 }, { 160, 50, 90 }, { 180, 200, 110 }, { 58, 84, 120 },
	{ 214, 196, 120 }, { 120, 92, 140 }, { 60, 140, 70 }, { 236, 126, 86 }, { 104, 116, 84 },
	{ 176, 140, 200 }, { 146, 60, 46 }, { 90, 196, 150 }, { 200, 160, 100 }, { 70, 100, 70 },
	{ 156, 112, 120 }, { 110, 150, 180 }, { 230, 200, 80 }, { 130, 80, 40 }, { 160, 210, 190 },
	{ 100, 60, 120 }, { 190, 130, 60 }, { 60, 160, 200 }, { 210, 110, 170 }, { 140, 140, 60 },
}

function Palette.distance(a, b)
	local dr, dg, db = a[1] - b[1], a[2] - b[2], a[3] - b[3]
	-- weighted RGB distance; close enough to perceptual for picking contrasting neighbours
	return math.sqrt(2 * dr * dr + 4 * dg * dg + 3 * db * db)
end

function Palette.shade(c, factor)
	return {
		math.floor(math.max(0, math.min(255, c[1] * factor))),
		math.floor(math.max(0, math.min(255, c[2] * factor))),
		math.floor(math.max(0, math.min(255, c[3] * factor))),
	}
end

function Palette.mix(a, b, t)
	return {
		math.floor(a[1] + (b[1] - a[1]) * t + 0.5),
		math.floor(a[2] + (b[2] - a[2]) * t + 0.5),
		math.floor(a[3] + (b[3] - a[3]) * t + 0.5),
	}
end

return Palette
