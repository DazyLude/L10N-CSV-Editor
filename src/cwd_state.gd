extends RefCounted
class_name CWDState


const PH_LOC_PREFIX := "unknown_locale";


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
var changes_stack : Array[FileChange] = [];
#endregion


func open_file(file_idx: int) -> void:
	pass;


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
	
	
	for locale_idx in range(1, header.size()):
		var locale_key := header[locale_idx];
		if locale_key == "":
			push_warning("malformed header: locale field empty (%s)" % path);
			continue;
		
		register_locale(locale_key, path);
	
	var file_idx = cwd_files.find(path);
	while file_handle.get_position() < file_handle.get_length():
		var line := file_handle.get_csv_line();
		if line.size() == 0 or line[0] == "":
			continue;
		register_key(line, header.size() - 1, file_idx);


func register_locale(locale: String, file: String) -> void:
	if localizations.has(locale):
		localizations[locale].missing_files.erase(file);
	else:
		localizations[locale] = LocaleData.new();
		localizations[locale].missing_files = Array(Array(cwd_files), TYPE_STRING, &"", null);
		localizations[locale].missing_files.erase(file);


func register_key(line: PackedStringArray, localization_count: int, file_idx: int) -> void:
	var key = line[0];
	var empty_l10ns = line.count("");
	
	if non_unique_keys.has(key):
		var data := non_unique_keys[key];
		data.file_idxs.push_back(file_idx);
		data.localization_count += localization_count - empty_l10ns;
		return;
	
	if keys.has(key):
		var old_data = keys[key];
		var data = NonUniqueKeyData.new();
		data.file_idxs.push_back(old_data.file_idx);
		data.file_idxs.push_back(file_idx);
		data.localization_count += old_data.localization_count;
		data.localization_count += localization_count - empty_l10ns;
		non_unique_keys[key] = data;
		
		old_data.file_idx = -1;
		return;
	
	var data = KeyData.new();
	data.file_idx = file_idx;
	data.localization_count = localization_count - empty_l10ns;
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


class FileData extends RefCounted:
	var path : String;
	var data : Dictionary[String, PackedStringArray];
	var header : PackedStringArray;
	
	
	static func open_at(path: String) -> FileData:
		var file_data = FileData.new();
		file_data.path = path;
		
		var handle = FileAccess.open(path, FileAccess.READ);
		file_data.header = handle.get_csv_line().slice(1);
		
		while handle.get_position() < handle.get_length():
			var line = handle.get_csv_line();
			
			if line.size() == 0 or line[0] == "":
				continue;
			
			if line.size() < file_data.header.size():
				line.resize(file_data.header.size())
			
			file_data.data[line[0]] = line.slice(1);
		
		return file_data;
	
	
	func get_key_localizations(key: String) -> Dictionary[String, String]:
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
	
	
	func set_key_localization(key: String, localization: String) -> void:
		


class FileChange extends RefCounted:
	enum {
		NEW_FILE,
		NEW_KEY,
		CHANGE_KEY,
		CHANGE_VALUE,
	}
	
	var type: int;
	var data : PackedStringArray;
	
	func _init() -> void:
		pass;
