# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert clean-workspace WORKSPACE

Delete a working directory previously created by audiobook-convert workspace.

The command refuses symbolic links, filesystem roots, unmarked directories,
and paths whose marker does not identify the directory itself as a workspace.
HELP
}

stage::parse_arguments() {
	if (($# == 1)) && [[ "$1" == "-h" || "$1" == "--help" ]]; then
		stage::usage
		exit 0
	fi
	if (($# != 1)); then
		echo "error: clean-workspace requires one argument" >&2
		stage::usage >&2
		exit 2
	fi
	workspace_dir="$1"
}

stage::validate_workspace() {
	local resolved discovered

	if [[ -L "$workspace_dir" ]]; then
		echo "error: workspace may not be a symbolic link: $workspace_dir" >&2
		exit 1
	fi
	if ! resolved="$(realpath -e -- "$workspace_dir")" || [[ ! -d "$resolved" ]]; then
		echo "error: workspace directory not found: $workspace_dir" >&2
		exit 1
	fi
	if [[ "$resolved" == "/" ]]; then
		echo "error: refusing to delete filesystem root" >&2
		exit 1
	fi
	case "$PWD" in
	"$resolved" | "$resolved"/*)
		echo "error: leave the workspace before deleting it: $workspace_dir" >&2
		exit 1
		;;
	esac
	if ! discovered="$(common::find_workspace "$resolved")" || [[ "$discovered" != "$resolved" ]]; then
		echo "error: not an audiobook-convert workspace: $workspace_dir" >&2
		exit 1
	fi
	workspace_dir="$resolved"
}

stage::run() {
	stage::parse_arguments "$@"
	common::require_commands realpath rm || exit 1
	stage::validate_workspace
	rm -rf --one-file-system -- "$workspace_dir"
	echo "deleted workspace $workspace_dir"
}
