<h1 align="center">Nashira</h1>

<p align="center">
  <strong>Deterministic CI report cards for JUnit, SimpleCov, and benchmark JSON.</strong>
</p>

<p align="center">
  <a href="https://rubygems.org/gems/nashira"><img src="https://img.shields.io/gem/v/nashira?style=flat-square" alt="Gem version"></a>
  <a href="https://rubygems.org/gems/nashira"><img src="https://img.shields.io/gem/dt/nashira?style=flat-square" alt="Gem downloads"></a>
  <a href="https://github.com/noxdea/nashira/actions/workflows/main.yml"><img src="https://github.com/noxdea/nashira/actions/workflows/main.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/Ruby-%3E%3D%203.2-CC342D?style=flat-square" alt="Ruby 3.2 or newer">
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT license"></a>
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#installation">Installation</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#github-action">GitHub Action</a> ·
  <a href="#failure-policies">Failure policies</a> ·
  <a href="#development">Development</a>
</p>

---

Nashira creates deterministic CI report cards from JUnit, SimpleCov, and
benchmark JSON. Every build writes both a PNG and a Markdown summary, so the
report remains useful when images are unavailable.

## Features

- **One CI snapshot** — combine tests, coverage, benchmarks, and run metadata.
- **Resilient parsing** — malformed report files become visible warnings.
- **Deterministic output** — render repeatable PNG cards through Zaniah.
- **Markdown fallback** — always emit a readable table for Job Summaries.
- **Coverage history** — retain up to 50 points and show recent trends.
- **Failure policies** — fail on test failures or coverage regression.
- **GitHub integration** — cache history, publish a history branch, or update a pull request comment.

## Installation

```bash
gem install nashira
```

Nashira requires Ruby 3.2 or newer.

## Quick start

```bash
nashira build \
  --junit "tmp/junit/*.xml" \
  --coverage coverage/.last_run.json \
  --bench tmp/benchmarks.json \
  --history .ci-history/history.json \
  --out nashira-card.png \
  --summary nashira-summary.md
```

The Markdown output includes test counts, coverage and delta, benchmark values,
slow tests, failures, and a coverage trend when enough history exists.

## GitHub Action

```yaml
permissions:
  contents: read

steps:
  - uses: actions/checkout@v4
  - name: Run tests
    run: bundle exec rake
  - uses: noxdea/nashira@v0.1.0
    with:
      junit: "tmp/junit/*.xml"
      coverage: coverage/.last_run.json
      bench: tmp/benchmarks.json
```

The action appends the generated Markdown to `GITHUB_STEP_SUMMARY` and caches
history by default.

| Input | Default | Description |
|---|---|---|
| `junit` | — | JUnit glob |
| `coverage` | — | SimpleCov JSON path |
| `bench` | — | Benchmark JSON path |
| `history` | `.ci-history/history.json` | History JSON path |
| `out` | `nashira-card.png` | PNG output path |
| `summary` | `nashira-summary.md` | Markdown output path |
| `history-branch` | — | Orphan branch used for persistent history and the image |
| `comment-on-pr` | `false` | Update one Nashira pull request comment |

`history-branch` requires `contents: write`. Pull request comments require
`issues: write`; pass `github-token` only when the default token is not
suitable.

## Failure policies

Fail when tests fail:

```bash
nashira build --junit "tmp/junit/*.xml" --fail-on tests
```

Fail when coverage drops below an explicit baseline:

```bash
nashira build \
  --coverage coverage/.last_run.json \
  --base-coverage 92.5 \
  --fail-on coverage-drop
```

Use `--theme`, `--title`, `--branch`, `--commit`, and `--run-url` to attach
presentation and run metadata.

## Development

```bash
bundle install
bundle exec rake
bundle exec rbs -I sig validate
gem build --strict nashira.gemspec
```

## Contributing

Bug reports and pull requests are welcome on
[GitHub](https://github.com/noxdea/nashira).

## License

Nashira is available under the [MIT License](LICENSE.txt).
