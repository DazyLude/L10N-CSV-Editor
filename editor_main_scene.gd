extends Control


var block_input : bool = false;
var data := CWDState.new();
var key_filter : String = "";


func _ready() -> void:
	$Main/DirInfo/ChangeDirButton.pressed.connect(change_folder);


func update_cwd_data_display() -> void:
	$Main/DirInfo/DirName.text = data.cwd_handle.get_current_dir(true);
	$Main/CWDInfo/FileCount.text = "files found: %d" % data.cwd_files.size();
	$Main/CWDInfo/KeyCount.text = "total keys: %d" % data.keys.size();
	$Main/CWDInfo/UniqueL10Ns.text = "total l10ns: %d" % data.localizations.size();


func refresh_list_of_keys() -> void:
	$Main/KeySelect/KeyList.clear();
	for key in data.keys.keys().filter(keys_filter):
		$Main/KeySelect/KeyList.add_item(key);


func keys_filter(key: String) -> bool:
	return true;


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
	data.scan_cwd(dir);
	
	update_cwd_data_display();
	refresh_list_of_keys();
	
	block_input = false;
