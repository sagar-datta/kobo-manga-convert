#!/bin/zsh

# Terminal UI functions from mangamerge.sh
spinner_chars=( "|" "/" "-" "\\" )
current_message=""
spinner_index=0

# Function to display spinner with status message
show_status() {
    local msg="$1"
    current_message="$msg"
    tput sc
    printf "\r[ %s ] %s" "${spinner_chars[$((spinner_index % 4))]}" "$msg"
    tput rc
    ((spinner_index++))
}

show_success() {
    printf "\r[+] %s\n" "$1"
    current_message=""
}

show_error() {
    printf "\r[-] %s\n" "$1"
    current_message=""
}

show_debug() {
    printf "\r    %s\n" "$1"
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

input="$1"

# Validate input
if [ ! -e "$input" ]; then
    show_error "Error: Input $input not found"
    exit 1
fi

# Get absolute path of input
input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
base_name="${input%.*}"

# Ask about spread detection
echo -n "Do you need double spread detection? (y/N): "
read spread_detection
spread_detection=${spread_detection:l} # Convert to lowercase

temp_dir=$(mktemp -d)
working_dir="$temp_dir/working"
mkdir -p "$working_dir"

# Extract/copy files to working directory
if [[ "$input" =~ \.(cbz|zip)$ ]]; then
    show_status "Extracting archive..."
    unzip -q "$input" -d "$working_dir"
else
    show_status "Copying directory contents..."
    cp -r "$input"/* "$working_dir"
fi

# Modify the spread detection section:
if [[ "$spread_detection" == "y"* ]]; then
    show_status "Running spread detection..."
    
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
            show_debug "Skipping white page: $file"
            continue
        fi
        files+=("$file")
    done < <(find . -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) -print0)
    
    if [ ${#files[@]} -gt 0 ]; then
        files=("${(@On)files[@]}")
    fi
    
    # Process spreads (using functions from mangamerge.sh)
    start_num=99
    for ((i=1; i<=${#files[@]}; i+=2)); do
        if [ $i -lt ${#files[@]} ]; then
            if should_merge "$files[$i]" "$files[$((i+1))]"; then
                show_status "Merging pages ${files[$i]} and ${files[$((i+1))]}"
                magick "$files[$i]" "$files[$((i+1))]" +append "$merged_dir/${start_num}.jpg"
                ((start_num--))
            else
                cp "$files[$i]" "$merged_dir/${start_num}.jpg"
                ((start_num--))
                cp "$files[$((i+1))]" "$merged_dir/${start_num}.jpg"
                ((start_num--))
            fi
        else
            cp "$files[$i]" "$merged_dir/${start_num}.jpg"
        fi
    done
    
    # Set working directory to merged directory for conversion
    working_dir="$merged_dir"
fi

# Create output filename
output="${base_name}_Kobo.cbz"

# Convert to Kobo format
show_status "Converting to Kobo format..."
if "$(dirname "$0")/kcc-wrapper.sh" -p KoL -f CBZ -m -c 1 --cp 1.0 -u --mozjpeg --splitter 2 -o "$output" "$working_dir"; then
    show_success "Conversion complete! Output saved as $output"
    
    # Clean up
    [ -d "$temp_dir" ] && rm -rf "$temp_dir"
    
    # Ask about moving original to trash
    echo -n "Move original to trash? (y/N): "
    read move_to_trash
    # Add this function near the top with other utility functions
    get_trash_dir() {
        case "$(uname)" in
            "Darwin") echo "$HOME/.Trash" ;;  # macOS
            "Linux")  echo "$HOME/.local/share/Trash/files" ;;  # Linux
            *) echo "$HOME/.Trash" ;;  # Default fallback
        esac
    }
    
    # Replace the trash section
    if [[ "${move_to_trash:l}" == "y"* ]]; then
        trash_dir=$(get_trash_dir)
        if [ -d "$trash_dir" ]; then
            mv "$input" "$trash_dir/"
            show_success "Moved to trash: $input"
        else
            show_error "Trash directory not found: $trash_dir"
            show_debug "File was not moved"
        fi
    fi
else
    show_error "Error during conversion of $input"
    [ -d "$temp_dir" ] && rm -rf "$temp_dir"
fi

show_success "Processing complete!"