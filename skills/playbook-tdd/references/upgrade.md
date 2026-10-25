# Dependency upgrade

## When it applies
Bumping a library, framework, runtime or tool version, by hand or from a bot pull request. Weight: Lite when the change stays within the Lite limits as `role-gate.sh size` counts it (an update of a lockfile that exists beside its manifest at the base is left out; a new lockfile counts) and no Full item applies; Full when the project's own exported API or critical code changes behaviour. State the weight with its reason.

## Breaking-changes checklist
1. Baseline: run the tests on the old version and see them green. Keep the run as evidence.
2. Read the release notes or changelog of every version between the old and the new one. Cite the URL or file and the version for each breaking change.
3. For each breaking change, search the usages: the command, the hits and each file:line. List the ones the project uses and the ones it does not.
4. For each affected usage that no test covers, write a characterization test that passes on the old version.
5. Bump through the package manager. Never hand-edit a lockfile. Run the official codemod if there is one.
6. Review the lockfile diff: only the intended packages and their dependencies changed. Ask about a new direct dependency before keeping it.
7. Run fresh test, lint, typecheck and build, and make one smoke observation of the running program.
8. Rollback is the previous manifest and lockfile commit. Name it in the report.

## Notes
- A characterization test that fails after the bump points to a breaking change missed in step 3: go back to that step.
- A vendored copy has no lockfile; its files count toward the size limit like any code.
- When the new version ships a generated lockfile (a vendored release, say), copy it unchanged; that is not a hand edit.
