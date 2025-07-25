extends RefCounted
class_name CWDState


const SESSION_DATA_PATH := "user://session.csv";

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
var empty_localizations : Dictionary[int, int];
#endregion

#region Data Manipulation
## in-memory representation of open files and their data
var table_data : Dictionary[int, FileData];
var changes : Array[CompositeChange];
var changes_position : int;
#endregion


func open_file(file_idx: int) -> void:
	table_data[file_idx] = FileData.open_at(cwd_files[file_idx]);


func create_file(file_path: String) -> void:
	if file_path in cwd_files:
		return;
	
	var full_path = cwd_handle.get_current_dir().path_join(file_path);
	cwd_files.push_back(full_path);
	table_data[cwd_files.size() - 1] = FileData.create_file(full_path);


func save_file(file_idx: int) -> void:
	table_data[file_idx].save_current();


func get_file_data(file_idx: int) -> FileData:
	if table_data.has(file_idx):
		return table_data[file_idx];
	
	open_file(file_idx);
	return table_data[file_idx];


func register_change(change: CompositeChange) -> void:
	changes.resize(changes_position + 1);
	changes[changes_position] = change;
	changes_position += 1;


## returns FAILED if at the top of changes stack, otherwise returns a String
func redo() -> Variant:
	if changes_position >= changes.size():
		return FAILED;
	
	var change = changes[changes_position];
	
	#redo
	for file_idx in change.changes:
		var file_data = get_file_data(file_idx);
		for _i in range(change.changes[file_idx]):
			if file_data.redo() != OK:
				push_error("less redoable actions than expected");
				break; # will fail only if undo stack bottom is reached (in theory)
	
	changes_position += 1;
	return change.editor_meta;


## returns FAILED if at the bottom of changes stack, otherwise returns a String
func undo() -> Variant:
	if changes_position <= 0:
		return FAILED;
	
	changes_position -= 1;
	var change = changes[changes_position];
	
	#undo
	return undo_temp(change);


## returns a String if undo was successful, otherwise returns FAILED
func undo_temp(change: CompositeChange) -> Variant:
	for file_idx in change.changes:
		var file_data = get_file_data(file_idx);
		for _i in range(change.changes[file_idx]):
			if file_data.undo() != OK:
				push_error("less undoable actions than expected in filedata for %s" % cwd_files[file_idx]);
				break; # will fail only if undo stack bottom is reached (in theory)
	
	return change.editor_meta;


func backup_changes() -> void:
	for file_data in table_data.values().filter(func(v): return v != null):
		file_data.backup_changes();


func restore_backup() -> void:
	for file_idx in table_data.keys().filter(func(v): return table_data[v] != null):
		var path = table_data[file_idx].path;
		table_data.erase(file_idx);
		table_data[file_idx] = FileData.open_at(path);
		table_data[file_idx].restore_changes();


func save_changes() -> void:
	for file_data in table_data.values().filter(func(v): return v != null):
		file_data.save_current();


## adds localization key to the currently opened file [br]
## returns FAILED if key already exists [br]
## returns ERR_INVALID_DATA if no files are open currently [br]
func add_new_key(key: String) -> Error:
	if current_file_idx == -1:
		return ERR_INVALID_DATA;
	
	if keys.has(key):
		return FAILED;
	
	var file_data = get_file_data(current_file_idx);
	if file_data.add_key(key) != OK:
		push_error("key was not registered, but was present in the current file");
		return FAILED;
	
	register_change(CompositeChange.create_new(current_file_idx, key));
	
	register_key(PackedStringArray([key]), 0, current_file_idx, []);
	
	return OK;


