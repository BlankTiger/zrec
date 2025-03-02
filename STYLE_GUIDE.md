# Style Guide

This document outlines the coding conventions and style guidelines for the zrec project.

## General Formatting

### Spacing and Indentation
- Use 4 spaces for indentation (not tabs)
- Add a space after keywords (`if`, `for`, `switch`, etc.)
- Add a space after commas in parameter lists
- No space between function name and opening parenthesis
- No space after opening or before closing parentheses in function declarations or calls

### Line Length
- Prefer keeping lines under 120 characters
- For long expressions, break after operators when wrapping

### Braces
- Opening braces stay on the same line as the statement
- Closing braces get their own line unless followed by `else`, `catch`, etc.

```zig
if (condition) {
    // code
} else {
    // code
}

fn example() !void {
    if (condition) {
        // code
    }
}
```

## Naming Conventions

### Variables and Functions
- Use `snake_case` for variable and function names
- Prefer descriptive names over abbreviations except for common ones (e.g., `idx`, `len`)
- Local variables with limited scope can use shorter names

### Types
- Use `PascalCase` for struct, enum, union, and error set names
- Prefix error sets with the associated type name or function

### Constants and Enums
- Use `SCREAMING_SNAKE_CASE` for constants declared at module level
- For enum variants, use either:
  - `PascalCase` for "type-like" enums
  - `SCREAMING_SNAKE_CASE` for "constant-like" enums

### Fields and Parameters
- Use `snake_case` for fields and function parameters

## Code Organization

### Imports
- Group imports by standard library, third-party, and local modules
- Place standard library imports first
- Use explicit imports for clarity (prefer `const log = std.log.scoped(.module_name)` over just importing `std`)

```zig
const std = @import("std");
const log = std.log.scoped(.module_name);
const Allocator = std.mem.Allocator;

const lib = @import("lib.zig");
const Reader = lib.Reader;
```

### Module Structure
- Start with imports
- Follow with constants and types
- Then declare public functions
- Place private/helper functions after public functions
- End with tests in a separate namespace

```zig
const std = @import("std");
// other imports

// Constants and types
pub const MyType = struct {
    // fields
};

// Public functions
pub fn publicFunction() void {
    // implementation
}

// Private functions
fn privateHelper() void {
    // implementation
}

test {
    std.testing.refAllDecls(Tests);
}

const Tests = struct {
    // test implementations
};
```

## Memory Management

### Allocation
- Always require an allocator to be passed in for functions that need allocation
- Use `errdefer` to handle allocation cleanup in case of errors
- Prefer `try` over `catch` for error handling in allocation paths

### Ownership
- Clearly document ownership of allocated memory in function comments
- Use "Caller owns returned memory" or similar for clarity
- Consistently use `deinit()` methods for cleanup

## Error Handling

### Error Sets
- Define error sets as part of the module or type they relate to
- Be specific with error names to aid debugging

### Error Propagation
- Use `try` for function calls that can error when you want to propagate the error
- Use `catch` with specific handling when you want to handle the error locally

## Comments and Documentation

### Function Documentation
- Document public functions with a brief description
- Include parameter descriptions for non-obvious parameters
- Indicate ownership of returned memory
- Document errors that can be returned

### Type Documentation
- Document public types with a clear description of their purpose
- Document fields that aren't self-explanatory

### Code Comments
- Use comments to explain "why" not "what" when the code isn't self-explanatory
- Use `// TODO:` for incomplete implementations

## Testing

### Test Organization
- Group tests in a `Tests` namespace after the main code
- Use descriptive test names that explain what is being tested
- Split test functionality into helper functions for complex tests
- Include appropriate error handling in tests

### Test Scoping
- Scope test logs with descriptive names (e.g., `const tlog = std.log.scoped(.module_tests)`)
- Clean up resources in tests using `defer`

## Specific Zig Patterns

### Comptime
- Use comptime blocks for compile-time computations
- Use inline for loops when appropriate for generating code
- Document complex comptime expressions

### Anonymous Structs
- Use anonymous structs with meaningful field names for simple parameter sets
- For complex options, define a named struct type

### Unions
- Use tagged unions for type safety
- Implement common methods for all union variants
- Use switch with exhaustive handling of variants

### Error Handling Patterns
- For resources that need cleanup, use `errdefer` to ensure proper cleanup
- Use the pattern `var x = try allocSomething(); errdefer freeSomething(x);`

## Platform-Specific Code

### Conditional Compilation
- Use `@import("builtin").os.tag` for OS-specific code
- Document platform limitations clearly
- Use switch statements for handling different platforms
- Provide meaningful error messages for unsupported platforms

## Performance Considerations

### Buffering
- Use appropriate buffer sizes based on the benchmarks (e.g., 4KB for general IO)
- Document performance characteristics of different implementations
- Use explicit alignments where needed for performance

### Memory Mapping
- Prefer memory mapping for large files
- Document limitations of memory mapping approaches

## Filesystem Implementations

### Interface Consistency
- All filesystem implementations should implement the same core interface
- Common methods: `init()`, `deinit()`, `get_size()`, `get_free_size()`
- Document filesystem-specific limitations

### Error Handling
- Use specific errors for filesystem-related issues
- Propagate underlying system errors when appropriate
