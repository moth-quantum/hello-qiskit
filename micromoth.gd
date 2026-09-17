# (C) Copyright Moth Quantum 2024.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

# (C) Copyright IBM 2023.
#
# This code is licensed under the Apache License, Version 2.0. You may
# obtain a copy of this license in the LICENSE.txt file in the root directory
# of this source tree or at http://www.apache.org/licenses/LICENSE-2.0.
#
# Any modifications or derivative works of this code must retain this
# copyright notice, and modified files need to carry a notice indicating
# that they have been altered from the originals.

class_name MicroMoth

const R2: float = 0.70710678118  # 1/sqrt(2)


class QuantumCircuit:

	var num_qubits: int
	var num_clbits: int
	var name: String
	var data: Array

	func _init(n: int, m: int = 0) -> void:
		num_qubits = n
		num_clbits = m
		name = ""
		data = []

	func initialize(k: Array) -> void:
		data.clear()
		data.append(["init", k.duplicate(true)])

	func x(q: int) -> void:
		data.append(["x", q])

	func rx(theta: float, q: int) -> void:
		data.append(["rx", theta, q])

	func rz(theta: float, q: int) -> void:
		data.append(["rz", theta, q])

	func h(q: int) -> void:
		data.append(["h", q])

	func cx(s: int, t: int) -> void:
		data.append(["cx", s, t])

	func crx(theta: float, s: int, t: int) -> void:
		data.append(["crx", theta, s, t])

	func swap(s: int, t: int) -> void:
		data.append(["swap", s, t])

	func measure(q: int, b: int) -> void:
		assert(b < num_clbits, "Index for output bit out of range.")
		assert(q < num_qubits, "Index for qubit out of range.")
		data.append(["m", q, b])

	func measure_all() -> void:
		if num_clbits == 0:
			num_clbits = num_qubits
		for q in range(num_qubits):
			measure(q, q)

	func ry(theta: float, q: int) -> void:
		rx(PI / 2.0, q)
		rz(theta, q)
		rx(-PI / 2.0, q)

	func z(q: int) -> void:
		rz(PI, q)

	func t(q: int) -> void:
		rz(PI / 4.0, q)

	func y(q: int) -> void:
		rz(PI, q)
		x(q)


static func _superpose(x: Array, y: Array) -> Array:
	return [
		[R2 * (x[0] + y[0]), R2 * (x[1] + y[1])],
		[R2 * (x[0] - y[0]), R2 * (x[1] - y[1])]
	]


static func _turn(x: Array, y: Array, theta: float) -> Array:
	var c: float = cos(theta / 2.0)
	var s: float = sin(theta / 2.0)
	return [
		[x[0] * c + y[1] * s, x[1] * c - y[0] * s],
		[y[0] * c + x[1] * s, y[1] * c - x[0] * s]
	]


static func _phaseturn(x: Array, y: Array, theta: float) -> Array:
	var c: float = cos(theta / 2.0)
	var s: float = sin(theta / 2.0)
	return [
		[x[0] * c + x[1] * s, x[1] * c - x[0] * s],
		[y[0] * c - y[1] * s, y[1] * c + y[0] * s]
	]


static func _int_to_bitstring(j: int, n_bits: int) -> String:
	var result: String = ""
	for i in range(n_bits - 1, -1, -1):
		result += "1" if (j >> i) & 1 else "0"
	return result


