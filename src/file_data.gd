extends RefCounted
class_name FileData


## in-memory and disk data manipulation, saving and managing backups


const PH_LOC_PREFIX := "unknown_locale";
const FIRST_CELL_VALUE := "key";
const BACKUP_LOCATION := "user://backups";


var undo_methods : Dictionary[int, Callable] = {
	FileChange.FILE_CREATED: un_create_file,
	FileChange.FILE_DELETED: Callable(),
	FileChange.FILE_MOVED: Callable(),
	
	FileChange.NEW_KEY: un_add_key,
	FileChange.NEW_LOCALE: un_add_locale,
	
	FileChange.CHANGE_KEY: un_change_key,
	FileChange.CHANGE_VALUE: un_change_translation,
	FileChange.CHANGE_LOCALE: un_change_locale,
	
	FileChange.REMOVE_KEY: un_remove_key,
	FileChange.REMOVE_LOCALE: un_remove_locale,
}


var redo_methods : Dictionary[int, Callable] = {
	FileChange.FILE_CREATED: re_create_file,
	FileChange.FILE_DELETED: Callable(),
	FileChange.FILE_MOVED: Callable(),
	
	FileChange.NEW_KEY: re_add_key,
	FileChange.NEW_LOCALE: re_add_locale,
	
	FileChange.CHANGE_KEY: re_change_key,
	FileChange.CHANGE_VALUE: re_change_translation,
	FileChange.CHANGE_LOCALE: re_change_locale,
	
	FileChange.REMOVE_KEY: re_remove_key,
	FileChange.REMOVE_LOCALE: re_remove_locale,
}


## an absolute path to the file
var path : String;
var data : Dictionary[String, PackedStringArray];
var header : PackedStringArray;

var changes : Array[FileChange] = [];
var changes_position : int = 0;
var on_disk_position : int = 0;
var on_disk_data_hash : int = 0;

var marked_for_deletion : bool = false;
var marked_for_move : String = "";


static func check_changes_backup_exists(file_path: String) -> bool:
	if file_path == "":
		return false;
	
	if not DirAccess.dir_exists_absolute(BACKUP_LOCATION):
		DirAccess.make_dir_absolute(BACKUP_LOCATION);
	
	var dir_handle = DirAccess.open(BACKUP_LOCATION);
	if dir_handle == null:
		push_error("error when looking for backup directory (static): ", error_string(DirAccess.get_open_error()));
		return false;
	
	var files = dir_handle.get_files();
	for file in files:
		if get_backup_owner_path(file) == file_path:
			return true;
	
	return false;


static func get_backup_change_hash(backup_path: String) -> int:
	if not FileAccess.file_exists(backup_path):
		return 0;
	
	var file_handle = FileAccess.open(backup_path, FileAccess.READ);
	if file_handle == null:
		push_error("error when looking for backup file (static): ", error_string(FileAccess.get_open_error()));
		return 0;
	
	var file_header := file_handle.get_csv_line();
	file_handle.close();
	
	if file_header.size() <= 2 or not file_header[2].is_valid_int():
		return 0;
	
	return int(file_header[2]);


static func get_backup_owner_path(backup_path: String) -> String:
	if not FileAccess.file_exists(backup_path):
		return "";
	
	var file_handle = FileAccess.open(backup_path, FileAccess.READ);
	if file_handle == null:
		push_error("error when looking for backup file (static): ", error_string(FileAccess.get_open_error()));
		return "";
	
	var file_header := file_handle.get_csv_line();
	file_handle.close();
	if file_header.size() == 0:
		return "";
	
	return file_header[0];


func get_backup_file_path() -> String:
	if not DirAccess.dir_exists_absolute(BACKUP_LOCATION):
		DirAccess.make_dir_absolute(BACKUP_LOCATION);
	
	var dir_handle = DirAccess.open(BACKUP_LOCATION);
	if dir_handle == null:
		push_error("error when looking for backup directory (%s): " % path, error_string(DirAccess.get_open_error()));
		return "";
	
	var files = dir_handle.get_files();
	for file in files:
		if get_backup_owner_path(file) == path and path != "":
			return file;
	
	# file not found, creating a new one
	var path_hash := "%s" % hash(path);
	if path_hash in files: # you won a lottery
		if not FileAccess.file_exists(get_backup_owner_path(path_hash)):
			# original backup onwer doesn't exist anymore, yoink
			OS.move_to_trash(BACKUP_LOCATION.path_join(path_hash));
			return BACKUP_LOCATION.path_join(path_hash);
		return BACKUP_LOCATION.path_join(make_filename_unique(path_hash, files));
	
	return BACKUP_LOCATION.path_join(path_hash);


