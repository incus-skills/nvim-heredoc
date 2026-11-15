package.path = "./lua/?.lua;./lua/?/init.lua;" .. package.path

local plugin = require("nvim-heredoc")

local function lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

local function fail(err)
  print(err)
  vim.cmd("cquit 1")
end

local function defer(fn)
  vim.defer_fn(function()
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
      fail(err)
    end
  end, 20)
end

local function assert_insert_mode(message)
  assert(vim.api.nvim_get_mode().mode == "i",
    message .. "; mode=" .. vim.inspect(vim.api.nvim_get_mode()))
end

local buf

local function wait_for(predicate, message)
  assert(vim.wait(1000, predicate, 10), message .. "; lines=" .. vim.inspect(lines(buf)))
end

if vim.env.NVIM_HEREDOC_FUNCTION_BOUNDARY == "1" or vim.env.NVIM_HEREDOC_FUNCTION_BOUNDARY_DELETE == "1" then
  local api = vim.api
  local actual
  local original = {
    "conf_print_test1() {",
    "  cat <<'EOF'",
    "hello1",
    " hello2",
    "  hello3",
    "hello4",
    "EOF",
    "}",
  }

  local function snapshot(label)
    local actual = lines(buf)
    print("===== " .. label .. " =====")
    for index, line in ipairs(actual) do
      print(string.format("%04d %q", index, line))
    end
    print("mode=" .. api.nvim_get_mode().mode)
    print("cursor=" .. vim.inspect(api.nvim_win_get_cursor(0)))
    return actual
  end

  local function assert_original(actual, first_line)
    for index, line in ipairs(original) do
      assert(actual[first_line + index - 1] == line,
        "the existing function-wrapped heredoc changed at original line " .. index
          .. "; actual=" .. vim.inspect(actual))
    end
  end

  vim.cmd("filetype plugin indent on")
  buf = api.nvim_create_buf(true, false)
  api.nvim_buf_set_lines(buf, 0, -1, false, original)
  api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = "sh"

  -- Use the real MiniPairs mappings from the pinned LazyVim integration
  -- environment. In particular, typing '{' must create the matching '}' and
  -- MiniPairs must handle Return inside that pair.
  require("mini.pairs").setup({
    modes = { insert = true, command = true, terminal = false },
    skip_ts = { "string" },
    skip_unbalanced = true,
    markdown = true,
  })

  -- Match the user's shell-buffer indentation settings.
  vim.bo[buf].expandtab = true
  vim.bo[buf].tabstop = 2
  vim.bo[buf].softtabstop = 0
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].autoindent = true
  vim.bo[buf].smartindent = false
  vim.bo[buf].cindent = false
  vim.bo[buf].formatoptions = "jncroql"

  -- The LazyVim plugin spec should attach on FileType. Calling setup is
  -- intentionally idempotent and also makes this test usable if load timing
  -- differs between Neovim versions.
  plugin.setup()
  assert(vim.wait(1000, function()
    return vim.b[buf].nvim_heredoc_attached == true
  end, 10), "nvim-heredoc did not attach to the shell buffer")

  local function finish()
    print("live function-boundary Insert-mode test: PASS")
    vim.cmd("qa!")
  end

  local function run()
    api.nvim_win_set_cursor(0, { 1, 0 })
    -- Open a fresh line above the existing function, as in the user's edit.
    api.nvim_input("O")
    defer(function()
      assert_insert_mode("entering Insert mode before typing the function header")
      api.nvim_input("conf_print_test2() {")
      defer(function()
        local actual = snapshot("after typing function header with MiniPairs")
        assert_insert_mode("typing the function header must remain in Insert mode")
        assert(actual[1] == "conf_print_test2() {}",
          "MiniPairs must insert the function's autoclose brace; lines=" .. vim.inspect(actual))
        local cursor = api.nvim_win_get_cursor(0)
        assert(cursor[1] == 1 and cursor[2] == #actual[1] - 1,
          "cursor should remain between MiniPairs' braces; cursor=" .. vim.inspect(cursor))

        -- This is MiniPairs' actual Insert-mode Return mapping, not a buffer
        -- API insertion or a synthetic process_buffer call.
        api.nvim_input(api.nvim_replace_termcodes("<CR>", true, false, true))
        defer(function()
          local after_pair_return = snapshot("after Return inside the function pair")
          assert_insert_mode("Return inside the function pair must remain in Insert mode")
          assert(after_pair_return[1] == "conf_print_test2() {"
            and after_pair_return[3] == "}",
            "MiniPairs Return should place the autoclose brace on its own line; lines="
              .. vim.inspect(after_pair_return))

          if vim.env.NVIM_HEREDOC_FUNCTION_BOUNDARY_DELETE == "1" then
            -- Withdraw MiniPairs' brace before opening the heredoc. This
            -- avoids racing the scheduled on_lines processor: the boundary
            -- is already absent when the new heredoc becomes visible.
            api.nvim_input(api.nvim_replace_termcodes("<C-o>j<C-o>x<C-o>k", true, false, true))
            defer(function()
              assert_insert_mode("withdrawing the function brace must remain in Insert mode")
              actual = snapshot("after deleting the auto-paired function brace")
              assert(actual[3] == "",
                "the deliberate brace deletion should leave the line empty; lines=" .. vim.inspect(actual))

              api.nvim_input(api.nvim_replace_termcodes("  cat <lt><lt>-'EOF'", true, false, true))
              defer(function()
                vim.wait(200, function() return false end, 10)
                actual = snapshot("after processing the opener with the brace withdrawn")
                assert(actual[1] == "conf_print_test2() {"
                  and actual[2] == "  cat <<-'EOF'",
                  "the new function and heredoc opener should remain; lines=" .. vim.inspect(actual))
                assert(actual[3] == "",
                  "the deleted function boundary should remain absent; lines=" .. vim.inspect(actual))
                assert_original(actual, 4)
                assert(#actual == #original + 3,
                  "the plugin must not recreate the deleted boundary or insert a closer; lines="
                    .. vim.inspect(actual))
                assert(not vim.tbl_contains(actual, "\\tEOF"),
                  "the plugin must not insert a managed closer after the boundary is withdrawn; lines="
                    .. vim.inspect(actual))
                print("live function-boundary withdrawal test: PASS")
                vim.cmd("qa!")
              end)
            end)
            return
          end
          api.nvim_input(api.nvim_replace_termcodes("cat <lt><lt>-'EOF'", true, false, true))
          defer(function()
            local after_opener = snapshot("after typing the new heredoc opener")
            assert_insert_mode("typing the heredoc opener must remain in Insert mode")
            assert(after_opener[2] == "  cat <<-'EOF'",
              "the heredoc opener should retain the function body's indentation; lines="
                .. vim.inspect(after_opener))

            -- Do not wait for processing of the opener as a standalone edit.
            -- The regression is specifically the first Return after typing
            -- the opener: the scheduled on_lines work must observe the new
            -- line break and reserve the closer before the function brace.
            api.nvim_input(api.nvim_replace_termcodes("<CR>", true, false, true))
            defer(function()
              wait_for(function()
                actual = lines(buf)
                return actual[4] == "\tEOF" and actual[5] == "}"
              end, "the first Return after the new opener should reserve its closer before the MiniPairs brace")
              local after_body_return = snapshot("immediately after the first Return following the new opener")
              assert_insert_mode("Return after the heredoc opener must remain in Insert mode")
              assert(after_body_return[1] == "conf_print_test2() {"
                and after_body_return[2] == "  cat <<-'EOF'"
                and after_body_return[4] == "\tEOF"
                and after_body_return[5] == "}",
                "the first Return must close the new heredoc inside the function; lines="
                  .. vim.inspect(after_body_return))
              assert_original(after_body_return, 6)

              api.nvim_input("new payload")
              defer(function()
                local after_payload = snapshot("after typing heredoc payload")
                assert_insert_mode("typing heredoc payload must remain in Insert mode")
                assert(after_payload[3] == "\t\tnew payload",
                  "payload should follow the structural body TAB; lines=" .. vim.inspect(after_payload))

                api.nvim_input(api.nvim_replace_termcodes("<Esc>", true, false, true))
                defer(function()
                  assert(api.nvim_get_mode().mode:sub(1, 1) ~= "i",
                    "Escape should leave Insert mode")
                  local final = snapshot("after InsertLeave")
                  assert(final[1] == "conf_print_test2() {"
                    and final[2] == "  cat <<-'EOF'"
                    and final[3] == "\t\tnew payload"
                    and final[4] == "\tEOF"
                    and final[5] == "}",
                    "the new function/heredoc structure must survive InsertLeave; lines="
                      .. vim.inspect(final))
                  assert_original(final, 6)
                  finish()
                end)
              end)
            end)
          end)
        end)
      end)
    end)
  end

  run()
  return
