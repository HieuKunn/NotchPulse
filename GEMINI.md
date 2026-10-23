# NotchPulse Project Context & Agent Instructions

Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

## ⛔️ STRICT RELEASE CONSTRAINT
If the prompt does **NOT** contain a direct, explicit command or instruction regarding releasing (such as "release", "publish", "tag", "release lại", "sửa lỗi build release", etc.), **DO NOT** bump versions or build numbers, **DO NOT** create/push tags, and **DO NOT** trigger any release process. Perform changes and verify correctness without creating a release.

## 🛑 BATCH COMMITTING RULE (NO INTERMEDIATE COMMITS)
**DO NOT** create git commits after every small edit, individual step, or turn. Simply edit code, verify correctness, and leave changes in the working tree. Wait until performing a release (or when the user explicitly requests to commit) to commit all changes together in a single consolidated commit.
