extends Node3D

const MODELS := ["res://vrm_samples/constraint_test/VRM1_Constraint_Twist_Sample.vrm",
	"res://vrm_samples/constraint_test/VRM1_Constraint_Twist_Sample_rotated_rests.vrm"]
const MASTER := preload("res://vrm_samples/constraint_test/bone_node_constraint_master.gd")
const VERSIONS := ["installed addon (this PR)", "master"]
const POSES := ["rest", "arms", "legs"]
const SECONDS_PER_POSE := 2.0
const LIMIT := 0.1

var version := 0
var constraints := [[], []]
var skels: Array[Skeleton3D] = []
var aims: Array = []
var results := {}
var passed := []
var pose := -1
var timer := 0.0


func _ready() -> void:
	for i in 2:
		var rig: Node3D = load(MODELS[i]).instantiate()
		rig.position.x = -0.5 if i == 0 else 0.5
		add_child(rig)
		var skel: Skeleton3D = rig.find_children("*", "Skeleton3D", true, false)[0]
		skels.append(skel)
		aims.append([])
		for node in rig.find_children("*", "", true, false):
			if "spring_bones" in node and node.internal_modifier_node != null:
				node.internal_modifier_node.active = false
			if "constraints" in node:
				_take_over(node, skel, i)
	_next_pose()


func _take_over(applier: Node, skel: Skeleton3D, model: int) -> void:
	applier.set_process(false)
	var mod: Node = applier.internal_modifier_node
	if mod != null and mod.modification_processed.is_connected(applier.do_process):
		mod.modification_processed.disconnect(applier.do_process)
	for c in applier.constraints:
		var old: Resource = MASTER.new()
		for p in c.get_property_list():
			if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
				old.set(p["name"], c.get(p["name"]))
		old.set_node_references_from_paths(applier)
		constraints[0].append([model, c])
		constraints[1].append([model, old])
		if c.constraint_type == c.ConstraintType.AIM:
			var rest := skel.get_bone_global_rest(c.target_bone)
			var to_source := skel.get_bone_global_rest(c.source_bone).origin - rest.origin
			aims[model].append([c.target_bone, c.source_bone, rest.basis.inverse() * to_source])


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
		_switch()


func _switch() -> void:
	version = 1 - version
	results.clear()
	pose = -1
	_next_pose()


func _process(delta: float) -> void:
	for mc in constraints[version]:
		mc[1].evaluate()
	timer += delta
	if timer >= SECONDS_PER_POSE:
		results[POSES[pose]] = [maxf(_aim_error(0), _aim_error(1)), _copy_difference()]
		print("%-26s %-5s  aim %6.2f deg   copy %6.2f deg" % ([VERSIONS[version], POSES[pose]] + results[POSES[pose]]))
		_next_pose()
	var lines := ["%s   (M = switch to %s)" % [VERSIONS[version], VERSIONS[1 - version]], ""]
	var ok := true
	for p in POSES:
		if results.has(p):
			lines.append("%-5s  aim %6.2f deg   copy %6.2f deg" % ([p] + results[p]))
			ok = ok and results[p][0] <= LIMIT and results[p][1] <= LIMIT
	if results.size() == POSES.size():
		lines.append("PASS" if ok else "FAIL")
		if DisplayServer.get_name() == "headless" and passed.size() == version:
			print(VERSIONS[version], ": ", lines[-1])
			passed.append(ok)
			if version == 0:
				_switch()
			else:
				get_tree().quit(0 if passed[0] else 1)
	$Label.text = "\n".join(lines)
	$Label.modulate = Color.WHITE if results.size() < POSES.size() else (Color(0.6, 1, 0.6) if ok else Color(1, 0.55, 0.5))


func _next_pose() -> void:
	pose = (pose + 1) % POSES.size()
	timer = 0.0
	for s in skels:
		s.reset_bone_poses()
		match POSES[pose]:
			"arms":
				_turn(s, "LeftUpperArm", Vector3.BACK, -60); _twist(s, "LeftUpperArm", 45)
				_twist(s, "LeftLowerArm", 50); _twist(s, "LeftHand", 30)
				_turn(s, "RightUpperArm", Vector3.UP, 70); _twist(s, "RightLowerArm", -50)
			"legs":
				_turn(s, "LeftUpperLeg", Vector3.RIGHT, -45); _turn(s, "RightUpperLeg", Vector3.RIGHT, -30)


func _aim_error(i: int) -> float:
	var err := 0.0
	for a in aims[i]:
		var t := skels[i].get_bone_global_pose(a[0])
		err = maxf(err, rad_to_deg((t.basis * a[2]).angle_to(skels[i].get_bone_global_pose(a[1]).origin - t.origin)))
	return err


func _copy_difference() -> float:
	var diff := 0.0
	for b in skels[0].get_bone_count():
		var q := skels[0].get_bone_global_pose(b).basis.get_rotation_quaternion().inverse() \
			* skels[1].get_bone_global_pose(skels[1].find_bone(skels[0].get_bone_name(b))).basis.get_rotation_quaternion()
		diff = maxf(diff, rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))))
	return diff


func _turn(s: Skeleton3D, bone: String, axis: Vector3, deg: float) -> void:
	var b := s.find_bone(bone)
	var g := s.get_bone_global_rest(b).basis.get_rotation_quaternion()
	s.set_bone_pose_rotation(b, s.get_bone_pose_rotation(b) * (g.inverse() * Quaternion(axis.normalized(), deg_to_rad(deg)) * g))


func _twist(s: Skeleton3D, bone: String, deg: float) -> void:
	var b := s.find_bone(bone)
	var child := s.get_bone_children(b)[0]
	_turn(s, bone, s.get_bone_global_rest(child).origin - s.get_bone_global_rest(b).origin, deg)
