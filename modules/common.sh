# Shared helpers for audiobook-convert stage modules.
# Keep this file limited to behavior already required by multiple modules.

readonly AUDIOBOOK_WORKSPACE_MARKER=".audiobook-workspace"
readonly AUDIOBOOK_WORKSPACE_VERSION="1"

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

# Find the nearest converter workspace containing DIRECTORY. The marker must be
# a regular file so a copied source tree cannot impersonate a workspace with a
# directory or symlink of the same name.
common::find_workspace() {
	local directory candidate

	directory="$(realpath -e -- "$1")" || return 1
	[[ -d "$directory" ]] || directory="$(dirname -- "$directory")"

	while :; do
		candidate="$directory/$AUDIOBOOK_WORKSPACE_MARKER"
		if [[ -f "$candidate" && ! -L "$candidate" ]] &&
			[[ "$(sed -n '1p' "$candidate")" == "version=$AUDIOBOOK_WORKSPACE_VERSION" ]]; then
			printf '%s\n' "$directory"
			return 0
		fi

		[[ "$directory" == "/" ]] && return 1
		directory="$(dirname -- "$directory")"
	done
}

# Require a command to run from a prepared workspace. This protects modifying
# stages even when their default output is the current directory.
common::require_workspace() {
	if ! workspace_root="$(common::find_workspace "$PWD")"; then
		echo "error: run this command inside an audiobook-convert workspace" >&2
		echo "hint: create one with: audiobook-convert workspace SOURCE" >&2
		return 1
	fi
}

# Ensure an existing input resolves inside the active workspace. realpath -e
# follows symlinks, so links that escape the workspace are rejected.
common::require_workspace_input() {
	local path="$1"
	local resolved

	if ! resolved="$(realpath -e -- "$path")"; then
		echo "error: path not found: $path" >&2
		return 1
	fi

	case "$resolved" in
	"$workspace_root" | "$workspace_root"/*) ;;
	*)
		echo "error: path is outside workspace: $path" >&2
		return 1
		;;
	esac
}

# Ensure a prospective output resolves inside the workspace. realpath -m
# normalizes missing path components while resolving existing symlink parents.
common::require_workspace_output() {
	local path="$1"
	local resolved

	if ! resolved="$(realpath -m -- "$path")"; then
		echo "error: invalid output path: $path" >&2
		return 1
	fi

	case "$resolved" in
	"$workspace_root" | "$workspace_root"/*) ;;
	*)
		echo "error: output is outside workspace: $path" >&2
		return 1
		;;
	esac

	if [[ -L "$path" ]]; then
		echo "error: output may not be a symbolic link: $path" >&2
		return 1
	fi
}
