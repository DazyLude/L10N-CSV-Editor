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


enum {
	DIRECTORY_MENU_OPEN,
	DIRECTORY_MENU_OPEN_CACHE,
	DIRECTORY_MENU_CREATE_FILE,
	DIRECTORY_MENU_SAVE,
	DIRECTORY_MENU_RESTORE,
}


enum {
	LOCALIZATION_MENU_ADD_KEY,
	LOCALIZATION_MENU_ADD_LOCALE,
}


@onready
var cwd_info : Control = $Main/CWDInfo;
@onready
var key_select : Control = $Main/KeySelect;
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
	key_info.hide();
	$Main/Edit.hide();
	
	PersistentData.load_fom_disk();
	if PersistentData.last_working_directory != "":
		folder_change_util(PersistentData.last_working_directory);
	
	prepare_file_menu();
	prepare_localization_menu();
	
	key_select.get_node(^"KeyFilter").text_submitted.connect(on_filter_string_submit);
	key_select.get_node(^"KeyList").item_selected.connect(display_key_translations);
	key_select.get_node(^"KeyList").item_selected.connect(update_key_files);
	
	localization_edit.get_node(^"Locale").item_selected.connect(update_translation);
	localization_edit.get_node(^"OtherLocale").item_selected.connect(update_other_translation);
	
	localization_edit.get_node(^"Translation").focus_entered.connect(start_editing.bind(true));
	localization_edit.get_node(^"Translation").focus_exited.connect(edit_translation);
	localization_edit.get_node(^"OtherTranslation").focus_entered.connect(start_editing.bind(false));
	localization_edit.get_node(^"OtherTranslation").focus_exited.connect(edit_translation);
	
	$AddItem/GridContainer/FileSelect.item_selected.connect(select_file)
	
	var display_other_switch := $Main/Edit/Localization/DisplayOther;
	display_other_switch.toggled.connect(display_other);
	display_other(display_other_switch.is_pressed());
	
	$Main/KeyInfo/RenameKey.pressed.connect(rename_key);
	
	$Main/Edit/Files/FileList.multi_selected.connect(update_provided_locales);
	$Main/Edit/Files/Info/Apply.pressed.connect(apply_filechange);
	$Main/Edit/Files/Info/Reset.pressed.connect(update_provided_locales);


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_CRASH:
			PersistentData.save();
			data.backup_changes();


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


func prepare_localization_menu() -> void:
	var menu : PopupMenu = $Main/Menu/Localization;
	menu.clear(true);
	
	menu.add_item("add key", LOCALIZATION_MENU_ADD_KEY);
	menu.add_item("add locale", LOCALIZATION_MENU_ADD_LOCALE);
	
	menu.id_pressed.connect(handle_localization_menu);


func handle_localization_menu(idx: int) -> void:
	match idx:
		LOCALIZATION_MENU_ADD_KEY:
			spawn_confirmation_with_string_and_file_input("key", "new key name", add_key, Callable());
		LOCALIZATION_MENU_ADD_LOCALE:
			spawn_confirmation_with_string_and_file_input("locale", "new locale code", add_locale, Callable());


func prepare_file_menu() -> void:
	var menu : PopupMenu = $Main/Menu/Directory;
	menu.clear(true);
	
	menu.add_item("change working directory", DIRECTORY_MENU_OPEN);
	menu.add_item("create file", DIRECTORY_MENU_CREATE_FILE)
	menu.add_item("save changes", DIRECTORY_MENU_SAVE);
	menu.add_item("open cache directory", DIRECTORY_MENU_OPEN_CACHE);
	menu.add_item("restore session", DIRECTORY_MENU_RESTORE);
	
	menu.id_pressed.connect(handle_file_menu);


func handle_file_menu(idx: int) -> void:
	match idx:
		DIRECTORY_MENU_OPEN:
			change_folder()
		DIRECTORY_MENU_OPEN_CACHE:
			open_userdata()
		DIRECTORY_MENU_CREATE_FILE:
			create_new_file();
		DIRECTORY_MENU_SAVE:
			save_data()
		DIRECTORY_MENU_RESTORE:
			data.restore_backup();


func spawn_confirmation_with_string_and_file_input(
		item: String,
		placeholder: String,
		on_submit: Callable,
		on_cancel: Callable
	) -> void:
		var popup : ConfirmationDialog = $AddItem;
		var file_select : OptionButton = $AddItem/GridContainer/FileSelect;
		var item_label : Label = $AddItem/GridContainer/ItemLabel;
		var item_input : LineEdit = $AddItem/GridContainer/ItemInput;
		
		# cleanup
		item_input.text = "";
		
		for connection in popup.canceled.get_connections():
			popup.canceled.disconnect(connection["callable"]);
		
		for connection in popup.confirmed.get_connections():
			popup.confirmed.disconnect(connection["callable"]);
		
		# setup
		item_label.text = item;
		item_input.placeholder_text = placeholder;
		popup.title = "add %s" % item;
		file_select.select(data.current_file_idx);
		
		if not on_submit.is_null():
			popup.confirmed.connect(on_submit);
		if not on_cancel.is_null():
			popup.canceled.connect(on_cancel);
		
		popup.popup();


