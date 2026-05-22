# lutifer

`lutifer` is a small command-line Hald CLUT applier written in freepascal.

It takes an input image, a Hald CLUT image, and writes a new image with the colour transform applied:

```sh
lutifer -i input.jpg -l lut.png -o out.jpg
```

A positional form is also accepted:

```sh
lutifer input.jpg lut.png out.jpg
```

Initial version was written with Lazarus for a UI app, and it used Lazarus LCL `Graphics`, `TBitmap`, `TPicture`, `Interfaces`, even GTK2, or an X display. Now we rewrote it to use just FPC `fcl-image` units for loading/saving images and a fast raw-pixel Hald CLUT engine for processing.

## Features

- command-line Hald CLUT application;
- supports PNG, JPEG, BMP, GIF, and TIFF input through FPC image readers;
- writes PNG, JPEG, or BMP depending on output filename extension;
- configurable JPEG quality with `-q` / `--quality`;
- multithreaded LUT application through `MTProcs`;
- optimized processing path using [compact pixel arrays](https://wiki.lazarus.freepascal.org/Fast_direct_pixel_access). (previously we used slower per-pixel `Colors[x, y]` access in the hot loop)

## Usage

```sh
lutifer -i INPUT -l LUT.png -o OUTPUT
```

Examples:

```sh
lutifer -i photo.jpg -l warm-hald.png -o photo-warm.jpg
lutifer -i photo.jpg -l warm-hald.png -o photo-warm.png
lutifer -q 95 -i photo.jpg -l warm-hald.png -o photo-warm-q95.jpg
lutifer -v -i photo.jpg -l lut.png -o out.jpg
```

Positional shorthand:

```sh
lutifer photo.jpg lut.png out.jpg
```

Help:

```sh
lutifer --help
```

## Options

| Option | Meaning |
|---|---|
| `-i`, `--input FILE` | Input image file |
| `-l`, `--lut FILE` | Hald CLUT image, usually PNG |
| `-o`, `--output FILE` | Output image file |
| `-q`, `--quality N`, `--jpeg-quality N` | JPEG quality, `1..100`; default is `92` |
| `-v`, `--verbose` | Print progress information |
| `-h`, `--help` | Show usage help |

## Output format

The output writer is selected from the output filename extension:

| Extension | Output format |
|---|---|
| `.png` | PNG |
| `.jpg`, `.jpeg` | JPEG |
| `.bmp` | BMP |
| anything else | PNG |

JPEG is lossy. There's an option `-q` to control JPEG quality:

```sh
lutifer -i input.jpg -l lut.png -o out.jpg -q 92
lutifer -i input.jpg -l lut.png -o out.jpg -q 97
```

Higher JPEG quality usually produces a larger file. PNG output is lossless but can be larger and slower to write.

## About Hald CLUTs

A Hald CLUT stores a 3D colour lookup table as a 2D image. A typical workflow is:

1. start with a neutral Hald CLUT image;
2. edit that image in a photo editor or colour-grading tool;
3. save the edited Hald CLUT as PNG;
4. apply it to photos with `lutifer`.

`lutifer` checks that the LUT dimensions look like a valid Hald CLUT before applying it. Do not resize or crop the LUT image after generating it.

## Building

Requirements:

- Free Pascal Compiler;
- FPC image units, especially `fcl-image` readers/writers;
- Lazarus `multithreadprocs` / `MTProcs` unit`(this is only build time dependency);
- local source files:
  - `lutifer.pas`
  - `haldclut.pas`
  - `Makefile`

Build:

```sh
make
```

Clean:

```sh
make clean
```

A minimal current build rule looks like this:

```makefile
UNITDIR ?= build/units
OUTFILE ?= lutifer
FPC ?= fpc

PARAMS = \
  -FU$(UNITDIR) \
  -MObjFPC -Scgi \
  -O3 -OoREGVAR -OoUNCERTAIN -OoLOOPUNROLL \
  -Xs -XX \
  -vewnhi \
  -Fu/usr/lib/fpc/3.2.2/units/$(shell uname -m)-linux/* \
  -Fu. \
  -o$(OUTFILE)
```

On some systems you may need to adjust the FPC unit path. For example, on non-`x86_64` systems or distributions with a different FPC layout, check where your `.ppu` files are installed:

```sh
find /usr/lib/fpc -name fpimage.ppu -o -name mtprocs.ppu
```

```sh
find /usr/share/lazarus -name mtprocs.ppu
```

Then add the corresponding directories with `-Fu...`.

## Performance notes

The first working version used high-level image pixel access. That is simple, but slow. The current engine converts image data once into compact raw pixel arrays, applies the LUT there, and copies the result back once for saving.

This avoids expensive property access such as:

```pascal
Image.Colors[X, Y]
```

inside the inner loop.

We also switched from floating-point to integer arithmetic, but that does not impact the speed as much as the pixel access.

The current interpolation path uses integer/fixed-point-style arithmetic. For ordinary 8-bit JPEG/PNG input and 8-bit LUT PNG files, this is usually visually indistinguishable from `Double` interpolation, while being faster. A future `--precise` mode could be added if exact comparison with a floating-point implementation is needed.

JPEG load/save time can still dominate total runtime on large images.

## Multithreading

On Unix, `cthreads` must be included before other threading-related units in the main program. `lutifer.pas` does this:

```pascal
uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  ...
```

The Hald CLUT work is split into blocks and dispatched through `ProcThreadPool.DoParallel` from `MTProcs`.

There is currently no `--threads N` command-line option. Thread count is controlled by the MTProcs thread pool defaults. A future version could expose a thread-count setting.

## Batch examples

Write PNG files into an `out/` directory:

```sh
mkdir -p out
for img in *.jpg; do
  base=${img%.*}
  ./lutifer -i "$img" -l my-lut.png -o "out/${base}.png"
done
```

Write JPEG files with quality 95:

```sh
mkdir -p out
for img in *.jpg; do
  base=${img%.*}
  ./lutifer -q 95 -i "$img" -l my-lut.png -o "out/${base}-lut.jpg"
done
```

Verbose batch run:

```sh
for img in *.jpg; do
  ./lutifer -v -i "$img" -l my-lut.png -o "${img%.jpg}-lut.jpg"
done
```

## Project files

Our current source tree:

```text
lutifer.pas      command-line frontend, image loading/saving, option parsing
haldclut.pas     headless fast Hald CLUT engine
Makefile         FPC build rules
readme.md        this file
```

## Exit codes

| Code | Meaning |
|---:|---|
| `0` | Success |
| `1` | Usage error, for example missing `-i`, `-l`, or `-o` |
| `2` | Runtime failure, for example unreadable file or invalid LUT |

## Troubleshooting

### `No widgetset object`

You are probably building/running the older LCL/`Graphics` version. Use the headless version that imports `FPImage`, `FPReadPNG`, `FPReadJPEG`, etc., and does **not** import `Graphics` or `Interfaces`.

### `Can't find unit fpimage`, `FPReadJPEG`, or similar

Your FPC image units are not installed or not in the compiler search path. Locate them:

```sh
find /usr/lib/fpc -name fpimage.ppu -o -name fpreadjpeg.ppu
```

Then add the directory to the Makefile with `-Fu...`.

### `Can't find unit mtprocs`

Install Lazarus or the Lazarus component units that provide `MTProcs`, then add the correct directory to `-Fu...`. Depending on distro layout, it may be under something like:

```text
/usr/share/lazarus/components/multithreadprocs/lib/<arch>
```

or a packaged FPC/Lazarus units directory.

### LUT dimensions do not look like a Hald CLUT

The LUT image is probably not a Hald CLUT, or it was resized/cropped. Use a real neutral or edited Hald CLUT PNG and keep its original dimensions.

### Output JPEG is too small or too large

Use `-q`:

```sh
./lutifer -q 97 -i input.jpg -l lut.png -o out.jpg
```

A higher value generally means less compression and a larger file.

## License

GPL-3
