extends RefCounted
class_name FilterData

## Parsing filter query and matching strings
##
## The following keywords can be used, separated by comma:[br]
## - [b]key:{string}[/b] (used by default): filters keys by "globbing" with the provided string.[br]
##   Example: [param key:FOO] (or just [param FOO]) will show keys [i]FOO[/i] and [i]FOOBAR[/i] but not [i]BAR[/i][br]
## - [b]exact:{string}[/b]: filters keys by equality.[br]
##   Example: [param exact:FOO] displays key [i]FOO[/i], but hides [i]FOOBAR[/i].[br]
## - [b]case[/b]: turns case sensitive search on.[br]
##   Example: [param FOO,case] will match [i]FOObar[/i], but not [i]fooBAR[/i].[br]
## - [b]file:{string}[/b]: limits the filter to files with matching names (paths). Works in a similar fashion to [b]key[/b] matching.[br]
##   Example: [param file:menu,case] will show keys in the file [i]cwd/l10ns/menu.csv[/i] but not in [i]cwd/l10ns/quests.csv[/i][br]
## [br]
## Shorthands and special filters:[br]
## - [b]cur[/b]: shorthand for [param file:{current_file_name}]. If no file is currently selected does nothing.[br]
## - [b]dupe[/b]: display single file dupes, so that you could fix them manually :) [br]
## - [b]collision[/b]: display keys with potential collisions[br]
## [br]
## Different keywords combine multiplicatevely:[br]
## [param file:FOO,key:CHUNGUS] will show only keys containing [i]CHUNGUS[/i] in files with [i]FOO[/i] in their name.[br][br]
## Similar keywords combine additively:[br]
## [param key:FIZZ,key:BUZZ] will display keys [i]FIZZ[/i] and [i]BUZZ[/i] and [i]FIZZBUZZ[/i].[br][br]
## The comma (,) is a special symbol. To use it: don't.[br]
## Whitespaces before and after arguments are ignored, as well as before the keywords.[br]


var key_filters : Array[String] = [];
var exact_match : Array[String] = [];
var file_idxs : Array[int] = [];
var is_case_sensitive : bool = false;
var cwd_state_ref : CWDState = null;


func _init(cwd_state_reference: CWDState) -> void:
	self.cwd_state_ref = cwd_state_reference;


static func from_query(filter_query: String, data: CWDState) -> FilterData:
	var new_filter_data = FilterData.new(data);
	
	var filter_settings = filter_query.split(",", false);
	var file_filters : Array = [];
	
	var ignore_file : bool = false;
	
	for setting in filter_settings:
		match setting.strip_edges():
			_ when setting.begins_with("key:"):
				new_filter_data.key_filters.push_back("*%s*" % setting.trim_prefix("key:").strip_edges());
			_ when setting.begins_with("file:"):
				file_filters.push_back("*%s*" % setting.trim_prefix("file:").strip_edges());
			_ when setting.begins_with("exact:"):
				new_filter_data.exact_match.push_back(setting.trim_prefix("file:").strip_edges());
			"case":
				new_filter_data.is_case_sensitive = true;
			"cur" when data.current_file_idx != -1:
				file_filters.push_back(data.cwd_files[data.current_file_idx]);
			"dupe":
				new_filter_data.exact_match.append_array(data.get_single_file_dupes());
			"collision":
				new_filter_data.exact_match.append_array(data.possible_collisions.keys());
			_:
				new_filter_data.key_filters.push_back("*%s*" % setting);
	
	file_filters = file_filters.map(func(s: String): return s.to_lower());
	var cwd_files_temp = Array(data.cwd_files).map(func(s: String): return s.to_lower());
	var file_idxs_temp = cwd_files_temp\
		.filter(func(file: String): return file_filters.any(
			file.match if new_filter_data.is_case_sensitive else file.matchn)
		)\
		.map(cwd_files_temp.find)\
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
	
	if not exact_match.is_empty():
		if not exact_match.any(func(exa: String): return exa == key):
			return false;
	
	if not key_filters.is_empty():
		if not key_filters.any(key.match if self.is_case_sensitive else key.matchn):
			return false;
	
	return true;
