# iBooru Bar

<p align="center">
  <a href="https://github.com/user-attachments/assets/803bd108-948a-4a30-a332-4dab03ace9ae">
    <img width="232" height="188" alt="image" src="https://github.com/user-attachments/assets/803bd108-948a-4a30-a332-4dab03ace9ae" />
  </a>
  <a href="https://github.com/user-attachments/assets/6e106369-d06c-4578-bcaf-2da653e44cff">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/6e106369-d06c-4578-bcaf-2da653e44cff" />
  </a>
  <a href="https://github.com/user-attachments/assets/6e3c386a-bc9d-49e4-8231-327726dce17b">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/6e3c386a-bc9d-49e4-8231-327726dce17b" />
  </a>
  <a href="https://github.com/user-attachments/assets/263aca2f-366b-4b74-9eba-93a9a8fc484e">
    <img width="253" height="383" alt="image" src="https://github.com/user-attachments/assets/263aca2f-366b-4b74-9eba-93a9a8fc484e" />
  </a>
</p>

A small macOS menu bar app for browsing art from booru imageboards.

I made this project mostly for myself and just for fun. I wanted to try native macOS development with Swift and SwiftUI in Xcode, and decided to combine learning something new with something fun. _And maybe useful?_

The app lives in the macOS menu bar and lets you quickly open a scrollable art feed without keeping a browser tab around.

## Features:
- Built with Swift and SwiftUI
- Scrollable image feed with automatic loading _(and probably unloading, if I remember to implement that, huh?)_
- Multiple booru sources
- Trending, Newest and Search tabs
- Search/filter content by tags
- NSFW-mode toggle switch
- e621 API key support

## Currently supported / tested:
- Derpibooru
- Furbooru
- Safebooru
- e621
- The Azure Blade
- All girl

The project supports multiple backend types instead of assuming that every booru uses the same API.

## Currently implemented:
- Philomena API - used by Derpibooru, Furbooru and similar sites.
- Gelbooru-style DAPI - used by Safebooru and compatible sites.
- e621 API - used by e621 site only.

_More backends may be added later._

## Requirements:
- macOS 13 or newer
- Intel or Apple Silicon Mac

The project was originally developed and tested on an Intel MacBook Air 2020 (MacBookAir9,1 macOS 15.7.7).

## Building
Open the project in Xcode, or build it from the terminal:

```bash
xcodebuild -project macos-booru-bar.xcodeproj -scheme macos-booru-bar -configuration Release -destination 'platform=macOS' build
```

The built .app can then be found inside Xcode's build products / DerivedData directory.

## Why?..

Mostly because I wanted to mess around with Swift and native macOS development with Xcode. A browser obviously works perfectly fine for browsing boorus, but having a small native menu bar app felt more fun. _(Also, I saw a similar project for Hyperland, but it didn't work well there, so I decided to make my own version, but natively for macOS)_ And it gave me a real project to learn SwiftUI, instead of creating another calculator or something like that, lol.
So yeah, pleasant && useful, I guess?
