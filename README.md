Query database from nvim

A lua copy of [vim-dadbod](https://github.com/tpope/vim-dadbod) and [vim-dadbod-ui](https://github.com/tpope/vim-dadbod).

Currently support mysql

```lua
require'praem90/db.nvim'.setup({
    connections = {
        {name = 'Local', host = '127.0.0.1', port= 3306, user = 'root', password = 'pass', database = 'test'}
    }
})
```
