extends Control


var block_input : bool = false;
var data := CWDState.new();

## The following keywords can be used, separated by comma:[br]
## 1) key:{string} (used by default): filters keys by "globbing" with the provided string.[br]
##    Example: key:FOO and FOO produce the same result.[br]
## 2) case: turns case sensitive search on.[br]
##    Example: FOO,case will not match a key "fooBAR".[br]
## 3) file:{string} : limits the filter to files with matching names (paths). Works in a similar fashion to key matching.[br]
##    Example: file:menu,case will show keys only in the files that have "menu" in name.[br]
## [br]
## Different keywords combine multiplicatevely:
## file:FOO,key:CHUNGUS will show only keys containing CHUNGUS in files with FOO in their name.[br]
## Similar keywords combine additevely:
## key:FIZZ,key:BUZZ will display keys with FIZZ and/or BUZZ in them.[br]
## The comma (,) is a special symbol. To use it: don't.
var filter_data : FilterData = FilterData.new(data);


func _ready() -> void:
	PersistentData.load_fom_disk();
	if PersistentData.last_working_directory != "":
		data.scan_cwd(PersistentData.last_working_directory);
		update_cwd_data_display();
		refresh_list_of_keys();
	
	$Main/DirInfo/ChangeDirButton.pressed.connect(change_folder);
	$Main/KeySelect/KeyFilter.text_submitted.connect(on_filter_string_submit);


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			PersistentData.save();


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
	data.scan_cwd(dir);
	
	update_cwd_data_display();
	refresh_list_of_keys();
	
	cancel_change_folder(dialog);


class FilterData:
	var key_filters : Array[String] = [];
	var file_idxs : Array[int] = [];
	var is_case_sensitive : bool = false;
	var cwd_state_ref : CWDState = null;
	
	
	func _init(cwd_state_reference: CWDState) -> void:
		self.cwd_state_ref = cwd_state_reference;
	
	
	static func from_query(filter_query: String, data: CWDState) -> FilterData:
		var new_filter_data = FilterData.new(data);
		
		var filter_settings = filter_query.split(",", false);
		var file_filters : Array = [];
		
		for setting in filter_settings:
			match setting:
				_ when setting.begins_with("key:"):
					new_filter_data.key_filters.push_back("*%s*" % setting.trim_prefix("key:"));
				_ when setting.begins_with("file:"):
					file_filters.push_back("*%s*" % setting.trim_prefix("file:"));
				"case":
					new_filter_data.is_case_sensitive = true;
				_:
					new_filter_data.key_filters.push_back("*%s*" % setting);
		
		if not new_filter_data.is_case_sensitive:
			file_filters = file_filters.map(func(s: String): return s.to_lower());
			var cwd_files_temp = Array(data.cwd_files).map(func(s: String): return s.to_lower());
			var file_idxs_temp = file_filters\
				.map(cwd_files_temp.find)\
				.filter(func(idx: int): return idx != -1);
			new_filter_data.file_idxs = Array(file_idxs_temp, TYPE_INT, &"", null);
		else:
			var file_idxs_temp = file_filters\
				.map(data.cwd_files.find)\
				.filter(func(idx: int): return idx != -1);
			new_filter_data.file_idxs = Array(file_idxs_temp, TYPE_INT, &"", null);
		
		return new_filter_data;
	
	
	func matches(key: String) -> bool:
		var key_data : CWDState.KeyData = self.cwd_state_ref.keys.get(key, null);
		if key_data == null:
			push_error("invalid key in the key list: %s" % key);
			return false;
		
		if not file_idxs.is_empty():
			var file_chk : bool;
			
			if key_data.file_idx != -1:
				file_chk = file_idxs.has(key_data.file_idx);
			else:
				var actual_data = self.cwd_state_ref.non_unique_keys[key];
				file_chk = file_idxs.any(actual_data.file_idxs.has);
		
			if not file_chk:
				return false;
		
		if not key_filters.is_empty():
			if not key_filters.any(key.match if self.is_case_sensitive else key.matchn):
				return false;
		
		return true;
