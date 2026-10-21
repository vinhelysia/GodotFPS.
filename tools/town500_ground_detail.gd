extends RefCounted
## Editor-only, seeded four-metre detail tiles; no Town geometry or runtime work.

const SIZE := 512
const TILE_METRES := 4.0
const OUTPUT := "res://Scene/World/Town500m/Art/GroundArt/"
const SEED := 20261022

func build() -> Dictionary:
	assert(Engine.is_editor_hint() and not EditorInterface.is_playing_scene())
	var grain := _noise(SEED, 0.24, 2)
	var aggregate := _noise(SEED + 1, 0.38, 2)
	var weather := _noise(SEED + 2, 0.025, 2)
	var ground := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var road := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y in SIZE:
		for x in SIZE:
			ground.set_pixel(x, y, Color(0.15 + grain.get_pixel(x, y).r * 0.70, 0, 0))
			road.set_pixel(x, y, Color(0.12 + aggregate.get_pixel(x, y).r * 0.76, 0, weather.get_pixel(x, y).r))
	var random := RandomNumberGenerator.new()
	random.seed = SEED
	for index in 900:
		_stamp_pebble(ground, Vector2(random.randf() * SIZE, random.randf() * SIZE), random)
	for index in 220:
		_stamp_leaf(ground, Vector2(random.randf() * SIZE, random.randf() * SIZE), random)
	for index in 7:
		var point := Vector2(random.randf() * SIZE, random.randf() * SIZE)
		var angle := random.randf() * TAU
		for segment in 5:
			angle += random.randf_range(-0.75, 0.75)
			var next := point + Vector2.from_angle(angle) * random.randf_range(14.0, 30.0)
			_crack_segment(road, point, next, random.randf_range(0.65, 1.25))
			point = next
	var normal := _normals(ground)
	var outputs := {}
	for entry in [["v2_ground_detail.png", ground], ["v2_road_detail.png", road], ["v2_detail_normal.png", normal]]:
		var filename: String = entry[0]
		var image: Image = entry[1]
		var metrics := _check_tile(image, filename.contains("normal"))
		var destination := OUTPUT + filename
		assert(image.save_png(destination) == OK, "Cannot save " + destination)
		outputs[destination] = {"sha256": FileAccess.get_sha256(destination), "metrics": metrics}
	return {
		"dimensions": [SIZE, SIZE], "tile_metres": TILE_METRES,
		"metres_per_texel": TILE_METRES / SIZE, "seed": SEED,
		"source_sha256": FileAccess.get_sha256(get_script().resource_path),
		"channels": {"ground": "R soil grain; G pebble height/coverage; B irregular individual leaf coverage", "road": "R fine aggregate; G crack coverage; B weather patches", "normal": "XYZ tangent-space unit normal from soil/pebble height; +Z up"},
		"recipe": "Native normalized seamless noise; 900 wrapped pebbles, 220 wrapped tapered leaves, seven irregular crack chains. No runtime hash/noise.",
		"outputs": outputs,
		"import": "Linear data, repeat with mipmaps, no source_color, no alpha-border fix. Normal map may use native normal compression.",
	}

func _noise(seed_value: int, frequency: float, octaves: int) -> Image:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise.get_seamless_image(SIZE, SIZE)

func _stamp_pebble(image: Image, centre: Vector2, random: RandomNumberGenerator) -> void:
	var radius := Vector2(random.randf_range(1.4, 4.2), random.randf_range(1.0, 2.7))
	var angle := random.randf() * TAU
	var extent := ceili(maxf(radius.x, radius.y)) + 1
	var height := random.randf_range(0.55, 1.0)
	for y in range(floori(centre.y) - extent, ceili(centre.y) + extent + 1):
		for x in range(floori(centre.x) - extent, ceili(centre.x) + extent + 1):
			var offset := (Vector2(x, y) - centre).rotated(-angle) / radius
			var distance := offset.length()
			if distance >= 1.0:
				continue
			var sample := image.get_pixel(posmod(x, SIZE), posmod(y, SIZE))
			sample.g = maxf(sample.g, sqrt(1.0 - distance * distance) * height)
			image.set_pixel(posmod(x, SIZE), posmod(y, SIZE), sample)

