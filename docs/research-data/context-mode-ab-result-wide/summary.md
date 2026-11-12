# Context Mode A/B (without playbook)

| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median tool-result KB | Median peak context tokens | Median turns | Plugin loaded (runs) | ctx tool calls (total) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| project-07-wide-refactor | baseline | 1 | 0 | 1/1 | 0.303 | 99 | 883986 | 31891 | 17.5 | 50085 | 29.0 | 0 | 0 |
| project-07-wide-refactor | context-mode | 1 | 0 | 1/1 | 0.280 | 88 | 709651 | 33549 | 23.7 | 52245 | 25.0 | 1 | 5 |

Total cost_usd of all runs: 0.583

Read with care: k is small, the transcript parser is untested, and 'Plugin loaded' 0 in the context-mode arm means the plugin did not load (then the arm measures nothing).
