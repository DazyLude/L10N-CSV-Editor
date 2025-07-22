extends Control


const ERR_EMPTY_LOCALE := "Files with empty locale fields found: %s. Resolve the issue manually.";
const ERR_KEY_DUPE := "Key duplicates within single files found: %s. Resolve the issue manually.";
const ERR_KEY_COLLISION := "Possible collisions found: %s. Move keys to files using the \"Files\" tab.";


var data := CWDState.new();
var status_strings : Array[String] = [];
var editing_main : bool = true;

var filter_data : FilterData = FilterData.new(data);

var selected_key_idx : int;
var selected_key : String;
var selected_key_data : Dictionary[String, String];
var key_lookup : Dictionary[String, int];


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
var localization_edit : Control = $Main/Edit/Localization/EditFields;
@onready
var file_edit : Control = $Main/Edit/Files;
@onready
var status_info : Control = $Main/Messages/MessagesContainer;


func _ready() -> void:
	cwd_info.hide();
	key_select.hide();
	file_info.hide();
	key_info.hide();
	$Main/Edit.hide();
	
	PersistentData.load_fom_disk();
	if PersistentData.last_working_directory != "":
		folder_change_util(PersistentData.last_working_directory);
	
	dir_info.get_node(^"ChangeDirButton").pressed.connect(change_folder);
	
	key_select.get_node(^"KeyFilter").text_submitted.connect(on_filter_string_submit);
	key_select.get_node(^"KeyList").item_selected.connect(display_key_translations);
	key_select.get_node(^"KeyList").item_selected.connect(update_key_files);
	
	$Main/Edit/Files/FileList.multi_selected.connect(update_provided_locales);
	
	$Main/FileInfo/CurrentFile.item_selected.connect(select_file);
	select_file(0);
	
	localization_edit.get_node(^"Locale").item_selected.connect(update_translation);
	localization_edit.get_node(^"OtherLocale").item_selected.connect(update_other_translation);
	
	localization_edit.get_node(^"Translation").focus_entered.connect(start_editing.bind(true));
	localization_edit.get_node(^"Translation").focus_exited.connect(edit_translation);
	localization_edit.get_node(^"OtherTranslation").focus_entered.connect(start_editing.bind(false));
	localization_edit.get_node(^"OtherTranslation").focus_exited.connect(edit_translation);
	
	var display_other_switch := $Main/Edit/Localization/DisplayOther;
	display_other_switch.toggled.connect(display_other);
	display_other(display_other_switch.is_pressed());
	
	dir_info.get_node(^"OpenUserdata").pressed.connect(open_userdata);
	dir_info.get_node(^"SaveData").pressed.connect(save_data);
	
	$Main/KeyInfo/AddNewKey.pressed.connect(add_key);
	$Main/KeyInfo/RenameKey.pressed.connect(rename_key);
	$Main/LocaleInfo/AddNewLocalization.pressed.connect(add_locale);
	$Main/FileInfo/AddFile.pressed.connect(create_new_file);


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			PersistentData.save();


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_undo"):
		var meta = data.undo();
		if typeof(meta) == TYPE_STRING:
			apply_meta(meta);
		update_all();
		get_viewport().set_input_as_handled();
	
	if event.is_action_pressed(&"ui_redo"):
		var meta = data.redo();
		if typeof(meta) == TYPE_STRING:
			apply_meta(meta);
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


func apply_meta(meta: String) -> void:
	match meta:
		"":
			refresh_list_of_keys()
			return;
		var key when key in key_lookup: # assuming meta is a key name
			var key_select : ItemList = key_select.get_node(^"KeyList");
			var key_idx = key_lookup[key];
			key_select.select(key_idx);
			display_key_translations(key_idx);
			update_key_files();


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
	var list_of_keys : ItemList = key_select.get_node(^"KeyList");
	list_of_keys.clear();
	key_lookup.clear();
	
	for key in data.keys.keys().filter(filter_data.matches):
		var idx = list_of_keys.add_item(key);
		key_lookup[key] = idx;
		if key == selected_key:
			selected_key_idx = idx;
			list_of_keys.select(idx);


func refresh_list_of_files() -> void:
	var file_selector : OptionButton = file_info.get_node(^"CurrentFile");
	var file_list : ItemList = file_edit.get_node(^"FileList");
	file_selector.clear();
	file_list.clear();
	
	file_selector.add_item("not selected");
	for file in data.cwd_files:
		file_selector.add_item(file.get_file());
		file_list.add_item(file.get_file());
	
	if data.current_file_idx != -1:
		file_selector.select(data.current_file_idx + 1);


func update_key_files(_idx: int = 0) -> void:
	var file_list : ItemList = file_edit.get_node(^"FileList");
	var provided_locales : Label = file_edit.get_node(^"Info/Provided");
	file_list.deselect_all();
	
	if selected_key == "":
		return;
	
	var current_filelist = data.get_key_files(selected_key);
	provided_locales.text = "current locales: %s" % data.get_files_localizations(current_filelist);
	
	for file in current_filelist:
		file_list.select(file);


