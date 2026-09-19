# Nashira

Deterministic CI report cards for JUnit, SimpleCov, and benchmark JSON. Nashira
always writes both a PNG card and a Markdown summary, so the result remains
useful when images are unavailable.

## Installation

```sh
gem install nashira
```

## Usage

```sh
nashira build --junit 'tmp/junit/*.xml' \
  --coverage coverage/.last_run.json \
  --history .ci-history/history.json \
  --now 2026-09-19T14:32:00Z \
  --out card.png --summary summary.md
```

Use `--fail-on coverage-drop` (or `--fail-on tests`) in CI. The composite
action in [`action.yml`](action.yml) installs the gem and appends the summary to
`GITHUB_STEP_SUMMARY`. Set `history-branch` to persist the history and image on
an orphan branch; that workflow needs `contents: write`. Without it, the
action falls back to the cache and still emits the Markdown summary.

## Development

Run `rake spec` and `gem build --strict nashira.gemspec`.

## Contributing

Bug reports and pull requests are welcome at https://github.com/noxdea/nashira.

## License

MIT.
