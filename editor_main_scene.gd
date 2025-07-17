extends Control


const ERR_EMPTY_LOCALE := "Files with empty locale fields found: %s. Resolve the issue manually.";
const ERR_KEY_DUPE := "Key duplicates within single files found: %s. Resolve the issue manually.";
const ERR_KEY_COLLISION := "Possible collisions found: %s. Move keys to files using the \"Files\" tab.";


var block_input : bool = false;
var data := CWDState.new();
var status_strings : Array[String] = [];
var editing_main : bool = true;

var filter_data : FilterData = FilterData.new(data);

var selected_key_idx : int;
var selected_key : String;
var selected_key_data : Dictionary[String, String];

@onready
var dir_info : Control = $Main/DirInfo;
@onready
var cwd_info : Control = $Main/CWDInfo;
@onready
var key_select : Control = $Main/KeySelect;
@onready
var file_info : Control = $Main/FileInfo;
@onready
var key_info : Control = $Main/KeyInfo;
@onready
var localization_edit : Control = $Main/Edit/Localization;
@onready
var file_edit : Control = $Main/Edit/Files;
@onready
var status_info : Control = $Main/Messages/MessagesContainer;


func _ready() -> void:
	PersistentData.load_fom_disk();
	if PersistentData.last_working_directory != "":
		folder_change_util(PersistentData.last_working_directory);
	
	dir_info.get_node(^"ChangeDirButton").pressed.connect(change_folder);
	
	key_select.get_node(^"KeyFilter").text_submitted.connect(on_filter_string_submit);
	key_select.get_node(^"KeyList").item_selected.connect(display_key_translations);
	
	localization_edit.get_node(^"Locale").item_selected.connect(update_translation);
	localization_edit.get_node(^"OtherLocale").item_selected.connect(update_other_translation);
	
	localization_edit.get_node(^"Translation").focus_entered.connect(start_editing.bind(true));
	localization_edit.get_node(^"Translation").focus_exited.connect(edit_translation);
	localization_edit.get_node(^"OtherTranslation").focus_entered.connect(start_editing.bind(false));
	localization_edit.get_node(^"OtherTranslation").focus_exited.connect(edit_translation);
	
	key_info.get_node(^"DisplayOther").toggled.connect(display_other);
	display_other(key_info.get_node(^"DisplayOther").is_pressed());
	
	dir_info.get_node(^"OpenUserdata").pressed.connect(open_userdata);
	dir_info.get_node(^"SaveData").pressed.connect(save_data)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			PersistentData.save();


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_undo"):
		data.undo();
		update_all();
		get_viewport().set_input_as_handled();
	
	if event.is_action_pressed(&"ui_redo"):
		data.redo();
		update_all();
		get_viewport().set_input_as_handled();
	
	
	if event.is_action_pressed(&"save_to_disk"):
		get_viewport().gui_release_focus();
		data.save_changes();
		get_viewport().set_input_as_handled();
	
	
	if event.is_action_pressed(&"save_backup"):
		get_viewport().gui_release_focus();
		data.backup_changes();
		get_viewport().set_input_as_handled();
	
	
	if event.is_action_pressed(&"restore_session"):
		get_viewport().gui_release_focus();
		data.restore_backup();
		update_all();
		get_viewport().set_input_as_handled();
	
	
	if event.is_action_pressed(&"submit_text_change"):
		get_viewport().gui_release_focus();
		get_viewport().set_input_as_handled();


func update_all() -> void:
	update_status();
	update_cwd_data_display();
	display_key_translations(selected_key_idx);


func update_status() -> void:
	status_strings.clear();
	
	if not data.empty_localizations.is_empty():
		var filenames = data.empty_localizations.keys().map(func(idx): return data.cwd_files[idx]);
		status_strings.push_back(ERR_EMPTY_LOCALE % filenames);
	
	var dupes = data.get_single_file_dupes();
	if not dupes.is_empty():
		status_strings.push_back(
			ERR_KEY_DUPE % dupes
		);
	
	if not data.possible_collisions.is_empty():
		status_strings.push_back(
			ERR_KEY_COLLISION % data.possible_collisions.keys()
		);
	
	display_status();


func display_status() -> void:
	for old in status_info.get_children():
		status_info.remove_child(old);
		old.free();
	
	for str in status_strings:
		var label = Label.new();
		label.text = str;
		status_info.add_child(label);
	
	if status_strings.is_empty():
		var label = Label.new();
		label.text = "no issues found";
		status_info.add_child(label);


func on_filter_string_submit(query: String) -> void:
	filter_data = FilterData.from_query(query, data);
	refresh_list_of_keys();


func update_cwd_data_display() -> void:
	dir_info.get_node(^"DirName").text = data.cwd_handle.get_current_dir(true);
	cwd_info.get_node(^"FileCount").text = "files found: %d" % data.cwd_files.size();
	cwd_info.get_node(^"KeyCount").text = "total keys: %d" % data.keys.size();
	cwd_info.get_node(^"UniqueL10Ns").text = "total localizations: %d" % data.localizations.size();


func refresh_list_of_keys() -> void:
	key_select.get_node(^"KeyList").clear();
	for key in data.keys.keys().filter(filter_data.matches):
		key_select.get_node(^"KeyList").add_item(key);


func refresh_list_of_files() -> void:
	file_info.get_node(^"CurrentFile").clear();
	for file in data.cwd_files:
		file_info.get_node(^"CurrentFile").add_item(file);


