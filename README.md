Query database from nvim

A lua copy of [vim-dadbod](https://github.com/tpope/vim-dadbod) and [vim-dadbod-ui](https://github.com/tpope/vim-dadbod).

Currently support mysql

```lua
require('db.nvim').setup({
    connections = {
        {name = 'Local', host = '127.0.0.1', port= 3306, user = 'root', password = 'pass', database = 'test'}
    }
})
```

To connect to a database
```lua
require('db.nvim').open()
```

Once connected the database, open any sql file and save it or enter in normal mode to run the query
Select query in visual mode and then hit enter to run the query

To list tables from the selected connection 
```lua
require('db.nvim').open_tables()
```