func make_filename_unique(file : String, other_files : PackedStringArray) -> String:
	var temp_file_name := file;
	var fail_counter := 1;
	
	while temp_file_name in other_files:
		temp_file_name = file + "(%d)" % fail_counter;
		fail_counter += 1;
	
	return temp_file_name;


## backs up changes between on_disk_position and changes_position
func backup_changes() -> Error:
	var backup_path = get_backup_file_path();
	
	var changes_count = changes_position - on_disk_position;
	if changes_count <= 0: # nothing to backup, removing existing file.
		return DirAccess.remove_absolute(backup_path);
	
	var change_data = changes.slice(on_disk_position, changes_position);
	var change_data_hash = hash(change_data);
	
	if change_data_hash == get_backup_change_hash(backup_path): # backup already done, no need to rewrite
		return OK;
	
	var handle = FileAccess.open(backup_path, FileAccess.WRITE);
	if handle == null:
		push_error("error when saving backup file (%s): " % path, error_string(FileAccess.get_open_error()));
		return FileAccess.get_open_error();
	
	handle.store_csv_line(PackedStringArray([path, "%s" % on_disk_data_hash, "%s" % change_data_hash]));
	
	for i in range(on_disk_position, changes_position):
		var change := changes[i];
		var stored_array := PackedStringArray([change.type]);
		stored_array.append_array(change.data);
		handle.store_csv_line(stored_array);
	
	return handle.get_error();


## loads back up from disk and applies changes
func restore_changes() -> Error:
	var backup_path = get_backup_file_path();
	if not FileAccess.file_exists(backup_path): # no backup to load
		return OK;
	
	var handle = FileAccess.open(backup_path, FileAccess.READ);
	if handle == null:
		push_error("error when loading backup file (%s): " % path, error_string(FileAccess.get_open_error()));
		return FileAccess.get_open_error();
	
	var backup_header = handle.get_csv_line();
	var data_hash = backup_header[1];
	if not data_hash.is_valid_int() or int(data_hash) != hash(data):
		push_error("backup out of sync with file data (%s), truncating" % path);
		handle.close();
		changes_position = on_disk_position;
		backup_changes();
		return OK;
	
	while handle.get_position() < handle.get_length():
		var line = handle.get_csv_line();
		var change_type = int(line[0]);
		var change_data = line.slice(1);
		var change = FileChange.new(change_type, change_data);
		register_change(change);
	
	changes_position = on_disk_position;
	while redo() == OK:
		pass;
	
	return OK;


## returns null if the file exists already or when failed creating one
static func create_file(file_path: String) -> FileData:
	var file_data = FileData.new();
	file_data.path = file_path;
	
	if FileAccess.file_exists(file_path):
		return null;
	
	var handle = FileAccess.open(file_path, FileAccess.WRITE);
	if handle == null:
		push_error("error when creating new file (%s): " % file_path, error_string(FileAccess.get_open_error()));
		return null;
	
	var change = FileChange.new(FileChange.FILE_CREATED, PackedStringArray());
	file_data.register_change(change);
	
	return file_data;


func un_create_file(_change: FileChange) -> void:
	marked_for_deletion = true;


func re_create_file(_change: FileChange) -> void:
	marked_for_deletion = false;


static func open_at(file_path: String) -> FileData:
	var file_data = FileData.new();
	file_data.path = file_path;
	
	var handle = FileAccess.open(file_path, FileAccess.READ);
	if handle == null:
		push_error("error when opening file (%s): " % file_path, error_string(FileAccess.get_open_error()));
		return null;
	
	file_data.header = handle.get_csv_line().slice(1);
	
	while handle.get_position() < handle.get_length():
		var line = handle.get_csv_line();
		
		if line.size() == 0 or line[0] == "":
			continue;
		
		if line.size() < file_data.header.size():
			line.resize(file_data.header.size())
		
		file_data.data[line[0]] = line.slice(1);
	
	handle.close();
	file_data.restore_changes();
	
	return file_data;


