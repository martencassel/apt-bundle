#!/bin/bash
set +x

# Default folder to store downloaded packages
DOWNLOAD_DIR="/var/cache/apt/archives"
INDEX_FILE="$DOWNLOAD_DIR/index.json"

# Ensure the download directory exists
mkdir -p "$DOWNLOAD_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to parse command line arguments
# Initialize variables
CREATE_BUNDLE=false
PKG_LIST=()

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --create-bundle)
            CREATE_BUNDLE=true
            ;;
        --outdir|-o)
            if [[ -n "$2" && "$2" != --* ]]; then
                DOWNLOAD_DIR="$2"
                shift
            else
                echo -e "${RED}Error: --outdir or -o requires a directory path.${RESET}"
                exit 1
            fi
            ;;
        --output)
            if [[ -n "$2" ]]; then
                INDEX_FILE="$2"
                shift
            else
                echo -e "${RED}Error: --output requires a file name.${RESET}"
                exit 1
            fi
            ;;
        --help)
            echo -e "${CYAN}Usage:${RESET} $0 <package1> <package2> ... [--create-bundle] [--outdir <directory>] [--output <file>]"
            exit 0
            ;;
        *)
            # Treat all other arguments as package names
            PKG_LIST+=("$1")
            ;;
    esac
    shift
done

# Ensure the download directory exists
mkdir -p "$DOWNLOAD_DIR"
INDEX_FILE="$DOWNLOAD_DIR/index.json"

