# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert combine-audio DIRECTORY OUTPUT

Combine naturally sorted audio files directly inside DIRECTORY into OUTPUT.

Arguments:
  DIRECTORY  Workspace directory containing source audio files
  OUTPUT     New combined file, with the same extension as every source file

The command requires at least two compatible files of one type. It copies the
first audio stream without re-encoding, preserves tags from the first naturally
sorted file, verifies the completed output, and only then removes the
original files. Subdirectories and non-audio files are ignored.
OUTPUT must not already exist, and all paths must be inside a workspace.

Example:
  audiobook-convert combine-audio ./part-1 ./part-1.mp3
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

	if (($# != 2)); then
		echo "error: combine-audio requires DIRECTORY and OUTPUT" >&2
		stage::usage >&2
		exit 2
	fi

	target_dir="$1"
	output="$2"
}

stage::validate_paths() {
	local output_dir

	if [[ ! -d "$target_dir" ]]; then
		echo "error: directory not found: $target_dir" >&2
		exit 1
	fi
	if [[ -e "$output" || -L "$output" ]]; then
		echo "error: output already exists: $output" >&2
		exit 1
	fi
	output_dir="$(dirname -- "$output")"
	if [[ ! -d "$output_dir" ]]; then
		echo "error: output directory not found: $output_dir" >&2
		exit 1
	fi
}

stage::find_audio_files() {
	mapfile -d '' audio_files < <(common::find_audio_files "$target_dir" direct)
	if ((${#audio_files[@]} < 2)); then
		echo "error: at least two supported audio files are required directly in $target_dir" >&2
		exit 1
	fi
}

stage::extension_for_file() {
	local extension="${1##*.}"
	printf '%s' "${extension,,}"
}

stage::validate_file_types() {
	local file

	input_extension="$(stage::extension_for_file "${audio_files[0]}")"
	output_extension="$(stage::extension_for_file "$output")"
	if [[ "$output_extension" != "$input_extension" ]]; then
		echo "error: OUTPUT must use the .$input_extension extension" >&2
		exit 1
	fi

	for file in "${audio_files[@]:1}"; do
		if [[ "$(stage::extension_for_file "$file")" != "$input_extension" ]]; then
			echo "error: all input files must use the .$input_extension extension: $file" >&2
			exit 1
		fi
	done
}

# Compare properties that must remain constant across a lossless concat. FFmpeg
# performs the final container-specific compatibility check.
stage::audio_signature() {
	local file="$1"
	ffprobe -v error -select_streams a:0 \
		-show_entries stream=codec_name,codec_tag_string,sample_fmt,sample_rate,channels,channel_layout \
		-of compact=p=0:nk=1 "$file"
}

stage::validate_audio_streams() {
	local file signature

	reference_signature="$(stage::audio_signature "${audio_files[0]}")"
	if [[ -z "$reference_signature" ]]; then
		echo "error: no readable audio stream found: ${audio_files[0]}" >&2
		exit 1
	fi

	for file in "${audio_files[@]:1}"; do
		signature="$(stage::audio_signature "$file")"
		if [[ -z "$signature" ]]; then
			echo "error: no readable audio stream found: $file" >&2
			exit 1
		fi
		if [[ "$signature" != "$reference_signature" ]]; then
			echo "error: incompatible audio stream: $file" >&2
			exit 1
		fi
	done
}

# FFmpeg concat manifests use shell-like single-quote escaping. Absolute paths
# avoid dependence on the temporary manifest's directory.
stage::manifest_path() {
	local path="$1"
	path="$(realpath -e -- "$path")"
	printf '%s' "${path//\'/\'\\\'\'}"
}

stage::create_manifest() {
	local file

	manifest="$(mktemp)"
	printf 'ffconcat version 1.0\n' >"$manifest"
	for file in "${audio_files[@]}"; do
		printf "file '%s'\n" "$(stage::manifest_path "$file")" >>"$manifest"
	done
}

stage::cleanup() {
	[[ -z "${manifest:-}" || ! -e "$manifest" ]] || rm -f -- "$manifest"
	[[ -z "${temporary_output:-}" || ! -e "$temporary_output" ]] || rm -f -- "$temporary_output"
}

stage::combine_files() {
	local muxer output_dir

	output_dir="$(dirname -- "$output")"
	temporary_output="$(mktemp -p "$output_dir" '.combine-audio.XXXXXX')"
	muxer="$(common::audio_muxer_for_file "${audio_files[0]}")"

	if ! ffmpeg -v error -nostdin -y -f concat -safe 0 -i "$manifest" \
		-i "${audio_files[0]}" -map 0:a:0 -map_metadata 1 -c copy -f "$muxer" "$temporary_output"; then
		echo "error: failed to combine audio files" >&2
		exit 1
	fi

	if ! ffprobe -v error -select_streams a:0 -show_entries stream=codec_name \
		-of default=nw=1:nk=1 "$temporary_output" | grep -q .; then
		echo "error: combined output verification failed" >&2
		exit 1
	fi
}

stage::replace_sources() {
	mv -- "$temporary_output" "$output"
	temporary_output=""
	rm -- "${audio_files[@]}"
	printf 'combined and removed %d audio files: %s\n' "${#audio_files[@]}" "$output"
}

stage::run() {
	stage::parse_arguments "$@"
	common::require_commands ffmpeg ffprobe find grep mktemp mv realpath rm sort || exit 1
	common::require_workspace || exit 1
	stage::validate_paths
	common::require_workspace_input "$target_dir" || exit 1
	common::require_workspace_output "$output" || exit 1
	stage::find_audio_files
	stage::validate_file_types
	stage::validate_audio_streams
	trap stage::cleanup EXIT
	stage::create_manifest
	stage::combine_files
	stage::replace_sources
}