## renames the key in the existing files.
## returns ERR_INVALID_DATA if key doesn't exist or new key name corresponds with another key 
## returns FAILED if any of the file_data changes fail
func rename_key(from: String, to: String) -> Error:
	if not keys.has(from) or keys.has(to):
		return ERR_INVALID_DATA;
	
	if from == to:
		return OK;
	
	var key_data = keys[from];
	var change = CompositeChange.new("");
	
	var files = [key_data.file_idx] if key_data.file_idx != -1 else non_unique_keys[from].file_idxs;
	for file in files:
		var file_data = get_file_data(file);
		if file_data.change_key(from, to) != OK:
			push_error("Failed to change key from %s to %s" % [from, to]);
			undo_temp(change);
			return FAILED;
		change.add(file);
	
	keys[to] = key_data;
	keys.erase(from);
	
	register_change(change);
	return OK;


## edits key in a file if it already exists (is not "" or file with key+locale combination exists)
## returns ERR_INVALID_DATA if key is one of the keys that have possible key collisions.
## returns ERR_CANT_RESOLVE if a file with key+locale doesn't exist.
## returns FAILED if file_data method failed for whatever reason
func change_translation(key: String, locale: String, new_value: String) -> Error:
	if possible_collisions.has(key):
		return ERR_INVALID_DATA;
	
	var locale_data := localizations[locale];
	var file_idx := keys[key].file_idx;
	
	if file_idx == -1: # scan containing files and get one with locale present
		var file_idxs := non_unique_keys[key].file_idxs;
		for i_file_idx in file_idxs:
			if locale_data.found_in.has(i_file_idx):
				file_idx = i_file_idx;
				break;
	
	if not locale_data.found_in.has(file_idx):
		return ERR_CANT_RESOLVE;
	
	var file := get_file_data(file_idx);
	var old_value = file.get_translation(key, locale);
	
	if old_value == new_value:
		return OK;
	
	var change_result = file.change_translation(locale, key, new_value);
	
	if change_result != OK:
		push_error("error when changing translation: %s" % error_string(change_result));
		return FAILED;
	
	if (new_value == "") != (old_value == ""):
		keys[key].localization_count += 1 if old_value == "" else -1;
	
	var change := CompositeChange.create_new(file_idx, key);
	register_change(change);
	
	return OK;


## moves key and it's values to new files, removing it from the old ones
## returns ERR_INVALID_DATA if selected files can cause key collision
## returns ERR_CANT_RESOLVE if new files don't have locales for all non "" translations
## returns FAILED if any of the file data methods failed for whatever reason
func move_key_to_files(key: String, files: Array[int]) -> Error:
	var new_locales = get_files_localizations(files);
	
	if get_files_localizations(files).values().any(func(c): return c > 1):
		return ERR_INVALID_DATA;
	
	var existing_translations = get_key_data(key);
	var non_empty_translations = existing_translations.keys().filter(
		func(k): return existing_translations[k] != ""
	);
	
	if not non_empty_translations.all(func(l): return new_locales.has(l)):
		return ERR_CANT_RESOLVE;
	
	# step 1: remove key from old files, which are not within files argument
	var change = CompositeChange.new(key);
	
	var old_files : Array[int] = Array(
		[keys[key].file_idx] if keys[key].file_idx != -1 else non_unique_keys[key].file_idxs,
		TYPE_INT, &"", null
	);
	
	var remove_from = old_files.filter(func(file): return not files.has(file));
	
	for file_idx in remove_from:
		var file_data = get_file_data(file_idx);
		for locale in file_data.get_key_translations(key):
			if file_data.change_translation(locale, key, "") != OK: # change all translations to ""
				push_error("failed removing translation when moving key to files: %s, %s" % [key, files]);
				undo_temp(change);
				return FAILED; # I hope they'll add try catch one day
			change.add(file_idx);
		
		if file_data.remove_key(key) != OK: # remove key from file
			push_error("failed removing key when moving key to files: %s, %s" % [key, files]);
			undo_temp(change);
			return FAILED;
		change.add(file_idx);
	
	# step 2: add key to the "totally new" files
	var add_to = files.filter(func(file): return not old_files.has(file));
	
	for file_idx in add_to:
		var file_data = get_file_data(file_idx);
		if file_data.add_key(key) != OK: # remove key from file
			push_error("failed adding key when moving key to files: %s, %s" % [key, files]);
			undo_temp(change);
			return FAILED;
		change.add(file_idx);
	
	# step 3: set key values as existing translations
	for file_idx in files:
		var file_data = get_file_data(file_idx);
		for locale in file_data.get_locales():
			if file_data.change_translation(locale, key, existing_translations.get(locale, "")) != OK: # remove key from file
				push_error("failed adding key when moving key to files: %s, %s" % [key, files]);
				undo_temp(change);
				return FAILED;
	
	if files.size() == 1:
		keys[key].file_idx = files[0];
	else:
		keys[key].file_idx = -1;
		non_unique_keys.get_or_add(key, NonUniqueKeyData.new()).file_idxs = PackedInt64Array(files);
	
	return OK;


