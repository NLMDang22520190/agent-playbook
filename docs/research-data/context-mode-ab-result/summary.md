# Context Mode A/B (without playbook)

| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median turns | Plugin loaded (runs) | ctx tool calls (total) |
|---|---|---|---|---|---|---|---|---|---|---|---|
| project-01-order-flow | baseline | 3 | 0 | 2/3 | 0.215 | 67 | 233529 | 28159 | 11.0 | 0 | 0 |
| project-01-order-flow | context-mode | 3 | 0 | 3/3 | 0.227 | 83 | 350559 | 17793 | 25.0 | 3 | 0 |
| project-02-tax-exempt | baseline | 3 | 0 | 3/3 | 0.126 | 47 | 445782 | 8883 | 19.0 | 0 | 0 |
| project-02-tax-exempt | context-mode | 3 | 0 | 3/3 | 0.115 | 42 | 302513 | 8141 | 16.0 | 3 | 0 |

Total cost_usd of all runs: 2.106

Read with care: k is small, the transcript parser is untested, and 'Plugin loaded' 0 in the context-mode arm means the plugin did not load (then the arm measures nothing).
