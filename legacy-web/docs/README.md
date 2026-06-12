# Documentation

This folder contains comprehensive documentation for the Roguelike-like codebase.

## Files

### [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
**For developers adding content or working on the codebase**

- How to use the new utility systems (Constants, Storage, StateMutator, CurseManager, BFSCache)
- Step-by-step guides for adding items, enemies, events, and games
- Code organization and file structure
- Best practices (DO/DON'T examples)
- Common patterns and troubleshooting
- Performance tips

**Start here if you want to:**
- Add new items, enemies, or events
- Understand how the utility systems work
- Learn the codebase conventions

---

### [CODE_QUALITY_REPORT.md](CODE_QUALITY_REPORT.md)
**Comprehensive analysis of code quality issues**

- Analysis of 10 JavaScript files (~5,200 lines)
- 30+ issue categories identified with line numbers
- Code duplication patterns (854+ magic numbers, 33+ duplicates)
- Performance bottlenecks and memory leaks
- Prioritized improvement roadmap (Critical → High → Medium → Low)
- Estimated impact and metrics

**Use this for:**
- Understanding what issues exist in the codebase
- Planning future refactoring work
- Finding specific code smells and their locations
- Seeing the big picture of technical debt

---

### [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)
**Status report of what was implemented**

- What was completed (5 utility systems + 3 code migrations)
- What remains to be done
- Metrics and impact analysis
- Testing recommendations
- Files changed and commits made
- Next steps and priorities

**Use this for:**
- Understanding what's been done
- Seeing what's left to do
- Tracking progress
- Planning next work items

---

## Quick Start

1. **Want to add content?** → Read [DEVELOPER_GUIDE.md](DEVELOPER_GUIDE.md)
2. **Want to understand issues?** → Read [CODE_QUALITY_REPORT.md](CODE_QUALITY_REPORT.md)
3. **Want to see progress?** → Read [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)

## Related Files

- `../README.md` - User-facing game documentation (in root)
- `../js/constants.js` - Configuration and magic numbers
- `../js/storage.js` - Safe localStorage wrapper
- `../js/state-mutator.js` - State management utility
- `../js/curse-manager.js` - Curse handling utility
- `../js/bfs-cache.js` - Pathfinding optimization
