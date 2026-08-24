# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert set-track-number [OPTIONS] DIRECTORY

Set sequential Track metadata on audio files directly inside DIRECTORY.

Arguments:
  DIRECTORY  Workspace directory containing the audio files to update

Options:
  -n, --dry-run  Print planned Track assignments without changing files
  -h, --help     Show this help output

Files are sorted naturally by path and numbered from 1. Subdirectories and
non-audio files are ignored. Audio streams are copied without re-encoding.

Examples:
  audiobook-convert set-track-number --dry-run "$PWD"
  audiobook-convert set-track-number "$PWD"
HELP
}

stage::parse_arguments() {
	dry_run=0
	target_dir=""

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

	if [[ -z "$target_dir" ]]; then
		echo "error: DIRECTORY is required" >&2
		stage::usage >&2
		exit 2
	fi

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
	mapfile -d '' audio_files < <(
		common::find_audio_files "$target_dir" direct
	)

	if ((${#audio_files[@]} == 0)); then
		echo "error: no supported audio files found directly in $target_dir" >&2
		exit 1
	fi
}

stage::print_plan() {
	local index

	for index in "${!audio_files[@]}"; do
		printf 'would set Track %d: %s\n' "$((index + 1))" "${audio_files[$index]}"
	done
	printf 'planned Track updates for %d files\n' "${#audio_files[@]}"
}

stage::cleanup_temporary_files() {
	local temporary

	for temporary in "${temporary_files[@]:-}"; do
		[[ -n "$temporary" && -e "$temporary" ]] || continue
		rm -f -- "$temporary"
	done
}

# Read either a container-level or audio-stream Track tag. FFmpeg exposes both
# common TRACKNUMBER spellings through the normalized "track" field.
stage::read_track_number() {
	local file="$1"

	ffprobe -v error \
		-show_entries format_tags=track:stream_tags=track \
		-of default=nw=1:nk=1 "$file" | sed -n '/./{p;q;}'
}

# Prepare every rewritten container before replacing originals. This prevents
# a media-format failure from leaving only part of the directory renumbered.
stage::prepare_updates() {
	local file index muxer temporary track_number
	local -a metadata_options

	temporary_files=()
	trap stage::cleanup_temporary_files EXIT

	for index in "${!audio_files[@]}"; do
		file="${audio_files[$index]}"
		track_number="$((index + 1))"
		muxer="$(common::audio_muxer_for_file "$file")"
		temporary="$(mktemp -p "$(dirname -- "$file")" '.set-track-number.XXXXXX')"
		temporary_files+=("$temporary")
		metadata_options=(-metadata "track=$track_number")

		case "$muxer" in
		adts) metadata_options+=(-write_id3v2 1) ;;
		ogg | opus) metadata_options=(-metadata:s:a "track=$track_number") ;;
		esac

		if ! ffmpeg -v error -nostdin -y -i "$file" -map 0 -map_metadata 0 -c copy \
			"${metadata_options[@]}" -f "$muxer" "$temporary"; then
			echo "error: failed to set Track metadata: $file" >&2
			exit 1
		fi

		if [[ "$(stage::read_track_number "$temporary")" != "$track_number" ]]; then
			echo "error: Track metadata verification failed: $file" >&2
			exit 1
		fi

		chmod --reference="$file" "$temporary"
	done
}

stage::replace_originals() {
	local index

	for index in "${!audio_files[@]}"; do
		mv -f -- "${temporary_files[$index]}" "${audio_files[$index]}"
		temporary_files[index]=""
		printf 'set Track %d: %s\n' "$((index + 1))" "${audio_files[$index]}"
	done
	printf 'updated Track metadata for %d files\n' "${#audio_files[@]}"
}

stage::run() {
	stage::parse_arguments "$@"
	stage::validate_target_directory
	common::require_commands chmod ffmpeg ffprobe find mktemp mv realpath sed sort || exit 1
	common::require_workspace || exit 1
	common::require_workspace_input "$target_dir" || exit 1
	stage::find_audio_files

	if ((dry_run)); then
		stage::print_plan
		exit 0
	fi

	stage::prepare_updates
	stage::replace_originals
}
