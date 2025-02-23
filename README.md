# Kobo Manga Convert 📚

A smart manga conversion script optimised for e-readers that automatically detects and merges double-page spreads while removing blank pages. Currently only tested with zsh on macOS.

## Features ✨

- Automatic double-page spread detection and merging
- Blank page detection and removal
- Interactive terminal UI with progress indicators
- Support for CBZ/ZIP archives or directories as input
- Optimised output for various e-reader devices
- Optional original file cleanup

## Prerequisites ⚙️

1. Install ImageMagick:

- For installation instructions, visit the [ImageMagick GitHub repository](https://github.com/ImageMagick/ImageMagick).

```bash
brew install imagemagick
```

2. Install KCC (Kindle Comic Converter):

- For installation instructions, visit the [KCC GitHub repository](https://github.com/ciromattia/kcc).

## Device Configuration 📱

1. Edit `device-config.sh` and uncomment the line for your device. For example, for Kobo Libra:

```bash
export DEVICE="KoL" DEVICE_NAME="Kobo Libra H2O/Kobo Libra 2"
```

Only one device should be uncommented at a time.

## Usage 🚀

```bash
./kobo-manga-convert.sh <input.cbz/input.zip/directory>
```

The script will:

1. Ask if you want to enable double-page spread detection
2. Process the input, detecting and merging spreads if enabled
3. Remove any blank pages
4. Convert to your device's optimal format
5. Optionally move the original file to trash

Output will be saved as `<input>_<device>.cbz` in the same directory as the input.

## KCC Wrapper 🛠️

The `kcc-wrapper` is a script that simplifies the usage of the Kindle Comic Converter (KCC). It acts as a convenient interface, allowing users to easily convert comic files into formats compatible with Kindle devices without needing to manually invoke KCC commands.

### How It Works:

- **Input Handling**: The wrapper accepts various input formats, including CBZ and ZIP files, as well as directories containing images.
- **Configuration**: It reads the device configuration from `device-config.sh`, ensuring that the output is optimised for the selected Kindle device.
- **Conversion Process**: The wrapper automates the process of calling KCC with the appropriate parameters, handling any necessary pre-processing, such as merging double-page spreads and removing blank pages.
- **Output Management**: After conversion, the wrapper saves the output file in the same directory as the input, appending the device name to the filename for easy identification.

This makes it easier for users to convert their comic files with minimal setup and configuration.

## Supported Devices 📖

The script supports various Kindle, Kobo, and reMarkable devices. Check `device-config.sh` for the full list of supported devices.

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