## adds locale to currently selected file
func add_locale_to_file(locale: String) -> Error:
	if current_file_idx == -1:
		return ERR_CANT_RESOLVE;
	
	var file_data := get_file_data(current_file_idx);
	if file_data.add_locale(locale) != OK:
		push_error("failed adding locale to file: %s, %s" % [locale, file_data.path]);
		return FAILED;
	
	if locale.begins_with("_"):
		register_comment(locale, current_file_idx);
	else:
		register_locale(locale, current_file_idx);
	
	register_change(CompositeChange.create_new(current_file_idx, ""));
	return OK;


## returns dictionary of [locale]: count for a given list of files. [br]
## example: file a.csv has en and cn locales, file b.csv has en and ru locales.
## When passing [{idx of "a.csv"}, {idx of "b.csv"}] as an argument, method will return {"en": 2, "ru": 1, "cn": 1} 
func get_files_localizations(files: Array[int]) -> Dictionary[String, int]:
	var result : Dictionary[String, int] = {};
	
	for locale in localizations:
		var l10n_data = localizations[locale];
		result[locale] = files.reduce(
			func(accum, file_idx): return accum + (1 if l10n_data.found_in.has(file_idx) else 0),
			0
		);
	
	for locale in result.keys().filter(func(l): return result[l] == 0):
		result.erase(locale);
	
	return result;


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


func get_key_files(key: String) -> Array[int]:
	if not key in keys:
		return Array([], TYPE_INT, &"", null);
	
	var key_data = keys[key];
	if key_data.file_idx != -1:
		return Array([key_data.file_idx], TYPE_INT, &"", null);
	
	return Array(non_unique_keys[key].file_idxs, TYPE_INT, &"", null);


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
	
	var locales := data.get_locales();
	var comment_columns : Array[int] = [];
	for locale_idx in locales.size():
		var locale_key := locales[locale_idx];
		if locale_key == "":
			empty_localizations[file_idx] = empty_localizations.get(file_idx, 0) + 1; 
			push_warning("malformed header: locale field empty (%s)" % path);
			continue;
		
		if locale_key.match("_*"):
			register_comment(locale_key, file_idx);
			comment_columns.push_back(locale_idx);
			continue;
		
		register_locale(locale_key, file_idx);
	
	var file_localization_count = locales.size() - 1 - comment_columns.size();
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
			empty_localizations[file_idx] = empty_localizations.get(file_idx, 0) + 1;
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
	
	for key in non_unique_keys:
		var files := non_unique_keys[key].file_idxs;
		files.sort();
		
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
	var editor_meta : String = "";
	
	
	func _init(meta: String) -> void:
		editor_meta = meta;
	
	
	static func create_new(file_idx: int, editor_meta: String) -> CompositeChange:
		var change = CompositeChange.new(editor_meta);
		change.changes[file_idx] = 1;
		return change;
	
	
	func add(file_idx: int) -> void:
		changes[file_idx] = changes.get(file_idx, 0) + 1;
