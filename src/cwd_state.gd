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
var comments : Dictionary[String, LocaleData] = {};
## unique string keys and paths to the files they're located in.
var keys : Dictionary[String, KeyData] = {};
## non unique string key file paths
var non_unique_keys : Dictionary[String, NonUniqueKeyData] = {};
## list of keys with possible key collisions, aka multiple files containing key + locale combination.
var possible_collisions : Dictionary[String, PackedInt64Array] = {};
#endregion

#region Data Manipulation
## in-memory representation of open files and their data
var table_data : Dictionary[int, FileData];
var change_stack : Array[CompositeChange];
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


func register_change(change: CompositeChange) -> void:
	change_stack.push_back(change);


## adds localization key to the currently opened file [br]
## returns FAILED if key already exists [br]
## returns ERR_INVALID_DATA if no files are open currently [br]
func add_new_key(key: String) -> Error:
	if current_file_idx == -1:
		return ERR_INVALID_DATA;
	
	if keys.has(key):
		return FAILED;
	
	register_key(PackedStringArray(), 0, current_file_idx, []);
	var file_data = get_file_data(current_file_idx);
	if file_data.add_key(key) != OK:
		printerr("key was not registered, but was present in the current file");
		return FAILED;
	
	register_change(CompositeChange.create_new(current_file_idx));
	
	return OK;


## edits key in a file if it already exists (is not "" or file with key+locale combination exists)
## returns ERR_INVALID_DATA if key is one of the keys that have possible key collisions.
## returns ERR_CANT_RESOLVE if a file with key+locale doesn't exist.
func change_translation(key: String, new_value: String) -> Error:
	return OK;


## moves key and it's values to new files, removing it from the old ones
## returns ERR_INVALID_DATA if selected files can cause key collision
func move_key_to_files(key: String, files: Array[int]) -> Error:
	return OK;


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
	check_for_possible_collisions();


func update_cwd_data() -> void:
	clear_cwd_data();
	for file in cwd_files:
		scan_file_contents(file);


func scan_file_contents(path: String) -> void:
	if FileData.check_changes_backup_exists(path):
		scan_open_file_data(path);
	else:
		scan_on_disk_data(path);


func scan_open_file_data(path: String) -> void:
	var file_idx := cwd_files.find(path);
	var data := get_file_data(file_idx);
	
	var header := data.header;
	var comment_columns : Array[int] = [];
	for locale_idx in range(1, header.size()):
		var locale_key := header[locale_idx];
		if locale_key == "":
			push_warning("malformed header: locale field empty (%s)" % path);
			continue;
		
		if locale_key.match("_*"):
			register_comment(locale_key, file_idx);
			comment_columns.push_back(locale_idx);
			continue;
		
		register_locale(locale_key, file_idx);
	
	var file_localization_count = header.size() - 1 - comment_columns.size();
	for key in data.data:
		var line = PackedStringArray([key]);
		line.append_array(data.data[key]);
		register_key(line, file_localization_count, file_idx, comment_columns);


func scan_on_disk_data(path: String) -> void:
	var file_handle := FileAccess.open(path, FileAccess.READ);
	var file_idx = cwd_files.find(path);
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
			register_comment(locale_key, file_idx);
			comment_columns.push_back(locale_idx);
			continue;
		
		register_locale(locale_key, file_idx);
	
	var file_localization_count = header.size() - 1 - comment_columns.size();
	while file_handle.get_position() < file_handle.get_length():
		var line := file_handle.get_csv_line();
		if line.size() == 0 or line[0] == "":
			continue;
		register_key(line, file_localization_count, file_idx, comment_columns);


func register_locale(locale: String, file_idx: int) -> void:
	localizations.get_or_add(locale, LocaleData.new()).found_in.push_back(file_idx);


func register_comment(comment: String, file_idx: int) -> void:
	comments.get_or_add(comment, LocaleData.new()).found_in.push_back(file_idx);


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


func check_for_possible_collisions() -> void:
	possible_collisions.clear();
	
	for key in non_unique_keys:
		var files := non_unique_keys[key].file_idxs;
		for locale in localizations:
			var found_in := localizations[locale].found_in;
			var key_loc_combination_found_in := found_in.filter(files.has); # files with key+loc combo
			if key_loc_combination_found_in.size() >= 2: # there is at least two identical key+loc pairs
				possible_collisions\
					.get_or_add(key, PackedInt64Array())\
					.append_array(
						PackedInt64Array([key_loc_combination_found_in])
					);
				possible_collisions[key].sort();


func get_single_file_dupes() -> Array[String]:
	var result : Array[String] = [];
	
	for key in possible_collisions:
		var files = possible_collisions[key];
		for idx in range(1, files.size()):
			if files[idx - 1] == files[idx]:
				result.push_back(key);
				break;
	
	return result;


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
	var found_in : Array[int];


class CompositeChange extends RefCounted:
	# [file idx] -> change_count
	var changes : Dictionary[int, int];
	
	
	static func create_new(file_idx: int) -> CompositeChange:
		var change = CompositeChange.new();
		change.changes[file_idx] = 1;
		return change;
	
	
	func add(file_idx: int) -> void:
		changes[file_idx] = changes.get(file_idx, 0) + 1;
