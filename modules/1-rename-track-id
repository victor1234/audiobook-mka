# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'EOF'
Usage: audiobook-convert rename-track-id [OPTIONS] [DIRECTORY]

Rename audio files to their track id from the Track metadata tag.

Arguments:
  DIRECTORY  Directory tree containing audio files. Default: current working directory

Options:
  -n, --dry-run  Print planned renames without changing files
  -h, --help     Show this help output

The script recursively scans audio files in DIRECTORY, reads each file's Track
tag with exiftool, and renames the file to TRACK_ID.EXT in its existing parent
directory while preserving the original extension. If a Track value contains a
total count such as 04/32, only the track id before the slash is used.

Applying renames requires a workspace created by `audiobook-convert workspace`.

Examples:
  audiobook-convert rename-track-id
  audiobook-convert rename-track-id --dry-run "$PWD"
EOF
}

stage::parse_arguments() {
dry_run=0
target_dir="."

while (($# > 0)); do
	case "$1" in
	-n | --dry-run)
		dry_run=1
		shift
		;;
	-h | --help)
		stage::usage
		exit 0
		;;
	--)
		shift
		if (($# > 0)); then
			target_dir="$1"
			shift
		fi
		break
		;;
	-*)
		echo "error: unknown option: $1" >&2
		stage::usage >&2
		exit 2
		;;
	*)
		target_dir="$1"
		shift
		break
		;;
	esac
done

if (($# > 0)); then
	echo "error: too many arguments" >&2
	stage::usage >&2
	exit 2
fi

}

stage::validate_target_directory() {
if [[ ! -d "$target_dir" ]]; then
	echo "error: directory not found: $target_dir" >&2
	exit 1
fi

}

stage::find_audio_files() {
# Recursively scan source audio files from the target directory. Sidecars such
# as cover.jpg, tags.xml, chapters.txt, and existing MKA outputs are ignored.
mapfile -d '' audio_files < <(
	common::find_audio_files "$target_dir"
)

if ((${#audio_files[@]} == 0)); then
	echo "error: no audio files found in $target_dir" >&2
	exit 1
fi

}

# Convert the Track tag to a filename-safe id. Track totals such as 04/32 are
# reduced to 04 because slash is a path separator.
stage::track_id() {
	local file="$1"
	local track

	track="$(exiftool -q -q -s3 -Track "$file")"
	track="$(common::trim "$track")"
	track="${track%%/*}"
	track="$(common::trim "$track")"

	if [[ -z "$track" ]]; then
		echo "error: missing Track tag: $file" >&2
		exit 1
	fi

	if [[ "$track" == *"/"* ]]; then
		echo "error: unsupported Track tag for $file: $track" >&2
		exit 1
	fi

	printf '%s' "$track"
}


stage::plan_renames() {
declare -ga sources=()
declare -ga targets=()
declare -ga temps=()
declare -gA planned_targets=()
declare -gA source_paths=()

for file in "${audio_files[@]}"; do
	source_paths["$file"]=1
done

for file in "${audio_files[@]}"; do
	dir="$(dirname "$file")"
	name="$(basename "$file")"
	ext="${name##*.}"
	id="$(stage::track_id "$file")"
	target="$dir/$id.$ext"

	if [[ -n "${planned_targets[$target]:-}" && "${planned_targets[$target]}" != "$file" ]]; then
		echo "error: duplicate target name: $target" >&2
		echo "  from: ${planned_targets[$target]}" >&2
		echo "  from: $file" >&2
		exit 1
	fi

	planned_targets["$target"]="$file"
	sources+=("$file")
	targets+=("$target")
done

for target in "${targets[@]}"; do
	if [[ -e "$target" && -z "${source_paths[$target]:-}" ]]; then
		echo "error: target already exists: $target" >&2
		exit 1
	fi
done

}

stage::count_planned_renames() {
rename_count=0
for index in "${!sources[@]}"; do
	source="${sources[$index]}"
	target="${targets[$index]}"

	if [[ "$source" == "$target" ]]; then
		continue
	fi

	((rename_count += 1))
	if ((dry_run)); then
		printf 'would rename: %s -> %s\n' "$source" "$target"
	fi
done

}

stage::handle_noop_or_dry_run() {
if ((rename_count == 0)); then
	echo "nothing to rename"
	exit 0
fi

if ((dry_run)); then
	echo "planned $rename_count renames"
	exit 0
fi

}

stage::rename_sources_to_temporary_paths() {
for index in "${!sources[@]}"; do
	source="${sources[$index]}"
	target="${targets[$index]}"

	if [[ "$source" == "$target" ]]; then
		temps+=("")
		continue
	fi

	temp="$(mktemp -p "$(dirname "$source")" ".rename-track-id.XXXXXX")"
	rm -f "$temp"
	mv "$source" "$temp"
	temps+=("$temp")
done

}

stage::rename_temporary_paths_to_targets() {
for index in "${!sources[@]}"; do
	temp="${temps[$index]}"
	target="${targets[$index]}"

	[[ -n "$temp" ]] || continue
	mv "$temp" "$target"
	printf 'renamed: %s -> %s\n' "${sources[$index]}" "$target"
done

}

stage::report_renamed_files() {
echo "renamed $rename_count files"

}

stage::run() {
	stage::parse_arguments "$@"
	stage::validate_target_directory
	common::require_commands exiftool realpath || exit 1
	common::require_workspace || exit 1
	common::require_workspace_input "$target_dir" || exit 1
	stage::find_audio_files
	stage::plan_renames
	stage::count_planned_renames
	stage::handle_noop_or_dry_run
	stage::rename_sources_to_temporary_paths
	stage::rename_temporary_paths_to_targets
	stage::report_renamed_files
}
