@tool
class_name SplatImporter
extends RefCounted
## Makes [SplatCloud]s: from a raw 64-byte surfel blob, or by scattering over a mesh.

const STRIDE := SplatCloud.STRIDE


## Reads a blob of 64-byte surfels. The same layout the Unity package writes, so a scene baked
## there opens here unchanged.
static func from_bytes(path: String) -> SplatCloud:
	var cloud := SplatCloud.from_bytes(path)
	if cloud == null:
		return null
	cloud.opaque_count = cloud.detect_opaque_count()
	return cloud


## Saves a cloud next to its source, so it can be a [Resource] in the scene.
static func save_resource(cloud: SplatCloud, path: String) -> Error:
	return ResourceSaver.save(cloud, path)


## Scatters surfels evenly over the triangles of a mesh. Colour comes from the material's albedo,
## its texture (if it can be read), and vertex colours.
##
## xform places the mesh in the cloud's space; target_count sets the splat spacing to
## sqrt(area / target_count), the same rule the browser's converter uses.
##
## radius_scale is the splat radius as a fraction of the spacing. 0.66 is the scene default and is
## enough when points sit on a regular grid; scattered points need more overlap or they leave
## pinholes, so meshes get 0.9.
static func from_mesh(meshes: Array[MeshInstance3D], xform: Transform3D, target_count: int,
		radius_scale := 0.9) -> SplatCloud:
	var parts: Array[Dictionary] = []
	var total_area := 0.0

	for node in meshes:
		var mesh := node.mesh
		if mesh == null:
			continue
		var node_xform := node.global_transform if node.is_inside_tree() else node.transform
		var world := xform * node_xform
		for s in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(s)
			var verts := _packed_v3(arrays, Mesh.ARRAY_VERTEX)
			if verts.is_empty():
				continue
			var idx := _packed_i32(arrays, Mesh.ARRAY_INDEX)
			if idx.is_empty():
				idx.resize(verts.size())
				for i in verts.size():
					idx[i] = i
			var norms := _packed_v3(arrays, Mesh.ARRAY_NORMAL)
			var uvs := _packed_v2(arrays, Mesh.ARRAY_TEX_UV)
			var cols := _packed_color(arrays, Mesh.ARRAY_COLOR)

			var pos := PackedVector3Array()
			pos.resize(verts.size())
			var nrm := PackedVector3Array()
			nrm.resize(verts.size())
			for i in verts.size():
				pos[i] = world * verts[i]
				nrm[i] = (world.basis.inverse().transposed() * norms[i]).normalized() if norms.size() == verts.size() else Vector3.UP

			var material: Material = node.get_active_material(s)
			var albedo := Color.WHITE
			var texture: Texture2D = null
			if material is BaseMaterial3D:
				albedo = (material as BaseMaterial3D).albedo_color
				texture = (material as BaseMaterial3D).albedo_texture

			var area := 0.0
			for t in range(0, idx.size() - 2, 3):
				area += _tri_area(pos, idx[t], idx[t + 1], idx[t + 2])
			total_area += area

			parts.append({
				"pos": pos, "nrm": nrm, "uv": uvs, "col": cols, "idx": idx,
				"albedo": albedo, "texture": _readable(texture), "area": area,
			})

	if parts.is_empty() or total_area <= 0.0:
		push_error("SplatImporter: nothing to bake.")
		return null

	var h := sqrt(total_area / float(maxi(1, target_count)))
	var radius := h * radius_scale
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var surfels := PackedFloat32Array()

	for part in parts:
		var pos: PackedVector3Array = part["pos"]
		var idx: PackedInt32Array = part["idx"]
		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var n := _tri_area(pos, a, b, c) / (h * h)
			if n > 3.0:
				# big triangle: jittered lattice so walls and floors are evenly covered
				var k := ceili(sqrt(2.0 * n))
				for i in k:
					for j in k - i:
						var u := (i + 0.2 + 0.6 * rng.randf()) / k
						var v := (j + 0.2 + 0.6 * rng.randf()) / k
						if u + v > 1.0:
							u = 1.0 - u
							v = 1.0 - v
						_emit(part, a, b, c, 1.0 - u - v, u, v, radius, surfels)
			else:
				# small triangle: probabilistic, slightly oversampled to avoid pinholes
				var count := n * 1.35
				var whole := int(floor(count))
				if rng.randf() < count - whole:
					whole += 1
				# every triangle gets at least one splat, or small clusters of them leave pinholes
				whole = maxi(whole, 1)
				for _s in whole:
					var u := rng.randf()
					var v := rng.randf()
					if u + v > 1.0:
						u = 1.0 - u
						v = 1.0 - v
					_emit(part, a, b, c, 1.0 - u - v, u, v, radius, surfels)

	var cloud := SplatCloud.new()
	cloud.data = surfels.to_byte_array()
	cloud.count = cloud.data.size() / STRIDE
	cloud.opaque_count = cloud.count
	cloud.spacing = h
	return cloud


