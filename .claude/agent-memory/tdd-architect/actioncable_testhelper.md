---
name: actioncable-testhelper-include
description: assert_broadcasts requires explicit include ActionCable::TestHelper in ActiveJob::TestCase subclasses
metadata:
  type: feedback
---

`ActiveJob::TestCase` does NOT automatically include `ActionCable::TestHelper`. Tests using `assert_broadcasts` in job test files must explicitly add `include ActionCable::TestHelper` in the test class body.

**Why:** Without it, calling `assert_broadcasts` raises `NoMethodError: undefined method 'assert_broadcasts'`.

**How to apply:** Any job test that verifies Turbo Stream broadcasts must include `ActionCable::TestHelper`.
