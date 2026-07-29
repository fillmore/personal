# AGENTS.md

When working with GitHub in this repository, always follow this sequence before and after any GitHub action.

1. Switch the active GitHub account to `fillmore`:
   `gh auth switch --hostname github.com --user fillmore`

2. Perform the required GitHub action using `fillmore` credentials, such as:
   - `gh issue create ...`
   - `gh pr create ...`
   - `gh repo view fillmore/personal ...`
   - any other GitHub CLI operation touching issues, pull requests, repo metadata, or workflow state

3. Switch back to the personal account after the GitHub action completes or fails:
   `gh auth switch --hostname github.com --user lingfw_green`

Important rules:
- Do not create issues, PRs, or perform repo-scoped GitHub actions while the active account is `lingfw_green` for this repository.
- `gh auth` is account-scoped, not repo-scoped, so the agent must actively switch before using GitHub commands here.
- If `fillmore` is not authenticated yet, authenticate it first with `gh auth login` and then switch to it.
- Always restore the active account to `lingfw_green` before finishing the task.
