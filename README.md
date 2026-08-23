# Audiobooks

A Bash command for turning a directory of audio tracks into a single Matroska
Audio (`.mka`) audiobook with chapters, global metadata, and cover art.

The processing stages operate on one audiobook directory tree at a time. Source
paths are sorted naturally so numbered directories and tracks retain their
intended playback order.

## Requirements

The audiobook command requires Bash and does not support execution with POSIX
`sh` or other shells.

The project uses [mise](https://mise.jdx.dev/) to add the repository root to `PATH` and
to manage development tools, including the
[prek](https://prek.j178.dev/) pre-commit runner. Install the tools declared in
`mise.toml` with:

```bash
mise install
```

The audiobook stages also require these system commands:

- `exiftool`
- `ffmpeg` and `ffprobe`
- `jq`
- `column`
- `mkvmerge`
- `xmllint`
- standard Unix tools including `awk`, `find`, `sort`, and `sha256sum`

Activate the mise environment from the repository root before using the
commands:

```bash
eval "$(mise activate bash)"
```

Alternatively, prefix an individual command with `mise exec --`.

## CLI

Use the `audiobook-convert` entrypoint to run any processing stage:

```bash
audiobook-convert --help
audiobook-convert track-tags .
audiobook-convert rename-track-id --dry-run .
audiobook-convert chapters chapters.txt
```

Global options are parsed before the subcommand. Use `--` to stop global option
parsing when needed. Each subcommand sources the corresponding numbered module
and receives its remaining arguments unchanged; command-specific options stay
with that module. Stages remain independently runnable through their
subcommands. Use `audiobook-convert help COMMAND` for a stage's detailed help,
for example:

```bash
audiobook-convert help create-mka
```

The entrypoint provides these stage subcommands:

| Subcommand | Sourced module | Stage |
| ----------------- | -------------------- | ----- |
| `track-tags` | `0-track-tags` | 0 |
| `rename-track-id` | `1-rename-track-id` | 1 |
| `chapters` | `2-chapters` | 2 |
| `images` | `3-images` | 3 |
| `audiobook-tags` | `4-audiobook-tags` | 4 |
| `create-mka` | `5-create-mka` | 5 |

Successful commands and help requests exit with status 0. Invalid CLI usage,
including a missing or unknown command or option, exits with status 2 after
printing an error to standard error. Processing failures exit with status 1.

The additional `show-tags` utility is available as `audiobook-convert show-tags`.

## Workflow

Run each needed stage from the directory containing an audiobook's source
tracks. No automatic pipeline is provided.

1. Inspect the source track numbers and titles:

   ```bash
   audiobook-convert track-tags .
   ```

1. Preview and then apply filenames based on each file's `Track` tag:

   ```bash
   audiobook-convert rename-track-id --dry-run .
   audiobook-convert rename-track-id .
   ```

1. Create chapter entries from recursively discovered, naturally sorted MP3
   files. Chapter names come from the files' `Title` tags; every MP3 becomes one
   chapter even when the files are arranged in nested directories:

   ```bash
   audiobook-convert chapters chapters.txt
   ```

1. Extract embedded artwork, remove exact duplicates, and select the largest
   image as `images/cover.jpg`:

   ```bash
   audiobook-convert images images
   ```

1. Enter the audiobook's global metadata interactively:

   ```bash
   audiobook-convert audiobook-tags tags.xml
   ```

1. Merge the tracks, chapters, tags, and cover into an MKA file:

   ```bash
   audiobook-convert create-mka chapters.txt tags.xml images .
   ```

   When no output path is supplied, the filename is generated from the
   `AUTHOR`, `TITLE`, and optional `NARRATOR` tags:

   ```text
   AUTHOR - TITLE {NARRATOR}.mka
   ```

   To choose the output path explicitly, pass it as the fifth argument:

   ```bash
   audiobook-convert create-mka chapters.txt tags.xml images . audiobook.mka
   ```

Every stage provides detailed command help:

```bash
audiobook-convert create-mka --help
```

## Additional commands

Inspect the raw ID3 metadata in a source audio file with:

```bash
audiobook-convert show-tags track.mp3
```

When invoking a script through mise while working in another directory, pass
the absolute directory where appropriate:

```bash
mise exec -- audiobook-convert track-tags "$PWD"
```

## Project structure

```text
.
├── audiobook-convert      # Executable CLI entrypoint
├── mise.toml               # Development tools and repository PATH configuration
├── modules/                 # Sourced stage modules and proven shared helpers
└── data/                   # Local source material and generated audiobook data
```

`modules/common.sh` contains only helpers already used by at least two stage
modules. Argument handling, validation, transformations, and output behavior
remain in the module for the stage that owns them.

Stages recursively process files beneath the selected audiobook directory.
Existing MKA outputs and sidecar files are excluded from source-audio
discovery, and directory symlinks are not followed.

## Development

Install the repository's Git pre-commit hook after installing the mise tools:

```bash
mise exec -- prek install
```

Run shfmt, ShellCheck, and mdformat across all supported files before committing
changes:

```bash
mise exec -- prek run --all-files
```

To run one check independently, continue to invoke it through prek:

```bash
mise exec -- prek run shfmt --all-files
mise exec -- prek run shellcheck --all-files
mise exec -- prek run mdformat --all-files
```

Keep modules documented with focused comments and useful command help output.
