# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert workspace SOURCE [WORKSPACE]

Copy an audiobook source tree into an isolated working directory.

Arguments:
  SOURCE     Original audiobook directory to copy without modifying
  WORKSPACE  Destination directory. Default: a sibling named
             SOURCE_NAME.audiobook-work

The entire source tree is copied. The destination must not already exist.
Conversion commands that create or rename files must run inside this workspace.
HELP
}

stage::parse_arguments() {
	while (($# > 0)); do
		case "$1" in
		-h | --help)
			stage::usage
			exit 0
			;;
		--)
			shift
			break
			;;
		-*)
			echo "error: unknown option: $1" >&2
			stage::usage >&2
			exit 2
			;;
		*) break ;;
		esac
	done

	if (($# < 1 || $# > 2)); then
		echo "error: workspace requires one or two arguments" >&2
		stage::usage >&2
		exit 2
	fi

	source_dir="$1"
	workspace_dir="${2:-}"
}

stage::validate_paths() {
	local canonical_source canonical_workspace workspace_parent

	if [[ ! -d "$source_dir" ]]; then
		echo "error: source directory not found: $source_dir" >&2
		exit 1
	fi
	if [[ -L "$source_dir" ]]; then
		echo "error: source directory may not be a symbolic link: $source_dir" >&2
		exit 1
	fi
	if [[ -e "$source_dir/$AUDIOBOOK_WORKSPACE_MARKER" || -L "$source_dir/$AUDIOBOOK_WORKSPACE_MARKER" ]]; then
		echo "error: source contains reserved marker: $AUDIOBOOK_WORKSPACE_MARKER" >&2
		exit 1
	fi

	canonical_source="$(realpath -e -- "$source_dir")"
	if [[ -z "$workspace_dir" ]]; then
		workspace_dir="$(dirname -- "$canonical_source")/$(basename -- "$canonical_source").audiobook-work"
	fi
	if [[ -e "$workspace_dir" || -L "$workspace_dir" ]]; then
		echo "error: workspace already exists: $workspace_dir" >&2
		exit 1
	fi

	workspace_parent="$(dirname -- "$workspace_dir")"
	if [[ ! -d "$workspace_parent" ]]; then
		echo "error: workspace parent not found: $workspace_parent" >&2
		exit 1
	fi
	canonical_workspace="$(realpath -m -- "$workspace_dir")"
	case "$canonical_workspace" in
	"$canonical_source" | "$canonical_source"/*)
		echo "error: workspace may not be inside source: $workspace_dir" >&2
		exit 1
		;;
	esac
}

stage::create_workspace() {
	local canonical_source workspace_parent workspace_name temporary_dir

	canonical_source="$(realpath -e -- "$source_dir")"
	workspace_parent="$(dirname -- "$workspace_dir")"
	workspace_name="$(basename -- "$workspace_dir")"
	temporary_dir="$(mktemp -d --tmpdir="$workspace_parent" ".${workspace_name}.tmp.XXXXXX")"
	trap 'rm -rf --one-file-system -- "$temporary_dir"' EXIT

	# --reflink=auto creates independent copy-on-write files where supported and
	# transparently falls back to normal copies. Hard links are never used.
	cp -a --reflink=auto -- "$source_dir/." "$temporary_dir/"
	{
		printf 'version=%s\n' "$AUDIOBOOK_WORKSPACE_VERSION"
		printf 'source=%s\n' "$canonical_source"
	} >"$temporary_dir/$AUDIOBOOK_WORKSPACE_MARKER"
	mv -- "$temporary_dir" "$workspace_dir"
	trap - EXIT
}

stage::run() {
	stage::parse_arguments "$@"
	common::require_commands cp mktemp mv realpath rm || exit 1
	stage::validate_paths
	stage::create_workspace
	echo "created workspace $workspace_dir"
}
