# Developer Notes

Run all commands from the repository root.

## After pulling

After pulling, run `tools/godot --headless --import` if new `class_name` scripts arrived, otherwise tests/scenes fail with unknown class errors.

```sh
tools/godot --headless --import
```
