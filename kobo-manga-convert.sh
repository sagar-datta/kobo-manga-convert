#!/bin/zsh

# =============================================================================
# Terminal UI Components
# Provides a clean, interactive CLI experience with spinners and status updates.
# Includes functions for showing status, success, error, and debug messages.
# =============================================================================

# Terminal UI functions
show_header() {
    printf "\n\033[1;34m=== %s ===\033[0m\n" "$1"
}

show_status() {
    printf "\033[1;36m→\033[0m %s\n" "$1"
}

show_success() {
    printf "\033[1;32m✓\033[0m %s\n" "$1"
}

show_error() {
    printf "\033[1;31m✗\033[0m %s\n" "$1"
}

show_debug() {
    printf "    \033[1;90m→\033[0m %s\n" "$1"
}

# =============================================================================
# Device Configuration Validation
# Ensures proper device settings are loaded from device-config.sh.
# Validates single device configuration and required parameters.
# =============================================================================

# Source device configuration
if [ ! -f "$(dirname "$0")/device-config.sh" ]; then
    show_error "Device configuration not found at $(dirname "$0")/device-config.sh"
    exit 1
fi

# Check for multiple device configurations
device_count=$(grep -c '^export DEVICE=' "$(dirname "$0")/device-config.sh")
if [ "$device_count" -gt 1 ]; then
    show_error "Multiple device configurations detected in device-config.sh. Please uncomment only one device configuration."
    exit 1
fi

source "$(dirname "$0")/device-config.sh"

if [ -z "$DEVICE" ] || [ -z "$DEVICE_NAME" ]; then
    show_error "Device configuration is incomplete. DEVICE and DEVICE_NAME must be set."
    exit 1
fi

# =============================================================================
# Image Analysis Functions
# Smart detection of double-page spreads and blank pages.
# Uses edge detection and brightness analysis to determine merge candidates.
# =============================================================================

# Function to check if images should be merged
should_merge() {
    local left_image="$1"
    local right_image="$2"
    
    # Edge brightness test
    local left_edge=$(magick "$left_image" -gravity East -crop 5x100+0+0 -format "%[mean]" info:)
    local right_edge=$(magick "$right_image" -gravity West -crop 5x100+0+0 -format "%[mean]" info:)
    
    # Skip if both edges are very bright or very dark
    if (( $(echo "$left_edge > 65000" | bc -l) )) && (( $(echo "$right_edge > 65000" | bc -l) )); then
        return 1
    elif (( $(echo "$left_edge < 500" | bc -l) )) && (( $(echo "$right_edge < 500" | bc -l) )); then
        return 1
    fi
    
    # Edge continuity test
    local temp_left=$(mktemp).png
    local temp_right=$(mktemp).png
    
    magick "$left_image" -gravity East -crop 10x200+0+0 "$temp_left"
    magick "$right_image" -gravity West -crop 10x200+0+0 "$temp_right"
    
    local similarity=$(magick compare -metric MAE "$temp_left" "$temp_right" null: 2>&1 || true)
    rm "$temp_left" "$temp_right"
    
    local normalized_similarity=$(echo "$similarity" | grep -o '([0-9.]*)'| tr -d '()' || echo "$similarity" | awk '{printf "%.6f", $1}')
    
    (( $(echo "$normalized_similarity < 0.4" | bc -l) ))
}

# Add after the should_merge function and before the dependency checks
is_white_page() {
    local image="$1"
    local stats=$(identify -format "%[mean] %[standard-deviation]" "$image")
    local mean=$(echo $stats | cut -d' ' -f1)
    local stddev=$(echo $stats | cut -d' ' -f2)
    
    # If mean is very high (close to white) and standard deviation is very low (uniform color)
    (( $(echo "$mean > 65000" | bc -l) )) && (( $(echo "$stddev < 500" | bc -l) ))
}

# =============================================================================
# Dependency Validation
# Checks for required system tools (ImageMagick, unzip) and script dependencies.
# Ensures all necessary components are available before processing.
# =============================================================================

# Check dependencies
if ! command -v magick &> /dev/null || ! command -v unzip &> /dev/null; then
    show_error "Required: ImageMagick and unzip. Please install missing dependencies."
    exit 1
fi

# Check if kcc-wrapper is available
if [ ! -f "$(dirname "$0")/kcc-wrapper.sh" ]; then
    show_error "KCC wrapper not found at $(dirname "$0")/kcc-wrapper.sh"
    exit 1
fi

# =============================================================================
# Input Processing and Workspace Setup
# Handles input validation, path resolution, and temporary workspace creation.
# Supports both archive (.cbz/.zip) and directory inputs.
# =============================================================================

