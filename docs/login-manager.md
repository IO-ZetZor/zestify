# Display manager appearance

The standalone `auth/` display manager uses a native Qt Quick greeter. Appearance
is separate from the root daemon's account/session configuration and from the
desktop shell. Themes are JSON data; changes do not alter authentication or
execute theme code.

## Build and preview

Build dependencies are a C++17 compiler, make, pkg-config, Qt 6 Core/Network/Quick,
libsystemd, and PAM development headers. At runtime the greeter needs Qt Quick
Controls and Layouts. Preview file browsing also uses the Qt Quick Dialogs
module; **video wallpaper also needs the Qt Multimedia QML module
and a working codec backend** (for example `qt6-multimedia` with its FFmpeg
backend on Arch). Static and animated images work without Qt Multimedia.

```sh
make -C auth -j2
auth/build/zestify-greeter --preview
auth/build/zestify-greeter --preview --theme auth/themes/split.json
auth/build/zestify-greeter --preview --theme auth/themes/minimal.json
```

Click **Customize** to open the live editor. Choose a section, change values,
and click **Save theme**. The filename field supports Save As. **Reload** reads
the saved file; **Defaults** resets the preview. Preview authentication is
disabled; submitted text is cleared and no credentials are saved.

## Sign in with just a password

The greeter lists regular local accounts and automatically selects an account.
The password field is ready and focused as soon as the login service connects;
type your password and press Enter. There is no username text field or separate
step to request the password. If there are several accounts, choose one from
the account menu. Account and session changes clear a partially typed password.
Subsequent PAM/MFA prompts still appear when needed.

Successful logins remember the selected account and session in the greeter
account's state directory. Only those identifiers are saved. `form.defaultUser`
and `form.defaultSession` can set explicit preferred selections; otherwise the
last successful selection wins, falling back to the first available choice.
Accounts come from `/etc/passwd`, using `UID_MIN`/`UID_MAX` from `/etc/login.defs`
(default 1000–60000); root, the greeter and accounts with `nologin`/`false` or
empty shells are excluded. This picker lists local accounts, not directory
accounts that are absent from `/etc/passwd`.

## Change fonts and the background

Open **Customize → fonts** and choose a family from the font dropdown. The list
contains every family Qt can use on the machine and includes a search box; each
entry previews its font. Body, clock and icon fonts have separate pickers.
Selecting a family clears its custom font-file override. **Browse…** beside a
custom font file can also load a local TTF/OTF/TTC.

Open **Customize → background**, then click **Browse…** beside **Wallpaper
file**. Pick an image, GIF or video. The editor switches to the appropriate
wallpaper type automatically; choose crop/fit/stretch and overlay opacity as
desired, then click **Save theme**. `type` remains editable for formats such as
animated WebP that may need an explicit choice.

Open **Customize → layout → Surface transparency** to make the sign-in card,
inputs, menus and button fills transparent. `0` keeps their configured fills;
`1` removes them completely. Text and icons retain full opacity. The editor
stays readable while previewing transparency. `form.opacity` still controls the
sign-in card separately, and background overlay opacity controls wallpaper tint.

Without `--theme`, preview saves by default to
`~/.config/zestify-dm/theme.json`. To use that saved theme at the system login
screen after installing the manager:

```sh
sudo install -m644 ~/.config/zestify-dm/theme.json /etc/zestify-dm/theme.json
```

Use system-login wallpaper and custom font files that the greeter account can
read, for example under `/usr/share/backgrounds/` and `/usr/share/fonts/`.
Fonts in a private user directory can appear in the preview but are unavailable
to the system greeter until installed in a shared location.

Without `--theme`, preview uses `$XDG_CONFIG_HOME/zestify-dm/theme.json` (usually
`~/.config/zestify-dm/theme.json`). The actual greeter defaults to
`/etc/zestify-dm/theme.json`; its editor is disabled. The supplied presets are
installed under `/usr/share/zestify-dm/themes/` by `make -C auth install`.

For a screenshot or headless syntax check:

```sh
auth/build/zestify-greeter --preview --theme auth/themes/split.json --screenshot /tmp/login.png
auth/build/zestify-greeter --check-theme auth/integration/theme.json
```

`--screenshot-delay 2000` allows more time for video decoding before capture.
`--check-theme` checks field names, types, ranges and local asset paths. It does
not load assets, test codecs or authenticate.

## What can be customized

Themes can contain only the values you want to change; omitted fields inherit
defaults. [The complete default theme](../auth/integration/theme.json) lists
all settings; [the schema](../auth/theme-schema.json) defines their allowed
types and ranges and drives the editor.

