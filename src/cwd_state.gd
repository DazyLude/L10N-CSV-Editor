extends RefCounted
class_name CWDState


## cwd path
var cwd_handle : DirAccess;
## paths to csv files located in cwd
var cwd_files : PackedStringArray = [];

#region cwd data
## idx of a "current" file
var current_file_idx : int = -1;
## uniques localization keys
var localizations : Dictionary[String, LocaleData] = {};
## unique string keys and paths to the files they're located in.
var keys : Dictionary[String, KeyData] = {};
## non unique string key file paths
var non_unique_keys : Dictionary[String, NonUniqueKeyData] = {};
#endregion

#region Data Manipulation
## in-memory representation of open files and their data
var table_data : Dictionary[int, FileData];
var change_stack : Array[int];
var change_stack_position : int;
#endregion


func open_file(file_idx: int) -> void:
	table_data[file_idx] = FileData.open_at(cwd_files[file_idx]);


func save_file(file_idx: int) -> void:
	table_data[file_idx].save_current();


func get_file_data(file_idx: int) -> FileData:
	if table_data.has(file_idx):
		return table_data[file_idx];
	
	open_file(file_idx);
	return table_data[file_idx];


func register_change(file_idx: int) -> void:
	change_stack.push_back(file_idx);


func get_key_data(key: String) -> Dictionary[String, String]:
	var key_data : KeyData = keys.get(key, null);
	var result : Dictionary[String, String] = {};
	if key_data == null:
		return result;
	
	if key_data.file_idx != -1:
		var file_data := get_file_data(key_data.file_idx);
		if file_data != null:
			return file_data.get_key_translations(key);
	else: # key is not contained in a single file
		for file_idx in non_unique_keys[key].file_idxs:
			var file_data := get_file_data(key_data.file_idx);
			if file_data != null:
				result.merge(file_data.get_key_translations(key));
	
	return result;


func scan_cwd(path: String) -> void:
	cwd_handle = DirAccess.open(path);
	if cwd_handle == null:
		push_error("error when opening directory:", error_string(DirAccess.get_open_error()));
		return;
	
	cwd_files = get_csv_files_recursively(cwd_handle);
	update_cwd_data();


func update_cwd_data() -> void:
	clear_cwd_data();
	for file in cwd_files:
		scan_file_contents(file);


func scan_file_contents(path: String) -> void:
	var file_handle := FileAccess.open(path, FileAccess.READ);
	if file_handle == null:
		push_error("error when opening file (%s): " % path, error_string(FileAccess.get_open_error()));
		return;
	
	var header := file_handle.get_csv_line();
	
	if header.size() == 0:
		push_warning("malformed header: empty (%s). Assuming not a localization file." % path);
		return;
	
	var comment_columns : Array[int] = [];
	for locale_idx in range(1, header.size()):
		var locale_key := header[locale_idx];
		if locale_key == "":
			push_warning("malformed header: locale field empty (%s)" % path);
			continue;
		
		if locale_key.match("_*"):
			comment_columns.push_back(locale_idx);
			continue;
		
		register_locale(locale_key, path);
	
	var file_idx = cwd_files.find(path);
	var file_localization_count = header.size() - 1 - comment_columns.size();
	while file_handle.get_position() < file_handle.get_length():
		var line := file_handle.get_csv_line();
		if line.size() == 0 or line[0] == "":
			continue;
		register_key(line, file_localization_count, file_idx, comment_columns);


func register_locale(locale: String, file: String) -> void:
	if localizations.has(locale):
		localizations[locale].missing_files.erase(file);
	else:
		localizations[locale] = LocaleData.new();
		localizations[locale].missing_files = Array(Array(cwd_files), TYPE_STRING, &"", null);
		localizations[locale].missing_files.erase(file);


func register_key(line: PackedStringArray, localization_count: int, file_idx: int, comment_columns: Array[int]) -> void:
	var key = line[0];
	for column_idx in comment_columns:
		pass;
	
	var empty_comments : int = 0;
	for comment_idx in comment_columns:
		if line[comment_idx] == "":
			empty_comments += 1;
	
	var empty_localizations = line.count("") - empty_comments;
	
	if non_unique_keys.has(key):
		var non_unique_data := non_unique_keys[key];
		non_unique_data.file_idxs.push_back(file_idx);
		non_unique_data.localization_count += localization_count - empty_localizations;
		return;
	
	if keys.has(key):
		var old_data = keys[key];
		var non_unique_data = NonUniqueKeyData.new();
		non_unique_data.file_idxs.push_back(old_data.file_idx);
		non_unique_data.file_idxs.push_back(file_idx);
		non_unique_data.localization_count += old_data.localization_count;
		non_unique_data.localization_count += localization_count - empty_localizations;
		non_unique_keys[key] = non_unique_data;
		
		old_data.file_idx = -1;
		return;
	
	var data = KeyData.new();
	data.file_idx = file_idx;
	data.localization_count = localization_count - empty_localizations;
	keys[key] = data;
	return;


func clear_cwd_data() -> void:
	current_file_idx = -1;
	keys.clear();
	localizations.clear();
	non_unique_keys.clear();


func get_csv_files_recursively(handle: DirAccess) -> PackedStringArray:
	var files := Array(handle.get_files());
	files = files.filter(csv_filter_predicate).map(handle.get_current_dir().path_join);
	var unprocessed_directories := Array(handle.get_directories());
	
	while unprocessed_directories.size() > 0:
		var processing : String = unprocessed_directories.pop_back();
		var processing_path := handle.get_current_dir().path_join(processing);
		var processing_handle := DirAccess.open(processing_path);
		if processing_handle == null:
			push_error("error when opening directory (%s): " % processing_path, error_string(DirAccess.get_open_error()));
			continue;
		
		var new_files := Array(processing_handle.get_files());
		new_files = new_files.filter(csv_filter_predicate).map(processing_path.path_join);
		files.append_array(new_files);
		
		var new_directories := Array(processing_handle.get_directories());
		new_directories = new_directories.map(processing.path_join);
		unprocessed_directories.append_array(new_directories);
	
	return PackedStringArray(files);


func csv_filter_predicate(file_name: String) -> bool:
	return file_name.get_extension() == "csv";


class KeyData extends RefCounted:
	var file_idx : int;
	var localization_count : int;


class NonUniqueKeyData extends RefCounted:
	var file_idxs : PackedInt64Array;
	var localization_count : int;


class LocaleData extends RefCounted:
	var key_count : int;
	var missing_files : Array[String];