func _stamp_leaf(image: Image, centre: Vector2, random: RandomNumberGenerator) -> void:
	var half_length := random.randf_range(3.2, 7.5)
	var half_width := random.randf_range(1.5, 3.0)
	var angle := random.randf() * TAU
	var extent := ceili(half_length) + 1
	var tone := random.randf_range(0.62, 1.0)
	for y in range(floori(centre.y) - extent, ceili(centre.y) + extent + 1):
		for x in range(floori(centre.x) - extent, ceili(centre.x) + extent + 1):
			var offset := (Vector2(x, y) - centre).rotated(-angle)
			var along := offset.x / half_length
			if absf(along) >= 1.0:
				continue
			var width := half_width * pow(1.0 - absf(along), 0.65) * (1.0 + along * 0.22)
			var coverage := clampf(width + 0.45 - absf(offset.y), 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var sample := image.get_pixel(posmod(x, SIZE), posmod(y, SIZE))
			sample.b = maxf(sample.b, coverage * tone)
			image.set_pixel(posmod(x, SIZE), posmod(y, SIZE), sample)

func _crack_segment(image: Image, start: Vector2, end: Vector2, radius: float) -> void:
	var delta := end - start
	var padding := ceili(radius) + 1
	for y in range(floori(minf(start.y, end.y)) - padding, ceili(maxf(start.y, end.y)) + padding + 1):
		for x in range(floori(minf(start.x, end.x)) - padding, ceili(maxf(start.x, end.x)) + padding + 1):
			var position := Vector2(x, y)
			var along := clampf((position - start).dot(delta) / delta.length_squared(), 0.0, 1.0)
			var coverage := clampf(radius + 0.5 - position.distance_to(start + delta * along), 0.0, 1.0)
			if coverage <= 0.0:
				continue
			var sample := image.get_pixel(posmod(x, SIZE), posmod(y, SIZE))
			sample.g = maxf(sample.g, coverage)
			image.set_pixel(posmod(x, SIZE), posmod(y, SIZE), sample)

func _height(image: Image, x: int, y: int) -> float:
	var sample := image.get_pixel(posmod(x, SIZE), posmod(y, SIZE))
	return sample.r * 0.003 + sample.g * 0.009

func _normals(ground: Image) -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var step_metres := TILE_METRES / SIZE
	for y in SIZE:
		for x in SIZE:
			var dx := (_height(ground, x + 1, y) - _height(ground, x - 1, y)) / (2.0 * step_metres)
			var dy := (_height(ground, x, y + 1) - _height(ground, x, y - 1)) / (2.0 * step_metres)
			var normal := Vector3(-dx, -dy, 1.0).normalized()
			image.set_pixel(x, y, Color(normal.x * 0.5 + 0.5, normal.y * 0.5 + 0.5, normal.z * 0.5 + 0.5))
	return image

func _check_tile(image: Image, is_normal: bool) -> Dictionary:
	assert(image.get_width() == SIZE and image.get_height() == SIZE)
	var minimum := Vector3.ONE
	var maximum := Vector3.ZERO
	for y in SIZE:
		for x in SIZE:
			var sample := image.get_pixel(x, y)
			var rgb := Vector3(sample.r, sample.g, sample.b)
			minimum = minimum.min(rgb)
			maximum = maximum.max(rgb)
			if is_normal:
				assert(absf((rgb * 2.0 - Vector3.ONE).length() - 1.0) < 0.02)
	var seam_mean := Vector3.ZERO
	for index in SIZE:
		var horizontal := image.get_pixel(0, index) - image.get_pixel(SIZE - 1, index)
		var vertical := image.get_pixel(index, 0) - image.get_pixel(index, SIZE - 1)
		seam_mean += Vector3(absf(horizontal.r) + absf(vertical.r), absf(horizontal.g) + absf(vertical.g), absf(horizontal.b) + absf(vertical.b)) / (SIZE * 2.0)
	assert(seam_mean.x < 0.14 and seam_mean.y < 0.14 and seam_mean.z < 0.14, "Unexpected tile border jump")
	assert((maximum - minimum).x > 0.15 and (maximum - minimum).y > 0.15)
	if not is_normal:
		assert((maximum - minimum).z > 0.15)
	return {"channel_min": [minimum.x, minimum.y, minimum.z], "channel_max": [maximum.x, maximum.y, maximum.z], "border_mean_delta": [seam_mean.x, seam_mean.y, seam_mean.z]}