| Section | Controls |
| --- | --- |
| `fonts` | Searchable lists of installed body, clock and icon font families; optional local font files |
| `colors` | Text, secondary text, accent, selected text, errors, panel, input, button and borders; alpha colors are supported |
| `layout` | Global scale, safe screen margin and surface transparency |
| `brand`, `welcome`, `hint` | Visibility, text, font size, letter spacing, color and independent position |
| `clock` | Time/date visibility and formats, sizes, time font weight, alignment, spacing and position |
| `form` | Position, width, padding, spacing, opacity, borders, radii, input/button/icon sizes, title/button alignment, field order, labels and preferred account/session |
| `icons` | Brand, user, session, password, submit, cancel and dropdown image/SVG paths or font glyphs; empty glyphs hide an icon |
| `background` | Gradient palette, local image/animation/video, fallback image, crop/fit/stretch, overlay color/opacity, wallpaper opacity, playback speed and pause rules |

Each `position` has normalized `x`/`y` coordinates, `anchorX`/`anchorY` and
pixel `offsetX`/`offsetY`. For example, this places the form 48 logical pixels
from the left, halfway down the screen:

```json
{
  "form": {
    "position": { "x": 0, "y": 0.5, "anchorX": 0, "anchorY": 0.5, "offsetX": 48, "offsetY": 0 }
  }
}
```

An anchor of `0` aligns the left/top edge, `0.5` the center and `1` the
right/bottom edge. Positions are clamped to the screen margin. The form shrinks
to fit narrow screens and scrolls vertically if needed. Independent widgets
can deliberately overlap, so inspect the preview at your intended resolution.

`form.fieldOrder` is a comma-separated permutation of
`title,username,session,response,message,actions`. Every name must occur once.
`form.showSession` can hide the selector while retaining the selected session;
`form.defaultSession` uses a session ID from the daemon configuration, falling
back to the first available session. PAM prompt text still comes from PAM.

For icons, `source` uses a local image or SVG. If it cannot load, `glyph` is the
fallback. Set `fonts.iconFamily` or `fonts.iconFile` for Nerd Font/icon-font
glyphs. A successfully loaded `fonts.file`, `clockFile` or `iconFile` takes
precedence over the corresponding family. Missing custom fonts fall back to
the configured family. Asset paths are local filenames (absolute or relative
to the theme JSON); URLs and executable wallpaper commands are rejected.

## Live wallpaper

For video, add a background section pointing to your local video and optional
still image. For example, after placing those files under
`/usr/share/backgrounds/zestify/`:

```json
{
  "background": {
    "type": "video",
    "source": "/usr/share/backgrounds/zestify/login.mp4",
    "fallback": "/usr/share/backgrounds/zestify/login-still.jpg",
    "fillMode": "crop",
    "speed": 1,
    "overlayColor": "#08090d",
    "overlayOpacity": 0.35,
    "pauseWhileAuthenticating": true,
    "pauseWhenInactive": true,
    "paused": false
  }
}
```

Video loops indefinitely and has no audio output. MP4/WebM support depends on
the installed Qt codec backend. The static fallback remains behind the video
until frames arrive and is shown if decoding fails or Qt Multimedia cannot
load. The gradient remains available if the fallback is missing. Switching
away from video releases its player. Paused videos decode an initial frame
and keep it on screen.

For a GIF or another Qt-supported animated image, use `"type": "animated"`.
Animation honors `speed` and the same pause settings, and avoids caching every
frame of large files. For a still wallpaper, use `"type": "image"`. Choose
`"fit"` to preserve the complete image with background around it, `"crop"`
to fill the screen, or `"stretch"` to fill without preserving aspect ratio.

## Use the theme at login

The greeter runs as the dedicated `zestify-greeter` account, so all theme assets
must be readable by that account and their parent directories traversable.
Keep system-login assets in a shared directory such as
`/usr/share/backgrounds/zestify/`, rather than a private or encrypted home.
Copy a finished theme to `/etc/zestify-dm/theme.json` with mode `0644`. Relative
paths resolve beside that installed file; the preview editor's Save As converts
relative asset references to absolute paths to preserve their meaning.

The greeter watches its theme and reloads valid edits, including atomic file
replacement. Invalid edits, deletion, nonregular files, and files larger than
256 KiB retain the last good theme; an invalid theme at startup uses defaults
and reports the error. Unrelated files beside the theme do not discard preview
edits. Theme files must be regular files, not symlinks.

`make -C auth install` installs the daemon, greeter, initial theme, PAM policies
and systemd integration without enabling the service. Existing configuration
and theme files are preserved. Selecting/enabling a system display manager is
a separate administrator operation; do it only after testing in a spare seat
or VM and retaining a working console login.

## Verification

```sh
make -C auth -j2 test
```

The tests exercise protocol/PAM cleanup with temporary policies, theme
validation, atomic reload and recreation, preview editor/save interactions,
local account filtering, password-first PAM/MFA handling and remembered selection,
complete installed-font lists/search, background browsing, font/layout updates,
password masking/clearing, and offscreen rendering. If
FFmpeg is installed, they generate small local media fixtures and verify video
decoding, looping, pausing, source recovery, fallback rendering and animated
image playback. They do not verify a real systemd seat, hardware decoding,
account login or compositor session startup.
