extends Node2D

# Hello Quantum — Godot 4 port of the original Hello Quantum / Hello Qiskit game.
# Two-qubit state displayed as Pauli expectation values in the original diamond layout.
# Gates: x, z, h (single-qubit Clifford) and cx, cz (two-qubit Clifford).
# State is tracked as a 4-element complex statevector; Pauli expectations are derived analytically.

# ── Statevector ────────────────────────────────────────────────────────────────
# Indices: 0=|00⟩, 1=|01⟩, 2=|10⟩, 3=|11⟩  (qubit 0 is the high bit)
var _sv: Array = [[1.0,0.0],[0.0,0.0],[0.0,0.0],[0.0,0.0]]

# Pauli expectations: ZI IZ ZZ XI IX XX ZX XZ  (all in [-1, +1])
var _rho: Dictionary = {}

# ── Puzzle data ────────────────────────────────────────────────────────────────
var _puzzles: Array = []
var _pidx: int = 0
# Working copy of remaining gate uses.  -1 = unlimited;  N>0 = N remaining.
var _uses: Dictionary = {}
var _moves: int = 0

# ── Visual constants ───────────────────────────────────────────────────────────
const W    := 960
const H    := 640
const CELL := 90        # grid unit → pixel
const BX   := 315       # screen x for grid x=0 (board centre)
const BY   := 320       # screen y for grid y=3.5 (vertical centre)
const DR   := 60        # diamond half-diagonal (≈ CELL/√2 → diagonally adjacent cells just touch)
const PX   := 630       # right panel x

# Grid positions from the original hello_quantum.py box dictionary.
const BOXES := {
	"ZI": Vector2(-1,2), "XI": Vector2(-2,3),
	"IZ": Vector2( 1,2), "IX": Vector2( 2,3),
	"ZZ": Vector2( 0,3), "ZX": Vector2( 1,4),
	"XZ": Vector2(-1,4), "XX": Vector2( 0,5)
}

# Connecting lines drawn behind the circles (mirror the original grid-lines).
const EDGES := [
	["ZI","IZ"],["ZI","ZZ"],["IZ","ZZ"],
	["ZI","XI"],["IZ","IX"],
	["XI","XZ"],["IX","ZX"],
	["ZZ","XZ"],["ZZ","ZX"],
	["XZ","XX"],["ZX","XX"]
]

const C_BG   := Color(0.04,0.04,0.14)
const C_GRID := Color(0.22,0.22,0.38)
const C_LBL  := Color(0.65,0.78,1.0)
const C_WIN  := Color(0.25,0.95,0.45)
const C_BTN  := Color(0.13,0.18,0.38)
const C_HOVR := Color(0.28,0.38,0.70)
const C_OFF  := Color(0.10,0.10,0.16)

# ── Phase ──────────────────────────────────────────────────────────────────────
enum Ph { TITLE, PLAY, SUCCESS }
var _ph: Ph = Ph.TITLE

# ── Buttons ────────────────────────────────────────────────────────────────────
# Each entry: {rect, gate, qkey}   qkey ∈ {"0","1","both"}
var _btns: Array = []
var _hov: int = -1  # hovered button index

# ── Font ───────────────────────────────────────────────────────────────────────
var _font: Font

# ── Visible boxes for current puzzle ──────────────────────────────────────────
var _visible: Array = []  # subset of BOXES keys

func _ready() -> void:
	_font = ThemeDB.fallback_font
	_build_puzzles()
	_load(0)

