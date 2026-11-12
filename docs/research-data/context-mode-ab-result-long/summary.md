# Context Mode A/B (without playbook)

| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median tool-result KB | Median peak context tokens | Median turns | Plugin loaded (runs) | ctx tool calls (total) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| project-06-long-session | baseline | 1 | 0 | 1/1 | 0.388 | 133 | 965291 | 40801 | 28.9 | 58995 | 29.0 | 0 | 0 |
| project-06-long-session | context-mode | 1 | 0 | 0/1 | 0.308 | 125 | 706594 | 32386 | 12.0 | 51082 | 33.0 | 1 | 1 |

Total cost_usd of all runs: 0.696

Read with care: k is small, the transcript parser is untested, and 'Plugin loaded' 0 in the context-mode arm means the plugin did not load (then the arm measures nothing).
