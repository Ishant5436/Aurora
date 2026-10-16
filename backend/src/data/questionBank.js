// Built-in question bank: the offline fallback and the seed for the cache.
// The first four questions come from the original Lovable prototype.
const q = (topic, difficulty, text, options, answerIndex, explanation) => ({
  topic,
  difficulty,
  text,
  options,
  answerIndex,
  explanation,
});

const QUESTIONS = [
  // JavaScript
  q('JavaScript', 'Easy', 'In JavaScript, what does `typeof null` return?', ['"null"', '"undefined"', '"object"', '"number"'], 2,
    'A historical quirk of the language: null is reported as "object".'),
  q('JavaScript', 'Easy', 'What does Array.prototype.map return?', ['The original array, modified', 'A new array', 'A single value', 'undefined'], 1,
    'map never mutates the source; it returns a new array of the callback results.'),
  q('JavaScript', 'Medium', 'What does `[] + {}` evaluate to in JavaScript?', ['0', '"[object Object]"', 'NaN', 'An empty string'], 1,
    'Both operands become strings: [] is "" and {} is "[object Object]".'),
  q('JavaScript', 'Medium', 'Which statement about let and var is correct?',
    ['Both are block-scoped', 'let is block-scoped while var is function-scoped', 'var is block-scoped while let is function-scoped', 'Neither can be reassigned'], 1,
    'let respects block scope; var is scoped to the whole function.'),
  q('JavaScript', 'Hard', 'What does Promise.all do if one of the promises rejects?',
    ['Waits for all, then resolves with partial results', 'Rejects immediately with the first rejection reason', 'Ignores the rejection and resolves the rest', 'Retries the rejected promise once'], 1,
    'Promise.all is fail-fast; use Promise.allSettled to collect every outcome.'),

  // Algorithms
  q('Algorithms', 'Easy', 'Which data structure offers O(1) average lookup by key?', ['Linked list', 'Hash map', 'Binary heap', 'Stack'], 1,
    'Hash maps compute a bucket from the key, giving constant average-time lookups.'),
  q('Algorithms', 'Easy', 'What is the time complexity of binary search?', ['O(n)', 'O(log n)', 'O(n log n)', 'O(1)'], 1,
    'Each step halves the search space, so it takes logarithmic time.'),
  q('Algorithms', 'Medium', 'Which data structure does breadth-first search use to track its frontier?', ['Stack', 'Queue', 'Heap', 'Hash set'], 1,
    'A FIFO queue visits nodes level by level.'),
  q('Algorithms', 'Medium', 'Which sorting algorithm has O(n log n) worst-case time but needs extra O(n) space?',
    ['Quick sort', 'Merge sort', 'Bubble sort', 'Insertion sort'], 1,
    'Merge sort guarantees O(n log n); quick sort degrades to O(n^2) in the worst case.'),
  q('Algorithms', 'Hard', "Dijkstra's algorithm can give wrong shortest paths when the graph has what?",
    ['Cycles', 'Negative edge weights', 'Disconnected nodes', 'Parallel edges'], 1,
    'It assumes a settled node can never be improved, which negative weights break. Use Bellman-Ford instead.'),

  // System Design
  q('System Design', 'Easy', 'What is the primary purpose of a load balancer?',
    ['Encrypt traffic', 'Distribute incoming traffic across servers', 'Store session data', 'Compile code'], 1,
    'It spreads requests over several servers for capacity and availability.'),
  q('System Design', 'Medium', 'What is the main benefit of a CDN?',
    ['Faster database writes', 'Serving content from locations closer to users', 'Stronger passwords', 'Smaller source code'], 1,
    'Edge caches cut latency by serving static assets from a nearby point of presence.'),
  q('System Design', 'Medium', 'During a network partition, the CAP theorem says a system must trade off between which two properties?',
    ['Consistency and availability', 'Latency and throughput', 'Durability and isolation', 'Scalability and cost'], 0,
    'Partitions are unavoidable, so you choose between consistent answers and always answering.'),
  q('System Design', 'Hard', 'Which technique minimises key remapping when cache nodes are added or removed?',
    ['Round-robin DNS', 'Consistent hashing', 'Two-phase commit', 'Leader election'], 1,
    'Consistent hashing remaps only about 1/N of the keys when the node set changes.'),

  // Databases
  q('Databases', 'Easy', 'Which SQL clause filters rows after grouping?', ['WHERE', 'HAVING', 'ORDER BY', 'LIMIT'], 1,
    'WHERE filters rows before GROUP BY; HAVING filters the groups.'),
  q('Databases', 'Medium', 'Which anomaly occurs when a transaction reads data another transaction has not committed?',
    ['Phantom read', 'Dirty read', 'Lost update', 'Write skew'], 1,
    'Reading uncommitted changes is a dirty read; READ COMMITTED and above prevent it.'),
  q('Databases', 'Medium', 'In MongoDB, which operator matches a field whose value is in a given array?', ['$all', '$in', '$elemMatch', '$exists'], 1,
    '$in matches any value in the list; $all requires an array field to contain all of them.'),
  q('Databases', 'Hard', 'A composite index on (a, b, c) can efficiently serve a query that filters only on which column(s)?',
    ['b only', 'c only', 'a only', 'b and c'], 2,
    'Composite indexes follow the leftmost-prefix rule, so the query must start with a.'),

  // Networking
  q('Networking', 'Easy', 'Which transport protocol guarantees ordered, reliable delivery?', ['UDP', 'TCP', 'ICMP', 'ARP'], 1,
    'TCP uses acknowledgements and retransmission; UDP does not.'),
  q('Networking', 'Easy', 'What does DNS primarily do?',
    ['Encrypts web traffic', 'Translates domain names to IP addresses', 'Assigns MAC addresses', 'Routes packets between networks'], 1,
    'DNS is the internet phone book mapping names to addresses.'),
  q('Networking', 'Medium', 'Which HTTP method is idempotent?', ['POST', 'PATCH', 'PUT', 'CONNECT'], 2,
    'Repeating a PUT leaves the resource in the same state as doing it once.'),
  q('Networking', 'Hard', 'How many round trips does a full TLS 1.3 handshake need before application data can flow?', ['0', '1', '2', '3'], 1,
    'TLS 1.3 completes in one round trip (1-RTT); 0-RTT applies only to resumed sessions.'),

  // React
  q('React', 'Easy', 'Which hook manages local state in a function component?', ['useRef', 'useState', 'useMemo', 'useId'], 1,
    'useState returns the current value and a setter that triggers a re-render.'),
  q('React', 'Medium', 'When does a useEffect with an empty dependency array run?',
    ['After every render', 'Once after the first render', 'Only on unmount', 'Before every render'], 1,
    'It runs after the initial render, and its cleanup runs on unmount.'),
  q('React', 'Medium', 'Why do list items need a stable key prop?',
    ['To style them', 'To let React identify items between renders', 'To make them clickable', 'To sort them'], 1,
    'Keys let React match old and new elements so state and DOM nodes are reused correctly.'),
  q('React', 'Hard', 'What happens if you mutate a state object directly instead of calling the setter?',
    ['React throws an error', 'The component may not re-render because the reference is unchanged', 'The change is saved to localStorage', 'The mutation is rolled back'], 1,
    'React compares references, so in-place mutation can leave the UI stale.'),

  // Python
  q('Python', 'Easy', 'Which of these is an immutable type in Python?', ['list', 'dict', 'tuple', 'set'], 2,
    'Tuples cannot be changed after creation; lists, dicts and sets can.'),
  q('Python', 'Medium', 'What does `[x*x for x in range(3)]` evaluate to?', ['[1, 4, 9]', '[0, 1, 4]', '[0, 1, 2]', '[0, 2, 4]'], 1,
    'range(3) yields 0, 1, 2, and each is squared.'),
  q('Python', 'Medium', 'What does the yield keyword do in a function?',
    ['Ends the program', 'Turns the function into a generator that produces values lazily', 'Raises an exception', 'Imports a module'], 1,
    'yield pauses the function and hands back a value, resuming on the next iteration.'),
  q('Python', 'Hard', 'What is the GIL in CPython?',
    ['A garbage collector', 'A lock allowing only one thread to execute Python bytecode at a time', 'A type checker', 'A package manager'], 1,
    'The Global Interpreter Lock limits CPU-bound threading, so use multiprocessing for parallel compute.'),
];

