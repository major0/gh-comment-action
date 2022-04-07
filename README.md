GitHub Comment Action
=====================

A [GitHub Action][] which can add/update comments to Issues and Pull-Requests
from a workflow. Useful for automatically adding reports-as-comments.

Features
--------

- Update existing comments.  E.g. re-running reports on a pull-request during
  resynchronization.
- Track multiple comments on the same issue/pull-request.  E.g.
  linkcheck-report, lighthouse-report, etc..
- Add links to build artifacts to the end of a comment/report.

Pull Request Example
--------------------

```yaml
on: [pull_request]

jobs:
comment:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    - uses: major0/gh-comment-action@v1
      with:
        id: example-report
        issue: ${{ github.event.pull_request.number }}
        template: report.md

    - uses: actions/upload-artifact@v3
      with:
        name: report
        path: report.md
```

Example with Artifacts
----------------------

Adding an artifact **can not** be done from the same workflow that generated
the artifact.  The end-result is the need to create a workflow which runs only
when some other workflow completes.

```yaml
on:
  workflow_run:
    workflows: ["Pull Request"]
    types: [completed]

jobs:
  report-links:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - run: |
        : Download previously uploaded `report` artifact.
        gh run download "${{ github.event.workflow_run.id }}" -n report

    - uses: major0/gh-comment-action@v1
      with:
        id: example-report
        template: report.md
        issue: ${{ github.event.workflow_run.pull_requests[0].number }}
        artifacts: |
          report@${{ github.event.workflow_run.id }}
```

Input Parameters
----------------

|    Input    |                             Description                                       | Required |    Default     |
|:------------|:------------------------------------------------------------------------------|:--------:|:--------------:|
| `issue`     | Issue/Pull-Request number to post to. | `true` | |
| `template`  | Post the contents of the named file as the comment to the PR. Supports Markdown. | `true` | |
| `id`        | Unique tracking ID used to track the comment w/in the issue/pull-request. This allows different comments/reports to be added/updated in the same issue/pull-request from different workflows. | `true` | |
| `artifacts` | Add links to the listed artifacts.  Artifact format should be in the form of NAME@RUN_ID. | `false` | |
| `token`     | Access token to use when pulling artifacts and posting comments. | `false` | |
| `dry-run`   | Report what would be done but do not actually modify the target issue/pull-request. | `false` | `false` |
| `debug`     | Enable execution debugging. | `false` | `false` |

[//]: # (references)

[GitHub]: https://github.com/
[GitHub Action]: https://github.com/features/actions/
