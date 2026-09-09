# iBooru Bar
A small MacOS Menu Bar App and iOS Application for browsing art from booru imageboards.

I made this project mostly for myself and just for fun. I wanted to try native macOS development with Swift and SwiftUI in Xcode, and decided to combine learning something new with something fun. _And maybe useful?_

<p align="center">
  <a href="https://github.com/user-attachments/assets/6e106369-d06c-4578-bcaf-2da653e44cff">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/6e106369-d06c-4578-bcaf-2da653e44cff" />
  </a>
  <a href="https://github.com/user-attachments/assets/6e3c386a-bc9d-49e4-8231-327726dce17b">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/6e3c386a-bc9d-49e4-8231-327726dce17b" />
  </a>
  <a href="https://github.com/user-attachments/assets/263aca2f-366b-4b74-9eba-93a9a8fc484e">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/263aca2f-366b-4b74-9eba-93a9a8fc484e" />
  </a>
  <a href="https://github.com/user-attachments/assets/e2817c0a-f508-407e-9199-82fd12d99f9e">
    <img width="228" height="383" alt="IMG_3225" src="https://github.com/user-attachments/assets/e2817c0a-f508-407e-9199-82fd12d99f9e" />
  </a>
  <a href="https://github.com/user-attachments/assets/43324ae9-ed31-4337-acfe-20dfc500cfde">
    <img width="228" height="383" alt="IMG_3201" src="https://github.com/user-attachments/assets/43324ae9-ed31-4337-acfe-20dfc500cfde" />
  </a>
  <a href="https://github.com/user-attachments/assets/803bd108-948a-4a30-a332-4dab03ace9ae">
    <img width="232" height="188" alt="image" src="https://github.com/user-attachments/assets/803bd108-948a-4a30-a332-4dab03ace9ae" />
  </a>
</p>

## Project description:

The app lives in the macOS menu bar and lets you quickly open a scrollable art feed without keeping a browser tab around. The iOS version is a full-fledged app with identical functionality _(inherited from the MacOS Menu Bar App version)_ but a design adapted for touch controls. The app's design has been tested on the iPhone SE 3 (iOS 26.5.2). I'm unsure how it performs on other iPhone models, so if you encounter any design issues, please feel free to submit a screenshot and a description of the problem in the [Issues](https://github.com/IlyaBOT/iBooru-Bar/issues) section!

## Features:
- Built with Swift and SwiftUI
- Scrollable image feed with automatic loading _(and probably unloading, if I remember to implement that, huh?)_
- Multiple booru sources
- Trending, Newest and Search tabs
- Search/filter content by tags
- NSFW-mode toggle switch
- e621 API key support

## Currently supported / tested:
- Derpibooru [Tested. The Popular and New list is working. Search is working. Filters is working]
- Furbooru [Tested. The Popular and New list is working. Search is working]
- Safebooru [Tested. The Popular and New list is working. Search is working]
- e621 [Tested. The Popular and New list is working. Search is working]
- The Azure Blade [Tested. The Popular and New list isn't working. Search is working]
- All girl [Tested. The Popular and New list isn't working. Search is working]

The project supports multiple backend types instead of assuming that every booru uses the same API.

## Currently implemented:
- Philomena API - used by Derpibooru, Furbooru and similar sites.
- Gelbooru-style DAPI - used by Safebooru and compatible sites.
- e621 API - used by e621 site only.

_More backends may be added later._

## Requirements:
- Intel or Apple Silicon Mac with macOS 13 or newer (There are plans to lower the requirements to macOS 11)
- iOS 15.5 or newer

The project was originally developed and tested on an Intel MacBook Air 2020 (MacBookAir9,1 macOS 15.7.7) and iPhone SE 3 (2022 128Gb).

## Building
Open the project in Xcode, or build it from the terminal:

```bash
xcodebuild -project macos-booru-bar.xcodeproj -scheme macos-booru-bar -configuration Release -destination 'platform=macOS' build
```

The built .app can then be found inside Xcode's build products / DerivedData directory.

## Why?..

Mostly because I wanted to mess around with Swift and native macOS development with Xcode. A browser obviously works perfectly fine for browsing boorus, but having a small native menu bar app felt more fun. _(Also, I saw a similar project for Hyperland, but it didn't work well there, so I decided to make my own version, but natively for macOS)_ And it gave me a real project to learn SwiftUI, instead of creating another calculator or something like that, lol.
So yeah, pleasant && useful, I guess?
