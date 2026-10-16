extends RefCounted
## Turns an island heightfield into a render mesh and a collision shape.


static func build_mesh(d) -> ArrayMesh:
	var res: int = d.res
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(res * res)
	norms.resize(res * res)
	uvs.resize(res * res)
	for j in res:
		for i in res:
			var k: int = j * res + i
			var x: float = d.x0 + i * d.step
			var z: float = d.x0 + j * d.step
			verts[k] = Vector3(x, d.heights[k], z)
			norms[k] = d.normal_idx(i, j)
			uvs[k] = Vector2(x, z)

	var indices := PackedInt32Array()
	indices.resize((res - 1) * (res - 1) * 6)
	var t := 0
	for j in res - 1:
		for i in res - 1:
			var a := j * res + i
			var b := a + 1
			var c := a + res
			var e := c + 1
			# Split each quad along the diagonal that best follows the surface,
			# which keeps cliff edges crisp instead of saw-toothed.
			var ha: float = d.heights[a]
			var hb: float = d.heights[b]
			var hc: float = d.heights[c]
			var he: float = d.heights[e]
			if absf(ha - he) < absf(hb - hc):
				indices[t] = a; indices[t + 1] = b; indices[t + 2] = e
				indices[t + 3] = a; indices[t + 4] = e; indices[t + 5] = c
			else:
				indices[t] = a; indices[t + 1] = b; indices[t + 2] = c
				indices[t + 3] = b; indices[t + 4] = e; indices[t + 5] = c
			t += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Height-field collision at a coarser resolution than the render mesh.
static func build_collision(d, every: int) -> ConcavePolygonShape3D:
	var faces := PackedVector3Array()
	var res: int = d.res
	var j := 0
	while j + every < res:
		var i := 0
		while i + every < res:
			var p := func(ii: int, jj: int) -> Vector3:
				return Vector3(d.x0 + ii * d.step, d.heights[jj * res + ii], d.x0 + jj * d.step)
			var a: Vector3 = p.call(i, j)
			var b: Vector3 = p.call(i + every, j)
			var c: Vector3 = p.call(i, j + every)
			var e: Vector3 = p.call(i + every, j + every)
			faces.append_array([a, b, c, b, e, c])
			i += every
		j += every
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	return shape
