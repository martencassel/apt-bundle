# apt-bundle

`apt-bundle` is a script to download and bundle APT packages along with their dependencies for offline use.

## Features

- Download APT packages and their dependencies.
- Create a self-contained bundle for offline installation.
- Generate an index of downloaded packages.

## Quick Start

Run the script directly using `curl`:

```bash
curl -sL https://bit.ly/421Q5Ao | sudo bash -- <package1> <package2> ... [options]
```

### Example:

```bash
curl -sL https://bit.ly/421Q5Ao | sudo bash -- git curl --create-bundle
```

```bash
apt-bundle.sh git curl --create-bundle
```


## Options

- `--create-bundle`: Create a tar.gz bundle of downloaded packages.
- `--outdir <directory>`: Specify the download directory.
- `--output <file>`: Specify the index file name.
- `--help`: Show usage information.

## Requirements
- `jq` (for JSON processing)
- Root or sudo privileges
