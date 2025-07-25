# L10N-CSV-Editor
A simple standalone CSV editor ad hoc built with Godot.

# What does it do
- Edit localization data for keys distributed between multiple localization files seamlessly.
- Detect key collisions or malformed localization files.
- Add, rename, move around localization keys.
- Add new locales or comment columns to localization files.
- Create new localization files.
- Scan your project folder for .csv files and merge their data for ease of access. Alternatively, work within subfolders to work with only a subset of localization data.

# important notes
- Use version control system to guarantee that no data is lost!
- App works with in-memory file representations, and saves changes to disk in bulk only when requested with **directory->save changes** or **ctrl+s**
When app closes or crashes it attemtps to save changes to backup files to allow restoration of session data,
but that feature hasn't been tested well enough.


# HOW TO'S
## creating a new file to add keys and localizations to:
1) press "directory" at the top, then press "create file"
2) enter a file name and choose a location with a dialog.
**WARNING**: it is possible to create a new file outside of the working directory.
You will be able to edit the file normally, but when launching the app the file won't be loaded.
## adding a new key:
1) press "localization" at the top, then press "add key"
2) select one of the files currently present in the working directory
3) enter new key name
4) press ok
## adding a new locale to a file:
1) press "localization" at the top, then press "add locale"
2) select one of the files currently present in the working directory
3) enter new locale code
4) press ok
## adding the new localizations to the existing key:
- Either add a locale to the file in which the key is already present,..
- Or move the key to the files which have needed locale combination with "Files" tab in the editor interface:
    1) open the "Files" editor tab
    2) files the key is already present in are selected by default. This selection can be restored with the "reset button"
    3) select a new set of files that has the needed combination of locales
    4) press apply 
## editing existing localization data
1) select a key with a key selector
2) open "Localization" editor tab
3) select locale you want to edit left to the text editor
4) edit localization data
5) **IMPORTANT:** focus out of the text editor or press **Shift+Enter** to commit changes
## renaming existing keys
1) select a key with a key selector
2) edit the key name in the key edit field
3) press "rename key"
## Filtering keys:
Key filter allows for a quick lookup using queries and special strings.

The following keywords can be used, separated by comma:
- key:{string} (used by default): filters keys by "globbing" with the provided string.
  Example: [param key:FOO] (or just [param FOO]) will show keys FOO and FOOBAR but not BAR
- exact:{string}: filters keys by equality.
  Example: [param exact:FOO] displays key FOO, but hides FOOBAR.
- case: turns case sensitive search on.
  Example: [param FOO,case] will match FOObar, but not fooBAR.
- file:{string}: limits the filter to files with matching names (paths). Works in a similar fashion to key matching.
  Example: [param file:menu,case] will show keys in the file cwd/l10ns/menu.csv but not in cwd/l10ns/quests.csv

Shorthands and special filters:
- cur: shorthand for [param file:{current_file_name}]. If no file is currently selected does nothing.
- dupe: display single file dupes, so that you could fix them manually :) 
- collision: display keys with potential collisions

Different keywords combine multiplicatevely:
[param file:FOO,key:CHUNGUS] will show only keys containing CHUNGUS in files with FOO in their name.
Similar keywords combine additively:
[param key:FIZZ,key:BUZZ] will display keys FIZZ and BUZZ and FIZZBUZZ.
The comma (,) is a special symbol. To use it: don't.
Whitespaces before and after arguments are ignored, as well as before the keywords.