# Zombies subtitle workflow

iwz-mod reuses Infinite Warfare's campaign subtitle renderer and sound-alias timing. Each entry associates a sound alias with the text that should appear while that alias plays, so timestamps and GSC changes are not required.

## Add a subtitle

1. Start the Zombies map that contains the dialogue.
2. Open the console and run `iwz_dump_sound_aliases`. To make the output smaller, add an alias, audio-file, or sound-bank fragment, such as `iwz_dump_sound_aliases zmb`.
3. Open `iw7-mod/subtitles/sound_aliases.csv` in the Infinite Warfare installation and find a likely dialogue alias.
4. Run `iwz_export_sound_alias <alias>` in the console. For example, `iwz_export_sound_alias zmb_example_dialogue_alias`. The client extracts every randomized variant of that exact alias as a playable FLAC in `iw7-mod/subtitles/audio`. Listen to the files to identify and transcribe the line.
5. Add the alias and its transcript to `iw7-mod/subtitles/zombies.json`:

```json
{
  "zmb_example_dialogue_alias": "Speaker: The subtitle text goes here."
}
```

6. Save the file and run `iwz_reload_subtitles` in the console. Trigger the dialogue again to test it.

Add further entries with commas between them. The file must remain valid UTF-8 JSON. Alias matching is case-insensitive.

The normal **SUBTITLES** setting in Audio Options controls these subtitles. The game displays each subtitle for its sound alias's playback time and uses the campaign subtitle placement and styling.

## Forced subtitles

The short string form above respects the player's Subtitles setting. For a line that must appear even when normal subtitles are disabled, use the expanded form:

```json
{
  "zmb_example_forced_alias": {
    "text": "Speaker: This line is always shown.",
    "force": true
  }
}
```

Changing or adding entries works with `iwz_reload_subtitles`. Restart the client after removing an entry, because an already-loaded sound alias retains its last applied metadata until its sound bank is unloaded.
