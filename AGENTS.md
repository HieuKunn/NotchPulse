# NotchPulse Agent Instructions & Rules

Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

## ⛔️ STRICT RELEASE CONSTRAINT
If the user's prompt does **NOT** contain a direct, explicit command or request regarding releasing (such as "release", "publish", "tag", "release lại", "sửa lỗi build release", etc.), **DO NOT** bump versions or build numbers, **DO NOT** create or push git tags, and **DO NOT** trigger release workflows. Simply make code edits and verify correctness.

## 🛑 BATCH COMMITTING RULE (NO INTERMEDIATE COMMITS)
**DO NOT** create git commits after every small edit, individual step, or turn. Simply edit code, verify correctness, and leave changes in the working tree. Wait until performing a release (or when the user explicitly requests to commit) to commit all changes together in a single consolidated commit.