func save_current() -> Error:
	if changes.is_empty() or on_disk_position == changes_position:
		return OK;
	
	if marked_for_deletion:
		return OS.move_to_trash(path);
	
	var handle = FileAccess.open(path, FileAccess.WRITE);
	if handle == null:
		push_error("error when opening file (%s): " % path, error_string(FileAccess.get_open_error()));
		return FileAccess.get_open_error();
	
	on_disk_position = changes_position;
	on_disk_data_hash = hash(data);
	
	var full_header := PackedStringArray([FIRST_CELL_VALUE]);
	full_header.append_array(header);
	handle.store_csv_line(full_header);
	
	for key in data:
		var full_line := PackedStringArray([key]);
		full_line.append_array(data[key]);
		full_line.resize(full_header.size());
		handle.store_csv_line(full_header);
	
	backup_changes();
	
	return handle.get_error();


func register_change(change: FileChange) -> void:
	changes.resize(changes_position + 1);
	changes[changes_position] = change;
	changes_position += 1;


## returns FAILED if at the top of changes stack
func redo() -> Error:
	if changes_position >= changes.size():
		return FAILED;
	
	var change = changes[changes_position];
	redo_methods[change.type].call(change);
	changes_position += 1;
	return OK;


## returns FAILED if at the bottom of changes stack
func undo() -> Error:
	if changes_position <= 0:
		return FAILED;
	
	changes_position -= 1;
	var change = changes[changes_position];
	undo_methods[change.type].call(change);
	return OK;


func get_locales() -> Array[String]:
	return Array(header, TYPE_STRING, &"", null);


func get_key_translations(key: String) -> Dictionary[String, String]:
	var dict : Dictionary[String, String] = {};
	var key_data = data.get(key, PackedStringArray());
	
	var placeholder_locale_n: int = 0;
	for idx in max(header.size(), key_data.size()):
		match idx:
			_ when idx >= header.size() or header[idx] == "": # missing locale code
				dict[PH_LOC_PREFIX + "" if placeholder_locale_n == 0 else "_%d" % placeholder_locale_n] = key_data[idx];
			_ when idx >= key_data.size(): # missing localization for a known locale
				dict[header[idx]] = "";
			_:
				dict[header[idx]] = key_data[idx];
	
	return dict;


func get_translation(key: String, locale: String) -> String:
	var locale_idx = header.find(locale);
	if locale_idx == -1:
		return "";
	return _get_translation_by_idx(key, locale_idx);


func _get_translation_by_idx(key: String, locale_idx: int) -> String:
	var translations = data.get(key, PackedStringArray());
	if locale_idx >= translations.size():
		return "";
	
	return translations[locale_idx];


## returns FAILED if locale not present in the filedata.
func change_translation(locale: String, key: String, new_value: String) -> Error:
	var old_value = get_translation(key, locale);
	if old_value == new_value:
		return OK;
	
	var locale_idx := header.find(locale);
	if locale_idx == -1:
		return FAILED;
	
	var change = FileChange.new(FileChange.CHANGE_VALUE, PackedStringArray([locale, key, old_value, new_value]));
	register_change(change);
	re_change_translation(change);
	
	return OK;


func un_change_translation(change: FileChange) -> void:
	var locale = change.data[0];
	var key = change.data[1];
	var old_value = change.data[2];
	
	var locale_idx := header.find(locale);
	var translations = data[key];
	
	translations[locale_idx] = old_value;


func re_change_translation(change: FileChange) -> void:
	var locale = change.data[0];
	var key = change.data[1];
	var new_value = change.data[3];
	
	var locale_idx := header.find(locale);
	
	var translations : PackedStringArray = data.get(key, PackedStringArray());
	if translations.size() <= locale_idx:
		translations.resize(locale_idx + 1);
	
	translations[locale_idx] = new_value;


