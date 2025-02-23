# Kobo Manga Convert

A script to convert manga files (CBZ/ZIP/directory) into a format optimized for Kobo e-readers. Features include:

- Double-spread page detection and merging
- White page removal
- Kobo-optimized output format
- Support for both macOS and Linux

## Prerequisites

1. **Zsh Shell**

   - Pre-installed on macOS
   - Linux: `sudo apt-get install zsh` (Ubuntu/Debian)

2. **ImageMagick**

   - macOS: `brew install imagemagick`
   - Linux: `sudo apt-get install imagemagick` (Ubuntu/Debian)

3. **Unzip**

   - macOS: Pre-installed
   - Linux: `sudo apt-get install unzip` (Ubuntu/Debian)

4. **Kindle Comic Converter (KCC)**
   - Install using pip: `pip install KindleComicConverter`
   - Or follow installation instructions at [KCC GitHub](https://github.com/ciromattia/kcc)

## Installation

1. Clone this repository:

   ```bash
   git clone [repository-url] ~/.scripts/kobo-manga-convert
   ```

2. Make the script executable:

   ```bash
   chmod +x ~/.scripts/kobo-manga-convert/kobo-manga-convert.sh
   ```

3. Add an alias to your shell configuration:

   For Zsh (add to ~/.zshrc):

   ```bash
   echo 'alias manga-convert="~/.scripts/kobo-manga-convert/kobo-manga-convert.sh"' >> ~/.zshrc
   source ~/.zshrc
   ```

## Usage

1. Basic usage:

   ```bash
   manga-convert <input-file>
   ```

   Replace `<input-file>` with your manga file (CBZ/ZIP) or directory path.

2. Example usage:

   ```bash
   manga-convert "~/Downloads/manga-chapter.cbz"
   # or
   manga-convert "~/Downloads/manga-folder"
   ```

3. Interactive prompts:

   - The script will ask if you want to enable double spread detection
   - After conversion, it will ask if you want to move the original file to trash

4. Output:
   - Converted files are saved in the same directory as the input
   - Output filename format: `<original-name>_Kobo.cbz`
