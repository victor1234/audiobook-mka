# Shared helpers for audiobook-convert stage modules.
# Keep this file limited to behavior already required by multiple modules.

# Verify that every external command needed by a stage is available.
common::require_commands() {
	local command

	for command in "$@"; do
		if ! command -v "$command" >/dev/null 2>&1; then
			echo "error: $command is required" >&2
			return 1
		fi
	done
}

# Print supported source audio files recursively beneath a directory in natural
# path order. NUL delimiters preserve paths containing whitespace or newlines.
common::find_audio_files() {
	local directory="$1"

	find "$directory" -type f \
		\( -iname '*.aac' -o -iname '*.alac' -o -iname '*.flac' -o -iname '*.m4a' \
		-o -iname '*.m4b' -o -iname '*.mp3' -o -iname '*.oga' -o -iname '*.ogg' \
		-o -iname '*.opus' -o -iname '*.wav' -o -iname '*.wma' \) \
		-print0 | sort -zV
}

# Trim leading and trailing whitespace from a value.
common::trim() {
	local value="$1"
	value="${value#"${value%%[![:space:]]*}"}"
	value="${value%"${value##*[![:space:]]}"}"
	printf '%s' "$value"
}

# Read the first matching global SimpleTag from Matroska tags XML. Missing and
# empty files have no value; malformed XML remains silent for existing callers.
common::matroska_tag_value() {
	local xml_file="$1"
	local name="$2"

	[[ -s "$xml_file" ]] || return 0

	xmllint --xpath "string((/Tags/Tag[not(Targets/*)]/Simple[Name='$name']/String)[1])" \
		"$xml_file" 2>/dev/null || true
}