func change_key(old_key: String, new_key: String) -> void:
	if old_key == new_key:
		return;
	
	var change = FileChange.new(FileChange.CHANGE_KEY, PackedStringArray([old_key, new_key]));
	register_change(change);
	
	_change_key_util(old_key, new_key);


func un_change_key(change: FileChange) -> void:
	var old_key = change.data[0];
	var new_key = change.data[1];
	
	_change_key_util(new_key, old_key);


func re_change_key(change: FileChange) -> void:
	var old_key = change.data[0];
	var new_key = change.data[1];
	
	_change_key_util(old_key, new_key);


func _change_key_util(from: String, to: String) -> void:
	var translations = data.get(from, PackedStringArray());
	data[to] = translations;
	data.erase(from);


## returns FAILED if key is already present
func add_key(key: String) -> Error:
	if data.has(key):
		return FAILED;
	
	var change = FileChange.new(FileChange.NEW_KEY, PackedStringArray([key]));
	register_change(change);
	
	data[key] = PackedStringArray();
	
	return OK;


func un_add_key(change: FileChange) -> void:
	var key = change.data[0];
	data.erase(key);


func re_add_key(change: FileChange) -> void:
	var key = change.data[0];
	data[key] = PackedStringArray();


## returns FAILED if key has non-empty value fields
func remove_key(key: String) -> Error:
	if not data.has(key):
		return OK;
	
	var translations := data[key];
	for s in translations: # <=> .any(func(s): return s != "")
		if s != "":
			return FAILED;
	
	var change = FileChange.new(FileChange.REMOVE_KEY, PackedStringArray([key]));
	register_change(change);
	
	data.erase(key);
	return OK;


func un_remove_key(change: FileChange) -> void:
	var key = change.data[0];
	data[key] = PackedStringArray();


func re_remove_key(change: FileChange) -> void:
	var key = change.data[0];
	data.erase(key);


## returns FAILED id the file already has this locale
func add_locale(locale: String) -> Error:
	if header.has(locale):
		return FAILED;
	
	var change = FileChange.new(FileChange.NEW_LOCALE, PackedStringArray([locale]));
	register_change(change);
	header.push_back(locale);
	
	return OK;


func un_add_locale(change: FileChange) -> void:
	var locale = change.data[0];
	header.remove_at(header.find(locale));


func re_add_locale(change: FileChange) -> void:
	var locale = change.data[0];
	header.push_back(locale);


## returns ERR_INVALID_DATA if removed locale has associated non "" keys [br]
## returns ERR_DOES_NOT_EXIST if locale is not present
func remove_locale(locale: String) -> Error:
	var locale_idx = header.find(locale);
	if locale_idx == -1:
		return ERR_DOES_NOT_EXIST;
	
	for key in data:
		if _get_translation_by_idx(key, locale_idx) != "":
			return ERR_INVALID_DATA;
	
	var change := FileChange.new(FileChange.REMOVE_LOCALE, PackedStringArray([locale]));
	register_change(change);
	re_remove_locale(change);
	
	return OK;


func un_remove_locale(change: FileChange) -> void:
	var locale = change.data[0];
	header.push_back(locale);


func re_remove_locale(change: FileChange) -> void:
	var locale = change.data[0];
	var locale_idx = header.find(locale);
	
	for key in data:
		data[key].remove_at(locale_idx);
	
	header.remove_at(locale_idx);


## returns FAILED if "from" is not in the file header
func change_locale(from: String, to: String) -> Error:
	var locale_idx = header.find(from);
	if locale_idx == -1:
		return FAILED;
	
	var change := FileChange.new(FileChange.CHANGE_LOCALE, PackedStringArray([from, to]));
	register_change(change);
	header[locale_idx] = to;
	
	return OK;


func un_change_locale(change: FileChange) -> void:
	var from = change.data[0];
	var to = change.data[1];
	
	var locale_idx = header.find(to);
	header[locale_idx] = from;


func re_change_locale(change: FileChange) -> void:
	var from = change.data[0];
	var to = change.data[1];
	
	var locale_idx = header.find(from);
	header[locale_idx] = to;


func delete_file(_change: FileChange) -> Error:
	return OK;


func move_file(_change: FileChange) -> Error:
	return OK;