func change_folder() -> void:
	block_input = true;
	
	var choose_new_file = FileDialog.new();
	choose_new_file.file_mode = FileDialog.FILE_MODE_OPEN_DIR;
	choose_new_file.access = FileDialog.ACCESS_FILESYSTEM;
	choose_new_file.current_dir = OS.get_executable_path();
	choose_new_file.close_requested.connect(cancel_change_folder.bind(choose_new_file));
	choose_new_file.dir_selected.connect(finish_change_folder.bind(choose_new_file));
	
	self.add_child(choose_new_file);
	choose_new_file.popup_centered();


func cancel_change_folder(dialog: FileDialog) -> void:
	dialog.hide();
	dialog.free();
	block_input = false;


func finish_change_folder(dir: String, dialog: FileDialog) -> void:
	PersistentData.last_working_directory = dir;
	folder_change_util(dir)
	cancel_change_folder(dialog);


func folder_change_util(path: String) -> void:
	data.scan_cwd(path);
	update_cwd_data_display();
	refresh_list_of_keys();
	update_localization_select();
	update_status();


func display_key_translations(key_idx: int) -> void:
	selected_key_idx = key_idx;
	selected_key = key_select.get_node(^"KeyList").get_item_text(key_idx);
	selected_key_data = data.get_key_data(selected_key);
	
	if localization_edit.get_node(^"Locale").selected != -1 \
		or localization_edit.get_node(^"OtherLocale").selected != -1:
			update_translation_data();


func update_translation_data(_idx: int = -1) -> void:
	var locale_check = {};
	locale_check.merge(selected_key_data);
	locale_check.merge(data.localizations);
	
	if locale_check.keys().size() > data.localizations.keys().size():
		update_localization_select_with_key_data();
		return;
	
	if localization_edit.get_node(^"Locale").item_count > locale_check.keys().size():
		update_localization_select();
		return;
	
	update_translation();
	update_other_translation();


func update_translation(_idx: int = -1) -> void:
	var selected_main = localization_edit.get_node(^"Locale").selected;
	if selected_main != -1:
		var locale = localization_edit.get_node(^"Locale").get_item_text(selected_main);
		localization_edit.get_node(^"Translation").text = selected_key_data.get(locale, "");
		localization_edit.get_node(^"Translation").clear_undo_history();


func update_other_translation(_idx: int = -1) -> void:
	var selected_other = localization_edit.get_node(^"OtherLocale").selected;
	if selected_other != -1:
		var locale = localization_edit.get_node(^"OtherLocale").get_item_text(selected_other);
		localization_edit.get_node(^"OtherTranslation").text = selected_key_data.get(locale, "");
		localization_edit.get_node(^"OtherTranslation").clear_undo_history();


func update_localization_select() -> void:
	var locale := localization_edit.get_node(^"Locale");
	var other_locale := localization_edit.get_node(^"OtherLocale");
	
	var temp_idx : int = locale.selected;
	var temp_idx_other : int = other_locale.selected;
	
	locale.clear();
	other_locale.clear();
	
	for locale_key in data.localizations:
		locale.add_item(locale_key);
		other_locale.add_item(locale_key);
	
	if temp_idx < locale.item_count:
		locale.select(temp_idx);
		update_translation();
	else:
		locale.select(0);
		update_translation();
	
	if temp_idx_other < other_locale.item_count:
		other_locale.select(temp_idx_other);
		update_other_translation();
	else:
		other_locale.select(0);
		update_other_translation();


func update_localization_select_with_key_data() -> void:
	var locale := localization_edit.get_node(^"Locale");
	var other_locale := localization_edit.get_node(^"OtherLocale");
	
	var temp_idx : int = locale.selected;
	var temp_idx_other : int = other_locale.selected;
	
	locale.clear();
	other_locale.clear();
	
	var locale_check = {};
	locale_check.merge(selected_key_data);
	locale_check.merge(data.localizations);
	
	for locale_key in locale_check.keys():
		locale.add_item(locale_key);
		other_locale.add_item(locale_key);
	
	if temp_idx < locale.item_count:
		locale.select(temp_idx);
		update_translation();
	else:
		locale.select(0);
		update_translation();
	
	if temp_idx_other < other_locale.item_count:
		other_locale.select(temp_idx_other);
		update_other_translation();
	else:
		other_locale.select(0);
		update_other_translation();


func display_other(y: bool) -> void:
	localization_edit.get_node(^"OtherLocale").visible = y;
	localization_edit.get_node(^"OtherTranslation").visible = y;


func start_editing(main: bool) -> void:
	editing_main = main;


func edit_translation() -> void:
	if selected_key == "":
		return;
	
	localization_edit.get_node(^"Translation").clear_undo_history();
	localization_edit.get_node(^"OtherTranslation").clear_undo_history();
	
	var locale : OptionButton =\
		localization_edit.get_node(^"Locale" if editing_main else ^"OtherLocale");
	var translation : TextEdit =\
		localization_edit.get_node(^"Translation" if editing_main else ^"OtherTranslation")
	
	var current_locale := locale.get_item_text(locale.selected);
	var current_text := translation.text;
	
	data.change_translation(selected_key, current_locale, current_text);
	
	display_key_translations(selected_key_idx);


func open_userdata() -> void:
	OS.shell_open(ProjectSettings.globalize_path(FileData.BACKUP_LOCATION));


func save_data() -> void:
	data.save_changes();
