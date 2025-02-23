#!/bin/zsh

# Source device configuration
if [ ! -f "$(dirname "$0")/device-config.sh" ]; then
    show_error "Device configuration not found at $(dirname "$0")/device-config.sh"
    exit 1
fi

source "$(dirname "$0")/device-config.sh"

if [ -z "$DEVICE" ] || [ -z "$DEVICE_NAME" ]; then
    show_error "Device configuration is incomplete. DEVICE and DEVICE_NAME must be set."
    exit 1
fi

# Terminal UI functions from mangamerge.sh
spinner_chars=( "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏" )
current_message=""
spinner_index=0

# Function to display spinner with status message
show_status() {
    local msg="$1"
    current_message="$msg"
    printf "\r\033[K[ \033[1;36m%s\033[0m ] %s" "${spinner_chars[$((spinner_index % 10))]}" "$msg"
    ((spinner_index++))
}

show_success() {
    printf "\r\033[K\033[1;32m[✓]\033[0m %s\n" "$1"
    current_message=""
}

show_error() {
    printf "\r\033[K\033[1;31m[✗]\033[0m %s\n" "$1"
    current_message=""
}

show_debug() {
    printf "\r\033[K    \033[1;90m→\033[0m %s\n" "$1"
}

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

show_debug "Using device: $DEVICE_NAME ($DEVICE)"

# Validate input
if [ ! -e "$input" ]; then
    show_error "Error: Input $input not found"
    exit 1
fi

# Ask about spread detection
echo -n "Do you need double spread detection? (y/N): "
read spread_detection
spread_detection=${spread_detection:l} # Convert to lowercase

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
    show_status "Analyzing pages for spread detection..."
    
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
            show_status "Processing final page - ${current_file}/${total_files}"
            cp "$files[$i]" "$merged_dir/${start_num}.jpg"
        fi
    done
    show_success "Spread detection and processing complete"
    
    # Set working directory to merged directory for conversion
    working_dir="$merged_dir"
fi

# Convert to Kobo format
show_status "Initializing Kobo format conversion..."
show_debug "Device profile: $DEVICE ($DEVICE_NAME)"
show_debug "Output file: $output"
show_debug "Processing directory: $working_dir"

if "$(dirname "$0")/kcc-wrapper.sh" -p "$DEVICE" -f CBZ -m -c 1 --cp 1.0 -u --mozjpeg --splitter 2 -o "$output" "$working_dir"; then
    show_success "Successfully converted to Kobo format: $output"
    
    # Clean up
    [ -d "$temp_dir" ] && rm -rf "$temp_dir"
    
    # Ask about moving original to trash
    echo -n "\nMove original to trash? (y/N): "
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