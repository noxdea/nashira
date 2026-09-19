# frozen_string_literal: true

require "tempfile"
require "stringio"
require "fileutils"

RSpec.describe Nashira do
  it "aggregates JUnit failures and skipped tests" do
    path = Tempfile.new(["nashira", ".xml"])
    path.write('<testsuite><testcase classname="a" name="ok" time="0.1"/><testcase name="bad"><failure/></testcase><testcase name="skip"><skipped/></testcase></testsuite>')
    path.close
    result = Nashira::JUnit.parse([path.path])
    expect(result.value).to have_attributes(total: 3, failed: 1, skipped: 1)
  ensure
    path&.unlink
  end

  it "parses simple coverage JSON" do
    path = Tempfile.new("coverage")
    path.write('{"metrics":{"lines":{"covered":9,"total":10}}}')
    path.close
    expect(Nashira::CoverageParser.parse(path.path).value.percent).to eq(90.0)
  ensure
    path&.unlink
  end

  it "renders a readable summary" do
    tests = Nashira::Tests.new(total: 1, failed: 0, skipped: 0, duration: 0.1, slowest: [], failures: [])
    report = Nashira::Report.build(tests: tests)
    expect(Nashira::Summary.markdown(report)).to include("PASS")
  end

  it "keeps parser warnings visible and records the current history point" do
    dir = Dir.mktmpdir("nashira-cli")
    history = File.join(dir, "history.json")
    junit = File.join(dir, "broken.xml")
    File.write(junit, "<testsuite>")
    out = StringIO.new
    err = StringIO.new
    expect(Nashira::CLI.run(["build", "--junit", junit, "--history", history,
      "--now", "2026-01-01T00:00:00Z", "--out", File.join(dir, "card.png"),
      "--summary", File.join(dir, "summary.md")], out: out, err: err)).to eq(0)
    expect(err.string).to include("warning")
    expect(File.read(history)).to include("2026-01-01T00:00:00Z")
  ensure
    FileUtils.remove_entry(dir) if dir
  end

  it "ignores malformed history shapes" do
    path = Tempfile.new("history")
    path.write('{"not":"an array"}')
    path.close
    expect(Nashira::History.load(path.path)).to eq([])
  ensure
    path&.unlink
  end
end
