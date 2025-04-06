# apt-bundle

`apt-bundle` is a script to download and bundle APT packages along with their dependencies for offline use.

## Features

- Download APT packages and their dependencies.
- Create a self-contained bundle for offline installation.
- Generate an index of downloaded packages.

## Quick Start

Run the script directly using `curl`:

### Example 1

```bash
curl -sL https://bit.ly/421Q5Ao > apt-bundle; chmod u+x apt-bundle
./apt-bundle git --create-bundle
tar tvf apt-package-bundle.tar.gz |wc -l
30
```

### Example 2

```bash
apt-bundle.sh git curl --create-bundle
```

### Example 3

```bash
docker run -it -v $(pwd):/host debian:12.9

apt update && apt install jq
curl -sL https://bit.ly/421Q5Ao > apt-bundle; chmod u+x apt-bundle

./apt-bundle git --create-bundle

cp apt-package-bundle.tar.gz /host/
```


## Options

- `--create-bundle`: Create a tar.gz bundle of downloaded packages.
- `--outdir <directory>`: Specify the download directory.
- `--output <file>`: Specify the index file name.
- `--help`: Show usage information.

## Requirements
- `jq` (for JSON processing)
- Root or sudo privileges
