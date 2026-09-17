extends Node2D

const MicroMoth = preload("res://micromoth.gd")

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
const CELL := 82        # grid unit → pixel
const BX   := 318       # screen x for grid x=0 (board centre within 640px board)
const BY   := 295       # screen y for grid y=3.5 (vertical centre, shifted up for button room)
const DR   := 52        # diamond cell half-diagonal
const CR   := 30        # circle radius inside each diamond cell
const PX   := 640       # right panel x

# Gate button geometry
const BTN_S  := 72      # button square side length
const BTN_Y  := 585     # centre-y for single-qubit gate buttons (below diamond)
const CZ_BTN_Y := 68    # centre-y for CZ gate button (above diamond)

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

const C_BG      := Color(0.30, 0.30, 0.62)          # blue-purple background
const C_CELL    := Color(0.40, 0.40, 0.75, 0.80)    # active diamond cell fill
const C_CELL_BG := Color(0.28, 0.28, 0.58, 0.50)    # background (inactive) cell
const C_EDGE    := Color(0.70, 0.70, 1.00, 0.35)    # grid connector lines
const C_CONN    := Color(0.80, 0.80, 1.00, 0.45)    # button connection lines
const C_LBL     := Color(0.85, 0.88, 1.00)          # labels
const C_WIN     := Color(0.35, 1.00, 0.55)          # success / goal highlight
const C_BTN_ON  := Color(0.95, 0.95, 1.00)          # active button background
const C_BTN_HOV := Color(1.00, 1.00, 1.00)          # hovered button background
const C_BTN_OFF := Color(0.55, 0.55, 0.72)          # exhausted / disabled button
const C_BTN_TXT := Color(0.15, 0.15, 0.35)          # button text (dark)
const C_PANEL   := Color(0.22, 0.22, 0.50)

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
			"desc": "q[0] in |+>, q[1] flipped.  CNOT entangles them.\nReach ZZ = -1.",
			"init": [["h","0"],["x","1"]], "goal": {"ZZ": -1.0},
			"gates": {"0": {"cx": 0}, "1": {"cx": 0}, "both": {}},
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

func _gate(gate_name: String, qubit: String) -> void:
	# MicroMoth uses qubit 0 = LSB; our qubit 0 = MSB, so mm_q = 1 - q.
	var q := int(qubit)
	var qc := MicroMoth.QuantumCircuit.new(2)
	qc.initialize(_sv.duplicate(true))
	match gate_name:
		"x", "NOT": qc.x(1 - q)
		"z":        qc.z(1 - q)
		"h":        qc.h(1 - q)
		"cx", "CNOT":
			if q == 0: qc.cx(1, 0)   # ctrl=our q0=mm q1, tgt=our q1=mm q0
			else:      qc.cx(0, 1)
		"cz":
			qc.h(0); qc.cx(1, 0); qc.h(0)   # CZ = H_t · CX · H_t
	_sv = MicroMoth.simulate(qc, 0, "statevector")

func _satisfied() -> bool:
	var goal: Dictionary = _puzzles[_pidx]["goal"]
	if goal.is_empty(): return false
	for p: String in goal:
		if abs(_rho.get(p, 0.0) - goal[p]) > 0.1:
			return false
	return true

# ── Buttons ────────────────────────────────────────────────────────────────────
# Fixed 7-button layout — always the same positions; grey when not in current puzzle.
# The "x" slot doubles as cx/CNOT: _actual_gate() picks which to apply.
const GATE_SLOT_0 := {"z": -2.5, "h": -1.5, "x": -0.5}
const GATE_SLOT_1 := {"z":  2.5, "h":  1.5, "x":  0.5}

const FIXED_BTN_SPECS: Array = [
	{"gate": "z",  "qkey": "0"},
	{"gate": "h",  "qkey": "0"},
	{"gate": "x",  "qkey": "0"},
	{"gate": "x",  "qkey": "1"},
	{"gate": "h",  "qkey": "1"},
	{"gate": "z",  "qkey": "1"},
	{"gate": "cz", "qkey": "both"},
]

# Which diamond cells each button's connection lines reach.
# Z affects X-type observables (top row); X affects Z-type (bottom row); H both.
const BTN_CONNECTS := {
	"0_z":  ["XI"],
	"0_x":  ["ZI"],
	"0_h":  ["ZI","XI"],
	"0_cx": ["ZI","IZ"],
	"1_z":  ["IX"],
	"1_x":  ["IZ"],
	"1_h":  ["IZ","IX"],
	"1_cx": ["IZ","ZI"],
	"both_cz": ["XZ","ZX"],
}

