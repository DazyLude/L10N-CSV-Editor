extends Control


var block_input : bool = false;
var data := CWDState.new();


var filter_data : FilterData = FilterData.new(data);

var selected_key : String;
var selected_key_data : Dictionary[String, String];


func _ready() -> void:
	PersistentData.load_fom_disk();
	if PersistentData.last_working_directory != "":
		folder_change_util(PersistentData.last_working_directory);
	
	$Main/DirInfo/ChangeDirButton.pressed.connect(change_folder);
	$Main/KeySelect/KeyFilter.text_submitted.connect(on_filter_string_submit);
	$Main/KeySelect/KeyList.item_selected.connect(display_key_translations);
	$Main/LocalizationInfo/Locale.item_selected.connect(update_translation);
	$Main/LocalizationInfo/OtherLocale.item_selected.connect(update_translation);
	$Main/KeyInfo/DisplayOther.toggled.connect(display_other);
	display_other($Main/KeyInfo/DisplayOther.is_pressed());


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			PersistentData.save();


func _shortcut_input(event: InputEvent) -> void:
	if event.is_action(&"ui_undo"):
		pass;
	
	if event.is_action(&"ui_redo"):
		pass;


func on_filter_string_submit(query: String) -> void:
	filter_data = FilterData.from_query(query, data);
	refresh_list_of_keys();


func update_cwd_data_display() -> void:
	$Main/DirInfo/DirName.text = data.cwd_handle.get_current_dir(true);
	$Main/CWDInfo/FileCount.text = "files found: %d" % data.cwd_files.size();
	$Main/CWDInfo/KeyCount.text = "total keys: %d" % data.keys.size();
	$Main/CWDInfo/UniqueL10Ns.text = "total l10ns: %d" % data.localizations.size();


func refresh_list_of_keys() -> void:
	$Main/KeySelect/KeyList.clear();
	for key in data.keys.keys().filter(filter_data.matches):
		$Main/KeySelect/KeyList.add_item(key);


func refresh_list_of_files() -> void:
	$Main/FileInfo/CurrentFile.clear();
	for file in data.cwd_files:
		$Main/FileInfo/CurrentFile.add_item(file);


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
	var dupes = data.get_single_file_dupes();
	if not dupes.is_empty():
		


func display_key_translations(key_idx: int) -> void:
	selected_key = $Main/KeySelect/KeyList.get_item_text(key_idx);
	selected_key_data = data.get_key_data(selected_key);
	
	if $Main/LocalizationInfo/Locale.selected != -1 or $Main/LocalizationInfo/OtherLocale.selected != -1:
		update_translation_data();


func update_translation_data(_idx: int = -1) -> void:
	update_translation();
	
	var locale_check = {};
	locale_check.merge(selected_key_data);
	locale_check.merge(data.localizations);
	
	if locale_check.keys().size() > data.localizations.keys().size():
		update_localization_select_with_key_data();
	elif $Main/LocalizationInfo/Locale.item_count > locale_check.keys().size():
		update_localization_select();


func update_translation(_idx: int = -1) -> void:
	var selected_main = $Main/LocalizationInfo/Locale.selected;
	if selected_main != -1:
		var locale = $Main/LocalizationInfo/Locale.get_item_text(selected_main);
		$Main/LocalizationInfo/Translation.text = selected_key_data.get(locale, "");
	
	var selected_other = $Main/LocalizationInfo/OtherLocale.selected;
	if selected_other != -1:
		var locale = $Main/LocalizationInfo/OtherLocale.get_item_text(selected_other);
		$Main/LocalizationInfo/OtherTranslation.text = selected_key_data.get(locale, "");


func update_localization_select() -> void:
	var temp_idx : int = $Main/LocalizationInfo/Locale.selected;
	var temp_idx_other : int = $Main/LocalizationInfo/OtherLocale.selected;
	
	$Main/LocalizationInfo/Locale.clear();
	$Main/LocalizationInfo/OtherLocale.clear();
	
	for locale in data.localizations:
		$Main/LocalizationInfo/Locale.add_item(locale);
		$Main/LocalizationInfo/OtherLocale.add_item(locale);
	
	if temp_idx < $Main/LocalizationInfo/Locale.item_count:
		$Main/LocalizationInfo/Locale.select(temp_idx);
	if temp_idx_other < $Main/LocalizationInfo/OtherLocale.item_count:
		$Main/LocalizationInfo/OtherLocale.select(temp_idx_other);


func update_localization_select_with_key_data() -> void:
	var temp_idx : int = $Main/LocalizationInfo/Locale.selected;
	var temp_idx_other : int = $Main/LocalizationInfo/OtherLocale.selected;
	
	$Main/LocalizationInfo/Locale.clear();
	$Main/LocalizationInfo/OtherLocale.clear();
	
	var locale_check = {};
	locale_check.merge(selected_key_data);
	locale_check.merge(data.localizations);
	
	for locale in locale_check.keys():
		$Main/LocalizationInfo/Locale.add_item(locale);
		$Main/LocalizationInfo/OtherLocale.add_item(locale);
	
	if temp_idx < $Main/LocalizationInfo/Locale.item_count:
		$Main/LocalizationInfo/Locale.select(temp_idx);
	if temp_idx_other < $Main/LocalizationInfo/OtherLocale.item_count:
		$Main/LocalizationInfo/OtherLocale.select(temp_idx_other);


func display_other(y: bool) -> void:
	$Main/LocalizationInfo/OtherLocale.visible = y;
	$Main/LocalizationInfo/OtherTranslation.visible = y;
