# TESTING

Automated tests cover the state/hook pipeline in isolation. Before
merging anything that touches the Claude Code hook path, run the
manual smoke checklist below - that path has the highest blast radius.

## Automated

    tests/run-tests.sh             # all suites
    tests/run-tests.sh tests/bats/test_state.bats   # single suite

## Manual smoke checklist

Requires a live tmux session and an installed `claude` binary.

- [ ] `./install.sh --check` reports all deps satisfied.
- [ ] `./install.sh` completes without error.
- [ ] `tmux source-file ~/.tmux.conf` succeeds.
- [ ] Press `prefix + A` -> a new pane opens in your current window
      with `claude` running.
- [ ] `tmux-ai list` shows the new pane registered as `claude` with
      state `idle`.
- [ ] Type a prompt in the claude pane -> `tmux-ai list` shows
      `state=working` within 2 seconds.
- [ ] Wait for claude to finish -> desktop notification fires, state
      returns to `done`.
- [ ] Press `prefix + a` -> dashboard popup shows the agent.
- [ ] Press `prefix + D` -> start a new turn -> **no** desktop
      notification fires.
- [ ] Press `prefix + D` again -> DND off; notifications resume.
- [ ] Kill the claude pane -> within 2 seconds `tmux-ai list` drops it
      (pane_exited or detect garbage-collects).
- [ ] Confirm a log file appeared under
      `~/.local/state/tmux-ai/logs/<project>/`.
- [ ] Check `~/.local/state/tmux-ai/tmux-ai.log` - no unexpected
      errors.

## Uninstall check

- [ ] `./install.sh --uninstall` completes.
- [ ] Grep `~/.tmux.conf` for `tmux-ai` -> no matches.
- [ ] `tmux-ai` not on PATH.
