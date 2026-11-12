# Context Mode A/B (without playbook)

| Task | Arm | Runs graded | Errors | Passed all hidden tests | Median cost USD | Median seconds | Median input-side tokens | Median cache write | Median tool-result KB | Median turns | Plugin loaded (runs) | ctx tool calls (total) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| project-05-tax-exempt-noisy | baseline | 3 | 0 | 3/3 | 0.161 | 45 | 405677 | 21740 | 6.6 | 17.0 | 0 | 0 |
| project-05-tax-exempt-noisy | context-mode | 3 | 0 | 1/3 | 0.085 | 50 | 369542 | 6223 | 7.4 | 13.0 | 3 | 0 |

Total cost_usd of all runs: 0.882

Read with care: k is small, the transcript parser is untested, and 'Plugin loaded' 0 in the context-mode arm means the plugin did not load (then the arm measures nothing).
