class_name CogitoOptionsKeyBindings
extends MarginContainer
## Owns the bindings tab's defaults and remap rows; the parent owns config file IO.

@onready var bindings_container: VBoxContainer = $ScrollContainer/MarginContainer/BindingsContainer

const INPUT_ACTIONS: Dictionary = {
	"separator_movement": "SEPARATOR_MOVEMENT",
	"forward": "INPUT_move_forward",
	"back": "INPUT_move_backward",
	"left": "INPUT_move_left",
	"right": "INPUT_move_right",
	"jump": "INPUT_jump",
	"crouch": "INPUT_crouch",
	"separator_actions": "SEPARATOR_ACTIONS",
	"action_primary": "INPUT_primary_action",
	"action_secondary": "INPUT_secondary_action",
	"interact": "INPUT_interact_1",
	"interact2": "INPUT_interact_1",
	"reload": "INPUT_reload",
	"quickslot_1": "INPUT_quickslot_1",
	"quickslot_2": "INPUT_quickslot_2",
	"quickslot_3": "INPUT_quickslot_3",
	"quickslot_4": "INPUT_quickslot_4",
	"quickslot_prev_wieldable": "INPUT_quickslot_prev",
	"quickslot_next_wieldable": "INPUT_quickslot_next",
	"separator_inventory": "SEPARATOR_MENUES",
	"menu": "INPUT_pause",
	"inventory": "INPUT_inventory",
	"inventory_drop_item": "INPUT_item_quick_drop",
	"inventory_move_item": "INPUT_item_move",
	"inventory_use_item": "INPUT_item_use",
}

