# This module is sourced by ./audiobook-convert.
stage::usage() {
	cat <<'EOF'
Usage: audiobook-convert audiobook-tags [OUTPUT]

Interactively create a Matroska global tags XML file for an audiobook.

Arguments:
  OUTPUT  Tags XML file to write. Default: tags.xml

If OUTPUT already exists, its values are used as prompt defaults. Press Enter
to keep a default, type - to clear a field, and confirm before writing.
Use the result later with mkvmerge --global-tags.
This command must run inside a workspace created by `audiobook-convert workspace`.
EOF
}

stage::parse_arguments() {
	output="tags.xml"

	while (($# > 0)); do
		case "$1" in
		-h | --help)
			stage::usage
			exit 0
			;;
		--)
			shift
			if (($# > 0)); then
				output="$1"
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
			output="$1"
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

stage::xml_escape() {
	local value="$1"
	value=${value//&/&amp;}
	value=${value//</&lt;}
	value=${value//>/&gt;}
	value=${value//\"/&quot;}
	value=${value//\'/&apos;}
	printf '%s' "$value"
}

# Prompt for one tag. Enter keeps the default; a single dash clears the value.
stage::ask_tag() {
	local key="$1"
	local label="$2"
	local default="$3"
	local input

	if [[ -n "$default" ]]; then
		read -r -p "$label [$default]: " input
	else
		read -r -p "$label: " input
	fi

	case "$input" in
	"")
		printf -v "$key" '%s' "$default"
		;;
	-)
		printf -v "$key" '%s' ""
		;;
	*)
		printf -v "$key" '%s' "$input"
		;;
	esac
}

# Matroska tags are represented as nested Simple elements. Empty fields are
# skipped so the generated XML only contains tags the user chose to keep.
stage::write_simple_tag() {
	local name="$1"
	local value="$2"

	[[ -n "$value" ]] || return 0

	printf '%s\n' '    <Simple>'
	printf '      <Name>%s</Name>\n' "$(stage::xml_escape "$name")"
	printf '      <String>%s</String>\n' "$(stage::xml_escape "$value")"
	printf '%s\n' '      <TagLanguageIETF>und</TagLanguageIETF>'
	printf '%s\n' '    </Simple>'
}

stage::load_tag_defaults() {
default_title="$(common::matroska_tag_value "$output" TITLE)"
# For a new audiobook folder, the directory name is usually a useful title seed.
[[ -n "$default_title" ]] || default_title="$(basename "$PWD")"

default_subtitle="$(common::matroska_tag_value "$output" SUBTITLE)"
default_author="$(common::matroska_tag_value "$output" AUTHOR)"
default_narrator="$(common::matroska_tag_value "$output" NARRATOR)"
default_publisher="$(common::matroska_tag_value "$output" PUBLISHER)"
default_date="$(common::matroska_tag_value "$output" DATE_RELEASED)"
default_language="$(common::matroska_tag_value "$output" LANGUAGE)"
default_genre="$(common::matroska_tag_value "$output" GENRE)"
default_description="$(common::matroska_tag_value "$output" DESCRIPTION)"

}

stage::prompt_for_tags() {
echo "Creating Matroska audiobook tags: $output"
echo "Press Enter to keep the default. Type - to clear a field."
echo

stage::ask_tag title "Title" "$default_title"
stage::ask_tag subtitle "Subtitle" "$default_subtitle"
stage::ask_tag author "Author" "$default_author"
stage::ask_tag narrator "Narrator" "$default_narrator"
stage::ask_tag publisher "Publisher" "$default_publisher"
stage::ask_tag date_released "Release date" "$default_date"
stage::ask_tag language "Language" "$default_language"
stage::ask_tag genre "Genre" "$default_genre"
stage::ask_tag description "Description" "$default_description"

}

stage::show_tag_summary() {
echo
echo "Tags to write:"
printf '  Title: %s\n' "${title:-<empty>}"
printf '  Subtitle: %s\n' "${subtitle:-<empty>}"
printf '  Author: %s\n' "${author:-<empty>}"
printf '  Narrator: %s\n' "${narrator:-<empty>}"
printf '  Publisher: %s\n' "${publisher:-<empty>}"
printf '  Release date: %s\n' "${date_released:-<empty>}"
printf '  Language: %s\n' "${language:-<empty>}"
printf '  Genre: %s\n' "${genre:-<empty>}"
printf '  Description: %s\n' "${description:-<empty>}"
echo

}

stage::confirm_write() {
read -r -p "Write $output? [y/N]: " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
	echo "aborted"
	exit 0
fi

}

stage::write_tags_file() {
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT

# Write to a temporary file first, validate it, then replace the output file.
{
	printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
	printf '%s\n' '<!DOCTYPE Tags SYSTEM "matroskatags.dtd">'
	printf '%s\n' '<Tags>'
	printf '%s\n' '  <Tag>'
	printf '%s\n' '    <Targets />'
	stage::write_simple_tag TITLE "$title"
	stage::write_simple_tag SUBTITLE "$subtitle"
	stage::write_simple_tag AUTHOR "$author"
	stage::write_simple_tag NARRATOR "$narrator"
	stage::write_simple_tag PUBLISHER "$publisher"
	stage::write_simple_tag DATE_RELEASED "$date_released"
	stage::write_simple_tag LANGUAGE "$language"
	stage::write_simple_tag GENRE "$genre"
	stage::write_simple_tag DESCRIPTION "$description"
	printf '%s\n' '  </Tag>'
	printf '%s\n' '</Tags>'
} >"$tmp_file"

xmllint --noout "$tmp_file"
mv "$tmp_file" "$output"
trap - EXIT

}

stage::report_created_tags() {
echo "created $output"

}

stage::run() {
	stage::parse_arguments "$@"
	common::require_commands realpath xmllint || exit 1
	common::require_workspace || exit 1
	common::require_workspace_output "$output" || exit 1
	stage::load_tag_defaults
	stage::prompt_for_tags
	stage::show_tag_summary
	stage::confirm_write
	stage::write_tags_file
	stage::report_created_tags
}