end

buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "\tcat <<-LIVE" })
vim.bo[buf].filetype = "bash"
vim.bo[buf].expandtab = false
vim.bo[buf].tabstop = 2
vim.bo[buf].softtabstop = 0
vim.bo[buf].shiftwidth = 2
-- Disable Neovim's own indentation so only the plugin can satisfy the
-- structural-prefix assertions after subsequent Enter presses.
vim.bo[buf].autoindent = false
vim.bo[buf].smartindent = false
vim.bo[buf].cindent = false
vim.bo[buf].indentexpr = ""
vim.bo[buf].formatoptions = ""
vim.api.nvim_set_current_buf(buf)
plugin.setup()

-- nvim_input queues keys for Neovim's normal input loop. Unlike feedkeys(...,
-- "x"), it does not drain the whole sequence inside this synchronous Lua
-- command and accidentally turn the test into a Normal-mode observation.
vim.api.nvim_win_set_cursor(0, { 1, #("\tcat <<-LIVE") })
vim.api.nvim_input("A\n")

defer(function()
  local actual = lines(buf)
  assert(actual[2] == "\t\t" and actual[3] == "\tLIVE",
    "Enter should create the deeper body prefix and reserve an opener-aligned closer; lines="
      .. vim.inspect(actual))
  assert_insert_mode("the first Enter transition must remain in Insert mode")

  vim.api.nvim_input("typed")
  defer(function()
    actual = lines(buf)
    assert(actual[2] == "\t\ttyped",
      "first body payload should have one TAB beyond the opener alignment; lines="
        .. vim.inspect(actual))
    assert_insert_mode("typing the first payload must remain in Insert mode")

    -- A second Enter creates a genuinely new body line. Wait for the
    -- deferred changed-range processor before typing; this regression guard
    -- checks the existing body-prefix behaviour without claiming that
    -- the live Insert-mode timing problem is solved.
    vim.api.nvim_input("\n")
    defer(function()
      wait_for(function()
        return lines(buf)[3] == "\t\t"
      end, "a subsequent body line must receive its body TAB prefix")
      assert_insert_mode("indentation after Enter must remain in Insert mode")

      vim.api.nvim_input("second")
      defer(function()
        actual = lines(buf)
        assert(actual[3] == "\t\tsecond",
          "second body payload must follow the structural TAB; lines=" .. vim.inspect(actual))
        assert_insert_mode("typing on the newly indented line must remain in Insert mode")

        vim.api.nvim_input("\n")
        defer(function()
          wait_for(function()
            return lines(buf)[4] == "\t\t"
          end, "the next body line must be structurally indented before paste")

        -- Exercise Neovim's paste API while still in Insert mode. The
        -- inserted lines begin with spaces; the plugin must prepend only
        -- the structural TAB to each changed line and retain those spaces.
        local pasted = vim.api.nvim_paste("  pasted one\n    pasted two", false, -1)
        assert(pasted, "Neovim rejected the multi-line paste")
        defer(function()
          wait_for(function()
            actual = lines(buf)
            return actual[4] == "\t\t  pasted one"
              and actual[5] == "\t\t    pasted two"
              and actual[6] == "\tLIVE"
          end, "multi-line paste must be indented before InsertLeave/save without changing payload bytes")
          assert_insert_mode("live paste processing must remain in Insert mode")

          vim.api.nvim_input(vim.api.nvim_replace_termcodes("<Esc>", true, false, true))
          defer(function()
            assert(vim.api.nvim_get_mode().mode ~= "i", "Escape should leave Insert mode")
            actual = lines(buf)
            assert(actual[2] == "\t\ttyped" and actual[3] == "\t\tsecond"
              and actual[4] == "\t\t  pasted one" and actual[5] == "\t\t    pasted two"
              and actual[6] == "\tLIVE",
              "InsertLeave must not be required to repair live body indentation; lines="
                .. vim.inspect(actual))
            print("live Insert-mode buffer tests: PASS")
            vim.cmd("qa!")
          end)
        end)
      end)
    end)
  end)
  end)
end)
