extends RefCounted
class_name FileChange


enum {
	FILE_CREATED,
	FILE_DELETED,
	FILE_MOVED,
	
	NEW_KEY,
	NEW_LOCALE,
	
	CHANGE_KEY,
	CHANGE_VALUE,
	CHANGE_LOCALE,
	
	REMOVE_KEY,
	REMOVE_LOCALE,
}


var type: int;
var data : PackedStringArray;


func _init(type_i: int, data_i: PackedStringArray) -> void:
	type = type_i;
	data = data_i;
