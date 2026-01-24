# Zsh Documentation Reference Skill

Use this skill when working with zsh syntax, patterns, or behavior in the juvy codebase.

## Triggers

Activate this skill when encountering questions or tasks involving:
- "zsh syntax", "zsh documentation", "zsh manual"
- "how does zsh handle"
- "zsh parameter expansion", "zsh conditionals"
- "zsh functions", "zsh builtins", "zsh options"
- Writing or modifying `.zsh` files in this project

## Documentation Reference

Use the Read tool to consult these HTML files in this skill directory:

### Core Language

| Topic | File |
|-------|------|
| Shell grammar & syntax | `Shell-Grammar.html` |
| Functions | `Functions.html` |
| Expansion overview | `Expansion.html` |
| Conditional expressions | `Conditional-Expressions.html` |
| Shell builtins | `Shell-Builtin-Commands.html` |
| Options | `Options.html` |

### Expansion & Substitution

| Topic | File |
|-------|------|
| Parameter expansion `${...}` | `Parameter-Expansion.html` |
| Arithmetic evaluation `((...))` | `Arithmetic-Evaluation.html` |
| Arithmetic expansion `$((...))` | `Arithmetic-Expansion.html` |
| Brace expansion `{a,b,c}` | `Brace-Expansion.html` |
| Filename expansion (globbing) | `Filename-Expansion.html` |
| Command substitution `$(...)` | `Command-Substitution.html` |
| Process substitution `<(...)` | `Process-Substitution.html` |

### Execution & Flow

| Topic | File |
|-------|------|
| I/O redirection | `Redirection.html` |
| Jobs & signals | `Jobs-_0026-Signals.html` |
| Precommand modifiers | `Precommand-Modifiers.html` |

### Variables & Parameters

| Topic | File |
|-------|------|
| Special shell variables | `Parameters-Set-By-The-Shell.html` |
| History modifiers `:h :t :r` | `Modifiers.html` |

### Advanced

| Topic | File |
|-------|------|
| Exception handling | `Exception-Handling.html` |
| Initialization & startup | `Initialization.html` |
| Startup files | `Files.html` |

### Useful Modules

| Topic | File |
|-------|------|
| Modules overview | `Zsh-Modules.html` |
| Parameter introspection | `The-zsh_002fparameter-Module.html` |
| File stat operations | `The-zsh_002fstat-Module.html` |
| Regex matching | `The-zsh_002fregex-Module.html` |
| System calls | `The-zsh_002fsystem-Module.html` |
| Date/time functions | `The-zsh_002fdatetime-Module.html` |

## Instructions

1. **Read relevant documentation** - Use the Read tool on the appropriate HTML file(s) above based on the topic
2. **Check CLAUDE.md** - Reference the "Zsh Best Practices & Patterns" section for project-specific idioms and patterns
3. **Mind special variables** - Never use `path`, `cdpath`, `fpath`, `mailpath`, or `manpath` as variable names (these are tied to shell paths in zsh)

## Example Usage

For a question about parameter expansion:
```
Read .claude/skills/zsh-reference/Parameter-Expansion.html
```

For function definition syntax:
```
Read .claude/skills/zsh-reference/Functions.html
```

For conditional test operators:
```
Read .claude/skills/zsh-reference/Conditional-Expressions.html
```

For I/O redirection:
```
Read .claude/skills/zsh-reference/Redirection.html
```

For zsh modules:
```
Read .claude/skills/zsh-reference/Zsh-Modules.html
```
