# clink carapace

carapace support for clink

## Installation

download script [`carapace.lua`](https://raw.githubusercontent.com/mwmi/clink-carapace/refs/heads/main/carapace.lua "Right-click and select 'Save As' to save the file") to your `scripts` folder ( run `clink info` to see the script paths ).

## Usage

> Enable carapace argument auto-completion

```cmd
clink set carapace.enable true
```

> Exclude commands from carapace completion

```cmd
clink set carapace.exclude scoop;cmd
```

## Icon Support 

download script  [`matchicons.lua`](https://raw.githubusercontent.com/chrisant996/clink-gizmos/refs/heads/main/matchicons.lua "Right-click and select 'Save As' to save the file") to your `scripts` folder.

> Enables icons in file completions

```cmd
clink set matchicons.enable true
```

## References

- [clink](https://github.com/chrisant996/clink)
- [clink-gizmos](https://github.com/chrisant996/clink-gizmos)
- [carapace-bin](https://github.com/carapace-sh/carapace-bin)
- [json.lua](https://github.com/rxi/json.lua)