# Check if arguments are provided
if [ $# -eq 0 ]; then
    show_error "Usage: kobo-manga-convert <file.cbz/file.zip/directory>"
    exit 1
fi

# Device configuration should already be set from device-config.sh
if [ -z "$DEVICE" ] || [ -z "$DEVICE_NAME" ]; then
    show_error "Device configuration is incomplete. DEVICE and DEVICE_NAME must be set in device-config.sh"
    exit 1
fi

input="$1"

# Get absolute path of input
input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
base_name="${input%.*}"

# Set output path
output="${base_name}_${DEVICE}.cbz"

show_header "Device Configuration"
show_debug "Using device: $DEVICE_NAME ($DEVICE)"

# =============================================================================
# Spread Detection and Processing
# Optional double-page spread detection and merging.
# Uses intelligent algorithms to identify and combine facing pages.
# =============================================================================

# Before spread detection
show_header "Spread Detection"
echo -n "Do you need double spread detection? (y/N): "
read spread_detection
spread_detection=${spread_detection:l}

temp_dir=$(mktemp -d)
working_dir="$temp_dir/working"
mkdir -p "$working_dir"

# Extract/copy files to working directory
if [[ "$input" =~ \.(cbz|zip)$ ]]; then
    show_status "Preparing workspace - Extracting archive..."
    unzip -q "$input" -d "$working_dir"
else
    show_status "Preparing workspace - Copying directory contents..."
    cp -r "$input"/* "$working_dir"
fi

# Modify the spread detection section:
if [[ "$spread_detection" == "y"* ]]; then
    show_status "Starting spread detection analysis..."
    
    # Create temporary directory for merged spreads
    merged_dir="$temp_dir/merged"
    mkdir -p "$merged_dir"
    
    # Move to working directory
    cd "$working_dir"
    
    # Find and sort all image files
    files=()
    while IFS= read -r -d '' file; do
        file="${file#./}"
        # Skip white pages
        if is_white_page "$file"; then
            show_debug "Detected and skipping blank page: $file"
            continue
        fi
        files+=("$file")
    done < <(find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0)
    
    if [ ${#files[@]} -gt 0 ]; then
        files=("${(@On)files[@]}")
    fi
    
    # Process spreads
    total_files=${#files[@]}
    current_file=0
    start_num=99
    for ((i=1; i<=${#files[@]}; i+=2)); do
        ((current_file+=2))
        if [ $i -lt ${#files[@]} ]; then
            show_status "Processing spreads - ${current_file}/${total_files} pages analyzed"
            if should_merge "$files[$i]" "$files[$((i+1))]"; then
                show_debug "Merging pages ${files[$i]} and ${files[$((i+1))]}"
                magick "$files[$i]" "$files[$((i+1))]" +append "$merged_dir/${start_num}.jpg"
                ((start_num--))
            else
                cp "$files[$i]" "$merged_dir/${start_num}.jpg"
                ((start_num--))
                cp "$files[$((i+1))]" "$merged_dir/${start_num}.jpg"
                ((start_num--))
            fi
        else
            show_status "Processing final page..."
            cp "$files[$i]" "$merged_dir/${start_num}.jpg"
        fi
    done
    show_success "Spread detection and processing complete"
    
    # Set working directory to merged directory for conversion
    working_dir="$merged_dir"
fi

# =============================================================================
# Kobo Format Conversion
# Final conversion to Kobo-optimized format using kcc-wrapper.
# Includes cleanup and optional original file management.
# =============================================================================

# Before conversion
show_header "Kobo Format Conversion"
show_status "Starting conversion process..."
show_debug "Device profile: $DEVICE ($DEVICE_NAME)"
show_debug "Output file: $output"
show_debug "Processing directory: $working_dir"

if "$(dirname "$0")/kcc-wrapper.sh" -p "$DEVICE" -f CBZ -m -c 1 --cp 1.0 -u --mozjpeg --splitter 2 -o "$output" "$working_dir"; then
    show_success "Successfully converted to Kobo format: $output"
    
    # Clean up
    [ -d "$temp_dir" ] && rm -rf "$temp_dir"
    
    show_header "Cleanup"
    echo -n "Move original to trash? (y/N): "
    read move_to_trash
    
    if [[ "${move_to_trash:l}" == "y"* ]]; then
        show_status "Moving original file to trash..."
        trash_dir=$(get_trash_dir)
        if [ -d "$trash_dir" ]; then
            mv "$input" "$trash_dir/"
            show_success "Original file moved to trash"
        else
            show_error "Failed to move to trash: trash directory not found"
            show_debug "Original file was not moved"
        fi
    fi
else
    show_error "Conversion failed for $input"
    [ -d "$temp_dir" ] && rm -rf "$temp_dir"
fi

show_success "All operations completed successfully!"