func spawn_notification(text: String) -> void:
	var noto : AcceptDialog = $Notification;
	
	noto.dialog_text = text;
	
	noto.popup();


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
	cwd_info.get_node(^"DirName").text = data.cwd_handle.get_current_dir(true);
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
	var popup_file_select : OptionButton = $AddItem/GridContainer/FileSelect;
	var file_list : ItemList = file_edit.get_node(^"FileList");
	file_list.clear();
	
	popup_file_select.add_item("not selected");
	for file in data.cwd_files:
		popup_file_select.add_item(file.get_file());
		file_list.add_item(file.get_file());
	
	if data.current_file_idx != -1:
		popup_file_select.select(data.current_file_idx);


func select_file(selected_idx: int) -> void:
	data.current_file_idx = selected_idx - 1;


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


func apply_filechange() -> void:
	var file_list : ItemList = file_edit.get_node(^"FileList");
	var selected_files := Array(file_list.get_selected_items());
	var selected_files_typed := Array(selected_files, TYPE_INT, &"", null);
	
	data.move_key_to_files(selected_key, selected_files_typed);
	
	if selected_key_idx != -1:
		update_localization_select();


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
	var locale : OptionButton = localization_edit.get_node(^"Locale");
	var other_locale : OptionButton = localization_edit.get_node(^"OtherLocale");
	
	var selected_locale_code := ""
	if locale.selected != -1:
		locale.get_item_text(locale.selected);
	var selected_other_code := "";
	if other_locale.selected != -1:
		other_locale.get_item_text(other_locale.selected);
	
	var temp_idx : int = locale.selected;
	var temp_idx_other : int = other_locale.selected;
	
	locale.clear();
	other_locale.clear();
	
	var locale_check = {};
	locale_check.merge(selected_key_data);
	
	var locales := locale_check.keys();
	
	for locale_key in locales:
		locale.add_item(locale_key);
		other_locale.add_item(locale_key);
	
	if selected_locale_code in locales:
		locale.select(locales.find(selected_locale_code));
	
	if selected_other_code in locales:
		other_locale.select(locales.find(selected_other_code));
	
	update_translation();
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


func add_key() -> void:
	var key_edit : LineEdit = $AddItem/GridContainer/ItemInput;
	var new_key_name = key_edit.text;
	
	if data.current_file_idx == -1:
		spawn_notification("couldn't add key: select a file");
		return;
	
	if new_key_name == "" or key_lookup.has(new_key_name):
		spawn_notification("couldn't add key: name exists or empty");
		return;
	
	var change_result = data.add_new_key(new_key_name);
	if change_result == OK:
		selected_key = new_key_name;
		refresh_list_of_keys();
	else:
		spawn_notification("couldn't add key: check logs");


func rename_key() -> void:
	var new_key_name = key_info.get_node(^"KeyEdit").text;
	var old_key_name = selected_key;
	
	if new_key_name == "" or new_key_name == old_key_name:
		spawn_notification("couldn't rename key: invalid name");
		return;
	
	var change_result = data.rename_key(old_key_name, new_key_name);
	if change_result == OK:
		selected_key = new_key_name;
		if selected_key_idx != -1:
			display_key_translations(selected_key_idx);
		update_key_files();
	else:
		match change_result:
			ERR_INVALID_DATA:
				spawn_notification("couldn't rename key: new name already taken, or old name doesn't exist");
			_, FAILED:
				spawn_notification("couldn't rename key");


func add_locale() -> void:
	var locale_edit : LineEdit = $AddItem/GridContainer/ItemInput;
	var new_locale = locale_edit.text;
	
	if data.current_file_idx == -1:
		spawn_notification("couldn't add locale: select a file");
		return;
	
	if new_locale in data.get_file_data(data.current_file_idx).get_locales():
		spawn_notification("couldn't add locale: locale already in the file");
		return;
	
	var change_result = data.add_locale_to_file(new_locale);
	if change_result == OK:
		update_translation_data();
		update_key_files();
		locale_edit.text = "";
	else:
		spawn_notification("couldn't add locale: check logs");


func open_userdata() -> void:
	OS.shell_open(ProjectSettings.globalize_path(FileData.BACKUP_LOCATION));


func save_data() -> void:
	data.save_changes();