static func _emit(part: Dictionary, a: int, b: int, c: int, wa: float, wb: float, wc: float,
		radius: float, out: PackedFloat32Array) -> void:
	var pos: PackedVector3Array = part["pos"]
	var nrm: PackedVector3Array = part["nrm"]
	var p := pos[a] * wa + pos[b] * wb + pos[c] * wc
	var n := nrm[a] * wa + nrm[b] * wb + nrm[c] * wc
	if n.length_squared() < 1e-12:
		n = (pos[b] - pos[a]).cross(pos[c] - pos[a])
	if n.length_squared() < 1e-12:
		return
	n = n.normalized()

	# two unit axes perpendicular to the normal, so the disc lies flat on the surface
	var t := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
	var bit := n.cross(t).normalized()

	var colour := Color(part["albedo"])
	var uvs: PackedVector2Array = part["uv"]
	if uvs.size() == pos.size():
		var u := uvs[a].x * wa + uvs[b].x * wb + uvs[c].x * wc
		var v := uvs[a].y * wa + uvs[b].y * wb + uvs[c].y * wc
		var image = part.get("texture")
		if image is Image:
			var px := clampi(int(u * image.get_width()) % image.get_width(), 0, image.get_width() - 1)
			var py := clampi(int(v * image.get_height()) % image.get_height(), 0, image.get_height() - 1)
			var tex: Color = image.get_pixel(px, py)
			colour = Color(colour.r * tex.r, colour.g * tex.g, colour.b * tex.b, colour.a)
	var cols: PackedColorArray = part["col"]
	if cols.size() == pos.size():
		var vc := cols[a] * wa + cols[b] * wb + cols[c] * wc
		colour = Color(colour.r * vc.r, colour.g * vc.g, colour.b * vc.b, colour.a)

	out.append_array(PackedFloat32Array([
		p.x, p.y, p.z,
		t.x * radius, t.y * radius, t.z * radius,
		bit.x * radius, bit.y * radius, bit.z * radius,
		n.x, n.y, n.z,
		colour.r, colour.g, colour.b,
	]))
	out.append(0.0)  # flags: 0, live-lit


static func _packed_v3(arrays: Array, slot: int) -> PackedVector3Array:
	var v = arrays[slot]
	return v if v is PackedVector3Array else PackedVector3Array()


static func _packed_v2(arrays: Array, slot: int) -> PackedVector2Array:
	var v = arrays[slot]
	return v if v is PackedVector2Array else PackedVector2Array()


static func _packed_color(arrays: Array, slot: int) -> PackedColorArray:
	var v = arrays[slot]
	return v if v is PackedColorArray else PackedColorArray()


static func _packed_i32(arrays: Array, slot: int) -> PackedInt32Array:
	var v = arrays[slot]
	return v if v is PackedInt32Array else PackedInt32Array()


static func _tri_area(pos: PackedVector3Array, a: int, b: int, c: int) -> float:
	return 0.5 * (pos[b] - pos[a]).cross(pos[c] - pos[a]).length()


static func _readable(tex: Texture2D) -> Image:
	if tex == null:
		return null
	var image := tex.get_image()
	if image == null:
		return null
	return image
