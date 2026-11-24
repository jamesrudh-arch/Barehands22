# LEVERAGE — License Record

## 1. Original content (the whole game)

All code, textures, UI art, faces, music, sound effects and voice blips in
this repository are **original works created for this project** (procedural
generators in `tools/forge/`, GDScript systems in `scripts/`, data in
`data/`). They carry no third-party license obligations. Project © its
author ("D'Youngs Games" presentation identity).

## 2. Godot Engine

The game runs on **Godot Engine 4.7.2-stable** (built from the official
`godotengine/godot` source tarball via codeload.github.com; no engine
binaries are redistributed in this repository).

> Godot Engine is free and open source software, released under the
> **MIT License**: Copyright (c) 2014-present Godot Engine contributors.
> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the
> "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to
> the conditions that the above copyright notice and this permission
> notice shall be included in all copies or substantial portions of the
> Software. THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY
> KIND.

## 3. DejaVu fonts (`assets/fonts/`)

Redistributed under the DejaVu license (Bitstream Vera + Arev bases):

> Fonts are (c) Bitstream (see below). DejaVu changes are in public
> domain. Glyphs imported from Arev fonts are (c) Tavmjong Bah (see below).
>
> **Bitstream Vera:** Permission is hereby granted, free of charge, to any
> person obtaining a copy of the fonts accompanying this license ("Fonts")
> and associated documentation files (the "Font Software"), to reproduce
> and distribute the Font Software, including without limitation the
> rights to use, copy, merge, publish, distribute, and/or sell copies of
> the Font Software, and to permit persons to whom the Font Software is
> furnished to do so, subject to the following conditions: The above
> copyright and trademark notices and this permission notice shall be
> included in all copies of one or more of the Font Software typefaces.
> The Font Software may be modified, altered, or added to, and in
> particular the designs of glyphs or characters in the Fonts may be
> modified and additional glyphs or characters may be added to the Fonts,
> only if the fonts are renamed to names not containing either the words
> "Bitstream" or the word "Vera". This License becomes null and void to
> the extent applicable to Fonts or Font Software that has been modified
> and is distributed under the "Bitstream Vera" names. The Font Software
> may be sold as part of a larger software package but no copy of one or
> more of the Font Software typefaces may be sold by itself. THE FONT
> SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
>
> **Arev (Tavmjong Bah):** Permission is hereby granted, free of charge,
> to any person obtaining a copy of the fonts accompanying this license
> ("Fonts") and associated documentation files (the "Font Software"), to
> reproduce and distribute the Font Software … under the same conditions
> as Bitstream Vera (renaming requirement for modifications; no standalone
> resale; provided "as is" without warranty).

The full unmodified license text ships at `assets/fonts/DejaVu-LICENSE.txt`.
No font files were modified, so the rename clause is not triggered.

Six faces ship, all from the same upstream DejaVu release, all mapped to a
typographic role by the `Type` autoload (`scripts/ui/type.gd`):

| File | Role |
|---|---|
| `DejaVuSerif.ttf` / `-Bold.ttf` | `display` — titles, cutscene slates, speaker names, place names, section headers |
| `DejaVuSans.ttf` / `-Bold.ttf` | `body` — objectives, barks, dialogue, buttons, help text; also the theme's default face |
| `DejaVuSansMono.ttf` / `-Bold.ttf` | `mono` — every figure: credits, wanted level, clock, ammo, speed, fuel, XP, prices |

Wave 49 added the two Serif faces (the same licence already shipped covers them)
and is also the wave in which any of these files were loaded at all: before it,
four faces sat in `assets/fonts/` with generated `.import` files, were credited
by name on the menu's about card, and not one was ever referenced by a single
line of code.

## 4. Third-party content NOT used

- No Kenney, Quaternius, Poly Pizza, OpenGameArt or AssetLib assets are
  included (researched and deliberately declined — see
  `docs/ASSET_REGISTER.md` §9 and `docs/DECISION_LOG.md` D-04).
- No stock music, stock SFX, or recorded voice talent.
- pkgconf and dejavu-fonts source tarballs were fetched only as build/
  asset tooling inputs in the sandbox; their outputs (built static lib,
  copied font files) are the only derivatives retained.

## 5. Tooling licenses (development-time only, not redistributed)

Python 3 + numpy + Pillow + soundfile (BSD/Apache/PSF-family licenses) —
used by `tools/forge/` generators; outputs are original assets, no GPL
contamination. gdparse (MIT) for syntax gating. scons (MIT) to build Godot.
