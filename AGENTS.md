# MetalSplatter Development Guide for Agentic Coding

## Build Commands
swift build                # Build the package
swift build -c release      # Build with optimizations
xcodebuild -project SampleApp/MetalSplatter_SampleApp.xcodeproj -scheme "MetalSplatter SampleApp" -configuration Release -destination "platform=visionOS Simulator,name=Apple Vision Pro" build  # Build sample app

## Code Style Guidelines
- Use Swift 5.9+ features including modern concurrency
- Follow Apple's Swift API Design Guidelines
- Use descriptive names for variables, functions, and types
- Prefer value types (structs, enums) over reference types when possible
- Use property wrappers (@State, @Observable) appropriately
- Leverage Swift Package Manager structure
- Use MetalKit and Metal Performance Shaders where applicable
- Follow existing code patterns in the repository

## Imports
- Import only necessary modules
- Use explicit imports (no umbrella imports)
- Keep imports at the top of files
- Platform-specific imports should be conditional with #if os() checks

## Formatting
- Use 4-space indentation
- Curly braces on same line for functions/types
- Line length maximum 120 characters
- Use trailing commas in arrays/dictionaries when helpful for diffs
- Prefer implicit self when possible

## Types
- Use Swift native types (SIMD, etc.) for mathematical operations
- Use explicit typing when it improves readability
- Use type aliases for complex Metal types to improve clarity
- Use enums for related constants and options

## Error Handling
- Use Swift's error handling (try/catch) rather than return codes
- Fail fast with fatalError() for unrecoverable errors
- Log errors appropriately with os.Logger
- Handle Metal API errors with guard statements

## Testing
- Tests are available but not considered critical for this library
- Focus on functional correctness over test coverage
- Manual testing via SampleApp is preferred approach
- Unit tests exist for PLYIO and SplatIO modules if needed

## File Organization
- Swift Package structure with separate modules (PLYIO, SplatIO, MetalSplatter)
- Metal shaders in Resources directory with .metal extension
- Source files organized by functionality
- Test files and data in separate directories