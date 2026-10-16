# Contributing to PaskalCPP

We welcome bug reports, feature ideas, documentation improvements, tests, and source-code contributions to the PaskalCPP Programming Language.

PaskalCPP is created and maintained by tinyBigGAMES™ LLC with help from its community.

## Before you begin

- Read the repository [README](https://github.com/tinyBigGAMES/PaskalCPP?tab=readme-ov-file) and [LICENSE](LICENSE).
- Search existing GitHub issues and pull requests before creating a duplicate.
- For substantial language changes, compiler architecture changes, or major new features, open an issue to discuss the proposal before investing significant effort.
- Keep changes focused and explain the reason for them.

## Reporting bugs

Please include, when available:

1. The PaskalCPP version or commit used.
2. Your operating system and relevant toolchain details.
3. A minimal source-code example or steps to reproduce the problem.
4. Expected behavior and actual behavior.
5. Relevant compiler diagnostics, logs, or screenshots (without secrets or personal data).

Please do not publish security-sensitive issues with exploit details in public issue threads. Contact the maintainers privately by email at support [at] paskalcpp [dot] org, or through the repository's security-reporting channel, if enabled.

## Proposing features

Describe the use case, desired behavior, potential compatibility impact, and any alternatives you considered. Language and toolchain changes should be consistent with the project's goals: readable Pascal/Oberon-inspired syntax, systems programming, and practical C/C++ interoperability.

## Submitting a pull request

1. Fork the repository and create a focused branch.
2. Make your changes and follow the conventions already used in the affected files.
3. Add or update tests for behavior changes when practical.
4. Update documentation and examples when relevant.
5. Confirm that your changes build and that relevant tests pass, when you have access to the necessary tooling.
6. Open a pull request summarizing what changed, why, and how you tested it. Link related issues.

Maintainers may request revisions. Submission does not guarantee acceptance or a particular review timeline.

## Delphi coding conventions

For Delphi source-code contributions, follow the existing project's style. In particular:

- Prefix local variable names with `L` and routine parameter names with `A`.
- Do not use inline variable declarations.
- Put each local variable declaration and each `uses` entry on its own line.
- Prefer `const` parameters where appropriate.
- Avoid Delphi keywords and directives as identifiers; do not escape them with `&`.
- Call parameterless routines with empty parentheses: `MyProcedure()`.
- Do not use strings in `case` statements; use `if..else if`.
- Initialize arrays and records as typed constants in a `const` section, never in `var`.
- Keep source readable, deterministic, and straightforward to maintain.

## Licensing contributions

Unless explicitly stated otherwise for a particular file or component, contributions accepted into MPL-2.0-covered source files are provided under the Mozilla Public License 2.0. By submitting a contribution, you represent that you have the rights needed to make it available under the applicable license.

You retain copyright in your original contributions. Do not replace your copyright with tinyBigGAMES™ LLC's copyright unless you have permission to do so. Preserve existing licensing and attribution notices, and identify additional copyright holders when appropriate.

Every new source file starts with the project's MPL-2.0 file header. Copy it from an existing file of the same kind.

Do not submit third-party code, assets, generated materials, or snippets unless you can confirm that their inclusion and licensing are permitted. Disclose the origin and license of any third-party material you propose to add.

At present, this document does not require copyright assignment or a separate contributor license agreement. If the project adopts a different contribution process later, it will be documented before that process applies to new submissions.

## Working together

Be constructive in reviews, document compatibility concerns, and discuss technical disagreements respectfully. Please also read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Community and project decisions

The maintainers determine the direction of the official project, including which changes are merged and what is included in official releases. Forking and independent development remain permitted under the applicable open-source licenses.

Official project information: https://paskalcpp.org
