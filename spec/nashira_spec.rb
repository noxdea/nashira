# frozen_string_literal: true

require "tempfile"

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
end
