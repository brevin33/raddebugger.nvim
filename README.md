# Rad Debugger Nvim

[Rad Debugger](https://github.com/EpicGamesExt/raddebugger) inigration for Neovim

# Showcase

<iframe width="560" height="315" src="https://www.youtube.com/embed/video-id" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

# Requirements

- [Rad Debugger](https://github.com/EpicGamesExt/raddebugger/releases) installed and in your path: [https://github.com/EpicGamesExt/raddebugger/releases](https://github.com/EpicGamesExt/raddebugger/releases)

# Installation

## Lazy.nvim

```lua
{
    'rad-dev/rad_debugger.nvim',
    dependencies = {
        'nvim-lua/plenary.nvim',
        'nvim-telescope/telescope.nvim',
    },
    config = function()
        require('rad_debugger').setup()
    end
}
```