func update_provided_locales(_idx: int = 0, _sel: bool = true) -> void:
	var file_list : ItemList = file_edit.get_node(^"FileList");
	var provided_locales : Label = file_edit.get_node(^"Info/Provided");
	
	var current_filelist := Array(file_list.get_selected_items() as Array, TYPE_INT, &"", null);
	provided_locales.text = "current locales: %s" % data.get_files_localizations(current_filelist);


func create_new_file() -> void:
	var create_new_file = FileDialog.new();
	create_new_file.file_mode = FileDialog.FILE_MODE_SAVE_FILE;
	create_new_file.access = FileDialog.ACCESS_FILESYSTEM;
	create_new_file.current_dir = data.cwd_handle.get_current_dir();
	create_new_file.close_requested.connect(close_file_dialog.bind(create_new_file));
	create_new_file.file_selected.connect(finish_create_new_file.bind(create_new_file));
	
	self.add_child(create_new_file);
	create_new_file.popup_centered();


func finish_create_new_file(file_path: String, dialog: FileDialog) -> void:
	var path = dialog.current_file;
	data.create_file(path);
	close_file_dialog(dialog);
	refresh_list_of_files();


func change_folder() -> void:
	var choose_new_file = FileDialog.new();
	choose_new_file.file_mode = FileDialog.FILE_MODE_OPEN_DIR;
	choose_new_file.access = FileDialog.ACCESS_FILESYSTEM;
	choose_new_file.current_dir = OS.get_executable_path();
	choose_new_file.close_requested.connect(close_file_dialog.bind(choose_new_file));
	choose_new_file.dir_selected.connect(finish_change_folder.bind(choose_new_file));
	
	self.add_child(choose_new_file);
	choose_new_file.popup_centered();


func close_file_dialog(dialog: FileDialog) -> void:
	dialog.get_parent().remove_child(dialog);
	dialog.hide();
	dialog.queue_free();


func finish_change_folder(dir: String, dialog: FileDialog) -> void:
	PersistentData.last_working_directory = dir;
	folder_change_util(dir)
	close_file_dialog(dialog);


func folder_change_util(path: String) -> void:
	cwd_info.show();
	key_select.show();
	file_info.show();
	key_info.show();
	$Main/Edit.show();
	
	
	data.scan_cwd(path);
	update_cwd_data_display();
	refresh_list_of_keys();
	refresh_list_of_files();
	update_localization_select();
	update_status();


func display_key_translations(key_idx: int) -> void:
	selected_key_idx = key_idx;
	selected_key = key_select.get_node(^"KeyList").get_item_text(key_idx);
	key_info.get_node(^"KeyEdit").text = selected_key;
	
	selected_key_data = data.get_key_data(selected_key);
	
	if localization_edit.get_node(^"Locale").selected != -1 \
		or localization_edit.get_node(^"OtherLocale").selected != -1:
			update_translation_data();


func update_translation_data(_idx: int = -1) -> void:
	update_localization_select();
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


func select_file(selected_idx: int) -> void:
	data.current_file_idx = selected_idx - 1;
	
	var key_count : Label = file_info.get_node(^"KeyCount");
	
	var file_selected = data.current_file_idx != -1;
	if file_selected:
		var filedata := data.get_file_data(data.current_file_idx);
		key_count.text = "keys: %d" % filedata.data.size();
	
	key_count.visible = file_selected;


func add_key() -> void:
	var new_key_name = key_info.get_node(^"KeyEdit").text;
	
	if new_key_name == "" or key_lookup.has(new_key_name):
		return;
	
	var change_result = data.add_new_key(new_key_name);
	if change_result == OK:
		selected_key = new_key_name;
		refresh_list_of_keys();


func rename_key() -> void:
	var new_key_name = key_info.get_node(^"KeyEdit").text;
	var old_key_name = selected_key;
	
	if new_key_name == "" or new_key_name == old_key_name:
		return;
	
	var change_result = data.rename_key(old_key_name, new_key_name);
	if change_result == OK:
		selected_key = new_key_name;
		if selected_key_idx != -1:
			display_key_translations(selected_key_idx);
		update_key_files();


func add_locale() -> void:
	var locale_edit = $Main/LocaleInfo/LocaleEdit
	var new_locale = locale_edit.text;
	
	if data.current_file_idx == -1:
		return;
	
	if new_locale in data.get_file_data(data.current_file_idx).get_locales():
		return;
	
	var change_result = data.add_locale_to_file(new_locale);
	if change_result == OK:
		update_translation_data();
		update_key_files();
		locale_edit.text = "";


func open_userdata() -> void:
	OS.shell_open(ProjectSettings.globalize_path(FileData.BACKUP_LOCATION));


func save_data() -> void:
	data.save_changes();
