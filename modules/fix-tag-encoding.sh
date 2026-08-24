# This module is sourced by ./audiobook-convert.
# Convert legacy-encoded ID3 text and comment frames without changing audio.
stage::usage() {
	cat <<'HELP'
Usage: audiobook-convert fix-tag-encoding ENCODING MP3_FILE...

Convert legacy-encoded MP3 ID3 text metadata to Unicode.

Arguments:
  ENCODING    Original iconv-compatible tag encoding, such as WINDOWS-1251
  MP3_FILE... One or more MP3 files inside the active workspace

The shell may expand file globs, for example:
  audiobook-convert fix-tag-encoding WINDOWS-1251 ./*.mp3

All ID3 text (T*) and comment (COMM) frame values supported by mid3iconv are
converted. ASCII values and values incompatible with the requested conversion
are preserved. Lyrics, URLs, artwork descriptions, binary frames, filenames,
and audio data are not changed. Output tags are stored as Unicode ID3v2 data.

This modifying command must run inside a workspace created by
`audiobook-convert workspace`.

Options:
  -h, --help  Show this help output
HELP
}

# Parse the one configuration argument followed by shell-expanded file paths.
stage::parse_arguments() {
	encoding_mode=""
	audio_files=()

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

	if (($# == 0)); then
		echo "error: ENCODING is required" >&2
		stage::usage >&2
		exit 2
	fi
	encoding_mode="$1"
	shift
	if [[ "${1:-}" == "--" ]]; then
		shift
	fi
	if (($# == 0)); then
		echo "error: at least one MP3_FILE is required" >&2
		stage::usage >&2
		exit 2
	fi
	audio_files=("$@")
}

stage::validate_encoding() {
	if ! common::encoding_supported "$encoding_mode"; then
		echo "error: unsupported encoding: $encoding_mode" >&2
		exit 2
	fi
}

# Confirm that ExifTool sees an ID3v2 group, which mid3iconv requires.
stage::has_id3v2() {
	local file="$1"

	exiftool -j -G1 -ID3:all -- "$file" 2>/dev/null |
		jq -e '.[0] | keys | any(startswith("ID3v2_"))' >/dev/null
}

# Validate the full input set before creating temporary files or changing tags.
stage::validate_files() {
	local file resolved extension
	local -A seen=()

	for file in "${audio_files[@]}"; do
		if [[ ! -e "$file" && ! -L "$file" ]]; then
			echo "error: file not found: $file" >&2
			exit 1
		fi
		if [[ -L "$file" ]]; then
			echo "error: MP3 file may not be a symbolic link: $file" >&2
			exit 1
		fi
		if [[ ! -f "$file" ]]; then
			echo "error: not a regular file: $file" >&2
			exit 1
		fi
		extension="${file##*.}"
		if [[ "${extension,,}" != "mp3" ]]; then
			echo "error: not an MP3 file: $file" >&2
			exit 1
		fi
		common::require_workspace_input "$file" || exit 1
		resolved="$(realpath -e -- "$file")"
		if [[ -n "${seen[$resolved]:-}" ]]; then
			echo "error: duplicate MP3 file: $file" >&2
			exit 1
		fi
		seen["$resolved"]=1
		if ! ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
			-of default=nw=1:nk=1 -- "$file" | grep -qx audio; then
			echo "error: unreadable MP3 audio: $file" >&2
			exit 1
		fi
		if ! stage::has_id3v2 "$file"; then
			echo "error: no ID3v2 metadata found: $file" >&2
			exit 1
		fi
	done
}

stage::cleanup_temporary_files() {
	local temporary

	for temporary in "${temporary_files[@]:-}"; do
		[[ -n "$temporary" && -e "$temporary" ]] || continue
		rm -f -- "$temporary"
	done
}

# Repair copies first so a conversion failure cannot partially rewrite inputs.
stage::prepare_updates() {
	local file temporary

	temporary_files=()
	trap stage::cleanup_temporary_files EXIT
	for file in "${audio_files[@]}"; do
		temporary="$(mktemp -p "$(dirname -- "$file")" '.fix-tag-encoding.XXXXXX.mp3')"
		temporary_files+=("$temporary")
		cp --preserve=mode,timestamps -- "$file" "$temporary"
		if ! mid3iconv --quiet --encoding "$encoding_mode" "$temporary"; then
			echo "error: failed to convert ID3 metadata: $file" >&2
			exit 1
		fi
		if ! stage::has_id3v2 "$temporary"; then
			echo "error: converted ID3 metadata verification failed: $file" >&2
			exit 1
		fi
		if ! ffprobe -v error -select_streams a:0 -show_entries stream=codec_type \
			-of default=nw=1:nk=1 -- "$temporary" | grep -qx audio; then
			echo "error: converted MP3 verification failed: $file" >&2
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
		printf 'fixed tag encoding: %s\n' "${audio_files[$index]}"
	done
	printf 'fixed tag encoding in %d MP3 file(s)\n' "${#audio_files[@]}"
}

stage::run() {
	stage::parse_arguments "$@"
	common::require_commands chmod cp exiftool ffprobe grep iconv jq mid3iconv mktemp mv realpath rm || exit 1
	stage::validate_encoding
	common::require_workspace || exit 1
	stage::validate_files
	stage::prepare_updates
	stage::replace_originals
}
