# Contributing

- Build and test: see the README. `cargo test -p pimp-my-grub-core && sh tests/helper.test.sh` must pass.
- `helper/pimp-my-grub-helper.sh` is the only code that changes system files. Any change there needs a test in
  `tests/helper.test.sh` (including a failure-injection case) and must keep: backup first, marked block only,
  comment-out instead of delete, validate before swap, automatic restore on error.
- Keep `crates/core` free of GUI dependencies so it stays testable headlessly.
- UI changes: include a screenshot in the PR.
