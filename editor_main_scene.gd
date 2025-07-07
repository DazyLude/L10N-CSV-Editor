extends Control


var block_input : bool = false;
var data := CWDState.new();


func _ready() -> void:
	$Main/DirInfo/ChangeDirButton.pressed.connect(change_folder);
	data.task_update.connect(update_progress);


func update_progress() -> void:
	$Main/Progress.visible = data.current_task != "";
	$Main/Progress.text = "%s[%s]" % [data.current_task, data.current_task_progress];


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
	var path = dialog.current_dir;
	data.scan_cwd(path);
	await data.task_finished;
	block_input = false;
