extends Node
class_name PersistentData

const persistent_data_path = "user://persistent.json";

static var last_working_directory : String = "";


static func save() -> void:
	var data := {
		"lwd": last_working_directory,
	}
	
	var data_string = JSON.stringify(data);
	var handle := FileAccess.open(persistent_data_path, FileAccess.WRITE);
	handle.store_string(data_string);
	handle.close();


static func load_fom_disk() -> void:
	if not FileAccess.file_exists(persistent_data_path):
		return;
	
	var handle := FileAccess.open(persistent_data_path, FileAccess.READ);
	var json = JSON.new();
	var parse_result = json.parse(handle.get_as_text());
	if parse_result != OK:
		push_error("Error when parsing persistent data: %s", error_string(parse_result));
		return;
	
	var data := json.data as Dictionary;
	last_working_directory = data.get("lwd", "");
	
	handle.close();