func _build_btns() -> void:
	if not _btns.is_empty(): return   # fixed layout — built once only
	for spec: Dictionary in FIXED_BTN_SPECS:
		var qk: String = spec["qkey"]
		var g:  String = spec["gate"]
		var center: Vector2
		if qk == "both":
			center = Vector2(BX, CZ_BTN_Y)
		else:
			var slots: Dictionary = GATE_SLOT_0 if qk == "0" else GATE_SLOT_1
			center = Vector2(BX + slots[g] * CELL, BTN_Y)
		_btns.append({"gate": g, "qkey": qk, "center": center})

func _btn_rect(b: Dictionary) -> Rect2:
	var c: Vector2 = b["center"]
	return Rect2(c.x - BTN_S/2.0, c.y - BTN_S/2.0, BTN_S, BTN_S)

# The x slot applies cx when cx is available, otherwise x.
func _actual_gate(b: Dictionary) -> String:
	if b["gate"] == "x" and _uses.get(b["qkey"], {}).get("cx", 0) != 0:
		return "cx"
	return b["gate"]

func _btn_enabled(b: Dictionary) -> bool:
	var qk: String = b["qkey"]
	var g:  String = b["gate"]
	if g == "x":
		return _uses.get(qk, {}).get("x", 0) != 0 or _uses.get(qk, {}).get("cx", 0) != 0
	return _uses.get(qk, {}).get(g, 0) != 0

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
			if _btn_rect(_btns[i]).has_point(ev.position) and _btn_enabled(_btns[i]):
				_hov = i; break
		if _hov != old: queue_redraw()

	if ev is InputEventMouseButton and ev.pressed and ev.button_index == 1:
		for b in _btns:
			if _btn_rect(b).has_point(ev.position) and _btn_enabled(b):
				_press(b); return

func _press(b: Dictionary) -> void:
	var qk: String = b["qkey"]
	var g:  String = _actual_gate(b)
	var q_arg := "0" if qk == "both" else qk
	_gate(g, q_arg)
	var rem = _uses.get(qk, {}).get(g, -1)
	if rem > 0:
		_uses[qk][g] = rem - 1
	_rho_from_sv()
	_moves += 1
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
		Ph.PLAY:    _draw_board(); _draw_board_buttons(); _draw_panel()
		Ph.SUCCESS: _draw_board(); _draw_board_buttons(); _draw_panel(); _draw_success()

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

	# All 8 background cells (dim, always visible for context)
	for pauli: String in BOXES:
		var pos := _sp(BOXES[pauli])
		_draw_diamond(pos, DR, C_CELL_BG, Color(0.55,0.55,0.85,0.5), 1.0)

	# Grid connector lines
	for e: Array in EDGES:
		draw_line(_sp(BOXES[e[0]]), _sp(BOXES[e[1]]), C_EDGE, 1.2)

	# Active cells: diamond container + circle inside
	for pauli: String in _visible:
		var pos  := _sp(BOXES[pauli])
		var rv   : float = _rho.get(pauli, 0.0)
		var prob := (1.0 - rv) / 2.0   # 0=black |0⟩, 1=white |1⟩
		var is_goal := goal.has(pauli)

		# Diamond container
		var oc := C_WIN if is_goal else Color(0.75,0.75,1.0,0.9)
		var ow := 3.0   if is_goal else 1.8
		_draw_diamond(pos, DR, C_CELL, oc, ow)

		# Circle fill inside
		draw_circle(pos, CR, Color(prob, prob, prob))
		draw_arc(pos, CR, 0.0, TAU, 40, Color(1,1,1,0.7), 1.5)

		# Pauli label
		var lc := Color(0.1,0.1,0.1) if prob > 0.55 else Color(0.95,0.95,0.95)
		draw_string(_font, pos + Vector2(-14, 6), pauli,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, lc)