# ── Puzzle definitions ─────────────────────────────────────────────────────────
# Each entry: title, description, init (list of [gate,qubit] pairs applied at load),
# goal (Pauli→target dict, empty = no auto-win), gates (allowed_gates structure),
# visible ("all" or list of Pauli keys to show).
func _build_puzzles() -> void:
	_puzzles = [
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
		# ── CNOT ──────────────────────────────────────────────────────────────
		{
			"title": "CNOT gate",
			"desc": "q[0] starts flipped.  Use CNOT to copy\nthe flip to q[1].  Reach ZI=1, IZ=−1.",
			"init": [["x","0"]], "goal": {"ZI": 1.0, "IZ": -1.0},
			"gates": {"0": {"cx": 0}, "1": {"cx": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "CNOT from superposition",
			"desc": "q[0] in |+⟩.  CNOT entangles qubits.\nReach IZ = 0.",
			"init": [["h","0"]], "goal": {"IZ": 0.0},
			"gates": {"0": {"cx": 0}, "1": {"cx": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "CNOT entanglement",
			"desc": "Reach ZZ = −1.",
			"init": [["h","0"]], "goal": {"ZZ": -1.0},
			"gates": {"0": {"cx": 0,"x": 0}, "1": {"cx": 0,"x": 0}, "both": {}},
			"visible": "all"
		},
		# ── CZ ────────────────────────────────────────────────────────────────
		{
			"title": "CZ gate",
			"desc": "q[0] in |+⟩, q[1] flipped.  CZ flips\nthe phase.  Reach XI = −1.",
			"init": [["h","0"],["x","1"]], "goal": {"XI": -1.0},
			"gates": {"0": {"cz": 0}, "1": {}, "both": {}},
			"visible": "all"
		},{
			"title": "CZ symmetry",
			"desc": "CZ is symmetric.  Start: q[1] in |+⟩,\nq[0] flipped.  Reach IX = −1.",
			"init": [["h","1"],["x","0"]], "goal": {"IX": -1.0},
			"gates": {"0": {"cz": 0}, "1": {}, "both": {}},
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
			"desc": "Start: both in |+⟩.  Reach XI = −1 and IX = −1.",
			"init": [["h","0"],["h","1"]], "goal": {"XI": -1.0, "IX": -1.0},
			"gates": {"0": {}, "1": {"z": 0, "cx": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "Swap logic",
			"desc": "q[1] is flipped.  Make IZ = 1 and ZI = −1.",
			"init": [["x","1"]], "goal": {"IZ": 1.0, "ZI": -1.0},
			"gates": {"0": {"h": 0}, "1": {"h": 0}, "both": {"cz": 0}},
			"visible": "all"
		},{
			"title": "Bell state",
			"desc": "Start: both flipped.  Reach ZI = 1, IZ = −1.",
			"init": [["x","0"],["x","1"]], "goal": {"ZI": 1.0, "IZ": -1.0},
			"gates": {"0": {"h": 0}, "1": {"h": 0, "cx": 0}, "both": {}},
			"visible": "all"
		},{
			"title": "Teleportation step",
			"desc": "q[0] flipped.  Reach ZI = 1, IZ = −1\nusing CNOT from q[1].",
			"init": [["x","0"]], "goal": {"ZI": 1.0, "IZ": -1.0},
			"gates": {"0": {"cx": 0}, "1": {"cx": 0}, "both": {}},
			"visible": "all"
		}
	]

func _load(idx: int) -> void:
	_pidx = idx
	_sv = [[1.0,0.0],[0.0,0.0],[0.0,0.0],[0.0,0.0]]
	for gp: Array in _puzzles[idx]["init"]:
		_gate(gp[0], gp[1])
	_rho_from_sv()
	_uses = {}
	for qk: String in _puzzles[idx]["gates"]:
		_uses[qk] = {}
		for g: String in _puzzles[idx]["gates"][qk]:
			var lim: int = _puzzles[idx]["gates"][qk][g]
			_uses[qk][g] = -1 if lim == 0 else lim
	_moves = 0
	_visible = _get_visible(idx)
	_ph = Ph.PLAY
	_build_btns()
	queue_redraw()

func _get_visible(idx: int) -> Array:
	var puz: Dictionary = _puzzles[idx]
	if puz["visible"] is String:
		return BOXES.keys()
	return puz["visible"]

# ── Quantum logic ──────────────────────────────────────────────────────────────
func _re_dot(a: Array, b: Array) -> float:
	return a[0]*b[0] + a[1]*b[1]

func _mag2(a: Array) -> float:
	return a[0]*a[0] + a[1]*a[1]

func _rho_from_sv() -> void:
	var a: Array = _sv
	_rho["ZI"] = _mag2(a[0]) + _mag2(a[1]) - _mag2(a[2]) - _mag2(a[3])
	_rho["IZ"] = _mag2(a[0]) - _mag2(a[1]) + _mag2(a[2]) - _mag2(a[3])
	_rho["ZZ"] = _mag2(a[0]) - _mag2(a[1]) - _mag2(a[2]) + _mag2(a[3])
	_rho["XI"] = 2.0*(_re_dot(a[0],a[2]) + _re_dot(a[1],a[3]))
	_rho["IX"] = 2.0*(_re_dot(a[0],a[1]) + _re_dot(a[2],a[3]))
	_rho["XX"] = 2.0*(_re_dot(a[0],a[3]) + _re_dot(a[1],a[2]))
	_rho["ZX"] = 2.0*(_re_dot(a[0],a[1]) - _re_dot(a[2],a[3]))
	_rho["XZ"] = 2.0*(_re_dot(a[0],a[2]) - _re_dot(a[1],a[3]))

func _vadd(a: Array, b: Array) -> Array: return [a[0]+b[0], a[1]+b[1]]
func _vsub(a: Array, b: Array) -> Array: return [a[0]-b[0], a[1]-b[1]]
func _vscl(a: Array, s: float)  -> Array: return [a[0]*s,   a[1]*s  ]

func _gate(gate_name: String, qubit: String) -> void:
	var q := int(qubit)
	match gate_name:
		"x","NOT":
			if q == 0:
				var t = _sv[0]; _sv[0] = _sv[2]; _sv[2] = t
				t = _sv[1]; _sv[1] = _sv[3]; _sv[3] = t
			else:
				var t = _sv[0]; _sv[0] = _sv[1]; _sv[1] = t
				t = _sv[2]; _sv[2] = _sv[3]; _sv[3] = t
		"z":
			if q == 0:
				_sv[2] = _vscl(_sv[2], -1.0); _sv[3] = _vscl(_sv[3], -1.0)
			else:
				_sv[1] = _vscl(_sv[1], -1.0); _sv[3] = _vscl(_sv[3], -1.0)
		"h":
			var s := 1.0/sqrt(2.0)
			if q == 0:
				var n0 = _vscl(_vadd(_sv[0],_sv[2]),s); var n2 = _vscl(_vsub(_sv[0],_sv[2]),s)
				var n1 = _vscl(_vadd(_sv[1],_sv[3]),s); var n3 = _vscl(_vsub(_sv[1],_sv[3]),s)
				_sv[0]=n0; _sv[1]=n1; _sv[2]=n2; _sv[3]=n3
			else:
				var n0 = _vscl(_vadd(_sv[0],_sv[1]),s); var n1 = _vscl(_vsub(_sv[0],_sv[1]),s)
				var n2 = _vscl(_vadd(_sv[2],_sv[3]),s); var n3 = _vscl(_vsub(_sv[2],_sv[3]),s)
				_sv[0]=n0; _sv[1]=n1; _sv[2]=n2; _sv[3]=n3
		"cx","CNOT":
			# ctrl=q0 target=q1 when qubit=="0"; ctrl=q1 target=q0 when qubit=="1"
			if q == 0:
				var t = _sv[2]; _sv[2] = _sv[3]; _sv[3] = t
			else:
				var t = _sv[1]; _sv[1] = _sv[3]; _sv[3] = t
		"cz":
			_sv[3] = _vscl(_sv[3], -1.0)

func _satisfied() -> bool:
	var goal: Dictionary = _puzzles[_pidx]["goal"]
	if goal.is_empty(): return false
	for p: String in goal:
		if abs(_rho.get(p, 0.0) - goal[p]) > 0.1:
			return false
	return true

# ── Buttons ────────────────────────────────────────────────────────────────────
func _build_btns() -> void:
	_btns.clear()
	var bx := PX + 12
	var by := 170
	var bw := 300
	var bh := 38
	var gap := 6
	var puz: Dictionary = _puzzles[_pidx]
	for qk: String in ["0","1","both"]:
		var gates: Dictionary = puz["gates"].get(qk, {})
		if gates.is_empty(): continue
		for g: String in gates:
			_btns.append({"rect": Rect2(bx,by,bw,bh), "gate": g, "qkey": qk})
			by += bh + gap
		by += 10

func _btn_enabled(b: Dictionary) -> bool:
	var rem = _uses.get(b["qkey"],{}).get(b["gate"], -1)
	return rem != 0  # -1=unlimited, N>0=remaining, 0=exhausted

# ── Input ──────────────────────────────────────────────────────────────────────
func _input(ev: InputEvent) -> void:
	if _ph == Ph.TITLE:
		if ev is InputEventMouseButton and ev.pressed:
			_load(0)
		return

	if _ph == Ph.SUCCESS:
		if ev is InputEventMouseButton and ev.pressed:
			var nxt := _pidx + 1
			if nxt < _puzzles.size(): _load(nxt)
			else: _ph = Ph.TITLE; queue_redraw()
		return

	if ev is InputEventMouseMotion:
		var old := _hov; _hov = -1
		for i in _btns.size():
			if _btns[i]["rect"].has_point(ev.position) and _btn_enabled(_btns[i]):
				_hov = i; break
		if _hov != old: queue_redraw()

	if ev is InputEventMouseButton and ev.pressed and ev.button_index == 1:
		for b in _btns:
			if b["rect"].has_point(ev.position) and _btn_enabled(b):
				_press(b); return

func _press(b: Dictionary) -> void:
	var qk: String = b["qkey"]
	var g: String = b["gate"]
	var q_arg := "0" if qk == "both" else qk
	_gate(g, q_arg)
	# Decrement limited uses
	var rem = _uses.get(qk,{}).get(g, -1)
	if rem > 0:
		_uses[qk][g] = rem - 1
	_rho_from_sv()
	_moves += 1
	_build_btns()
	if _satisfied():
		_ph = Ph.SUCCESS
	queue_redraw()

# ── Drawing ────────────────────────────────────────────────────────────────────
func _sp(gv: Vector2) -> Vector2:
	# y-axis is inverted vs screen: larger grid-y → higher on screen (smaller pixel-y)
	return Vector2(BX + gv.x * CELL, BY + (3.5 - gv.y) * CELL)

func _draw() -> void:
	draw_rect(Rect2(0,0,W,H), C_BG)
	match _ph:
		Ph.TITLE:   _draw_title()
		Ph.PLAY:    _draw_board(); _draw_panel()
		Ph.SUCCESS: _draw_board(); _draw_panel(); _draw_success()

func _draw_title() -> void:
	var cx := W/2.0
	draw_string(_font, Vector2(cx-160, H/2.0-70), "Hello Quantum",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 52, Color.WHITE)
	draw_string(_font, Vector2(cx-190, H/2.0+10),
		"A two-qubit quantum computing puzzle game",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_LBL)
	draw_string(_font, Vector2(cx-65, H/2.0+60), "Click to start",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, C_WIN)

func _diamond_pts(center: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(0, -r),
		center + Vector2(r,  0),
		center + Vector2(0,  r),
		center + Vector2(-r, 0),
	])

func _draw_diamond(center: Vector2, r: float, fill: Color,
		outline_col: Color, outline_w: float) -> void:
	var pts := _diamond_pts(center, r)
	draw_polygon(pts, PackedColorArray([fill, fill, fill, fill]))
	draw_polyline(PackedVector2Array([pts[0],pts[1],pts[2],pts[3],pts[0]]),
		outline_col, outline_w)

func _draw_board() -> void:
	var goal: Dictionary = _puzzles[_pidx]["goal"]

	# Background grid: draw all 8 cells as dim outlines so the full
	# diamond lattice is always visible even in single-qubit puzzles.
	for pauli: String in BOXES:
		var pos := _sp(BOXES[pauli])
		_draw_diamond(pos, DR, Color(0.09,0.09,0.20), Color(0.20,0.20,0.35), 1.0)

	# Thin connector lines between adjacent active boxes
	for e: Array in EDGES:
		draw_line(_sp(BOXES[e[0]]), _sp(BOXES[e[1]]), C_GRID, 1.0)

	# Filled, labelled cells for active Pauli expectations
	for pauli: String in _visible:
		var pos  := _sp(BOXES[pauli])
		var rv   : float = _rho.get(pauli, 0.0)
		var prob := (1.0 - rv) / 2.0   # 0=black |0⟩, 1=white |1⟩

		var is_goal := goal.has(pauli)
		var oc      := C_WIN if is_goal else C_LBL
		var ow      := 3.5   if is_goal else 1.5

		_draw_diamond(pos, DR, Color(prob, prob, prob), oc, ow)

		var lc := Color(0.1,0.1,0.1) if prob > 0.55 else Color(0.95,0.95,0.95)
		draw_string(_font, pos + Vector2(-15, 7), pauli,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, lc)

	# Qubit axis labels beside their respective diagonal columns
	draw_string(_font, _sp(Vector2(-1, 2)) + Vector2(-DR - 42, 7),
		"q[0]", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_LBL)
	draw_string(_font, _sp(Vector2(1, 2)) + Vector2(DR + 6, 7),
		"q[1]", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_LBL)

func _draw_panel() -> void:
	draw_rect(Rect2(PX, 0, W-PX, H), Color(0.07,0.07,0.18))

	var puz: Dictionary = _puzzles[_pidx]
	draw_string(_font, Vector2(PX+12, 28),
		"Puzzle %d / %d" % [_pidx+1, _puzzles.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)
	draw_string(_font, Vector2(PX+12, 58), puz["title"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	# Description (wrapped manually at '\n')
	var dy := 92.0
	for line: String in puz["desc"].split("\n"):
		draw_string(_font, Vector2(PX+12, dy), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)
		dy += 22

	# Goal display
	var goal_str := ""
	for p: String in puz["goal"]:
		goal_str += "%s=%s  " % [p, str(puz["goal"][p])]
	if goal_str == "": goal_str = "(explore)"
	draw_string(_font, Vector2(PX+12, dy+4),
		"Goal: " + goal_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_WIN)

	# Gate buttons
	draw_string(_font, Vector2(PX+12, 158), "Gates:",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_LBL)

	for i in _btns.size():
		var b: Dictionary = _btns[i]
		var r   : Rect2  = b["rect"]
		var en  := _btn_enabled(b)
		var hov := en and (i == _hov)
		draw_rect(r, C_HOVR if hov else (C_BTN if en else C_OFF))
		draw_rect(r, C_LBL if en else C_GRID, false, 1.0)

		var lbl: String = b["gate"]
		if b["qkey"] != "both": lbl += " [q%s]" % b["qkey"]
		var rem = _uses.get(b["qkey"],{}).get(b["gate"], -1)
		if rem > 0: lbl += "  (%d left)" % rem
		var tc := Color.WHITE if en else C_GRID
		draw_string(_font, r.position + Vector2(10, 26), lbl,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, tc)

	draw_string(_font, Vector2(PX+12, H-20),
		"Moves: %d" % _moves, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)

func _draw_success() -> void:
	draw_rect(Rect2(0, H/2.0-65, W, 130), Color(0,0,0,0.78))
	draw_string(_font, Vector2(W/2.0-110, H/2.0-12),
		"Puzzle solved!", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, C_WIN)
	draw_string(_font, Vector2(W/2.0-100, H/2.0+42),
		"Click to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_LBL)
