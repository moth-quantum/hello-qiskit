# Puzzle definitions for Hello Qubits.
# Each entry: title, desc, init (list of [gate,qubit] pairs applied at load),
# goal (Pauli→target dict, empty = no auto-win), gates (allowed-uses structure),
# visible ("all" or list of Pauli keys to show).
# In gates dicts, 0 = unlimited uses; N > 0 = exactly N uses.

static func get_all() -> Array:
	return [
		# ── Single-qubit intro ─────────────────────────────────────────────────
		{
			"title": "Bit flip",
			"desc": "Flip the qubit from |0⟩ to |1⟩.\nThe circle goes black → white.",
			"init": [], "goal": {"ZI": -1.0},
			"gates": {"0": {"x": 0}, "1": {}, "both": {}},
			"visible": ["ZI"]
		},{
			"title": "Undo the flip",
			"desc": "The qubit has been flipped.\nFlip it back.",
			"init": [["x","0"]], "goal": {"ZI": 1.0},
			"gates": {"0": {"x": 3}, "1": {}, "both": {}},
			"visible": ["ZI"]
		},{
			"title": "Superposition",
			"desc": "The H gate puts a qubit into superposition.\nMake ZI = 0  (the grey circle).",
			"init": [], "goal": {"ZI": 0.0},
			"gates": {"0": {"h": 3}, "1": {}, "both": {}},
			"visible": ["ZI","XI"]
		},{
			"title": "Phase",
			"desc": "Start in superposition (XI=−1).\nUse Z and H to recover XI=+1.",
			"init": [["h","0"],["z","0"]], "goal": {"XI": 1.0},
			"gates": {"0": {"z": 0, "h": 0}, "1": {}, "both": {}},
			"visible": ["ZI","XI"]
		},{
			"title": "Minus state",
			"desc": "Reach ZI = −1 using only Z and H.",
			"init": [], "goal": {"ZI": -1.0},
			"gates": {"0": {"z": 0, "h": 0}, "1": {}, "both": {}},
			"visible": ["ZI","XI"]
		},
		# ── Two-qubit intro ────────────────────────────────────────────────────
		{
			"title": "Second qubit",
			"desc": "q[1] has been flipped.  Use H on q[1]\nto put it in superposition (IZ=0).",
			"init": [["h","1"]], "goal": {"IZ": 1.0},
			"gates": {"0": {}, "1": {"x": 3, "h": 0}, "both": {}},
			"visible": ["ZI","XI","IZ","IX"]
		},{
			"title": "Phase on q[1]",
			"desc": "Make IX = +1.",
			"init": [["h","0"]], "goal": {"IX": 1.0},
			"gates": {"0": {}, "1": {"z": 0, "h": 0}, "both": {}},
			"visible": ["ZI","XI","IZ","IX"]
		},{
			"title": "Two qubits free",
			"desc": "q[1] starts flipped.  Make ZI = 0 and IZ = 0.",
			"init": [["x","1"]], "goal": {"ZI": 0.0, "IZ": 0.0},
			"gates": {"0": {"x": 0,"z": 0,"h": 0}, "1": {"x": 0,"z": 0,"h": 0}, "both": {}},
			"visible": "all"
		},
		# ── Correlations ───────────────────────────────────────────────────────
		{
			"title": "ZZ correlation",
			"desc": "Start: both in |+⟩.  Reach ZZ = −1.",
			"init": [["h","0"],["h","1"]], "goal": {"ZZ": -1.0},
			"gates": {"0": {"x": 0,"z": 0,"h": 0}, "1": {"x": 0,"z": 0,"h": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "XX correlation",
			"desc": "Reach XX = +1.",
			"init": [["x","0"]], "goal": {"XX": 1.0},
			"gates": {"0": {"x": 0,"z": 0,"h": 0}, "1": {"x": 0,"z": 0,"h": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "XZ correlation",
			"desc": "Reach XZ = −1.",
			"init": [], "goal": {"XZ": -1.0},
			"gates": {"0": {"x": 0,"z": 0,"h": 0}, "1": {"x": 0,"z": 0,"h": 0}, "both": {}},
			"visible": "all"
		},
		# ── CZ ────────────────────────────────────────────────────────────────
		{
			"title": "CZ gate",
			"desc": "q[0] in |+⟩, q[1] flipped.  CZ flips\nthe phase.  Reach XI = −1.",
			"init": [["h","0"],["x","1"]], "goal": {"XI": -1.0},
			"gates": {"0": {}, "1": {}, "both": {"cz": 0}},
			"visible": "all"
		},{
			"title": "CZ symmetry",
			"desc": "CZ is symmetric.  Start: q[1] in |+⟩,\nq[0] flipped.  Reach IX = −1.",
			"init": [["h","1"],["x","0"]], "goal": {"IX": -1.0},
			"gates": {"0": {}, "1": {}, "both": {"cz": 0}},
			"visible": "all"
		},
		# ── Entanglement ───────────────────────────────────────────────────────
		{
			"title": "Entangle with CZ",
			"desc": "Reach IZ = −1 using H and CZ.",
			"init": [["x","0"]], "goal": {"IZ": -1.0},
			"gates": {"0": {"h": 0}, "1": {"h": 0}, "both": {"cz": 0}},
			"visible": "all"
		},{
			"title": "Correlated superposition",
			"desc": "Both qubits in |+⟩.  Apply Z to each qubit\nto reach XI = −1 and IX = −1.",
			"init": [["h","0"],["h","1"]], "goal": {"XI": -1.0, "IX": -1.0},
			"gates": {"0": {"z": 0}, "1": {"z": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "Swap logic",
			"desc": "q[1] is flipped.  Make IZ = 1 and ZI = −1.",
			"init": [["x","1"]], "goal": {"IZ": 1.0, "ZI": -1.0},
			"gates": {"0": {"h": 0}, "1": {"h": 0}, "both": {"cz": 0}},
			"visible": "all"
		},{
			"title": "Bell state",
			"desc": "Both qubits in |+⟩.  Apply CZ then H to\ncreate the Bell state: ZZ = 1 and XX = 1.",
			"init": [["h","0"],["h","1"]], "goal": {"ZZ": 1.0, "XX": 1.0},
			"gates": {"0": {"h": 0}, "1": {}, "both": {"cz": 0}},
			"visible": "all"
		},{
			"title": "Cluster state",
			"desc": "Both qubits in |+⟩.  A single CZ creates\nthe cluster state: ZX = 1 and XZ = 1.",
			"init": [["h","0"],["h","1"]], "goal": {"ZX": 1.0, "XZ": 1.0},
			"gates": {"0": {}, "1": {}, "both": {"cz": 0}},
			"visible": "all"
		},
	]
