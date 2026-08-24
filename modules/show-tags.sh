# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'EOF'
Usage: audiobook-convert show-tags AUDIO_FILE

Show ID3 tag metadata for one audio file using exiftool.

Arguments:
  AUDIO_FILE  Audio file to inspect.
EOF
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
		*)
			break
			;;
		esac
	done

	if (($# == 0)); then
		echo "error: audio file is required" >&2
		stage::usage >&2
		exit 2
	fi
	if (($# > 1)); then
		echo "error: too many arguments" >&2
		stage::usage >&2
		exit 2
	fi

	audio_file="$1"

}

stage::show_tags() {
# Show raw ID3 fields with group names, duplicate fields, stable sorting, and
# short tag names. This is useful for inspecting source MP3 metadata.
exiftool -G1 -a -sort -s -s -ID3:all "$1"

}

stage::run() {
	stage::parse_arguments "$@"
	stage::show_tags "$audio_file"
}
