if vim.fn.has('nvim') ~= 1 then
  return
end

vim.api.nvim_create_user_command('Matrix', function(opts)
  require('matrix.screensaver').start(opts.fargs)
end, { nargs = '*' })
