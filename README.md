# db.nvim

`db.nvim` is a Neovim plugin designed to bring database interaction and management directly into your editor, allowing you to connect to, query, and explore your databases without leaving your Neovim environment.

## Features

- **Seamless Database Connectivity:** Connect to various database systems directly within Neovim.
- **Execute Queries with Ease:** Run SQL queries on the fly from your Neovim buffers.
- **Intuitive Result Viewing:** View query results cleanly displayed in a dedicated buffer.
- **Effortless Database Exploration:** Navigate and inspect database schemas, tables, and columns.

---

## Getting Started

### Installation

Use your preferred plugin manager to install `db.nvim`.

**Using `lazy.nvim`:**

```lua
-- Add this to your lazy.nvim configuration
{
  'praem90/db.nvim',
  config = function()
    require('db').setup({
      dependencies = {
        'nvim-lua/plenary.nvim',
        'MunifTanjim/nui.nvim',
        'nvim-telescope/telescope.nvim',
      },
      main = 'db',
      opts = {
        connections = {
          { name = 'QZ Local', host = '127.0.0.1', port = 3306, user = 'root', password = 'hunter2', database = 'quartzy_development' },
        },
      },
      keys = {
        {
          '<leader>dbo',
          function()
            require('db').open()
          end,
          desc = 'Open DB',
        },
        {
          '<leader>dbc',
          function()
            require('db').open_active_connections()
          end,
          desc = 'Open Connections',
        },
        {
          '<leader>dbt',
          function()
            require('db').open_tables()
          end,
          desc = 'Open Tables',
        },
        {
          '<leader>dbh',
          function()
            require('db').open_history()
          end,
          desc = 'Open Tables',
        },
      },
    })
  end
}
```

### Configuration
db.nvim requires a setup() call with a connections table to define your database connections.

The plugin currently **supports MySQL only**. More database drivers will be added in future updates.

Here is an example of a basic setup with a local MySQL connection:

```lua
require('db').setup({
    connections = {
        {name = 'Local', host = '127.0.0.1', port= 3306, user = 'root', password = 'pass', database = 'test'}
    }
})
```

### Usage

To connect to a database
```lua
require('db').open()
```

Once connected the database, open any sql file and save it or enter in normal mode to run the query
Select query in visual mode and then hit enter to run the query

To list tables from the selected connection.
Press `<CR>` to run the select query with limit 10;
Press `<C-i>` to get the table information
```lua
require('db').open_tables()
```
To show histories
```lua
require('db').open_history()
```

## Statusline Integration

`db.nvim` provides two functions to display the current connection status and active database in your statusline. This is a great way to always know which database you are working with.

You can add these components to your statusline configuration (e.g., in a plugin like `lualine.nvim` or a custom statusline).

  * `require('db').connection_statusline()`: Displays the name of the currently active database connection.
  * `require('db').database_statusline()`: Displays the name of the currently active database.

### Example with `lualine.nvim`

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      'filetype',
      -- Add the db.nvim statusline components
      {
        require('db').connection_statusline,
        color = { fg = '#00af5f' } -- Optional: Customize the color
      },
      {
        require('db').database_statusline,
        color = { fg = '#005f87' } -- Optional: Customize the color
      }
    }
  }
})
```

