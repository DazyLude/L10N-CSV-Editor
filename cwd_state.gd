extends RefCounted
class_name CWDState


## cwd path
var cwd_handle : DirAccess;
## paths to csv files located in cwd
var cwd_files : PackedStringArray = [];

#region cwd data
## idx of a "current" file
var current_file_idx : int = -1;
## unique string keys and paths to the files they're located in.
var keys : Dictionary[String, KeyData] = {};
## uniques localization keys
var localizations : Dictionary[String, LocaleData] = {};
## non unique string key file paths
var non_unique_keys : Dictionary[String, NonUniqueKeyData] = {};
#endregion

#region Data Manipulation
## current working file handle
var cwf : FileAccess;
## in-memory representation of lines of the current working file
var cwf_data : Dictionary[String, PackedStringArray];
#endregion


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
		read_file_contents(file);


func read_file_contents(path: String) -> void:
	var file_handle := FileAccess.open(path, FileAccess.READ);
	if file_handle == null:
		push_error("error when opening file (%s): " % path, error_string(FileAccess.get_open_error()));
		return;
	
	var header := file_handle.get_csv_line();
	
	if header.size() == 0:
		push_error("malformed header: empty (%s)" % path);
		return;
	
	if header[0] != "key":
		push_error("malformed header: first value not \"key\" (%s)" % path);
		return;
	
	while file_handle.get_position() < file_handle.get_length():
		var line := file_handle.get_csv_line();
		

	
	


func clear_cwd_data() -> void:
	current_file_idx = -1;
	keys.clear();
	localizations.clear();
	non_unique_keys.clear();


func get_csv_files_recursively(handle: DirAccess) -> PackedStringArray:
	var files := Array(handle.get_files());
	files = files.filter(csv_filter_predicate);
	var unprocessed_directories := Array(handle.get_directories());
	
	while unprocessed_directories.size() > 0:
		var processing : String = unprocessed_directories.pop_back();
		var processing_path := handle.get_current_dir().path_join(processing);
		var processing_handle := DirAccess.open(processing_path);
		if processing_handle == null:
			push_error("error when opening directory (%s): " % processing_path, error_string(DirAccess.get_open_error()));
			continue;
		
		var new_files := Array(processing_handle.get_files());
		new_files = new_files.filter(csv_filter_predicate).map(processing.path_join);
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
	var file_idxs : Array[int];


class LocaleData extends RefCounted:
	var key_count : int;