static func simulate(qc: QuantumCircuit, shots: int = 1024, get: String = "counts", noise_model: Array = []) -> Variant:

	# Initialize statevector: complex numbers as [real, imag]
	var k: Array = []
	for _i in range(1 << qc.num_qubits):
		k.append([0.0, 0.0])
	k[0] = [1.0, 0.0]

	# Expand scalar noise model to per-qubit list
	var nm: Array = noise_model.duplicate()
	if nm.size() == 1 and nm[0] is float:
		nm = []
		for _i in range(qc.num_qubits):
			nm.append(noise_model[0])

	var output_map: Dictionary = {}

	for gate in qc.data:

		if gate[0] == "init":
			var init_state: Array = gate[1]
			if init_state.size() > 0 and init_state[0] is Array:
				k = init_state.duplicate(true)
			else:
				k = []
				for e in init_state:
					k.append([float(e), 0.0])

		elif gate[0] == "m":
			output_map[gate[2]] = gate[1]

		elif gate[0] in ["x", "h", "rx", "rz"]:
			var j: int = gate[gate.size() - 1]
			for i0 in range(1 << j):
				for i1 in range(1 << (qc.num_qubits - j - 1)):
					var b0: int = i0 + (1 << (j + 1)) * i1
					var b1: int = b0 + (1 << j)
					var result: Array
					if gate[0] == "x":
						var tmp: Array = k[b0].duplicate()
						k[b0] = k[b1].duplicate()
						k[b1] = tmp
					elif gate[0] == "h":
						result = _superpose(k[b0], k[b1])
						k[b0] = result[0]
						k[b1] = result[1]
					elif gate[0] == "rx":
						result = _turn(k[b0], k[b1], float(gate[1]))
						k[b0] = result[0]
						k[b1] = result[1]
					elif gate[0] == "rz":
						result = _phaseturn(k[b0], k[b1], float(gate[1]))
						k[b0] = result[0]
						k[b1] = result[1]

		elif gate[0] in ["cx", "crx", "swap"]:
			var s: int
			var t: int
			var theta: float = 0.0
			if gate[0] == "crx":
				theta = float(gate[1])
				s = gate[2]
				t = gate[3]
			else:
				s = gate[1]
				t = gate[2]

			var l: int = mini(s, t)
			var h: int = maxi(s, t)

			for i0 in range(1 << l):
				for i1 in range(1 << (h - l - 1)):
					for i2 in range(1 << (qc.num_qubits - h - 1)):
						var b00: int = i0 + (1 << (l + 1)) * i1 + (1 << (h + 1)) * i2
						var b01: int = b00 + (1 << t)
						var b10: int = b00 + (1 << s)
						var b11: int = b10 + (1 << t)
						var result: Array
						if gate[0] == "cx":
							var tmp: Array = k[b10].duplicate()
							k[b10] = k[b11].duplicate()
							k[b11] = tmp
						elif gate[0] == "crx":
							result = _turn(k[b10], k[b11], theta)
							k[b10] = result[0]
							k[b11] = result[1]
						elif gate[0] == "swap":
							var tmp: Array = k[b01].duplicate()
							k[b01] = k[b10].duplicate()
							k[b10] = tmp

	if get == "statevector":
		return k

	# Compute probabilities from statevector
	var probs: Array = []
	for e in k:
		probs.append(e[0] * e[0] + e[1] * e[1])

	# Apply noise model if present
	if nm.size() > 0:
		for j in range(qc.num_qubits):
			var p_meas: float = float(nm[j])
			for i0 in range(1 << j):
				for i1 in range(1 << (qc.num_qubits - j - 1)):
					var b0: int = i0 + (1 << (j + 1)) * i1
					var b1: int = b0 + (1 << j)
					var p0: float = probs[b0]
					var p1: float = probs[b1]
					probs[b0] = (1.0 - p_meas) * p0 + p_meas * p1
					probs[b1] = (1.0 - p_meas) * p1 + p_meas * p0

	if get == "probabilities_dict":
		var result: Dictionary = {}
		for j in range(probs.size()):
			result[_int_to_bitstring(j, qc.num_qubits)] = probs[j]
		return result

	# Sampling for counts/memory
	var m: Array = []
	for _shot in range(shots):
		var cumu: float = 0.0
		var r: float = randf()
		for j in range(probs.size()):
			cumu += probs[j]
			if r < cumu:
				var raw_out: String = _int_to_bitstring(j, qc.num_qubits)
				var out_list: Array = []
				for _i in range(qc.num_clbits):
					out_list.append("0")
				for bit in output_map:
					out_list[qc.num_clbits - 1 - bit] = raw_out[qc.num_qubits - 1 - output_map[bit]]
				var out: String = ""
				for c in out_list:
					out += c
				m.append(out)
				break

	if get == "memory":
		return m

	var counts: Dictionary = {}
	for out in m:
		if out in counts:
			counts[out] += 1
		else:
			counts[out] = 1
	return counts