const VOICE_PROMPTS = {
  JavaScript: [
    'Explain how closures work in JavaScript and give one practical use for them.',
    'Describe the JavaScript event loop and why long synchronous tasks block the UI.',
    'Explain the difference between var, let and const, and how scope and hoisting affect each of them.',
    'Describe how promises and async await work, and how you would handle errors across several concurrent requests.',
  ],
  Algorithms: [
    'Explain the difference between breadth-first and depth-first search, and when you would choose each.',
    'Walk through how binary search works and why it requires sorted input.',
    'Explain what Big O notation tells you, and compare searching a hash map with searching a sorted array.',
    'Describe how a hash table handles collisions, and what happens to performance as it fills up.',
  ],
  'System Design': [
    'Explain how you would scale a read-heavy web service, and name one trade-off of your approach.',
    'Describe what a cache is, where you would place one, and how you would handle invalidation.',
    'Explain the trade-offs between a relational database and a document store when designing a new service.',
    'Describe how you would make a service highly available, and which failure you would worry about first.',
  ],
  Databases: [
    'Explain how a database index speeds up queries, and describe one trade-off of adding too many indexes.',
    'Describe what a database transaction is and what the ACID properties guarantee.',
    'Explain the difference between an inner join and a left join, and when each is the right choice.',
    'Describe database normalization, and one situation where you would deliberately denormalize.',
  ],
  Networking: [
    'Explain at a high level what happens when you type a URL into a browser and press enter.',
    'Compare TCP and UDP and give an example use case for each.',
    'Explain how HTTPS protects a connection, including what the TLS handshake accomplishes.',
    'Describe what DNS does and how a lookup travels from your device to an authoritative server.',
  ],
  React: [
    'Explain how React decides when to re-render a component, and one way to avoid unnecessary renders.',
    'Describe the difference between state and props, and who owns each.',
    'Explain what the useEffect hook is for, and how its dependency array changes when it runs.',
    'Describe how you would share state between distant components, and the trade-offs of the options.',
  ],
  Python: [
    'Explain the difference between a list and a tuple in Python and when you would use each.',
    'Describe how Python generators work and why they save memory.',
    'Explain what decorators are in Python and show where you would use one.',
    'Describe the difference between a shallow copy and a deep copy, and when each causes surprises.',
  ],
};

module.exports = { QUESTIONS, VOICE_PROMPTS };
