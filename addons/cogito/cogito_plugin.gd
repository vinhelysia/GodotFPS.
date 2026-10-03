@tool
extends EditorPlugin
const cogito_plugin_icon : Texture2D = preload("./Cogito.svg")
const cogito_default_settings = preload("./CogitoSettings.tres")

var cog_settings : CogitoSettings

var parser_plugin: EditorTranslationParserPlugin

func _enter_tree():
	# Prefer permanent project.godot autoloads (res:// paths). Only inject if missing
	# so headless runs and editor reloads still resolve CogitoGlobals/etc.
	_ensure_autoload("CogitoGlobals", "res://addons/cogito/cogito_globals.gd")
	_ensure_autoload("CogitoSceneManager", "res://addons/cogito/SceneManagement/cogito_scene_manager.gd")
	_ensure_autoload("CogitoQuestManager", "res://addons/cogito/QuestSystem/cogito_quest_manager.gd")
	_ensure_autoload("MenuTemplateManager", "res://addons/cogito/EasyMenus/Nodes/menu_template_manager.tscn")

	# Initialization of the plugin goes here.
	parser_plugin = load("res://addons/cogito/Localization/scripts/loc_resource_parser.gd").new()
	add_translation_parser_plugin(parser_plugin)

	cog_settings = cogito_default_settings


func _ensure_autoload(name: String, path: String) -> void:
	var key := "autoload/" + name
	if ProjectSettings.has_setting(key):
		return
	# Leading * = singleton enabled (Godot project setting convention).
	ProjectSettings.set_setting(key, "*" + path)
	ProjectSettings.save()


func _exit_tree():
	# Do NOT remove Cogito autoloads — they are project-owned (project.godot).
	# Upstream Cogito removed them here, which left scripts unable to parse
	# "CogitoGlobals" after the plugin unloaded or in headless runs.
	remove_translation_parser_plugin(parser_plugin)



func _get_plugin_name():
	return "Cogito"


func _get_plugin_icon():
	return cogito_plugin_icon