# Check if at least one package is provided
if [ ${#PKG_LIST[@]} -eq 0 ]; then
    echo -e "${RED}Error: No packages specified.${RESET}"
    echo -e "${CYAN}Usage:${RESET} $0 <package1> <package2> ... [--create-bundle] [--outdir <directory>] [--output <file>]"
    exit 1
fi

# Debug output (optional)
echo -e "${CYAN}Packages to process:${RESET} ${PKG_LIST[*]}"
echo -e "${CYAN}Download directory:${RESET} $DOWNLOAD_DIR"
if $CREATE_BUNDLE; then
    echo -e "${CYAN}The --create-bundle flag is set.${RESET}"
fi


# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed. Please install jq and try again.${RESET}"
    exit 1
fi

# Check if the script is running as root or if sudo is available
if [ "$EUID" -ne 0 ]; then
    if ! command -v sudo &> /dev/null; then
        echo -e "${RED}This script requires root privileges. Please run as root or install sudo.${RESET}"
        exit 1
    fi
    SUDO="sudo"
else
    SUDO=""
fi

# Update the package cache
echo -e "${CYAN}Updating package cache...${RESET}"
$SUDO apt update

# Precheck if all requested packages are available
echo -e "${CYAN}Checking package availability...${RESET}"
UNAVAILABLE_PACKAGES=()
for package in "${PKG_LIST[@]}"; do
    # Skip commands like --create-bundle, --list-sources, etc.
    if [[ "$package" == --* ]]; then
        continue
    fi

    if ! apt-cache show "$package" &> /dev/null; then
        UNAVAILABLE_PACKAGES+=("$package")
    fi
done

if [ ${#UNAVAILABLE_PACKAGES[@]} -gt 0 ]; then
    echo -e "${RED}The following packages are not available:${RESET}"
    for pkg in "${UNAVAILABLE_PACKAGES[@]}"; do
        echo -e "  - ${RED}$pkg${RESET}"
    done
    echo -e "${YELLOW}Please check the package names or ensure the correct repositories are configured.${RESET}"
    exit 1
fi

echo -e "${GREEN}All requested packages are available.${RESET}"

# Initialize counters
SUCCESS_COUNT=0
FAIL_COUNT=0
FAILED_PACKAGES=()
DOWNLOADED_PACKAGES=()

# Load existing index.json if it exists
if [ -f "$INDEX_FILE" ]; then
    echo -e "${CYAN}Existing index.json found. Loading...${RESET}"
    EXISTING_INDEX=$(jq '.' "$INDEX_FILE")
else
    EXISTING_INDEX='{"directory": "'"$DOWNLOAD_DIR"'", "host_info": {}, "files": [], "dependency_tree": {}}'
fi

# Function to check if a package is already downloaded and indexed
is_package_downloaded() {
    local package="$1"
    local deb_file

    # Find the .deb file for the package in the download directory
    deb_file=$(find "$DOWNLOAD_DIR" -name "${package}_*.deb" | head -n 1)

    if [ -n "$deb_file" ]; then
        # Check if the file is already in the index
        if echo "$EXISTING_INDEX" | jq -e ".files[] | select(.file == \"$deb_file\")" &> /dev/null; then
            echo -e "${YELLOW}Package $package is already downloaded and indexed. Skipping...${RESET}"
            return 0
        else
            echo -e "${YELLOW}Package $package is already downloaded but not indexed. Adding to index...${RESET}"
            return 2
        fi
    fi

    # Package is not downloaded
    return 1
}

# Function to generate the dependency tree for a package
generate_dependency_tree() {
    local package="$1"
    apt-cache depends "$package" | awk '/Depends:/ {print $2}' | jq -R . | jq -s .
}

# Loop through each package and download it with dependencies
for package in "${PKG_LIST[@]}"; do
    echo "${CYAN}Processing package: ${YELLOW}$package${RESET}"
    # Check if the package includes a version (e.g., gitlab-ee=15.10.0-ee.0)
    # --create-bundle and --list-sources are skipped
    if [[ "$package" == --* ]]; then
        continue
    fi
    if [[ "$package" == *"="* ]]; then
        PACKAGE_NAME="${package%%=*}"
        PACKAGE_VERSION="${package##*=}"
        echo -e "${BLUE}Processing package: ${YELLOW}$PACKAGE_NAME (version: $PACKAGE_VERSION)${RESET}"
    else
        PACKAGE_NAME="$package"
        PACKAGE_VERSION=""
        echo -e "${BLUE}Processing package: ${YELLOW}$PACKAGE_NAME${RESET}"
    fi

    is_package_downloaded "$PACKAGE_NAME"
    case $? in
        0)
            # Package is already downloaded and indexed
            continue
            ;;
        2)
            # Package is downloaded but not indexed
            ABS_PATH=$(find "$DOWNLOAD_DIR" -name "${PACKAGE_NAME}_*.deb" | head -n 1)
            CHECKSUM=$(sha256sum "$ABS_PATH" | awk '{print $1}')
            NEW_FILES+=("{\"file\": \"$ABS_PATH\", \"checksum\": \"$CHECKSUM\", \"checksum_type\": \"sha256\"}")
            continue
            ;;
        1)
            # Package is not downloaded, proceed to download
            echo "${CYAN}Downloading package: ${YELLOW}$PACKAGE_NAME${RESET}"
            if [ -n "$PACKAGE_VERSION" ]; then
                echo -e "${BLUE}Downloading specific version: ${YELLOW}$PACKAGE_NAME=$PACKAGE_VERSION${RESET}"
                $SUDO apt-get install --download-only -y "$PACKAGE_NAME=$PACKAGE_VERSION"
            else
                echo -e "${BLUE}Downloading latest version: ${YELLOW}$PACKAGE_NAME${RESET}"
                $SUDO apt-get install --download-only -y "$PACKAGE_NAME"
            fi
            ls -l "$DOWNLOAD_DIR" | grep "$PACKAGE_NAME"

            if [ $? -eq 0 ]; then
                echo -e "${GREEN}Downloaded $PACKAGE_NAME and its dependencies to $DOWNLOAD_DIR${RESET}"
                ((SUCCESS_COUNT++))
                DOWNLOADED_PACKAGES+=("$PACKAGE_NAME")
            else
                echo -e "${RED}Failed to download $PACKAGE_NAME. Skipping...${RESET}"
                ((FAIL_COUNT++))
                FAILED_PACKAGES+=("$PACKAGE_NAME")
            fi
            ;;
    esac
done

# Display summary
echo -e "\n${CYAN}Download Summary:${RESET}"
echo -e "${GREEN}Successfully downloaded packages: $SUCCESS_COUNT${RESET}"
if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${RED}Failed to download packages: $FAIL_COUNT${RESET}"
    echo -e "${YELLOW}Failed packages:${RESET}"
    for failed in "${FAILED_PACKAGES[@]}"; do
        echo -e "  - ${RED}$failed${RESET}"
    done
else
    echo -e "${GREEN}All packages downloaded successfully!${RESET}"
fi

# Prepare new entries for files and dependency tree
NEW_FILES=()
NEW_DEPENDENCY_TREE=$(jq -n '{}')

for deb_file in "$DOWNLOAD_DIR"/*.deb; do
    if [ -f "$deb_file" ]; then
        ABS_PATH=$(realpath "$deb_file")
        CHECKSUM=$(sha256sum "$deb_file" | awk '{print $1}')

        # Check if the file is already in the index
        if ! echo "$EXISTING_INDEX" | jq -e ".files[] | select(.file == \"$ABS_PATH\")" &> /dev/null; then
            echo -e "${BLUE}Adding new file to index: ${YELLOW}$ABS_PATH${RESET}"
            NEW_FILES+=("{\"file\": \"$ABS_PATH\", \"checksum\": \"$CHECKSUM\", \"checksum_type\": \"sha256\"}")
        fi
    fi
done

for package in "${DOWNLOADED_PACKAGES[@]}"; do
    if ! echo "$EXISTING_INDEX" | jq -e ".dependency_tree[\"$package\"]" &> /dev/null; then
        echo -e "${BLUE}Adding new dependency tree for package: ${YELLOW}$package${RESET}"
        NEW_DEPENDENCY_TREE=$(echo "$NEW_DEPENDENCY_TREE" | jq ". + {\"$package\": $(generate_dependency_tree "$package")}")
    fi
done

# Merge new entries into the existing index
UPDATED_INDEX=$(echo "$EXISTING_INDEX" | jq \
    --argjson newFiles "[$(IFS=,; echo "${NEW_FILES[*]}")]" \
    --argjson newDeps "$NEW_DEPENDENCY_TREE" \
    '.files += $newFiles | .dependency_tree += $newDeps')

# Save the updated index to the file
echo "$UPDATED_INDEX" > "$INDEX_FILE"

# Generate a checksum file for the index.json
CHECKSUM_FILE="${INDEX_FILE}.sha512"
echo -e "${CYAN}Generating checksum file with progress: ${YELLOW}$CHECKSUM_FILE${RESET}"

# Check if `pv` is installed
if ! command -v pv &> /dev/null; then
    echo -e "${YELLOW}Warning: 'pv' is not installed. Progress status will not be displayed.${RESET}"
    echo -e "${CYAN}Generating checksum without progress...${RESET}"
    sha512sum "$INDEX_FILE" > "$CHECKSUM_FILE"
else
    # Use `pv` to display progress
    FILE_SIZE=$(stat --printf="%s" "$INDEX_FILE")
    pv -s "$FILE_SIZE" "$INDEX_FILE" | sha512sum > "$CHECKSUM_FILE"
fi

# Display the checksum file content
echo -e "${GREEN}Checksum file created successfully:${RESET}"
cat "$CHECKSUM_FILE"



# Handle the --create-bundle command at the end of
if $CREATE_BUNDLE; then
    BUNDLE_NAME="apt-package-bundle.tar.gz"
    TEMP_DIR=$(mktemp -d)

    echo -e "${CYAN}Creating a self-contained bundle...${RESET}"

    # Copy all .deb files to the temporary directory
    echo -e "${BLUE}Copying .deb files to the bundle...${RESET}"
    cp "$DOWNLOAD_DIR"/*.deb "$TEMP_DIR"

    # Copy the index.json file to the temporary directory
    if [ -f "$INDEX_FILE" ]; then
        echo -e "${BLUE}Copying index.json to the bundle...${RESET}"
        cp "$INDEX_FILE" "$TEMP_DIR"
    else
        echo -e "${RED}Error: index.json not found. Please run the script to generate it first.${RESET}"
        exit 1
    fi

    # Copy the script itself to the temporary directory
    echo -e "${BLUE}Copying the script to the bundle...${RESET}"
    SCRIPT_PATH=$(realpath "$0")
    cp "$SCRIPT_PATH" "$TEMP_DIR"

    # Download and include jq (statically compiled binary)
    echo -e "${BLUE}Downloading jq binary...${RESET}"
    JQ_BINARY="$TEMP_DIR/jq"
    curl -L -o "$JQ_BINARY" https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64
    chmod +x "$JQ_BINARY"

    # Create the tar.gz bundle
    echo -e "${BLUE}Creating the tar.gz bundle: ${YELLOW}$BUNDLE_NAME${RESET}"
    tar -czf "$BUNDLE_NAME" -C "$TEMP_DIR" .

    echo -e "${GREEN}Bundle created successfully: ${YELLOW}$BUNDLE_NAME${RESET}"
    exit 0
fi
