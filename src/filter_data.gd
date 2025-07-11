extends RefCounted
class_name FilterData

var key_filters : Array[String] = [];
var file_idxs : Array[int] = [];
var is_case_sensitive : bool = false;
var cwd_state_ref : CWDState = null;


func _init(cwd_state_reference: CWDState) -> void:
	self.cwd_state_ref = cwd_state_reference;


static func from_query(filter_query: String, data: CWDState) -> FilterData:
	var new_filter_data = FilterData.new(data);
	
	var filter_settings = filter_query.split(",", false);
	var file_filters : Array = [];
	
	for setting in filter_settings:
		match setting:
			_ when setting.begins_with("key:"):
				new_filter_data.key_filters.push_back("*%s*" % setting.trim_prefix("key:"));
			_ when setting.begins_with("file:"):
				file_filters.push_back("*%s*" % setting.trim_prefix("file:"));
			"case":
				new_filter_data.is_case_sensitive = true;
			_:
				new_filter_data.key_filters.push_back("*%s*" % setting);
	
	if not new_filter_data.is_case_sensitive:
		file_filters = file_filters.map(func(s: String): return s.to_lower());
		var cwd_files_temp = Array(data.cwd_files).map(func(s: String): return s.to_lower());
		var file_idxs_temp = file_filters\
			.map(cwd_files_temp.find)\
			.filter(func(idx: int): return idx != -1);
		new_filter_data.file_idxs = Array(file_idxs_temp, TYPE_INT, &"", null);
	else:
		var file_idxs_temp = file_filters\
			.map(data.cwd_files.find)\
			.filter(func(idx: int): return idx != -1);
		new_filter_data.file_idxs = Array(file_idxs_temp, TYPE_INT, &"", null);
	
	return new_filter_data;


func matches(key: String) -> bool:
	var key_data : CWDState.KeyData = self.cwd_state_ref.keys.get(key, null);
	if key_data == null:
		push_error("invalid key in the key list: %s" % key);
		return false;
	
	if not file_idxs.is_empty():
		var file_chk : bool;
		
		if key_data.file_idx != -1:
			file_chk = file_idxs.has(key_data.file_idx);
		else:
			var actual_data = self.cwd_state_ref.non_unique_keys[key];
			file_chk = file_idxs.any(actual_data.file_idxs.has);
	
		if not file_chk:
			return false;
	
	if not key_filters.is_empty():
		if not key_filters.any(key.match if self.is_case_sensitive else key.matchn):
			return false;
	
	return true;
