# SnapText

SnapText is a macOS menu bar app that reads text from an image on your Mac. Drop an image on its icon, choose a file, paste an image, or select an area of the screen. The text shows up in a small panel, where you can edit it and copy it.

Recognition uses Apple’s Vision framework and stays on this Mac. SnapText does not upload the image or the text.

## Download

You can install and use SnapText without building it. Download [SnapText-0.3.1.zip](https://github.com/etc11/SnapText/releases/tag/v0.3.1). Unzip it and move SnapText.app to Applications. You need macOS 14 or newer.

## What you need to build

macOS 14 or newer, and Xcode or the Swift command-line tools. There are no extra packages to install and no account to sign in to.

## Build

In this folder, run:

```sh
swift build -c release
```

## Run

```sh
swift run -c release
```

You can also open the built program directly:

```sh
.build/release/SnapText
```

SnapText sits in the menu bar and does not add a Dock icon. Starting it yourself opens the panel. If macOS starts it at login, it stays in the menu bar until you click the icon.

To read one image file and print the text:

```sh
.build/release/SnapText --ocr /path/to/image.png
```

## How to use it

- Drop one image on the menu bar icon, or onto the image area in the panel.
- **Choose image** opens a file picker. **Paste image** uses an image already on the clipboard. **Clear** removes the current image and text.
- **Capture text**, or Command-Shift-2, lets you drag a rectangle on the screen. Escape cancels and leaves the current text as it is. If another app already owns that shortcut, the panel says so and **Capture text** still works.
- The first screen capture asks for Screen Recording permission. Turn SnapText on in System Settings → Privacy & Security → Screen Recording, then quit and reopen the app if macOS asks you to. Choosing or dropping a file does not need that permission.
- Edit the text in the panel. **Copy text** puts the whole result on the clipboard. The panel also shows a character count and a short line such as `Auto · 0.42 s`.
- **Read Again** runs recognition once more on the same image.
- The **⋯** menu has **Launch at login** and **Quit SnapText**. The login switch follows the setting macOS already has. If macOS needs approval, SnapText opens Login Items settings. Keep the app in a stable place, such as Applications, before turning this on.

English, Simplified Chinese, Traditional Chinese, and mixed text are recognized together. There is no language menu. If that recognizer cannot start, SnapText may return English-only text and says that Chinese may be missing.

One image is handled at a time. Files larger than 100 MB are refused, and images larger than 80 megapixels are refused. The first frame or page is the one that is read. Handwriting, tight columns, tables, and very small text can still come out wrong. The result is plain text, not the original layout.

When SnapText launches, it prepares the recognizer in the background with a small generated sample. That sample is not shown in the panel. A capture you start immediately can still wait for that preparation to finish.

## Privacy

The current image and text stay in memory until you clear them or quit. Original files are not changed. A screen selection is written to a temporary folder that is deleted after it is read or cancelled. The clipboard is read when you click **Paste image**, and written when you click **Copy text** or use the usual editing commands.
