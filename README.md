# Basic XML Parser

1. Get all tags
   - tags open close w/ '<' and '>'
   - vectorize + multiple threads to get tags
   - time difference
2. Get all elements
   - Define tag types: open, close, prolog
   - Combine open and close tags + ensure only 1 prolog
   - Define parent and children relationship b/w tags
3. Parse tags into zig data structures:
   - define the types of data structures:
     - enums
       - exhaustive
       - non-exhaustive
     - extern structs
     - inline fns
     - inline pfns
     - structs
     - types (u16, u64)
4. Test XML Parser
   - on vk.xml
