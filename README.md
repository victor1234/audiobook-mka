# Audiobooks

A collection of Bash scripts for turning a directory of audio tracks into a
single Matroska Audio (`.mka`) audiobook with chapters, global metadata, and
cover art.

The scripts operate on one audiobook directory at a time. Source files are
sorted naturally so numbered tracks such as `2.mp3` come before `10.mp3`.

## Requirements

The project uses [mise](https://mise.jdx.dev/) to add `scripts/` to `PATH` and
to manage development tools, including the
[prek](https://prek.j178.dev/) pre-commit runner. Install the tools declared in
`mise.toml` with:

```bash
mise install
```

The audiobook scripts also require these system commands:

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

## Workflow

Run the pipeline from the directory containing an audiobook's source tracks.
The examples assume the repository is located at `/path/to/audiobooks`.

1. Inspect the source track numbers and titles:

   ```bash
   0-track-tags .
   ```

2. Preview and then apply filenames based on each file's `Track` tag:

   ```bash
   1-rename-track-id --dry-run .
   1-rename-track-id .
   ```

3. Create chapter entries from naturally sorted MP3 files. Chapter names come
   from the files' `Title` tags:

   ```bash
   2-chapters chapters.txt
   ```

4. Extract embedded artwork, remove exact duplicates, and select the largest
   image as `images/cover.jpg`:

   ```bash
   3-images images
   ```

5. Enter the audiobook's global metadata interactively:

   ```bash
   4-audiobook-tags tags.xml
   ```

6. Merge the tracks, chapters, tags, and cover into an MKA file:

   ```bash
   5-create-mka chapters.txt tags.xml images .
   ```

   When no output path is supplied, the filename is generated from the
   `AUTHOR`, `TITLE`, and optional `NARRATOR` tags:

   ```text
   AUTHOR - TITLE {NARRATOR}.mka
   ```

   To choose the output path explicitly, pass it as the fifth argument:

   ```bash
   5-create-mka chapters.txt tags.xml images . audiobook.mka
   ```

Every script provides detailed command help:

```bash
5-create-mka --help
```

## Additional commands

Inspect the raw ID3 metadata in a source audio file with:

```bash
show-tags track.mp3
```

When invoking a script through mise while working in another directory, pass
the absolute directory where appropriate:

```bash
mise exec -- 0-track-tags "$PWD"
```

## Project structure

```text
.
├── mise.toml       # Development tools and scripts PATH configuration
├── scripts/        # Audiobook preparation and MKA creation commands
└── data/           # Local source material and generated audiobook data
```

Scripts process only files directly inside the selected audiobook directory;
they do not scan nested directories recursively. Existing MKA outputs and
sidecar files are excluded from source-audio discovery.

## Development

Install the repository's Git pre-commit hook after installing the mise tools:

```bash
mise exec -- prek install
```

Run shfmt and ShellCheck across all shell scripts before committing changes:

```bash
mise exec -- prek run --all-files
```

To run one check independently, continue to invoke it through prek:

```bash
mise exec -- prek run shfmt --all-files
mise exec -- prek run shellcheck --all-files
```

Keep scripts documented with focused comments and a useful `--help` output.
