extends RefCounted
## Editor-only bake: filtered world-space variation replaces per-pixel hash noise.

func build() -> Dictionary:
	assert(Engine.is_editor_hint() and not EditorInterface.is_playing_scene())
	var broad := FastNoiseLite.new()
	broad.seed = 20261020
	broad.frequency = 0.045
	broad.fractal_octaves = 3
	var patches := FastNoiseLite.new()
	patches.seed = 20261021
	patches.frequency = 0.28
	patches.fractal_octaves = 2
	var image := Image.create(1024, 1024, false, Image.FORMAT_RGB8)
	var low := 1.0
	var high := 0.0
	for z in 1024:
		for x in 1024:
			var world_x := (float(x) + 0.5) * 500.0 / 1024.0 - 250.0
			var world_z := (float(z) + 0.5) * 500.0 / 1024.0 - 250.0
			var red := clampf(0.5 + broad.get_noise_2d(world_x, world_z) * 0.95, 0, 1)
			var green := clampf(0.5 + patches.get_noise_2d(world_x, world_z) * 0.9, 0, 1)
			low = minf(low, red)
			high = maxf(high, red)
			image.set_pixel(x, z, Color(red, green, 0))
	assert(high - low > 0.3)
	var path := "res://Scene/World/Town500m/Art/GroundArt/mask_variation.png"
	assert(image.save_png(path) == OK)
	return {"path": path, "seed": [broad.seed, patches.seed], "dimensions": [1024, 1024], "metres_per_texel": 500.0 / 1024.0, "broad_range": [low, high], "scope": "Linear RGB data, unique world500m field; red macro terrain, green local patches. No terrain vertices or gameplay changes."}
