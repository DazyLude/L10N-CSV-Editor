extends RefCounted
class_name FileData


const PH_LOC_PREFIX := "unknown_locale";
const FIRST_CELL_VALUE := "key";
var undo_methods : Dictionary[int, Callable] = {
	FileChange.FILE_CREATED: Callable(),
	FileChange.FILE_DELETED: Callable(),
	FileChange.FILE_MOVED: Callable(),
	
	FileChange.NEW_KEY: un_add_key,
	FileChange.NEW_LOCALE: Callable(),
	
	FileChange.CHANGE_KEY: un_change_key,
	FileChange.CHANGE_VALUE: un_change_translation,
	
	FileChange.REMOVE_KEY: Callable(),
	FileChange.REMOVE_LOCALE: Callable(),
}
var redo_methods : Dictionary[int, Callable] = {
	FileChange.FILE_CREATED: Callable(),
	FileChange.FILE_DELETED: Callable(),
	FileChange.FILE_MOVED: Callable(),
	
	FileChange.NEW_KEY: re_add_key,
	FileChange.NEW_LOCALE: Callable(),
	
	FileChange.CHANGE_KEY: re_change_key,
	FileChange.CHANGE_VALUE: re_change_translation,
	
	FileChange.REMOVE_KEY: Callable(),
	FileChange.REMOVE_LOCALE: Callable(),
}


var path : String;
var data : Dictionary[String, PackedStringArray];
var header : PackedStringArray;

var changes : Array[FileChange] = [];
var changes_position : int = 0;

var marked_for_deletion : bool = false;
var marked_for_move : String = "";


static func open_at(path: String) -> FileData:
	var file_data = FileData.new();
	file_data.path = path;
	
	var handle = FileAccess.open(path, FileAccess.READ);
	if handle == null:
		push_error("error when opening file (%s): " % path, error_string(handle.get_open_error()));
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
	return file_data;


func save_current() -> Error:
	if changes.is_empty():
		return OK;
	
	var handle = FileAccess.open(path, FileAccess.WRITE);
	if handle == null:
		push_error("error when opening file (%s): " % path, error_string(handle.get_open_error()));
		return FileAccess.get_open_error();
	
	var full_header := PackedStringArray([FIRST_CELL_VALUE]);
	full_header.append_array(header);
	handle.store_csv_line(full_header);
	
	for key in data:
		var full_line := PackedStringArray([key]);
		full_line.append_array(data[key]);
		full_line.resize(full_header.size());
		handle.store_csv_line(full_header);
	
	return handle.get_error();


func register_change(change: FileChange) -> void:
	changes.resize(changes_position);
	changes.push_back(change);
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


func get_key_translations(key: String) -> Dictionary[String, String]:
	var dict : Dictionary[String, String] = {};
	var key_data = data.get(key, PackedStringArray());
	
	var placeholder_locale_n: int = 0;
	for idx in max(header.size(), key_data.size()):
		match idx:
			_ when idx >= header.size(): # missing locale code
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
	
	var translations = data.get(key, PackedStringArray());
	if locale_idx >= translations.size():
		return "";
	
	return translations[locale_idx];


## returns FAILED if locale not present in the filedata.
func change_translation(key: String, locale: String, new_value: String) -> Error:
	var old_value = get_translation(key, locale);
	if old_value == new_value:
		return OK;
	
	var locale_idx := header.find(locale);
	if locale_idx == -1:
		return FAILED;
	
	var change = FileChange.new(FileChange.CHANGE_VALUE, PackedStringArray([locale, key, old_value, new_value]));
	register_change(change);
	
	var translations : PackedStringArray = data.get(key, PackedStringArray());
	if translations.size() <= locale_idx:
		translations.resize(locale_idx + 1);
	
	translations[locale_idx] = new_value;
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
	var translations = data[key];
	
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
	
	var translations = data[key]
	
	
	return OK;


func add_locale() -> void:
	pass;


func remove_locale() -> void:
	pass;


func create_file() -> void:
	pass;


func delete_file() -> void:
	pass;


class FileChange extends RefCounted:
	enum {
		FILE_CREATED,
		FILE_DELETED,
		FILE_MOVED,
		
		NEW_KEY,
		NEW_LOCALE,
		
		CHANGE_KEY,
		CHANGE_VALUE,
		
		REMOVE_KEY,
		REMOVE_LOCALE,
	}
	
	var type: int;
	var data : PackedStringArray;
	
	
	func _init(type_i: int, data_i: PackedStringArray) -> void:
		type = type_i;
		data = data_i;