func _draw_board_buttons() -> void:
	for i in _btns.size():
		var b: Dictionary = _btns[i]
		var r  := _btn_rect(b)
		var en := _btn_enabled(b)
		var hov := en and (i == _hov)

		# Connection lines — two independent branches, one per target cell
		var actual_g: String = _actual_gate(b)
		var conn_key: String = b["qkey"] + "_" + actual_g
		if BTN_CONNECTS.has(conn_key):
			var lc: Color = C_CONN if en else Color(C_CONN.r, C_CONN.g, C_CONN.b, C_CONN.a * 0.35)
			var bx: float = b["center"].x
			if b["qkey"] == "both":
				# CZ: V-shape, lines go DOWN from shared junction to XZ/ZX top vertices
				var start_y: float = r.position.y + BTN_S
				for tp: String in BTN_CONNECTS[conn_key]:
					var cp := _sp(BOXES[tp])
					var tx: float = cp.x;  var ty: float = cp.y - DR
					var jy: float = ty - abs(tx - bx)
					if jy > start_y:
						draw_line(Vector2(bx, start_y), Vector2(bx, jy), lc, 1.5)
						draw_line(Vector2(bx, jy), Vector2(tx, ty), lc, 1.5)
					else:
						draw_line(Vector2(bx, start_y), Vector2(tx, ty), lc, 1.5)
			else:
				# Rectangular routing: vertical trunk up to ZI/IZ row, horizontal to each
				# target's x, then vertical up to cell bottom if above that row.
				var junc_y: float = BY + 1.5 * CELL + DR  # y of ZI/IZ bottom vertices = 470
				var start_y: float = r.position.y
				draw_line(Vector2(bx, start_y), Vector2(bx, junc_y), lc, 1.5)
				for tp: String in BTN_CONNECTS[conn_key]:
					var cp := _sp(BOXES[tp])
					var tx: float = cp.x
					var ty: float = cp.y + DR
					draw_line(Vector2(bx, junc_y), Vector2(tx, junc_y), lc, 1.5)
					if ty < junc_y - 0.5:
						draw_line(Vector2(tx, junc_y), Vector2(tx, ty), lc, 1.5)

		# Button square
		var bg := C_BTN_HOV if hov else (C_BTN_ON if en else C_BTN_OFF)
		draw_rect(r, bg)
		draw_rect(r, Color(1,1,1,0.3) if en else Color(0,0,0,0.1), false, 1.5)

		# Gate letter (large) + "GATE" text below
		var tc := C_BTN_TXT if en else Color(0.35,0.35,0.50)
		var letter: String = (b["gate"] as String).to_upper()
		# Shorten long names
		if letter in ["CNOT","NOT"]: letter = "X"
		if letter == "CX": letter = "X"
		if letter == "CZ": letter = "CZ"
		draw_string(_font, r.position + Vector2(BTN_S/2.0 - 10, BTN_S/2.0 + 4),
			letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, tc)
		draw_string(_font, r.position + Vector2(BTN_S/2.0 - 17, BTN_S/2.0 + 22),
			"GATE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, tc)

		# Remaining uses badge
		var rem = _uses.get(b["qkey"], {}).get(actual_g, -1)
		if rem > 0:
			draw_string(_font, r.position + Vector2(2, 14), "(%d)" % rem,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tc)

func _draw_panel() -> void:
	draw_rect(Rect2(PX, 0, W-PX, H), C_PANEL)

	var puz: Dictionary = _puzzles[_pidx]
	draw_string(_font, Vector2(PX+12, 28),
		"Puzzle %d / %d" % [_pidx+1, _puzzles.size()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)
	draw_string(_font, Vector2(PX+12, 58), puz["title"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	var dy := 92.0
	for line: String in puz["desc"].split("\n"):
		draw_string(_font, Vector2(PX+12, dy), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)
		dy += 22

	var goal_str := ""
	for p: String in puz["goal"]:
		goal_str += "%s=%s  " % [p, str(puz["goal"][p])]
	if goal_str == "": goal_str = "(explore)"
	draw_string(_font, Vector2(PX+12, dy+4),
		"Goal: " + goal_str, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_WIN)

	draw_string(_font, Vector2(PX+12, H-20),
		"Moves: %d" % _moves, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, C_LBL)

func _draw_success() -> void:
	draw_rect(Rect2(0, H/2.0-65, W, 130), Color(0,0,0,0.78))
	draw_string(_font, Vector2(W/2.0-110, H/2.0-12),
		"Puzzle solved!", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, C_WIN)
	draw_string(_font, Vector2(W/2.0-100, H/2.0+42),
		"Click to continue", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_LBL)
