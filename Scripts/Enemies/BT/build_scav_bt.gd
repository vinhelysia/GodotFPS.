extends SceneTree

## Dev tool — regenerates Scene/Enemies/BT/scav_brain.tres programmatically.
## Run from Project → Tools, or call via `godot --script`.
## The .tres file is the authoritative source; this script is for reference only.

func _init():
	var bt := BehaviorTree.new()
	var root := BTDynamicSelector.new()
	bt.root_task = root

	# --- Combat branch (guard: alert >= COMBAT=2) ---
	var combat_seq := BTDynamicSequence.new()
	combat_seq.custom_name = "CombatSequence"

	var cond_combat := load("res://Scripts/Enemies/BT/Tasks/btc_alert_at_least.gd").new()
	cond_combat.min_level = 2  # Alert.COMBAT
	cond_combat.custom_name = "IsCombatAlert"

	var face := load("res://Scripts/Enemies/BT/Tasks/bt_face_target.gd").new()
	face.custom_name = "FaceTarget"

	var combat_actions := BTDynamicSelector.new()
	combat_actions.custom_name = "CombatActions"

	var reload := load("res://Scripts/Enemies/BT/Tasks/bt_reload.gd").new()
	reload.custom_name = "ReloadWeapon"
	if ResourceLoader.exists("res://addons/cogito/Assets/Audio/Kenney/Handle_Click.wav"):
		reload.reload_sound = load("res://addons/cogito/Assets/Audio/Kenney/Handle_Click.wav")

	var shoot := load("res://Scripts/Enemies/BT/Tasks/bt_shoot.gd").new()
	shoot.custom_name = "ShootTarget"
	if ResourceLoader.exists("res://addons/cogito/Assets/Audio/Kenney/Pistol_Shot.wav"):
		shoot.shoot_sound = load("res://addons/cogito/Assets/Audio/Kenney/Pistol_Shot.wav")

	var move_to_target := load("res://Scripts/Enemies/BT/Tasks/bt_move_to.gd").new()
	move_to_target.custom_name = "MoveToTarget"
	move_to_target.position_var = &"last_known_pos"

	var should_strafe := load("res://Scripts/Enemies/BT/Tasks/btc_should_strafe.gd").new()
	should_strafe.custom_name = "ShouldStrafe"

	var strafe := load("res://Scripts/Enemies/BT/Tasks/bt_strafe.gd").new()
	strafe.custom_name = "Strafe"

	var strafe_seq := BTDynamicSequence.new()
	strafe_seq.custom_name = "StrafeSequence"
	strafe_seq.add_child(should_strafe)
	strafe_seq.add_child(strafe)

	combat_actions.add_child(reload)     # 1st: reload if empty
	combat_actions.add_child(strafe_seq) # 2nd: reposition after enough shots fired
	combat_actions.add_child(shoot)      # 3rd: shoot if LOS+range
	combat_actions.add_child(move_to_target)  # 4th: chase

	combat_seq.add_child(cond_combat)
	combat_seq.add_child(face)
	combat_seq.add_child(combat_actions)
	root.add_child(combat_seq)

	# --- Investigate branch (guard: has_last_known) ---
	var invest_seq := BTDynamicSequence.new()
	invest_seq.custom_name = "InvestigateSequence"

	var cond_invest := load("res://Scripts/Enemies/BT/Tasks/btc_has_last_known.gd").new()
	cond_invest.custom_name = "HasInvestigationTarget"

	var move_to_invest := load("res://Scripts/Enemies/BT/Tasks/bt_move_to.gd").new()
	move_to_invest.custom_name = "MoveToInvestigation"
	move_to_invest.position_var = &"last_known_pos"

	var look_around := load("res://Scripts/Enemies/BT/Tasks/bt_look_around.gd").new()
	look_around.custom_name = "LookAround"

	invest_seq.add_child(cond_invest)
	invest_seq.add_child(move_to_invest)
	invest_seq.add_child(look_around)
	root.add_child(invest_seq)

	# --- Patrol branch (default) ---
	var patrol := load("res://Scripts/Enemies/BT/Tasks/bt_patrol.gd").new()
	patrol.custom_name = "PatrolPath"
	root.add_child(patrol)

	DirAccess.make_dir_recursive_absolute("res://Scene/Enemies/BT")
	var err := ResourceSaver.save(bt, "res://Scene/Enemies/BT/scav_brain.tres")
	print("Saved scav_brain.tres: ", err)