const SERIALIZED_DEFAULT_INPUTS: String = "{\"action_primary\":{\"joypad\":[\"5|0.345098\"],\"keyboard\":[],\"mouse\":[1]},\"action_secondary\":{\"joypad\":[\"4|0.223529\"],\"keyboard\":[],\"mouse\":[2]},\"back\":{\"joypad\":[\"1|0.207062\"],\"keyboard\":[\"S\"],\"mouse\":[]},\"crouch\":{\"joypad\":[1],\"keyboard\":[\"C\"],\"mouse\":[]},\"forward\":{\"joypad\":[\"1|-0.225074\"],\"keyboard\":[\"W\"],\"mouse\":[]},\"free_look\":{\"joypad\":[],\"keyboard\":[\"CapsLock\"],\"mouse\":[]},\"interact\":{\"joypad\":[2],\"keyboard\":[\"F\"],\"mouse\":[]},\"interact2\":{\"joypad\":[3],\"keyboard\":[\"V\"],\"mouse\":[]},\"inventory\":{\"joypad\":[4],\"keyboard\":[\"Tab\"],\"mouse\":[]},\"inventory_drop_item\":{\"joypad\":[3],\"keyboard\":[\"G\"],\"mouse\":[]},\"inventory_move_item\":{\"joypad\":[0],\"keyboard\":[],\"mouse\":[1]},\"inventory_use_item\":{\"joypad\":[1],\"keyboard\":[],\"mouse\":[2]},\"jump\":{\"joypad\":[0],\"keyboard\":[\"Space\"],\"mouse\":[]},\"left\":{\"joypad\":[\"0|-0.172882\"],\"keyboard\":[\"A\"],\"mouse\":[]},\"menu\":{\"joypad\":[6],\"keyboard\":[\"Escape\"],\"mouse\":[]},\"quickslot_1\":{\"joypad\":[13],\"keyboard\":[\"1\"],\"mouse\":[]},\"quickslot_2\":{\"joypad\":[11],\"keyboard\":[\"2\"],\"mouse\":[]},\"quickslot_3\":{\"joypad\":[14],\"keyboard\":[\"3\"],\"mouse\":[]},\"quickslot_4\":{\"joypad\":[12],\"keyboard\":[\"4\"],\"mouse\":[]},\"reload\":{\"joypad\":[2],\"keyboard\":[\"R\"],\"mouse\":[]},\"right\":{\"joypad\":[\"0|0.136204\"],\"keyboard\":[\"D\"],\"mouse\":[]},\"sprint\":{\"joypad\":[7],\"keyboard\":[\"Shift\"],\"mouse\":[]},\"ui_accept\":{\"joypad\":[0],\"keyboard\":[\"Enter\",\"Kp Enter\",\"Space\"],\"mouse\":[]},\"ui_cancel\":{\"joypad\":[1],\"keyboard\":[\"Escape\"],\"mouse\":[]},\"ui_copy\":{\"joypad\":[],\"keyboard\":[\"C|ctrl\",\"Insert|ctrl\"],\"mouse\":[]},\"ui_cut\":{\"joypad\":[],\"keyboard\":[\"X|ctrl\",\"Delete|shift\"],\"mouse\":[]},\"ui_down\":{\"joypad\":[12,\"1|1.000000\"],\"keyboard\":[\"Down\"],\"mouse\":[]},\"ui_end\":{\"joypad\":[],\"keyboard\":[\"End\"],\"mouse\":[]},\"ui_filedialog_refresh\":{\"joypad\":[],\"keyboard\":[\"F5\"],\"mouse\":[]},\"ui_filedialog_show_hidden\":{\"joypad\":[],\"keyboard\":[\"H\"],\"mouse\":[]},\"ui_filedialog_up_one_level\":{\"joypad\":[],\"keyboard\":[\"Backspace\"],\"mouse\":[]},\"ui_focus_next\":{\"joypad\":[],\"keyboard\":[\"Tab\"],\"mouse\":[]},\"ui_focus_prev\":{\"joypad\":[],\"keyboard\":[\"Tab|shift\"],\"mouse\":[]},\"ui_graph_delete\":{\"joypad\":[],\"keyboard\":[\"Delete\"],\"mouse\":[]},\"ui_graph_duplicate\":{\"joypad\":[],\"keyboard\":[\"D|ctrl\"],\"mouse\":[]},\"ui_home\":{\"joypad\":[],\"keyboard\":[\"Home\"],\"mouse\":[]},\"ui_left\":{\"joypad\":[13,\"0|-1.000000\"],\"keyboard\":[\"Left\"],\"mouse\":[]},\"ui_menu\":{\"joypad\":[],\"keyboard\":[\"Menu\"],\"mouse\":[]},\"ui_next_tab\":{\"joypad\":[10],\"keyboard\":[\"E\"],\"mouse\":[]},\"ui_page_down\":{\"joypad\":[],\"keyboard\":[\"PageDown\"],\"mouse\":[]},\"ui_page_up\":{\"joypad\":[],\"keyboard\":[\"PageUp\"],\"mouse\":[]},\"ui_paste\":{\"joypad\":[],\"keyboard\":[\"V|ctrl\",\"Insert|shift\"],\"mouse\":[]},\"ui_prev_tab\":{\"joypad\":[9],\"keyboard\":[\"Q\"],\"mouse\":[]},\"ui_redo\":{\"joypad\":[],\"keyboard\":[\"Z|shift,ctrl\",\"Y|ctrl\"],\"mouse\":[]},\"ui_right\":{\"joypad\":[14,\"0|1.000000\"],\"keyboard\":[\"Right\"],\"mouse\":[]},\"ui_select\":{\"joypad\":[3],\"keyboard\":[\"Space\"],\"mouse\":[]},\"ui_swap_input_direction\":{\"joypad\":[],\"keyboard\":[\"QuoteLeft|ctrl\"],\"mouse\":[]},\"ui_text_add_selection_for_next_occurrence\":{\"joypad\":[],\"keyboard\":[\"D|ctrl\"],\"mouse\":[]},\"ui_text_backspace\":{\"joypad\":[],\"keyboard\":[\"Backspace\",\"Backspace|shift\"],\"mouse\":[]},\"ui_text_backspace_all_to_left\":{\"joypad\":[],\"keyboard\":[],\"mouse\":[]},\"ui_text_backspace_all_to_left.macos\":{\"joypad\":[],\"keyboard\":[\"Backspace|ctrl\"],\"mouse\":[]},\"ui_text_backspace_word\":{\"joypad\":[],\"keyboard\":[\"Backspace|ctrl\"],\"mouse\":[]},\"ui_text_backspace_word.macos\":{\"joypad\":[],\"keyboard\":[\"Backspace|alt\"],\"mouse\":[]},\"ui_text_caret_add_above\":{\"joypad\":[],\"keyboard\":[\"Up|shift,ctrl\"],\"mouse\":[]},\"ui_text_caret_add_above.macos\":{\"joypad\":[],\"keyboard\":[\"O|shift,ctrl\"],\"mouse\":[]},\"ui_text_caret_add_below\":{\"joypad\":[],\"keyboard\":[\"Down|shift,ctrl\"],\"mouse\":[]},\"ui_text_caret_add_below.macos\":{\"joypad\":[],\"keyboard\":[\"L|shift,ctrl\"],\"mouse\":[]},\"ui_text_caret_document_end\":{\"joypad\":[],\"keyboard\":[\"End|ctrl\"],\"mouse\":[]},\"ui_text_caret_document_end.macos\":{\"joypad\":[],\"keyboard\":[\"Down|ctrl\",\"End|ctrl\"],\"mouse\":[]},\"ui_text_caret_document_start\":{\"joypad\":[],\"keyboard\":[\"Home|ctrl\"],\"mouse\":[]},\"ui_text_caret_document_start.macos\":{\"joypad\":[],\"keyboard\":[\"Up|ctrl\",\"Home|ctrl\"],\"mouse\":[]},\"ui_text_caret_down\":{\"joypad\":[],\"keyboard\":[\"Down\"],\"mouse\":[]},\"ui_text_caret_left\":{\"joypad\":[],\"keyboard\":[\"Left\"],\"mouse\":[]},\"ui_text_caret_line_end\":{\"joypad\":[],\"keyboard\":[\"End\"],\"mouse\":[]},\"ui_text_caret_line_end.macos\":{\"joypad\":[],\"keyboard\":[\"E|ctrl\",\"Right|ctrl\",\"End\"],\"mouse\":[]},\"ui_text_caret_line_start\":{\"joypad\":[],\"keyboard\":[\"Home\"],\"mouse\":[]},\"ui_text_caret_line_start.macos\":{\"joypad\":[],\"keyboard\":[\"A|ctrl\",\"Left|ctrl\",\"Home\"],\"mouse\":[]},\"ui_text_caret_page_down\":{\"joypad\":[],\"keyboard\":[\"PageDown\"],\"mouse\":[]},\"ui_text_caret_page_up\":{\"joypad\":[],\"keyboard\":[\"PageUp\"],\"mouse\":[]},\"ui_text_caret_right\":{\"joypad\":[],\"keyboard\":[\"Right\"],\"mouse\":[]},\"ui_text_caret_up\":{\"joypad\":[],\"keyboard\":[\"Up\"],\"mouse\":[]},\"ui_text_caret_word_left\":{\"joypad\":[],\"keyboard\":[\"Left|ctrl\"],\"mouse\":[]},\"ui_text_caret_word_left.macos\":{\"joypad\":[],\"keyboard\":[\"Left|alt\"],\"mouse\":[]},\"ui_text_caret_word_right\":{\"joypad\":[],\"keyboard\":[\"Right|ctrl\"],\"mouse\":[]},\"ui_text_caret_word_right.macos\":{\"joypad\":[],\"keyboard\":[\"Right|alt\"],\"mouse\":[]},\"ui_text_clear_carets_and_selection\":{\"joypad\":[],\"keyboard\":[\"Escape\"],\"mouse\":[]},\"ui_text_completion_accept\":{\"joypad\":[],\"keyboard\":[\"Enter\",\"Kp Enter\"],\"mouse\":[]},\"ui_text_completion_query\":{\"joypad\":[],\"keyboard\":[\"Space|ctrl\"],\"mouse\":[]},\"ui_text_completion_replace\":{\"joypad\":[],\"keyboard\":[\"Tab\"],\"mouse\":[]},\"ui_text_dedent\":{\"joypad\":[],\"keyboard\":[\"Tab|shift\"],\"mouse\":[]},\"ui_text_delete\":{\"joypad\":[],\"keyboard\":[\"Delete\"],\"mouse\":[]},\"ui_text_delete_all_to_right\":{\"joypad\":[],\"keyboard\":[],\"mouse\":[]},\"ui_text_delete_all_to_right.macos\":{\"joypad\":[],\"keyboard\":[\"Delete|ctrl\"],\"mouse\":[]},\"ui_text_delete_word\":{\"joypad\":[],\"keyboard\":[\"Delete|ctrl\"],\"mouse\":[]},\"ui_text_delete_word.macos\":{\"joypad\":[],\"keyboard\":[\"Delete|alt\"],\"mouse\":[]},\"ui_text_indent\":{\"joypad\":[],\"keyboard\":[\"Tab\"],\"mouse\":[]},\"ui_text_newline\":{\"joypad\":[],\"keyboard\":[\"Enter\",\"Kp Enter\"],\"mouse\":[]},\"ui_text_newline_above\":{\"joypad\":[],\"keyboard\":[\"Enter|shift,ctrl\",\"Kp Enter|shift,ctrl\"],\"mouse\":[]},\"ui_text_newline_blank\":{\"joypad\":[],\"keyboard\":[\"Enter|ctrl\",\"Kp Enter|ctrl\"],\"mouse\":[]},\"ui_text_scroll_down\":{\"joypad\":[],\"keyboard\":[\"Down|ctrl\"],\"mouse\":[]},\"ui_text_scroll_down.macos\":{\"joypad\":[],\"keyboard\":[\"Down|alt,ctrl\"],\"mouse\":[]},\"ui_text_scroll_up\":{\"joypad\":[],\"keyboard\":[\"Up|ctrl\"],\"mouse\":[]},\"ui_text_scroll_up.macos\":{\"joypad\":[],\"keyboard\":[\"Up|alt,ctrl\"],\"mouse\":[]},\"ui_text_select_all\":{\"joypad\":[],\"keyboard\":[\"A|ctrl\"],\"mouse\":[]},\"ui_text_select_word_under_caret\":{\"joypad\":[],\"keyboard\":[\"G|alt\"],\"mouse\":[]},\"ui_text_select_word_under_caret.macos\":{\"joypad\":[],\"keyboard\":[\"G|ctrl,meta\"],\"mouse\":[]},\"ui_text_skip_selection_for_next_occurrence\":{\"joypad\":[],\"keyboard\":[\"D|alt,ctrl\"],\"mouse\":[]},\"ui_text_submit\":{\"joypad\":[],\"keyboard\":[\"Enter\",\"Kp Enter\"],\"mouse\":[]},\"ui_text_toggle_insert_mode\":{\"joypad\":[],\"keyboard\":[\"Insert\"],\"mouse\":[]},\"ui_undo\":{\"joypad\":[],\"keyboard\":[\"Z|ctrl\"],\"mouse\":[]},\"ui_up\":{\"joypad\":[11,\"1|-1.000000\"],\"keyboard\":[\"Up\"],\"mouse\":[]}}"


func apply_config(config: ConfigFile) -> void:
	var serialized_inputs = config.get_value(OptionsConstants.key_binds, OptionsConstants.input_helper_string, SERIALIZED_DEFAULT_INPUTS)
	if serialized_inputs:
		InputHelper.deserialize_inputs_for_actions(serialized_inputs)
	else:
		CogitoGlobals.debug_log(true, "OptionsTabMenu.gd", "Keybindings: No saved bindings found.")


func store_in_config(config: ConfigFile) -> void:
	var serialized_inputs = InputHelper.serialize_inputs_for_actions()
	config.set_value(OptionsConstants.key_binds, OptionsConstants.input_helper_string, serialized_inputs)


func populate_rows(remap_scene: PackedScene, separator_scene: PackedScene, actions: Dictionary) -> void:
	for action in actions:
		if action.contains("separator"):
			var separator = separator_scene.instantiate()
			bindings_container.add_child(separator)
			separator.separator_text = actions[action]
		else:
			var input_entry = remap_scene.instantiate()
			input_entry.action = action
			bindings_container.add_child(input_entry)
			input_entry.label.text = tr(actions[action])

