package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path
local scanner = require("nvim-heredoc.scanner")
local result = scanner.scan("cat <<EOF\nordinary payload\nEOF\n")
-- This deliberately asserts the forbidden classification. It must fail while
-- ordinary << remains excluded; if the scanner regresses, this control passes.
assert(#result.regions > 0,
  "NEGATIVE_CONTROL: ordinary heredoc was classified as managed")
