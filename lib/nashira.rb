# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "rexml/document"
require "time"
require "zlib"
require "zaniah"
require "zaniah/ui"
begin
  require "auva"
rescue LoadError
end
require_relative "nashira/version"

module Nashira
  class Error < StandardError; end
  Tests = Data.define(:total, :failed, :skipped, :duration, :slowest, :failures)
  CoverageData = Data.define(:percent, :covered, :total, :delta)
  Bench = Data.define(:name, :value, :unit, :delta)
  HistoryPoint = Data.define(:commit, :coverage, :tests, :at)
  Report = Data.define(:status, :repository, :branch, :commit, :run_url, :finished_at,
    :duration, :tests, :coverage, :benchmarks, :history) do
    def self.build(tests: nil, coverage: nil, benchmarks: [], history: [], **metadata)
      status = tests&.failed.to_i.positive? ? :fail : :pass
      new(status: status, repository: metadata[:repository], branch: metadata[:branch],
        commit: metadata[:commit], run_url: metadata[:run_url], finished_at: metadata[:finished_at],
        duration: tests&.duration, tests: tests, coverage: coverage,
        benchmarks: benchmarks || [], history: history || [])
    end
  end
  ParseResult = Data.define(:value, :warnings)

  module JUnit
    module_function

    def parse(paths, top: 5)
      warnings = []
      cases = []
      Array(paths).flat_map { |path| Dir[path.to_s] }.sort.each do |path|
        begin
          root = REXML::Document.new(File.read(path, encoding: "UTF-8")).root
          raise REXML::ParseException, "missing root" unless root
          root.each_element(".//testcase") do |testcase|
            time = Float(testcase.attributes["time"] || 0)
            name = [testcase.attributes["classname"], testcase.attributes["name"]].compact.join("#")
            kind = testcase.elements["failure"] ? :failure : testcase.elements["error"] ? :error : testcase.elements["skipped"] ? :skipped : :pass
            cases << [name.empty? ? "unknown" : name, time, kind]
          rescue ArgumentError
            cases << [testcase.attributes["name"] || "unknown", 0.0, :pass]
            warnings << "#{path}: invalid testcase time"
          end
        rescue StandardError => error
          warnings << "#{path}: #{error.message}"
        end
      end
      failures = cases.filter_map { |name, _, kind| name if %i[failure error].include?(kind) }
      result = Tests.new(total: cases.length, failed: failures.length,
        skipped: cases.count { |_, _, kind| kind == :skipped }, duration: cases.sum { |_, time, _| time },
        slowest: cases.sort_by { |_, time, _| -time }.first(top).map { |name, time, _| [name, time] }, failures: failures.first(8))
      ParseResult.new(value: result, warnings: warnings)
    end
  end

  module CoverageParser
    module_function

    def parse(path, base: nil)
      return ParseResult.new(value: nil, warnings: []) unless path && File.file?(path)
      warnings = []
      data = JSON.parse(File.read(path, encoding: "UTF-8"))
      lines = data.dig("result", "line") || data.dig("result", "lines") || data.dig("metrics", "lines") || data["lines"] || {}
      percent = lines["percent"] || lines["covered_percent"] || data["covered_percent"] || data["percent"]
      covered = lines["covered"] || data["covered"]
      total = lines["total"] || data["total"]
      percent = percent.to_f
      percent = covered.to_f * 100 / total if percent.zero? && covered && total && total.to_f.positive?
      ParseResult.new(value: CoverageData.new(percent: percent, covered: covered, total: total,
        delta: base.nil? ? nil : percent - base.to_f), warnings: warnings)
    rescue JSON::ParserError, Errno::ENOENT, TypeError, NoMethodError => error
      ParseResult.new(value: nil, warnings: ["#{path}: #{error.message}"])
    end
  end

  module Benchmarks
    module_function

    def parse(path)
      return ParseResult.new(value: [], warnings: []) unless path && File.file?(path)
      value = JSON.parse(File.read(path, encoding: "UTF-8"))
      values = value.is_a?(Array) ? value : value.fetch("benchmarks", value.fetch("results", []))
      values = values.map.with_index do |entry, index|
        entry = {"value" => entry} unless entry.is_a?(Hash)
        Bench.new(name: (entry["name"] || entry["label"] || "bench-#{index}"), value: entry["value"].to_f,
          unit: entry["unit"] || "", delta: entry["delta"])
      end
      ParseResult.new(value: values, warnings: [])
    rescue JSON::ParserError, Errno::ENOENT, TypeError, NoMethodError => error
      ParseResult.new(value: [], warnings: ["#{path}: #{error.message}"])
    end
  end

  module History
    MAX = 50
    module_function

    def load(path)
      return [] unless path && File.file?(path)
      values = JSON.parse(File.read(path, encoding: "UTF-8"))
      return [] unless values.is_a?(Array)
      values.filter_map do |entry|
        next unless entry.is_a?(Hash)
        HistoryPoint.new(commit: entry["commit"], coverage: entry["coverage"], tests: entry["tests"], at: entry["at"])
      end
    rescue JSON::ParserError, Errno::ENOENT, TypeError
      []
    end

    def append(path, point)
      values = load(path) + [point]
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(values.last(MAX).map(&:to_h)) + "\n")
      values.last(MAX)
    end
  end

  module Summary
    module_function

    def markdown(report, image: nil)
      lines = ["## Nashira: #{report.status.to_s.upcase}", ""]
      lines << "![CI report](#{image})" if image
      lines << "| Metric | Value |" << "| --- | --- |"
      if report.tests
        lines << "| Tests | #{report.tests.total} (#{report.tests.failed} failed, #{report.tests.skipped} skipped) |"
      end
      if report.coverage
        delta = report.coverage.delta ? format(" (%+.2f%%)", report.coverage.delta) : ""
        lines << "| Coverage | #{format("%.2f", report.coverage.percent)}%#{delta} |"
      end
      report.benchmarks.each { |bench| lines << "| #{bench.name} | #{bench.value} #{bench.unit} |" }
      if report.status != :fail && report.history.length > 1
        trend = report.history.last(20).filter_map(&:coverage).map { |value| format("%.2f", value) }.join(" → ")
        lines << "| Coverage trend | #{trend} |"
      end
      if report.tests&.slowest&.any?
        lines.concat(["", "### Slowest tests", *report.tests.slowest.map { |name, seconds| "- `#{name}` (#{format("%.3f", seconds)}s)" }])
      end
      if report.tests&.failures&.any?
        lines.concat(["", "### Failed tests", *report.tests.failures.map { |name| "- `#{name}`" }]) if report.status == :fail
      end
      lines.join("\n") + "\n"
    end
  end

  module View
    module_function

    def call(report, theme: Zaniah::Theme.dark)
      title = "[#{report.status.to_s.upcase}] #{report.repository || "CI report"}"
      status = report.status == :pass ? :success : :danger
      header = Zaniah::UI::Card.new(
        Zaniah::UI::Label.new(title, size: :xl),
        Zaniah::UI::Badge.new(report.status.to_s.upcase, variant: status)
      )
      metrics = Zaniah::Div.new.flex_row.gap(12).children([
        metric("Tests", report.tests && "#{report.tests.total} (#{report.tests.failed} failed)", theme),
        metric("Coverage", report.coverage && format("%.2f%%", report.coverage.percent), theme),
        *report.benchmarks.first(3).map { |bench| metric(bench.name, "#{bench.value} #{bench.unit}", theme) }
      ].compact)
      trend = if report.status != :fail && report.history.length > 1
        values = report.history.last(20).filter_map(&:coverage)
        Zaniah::UI::Card.new(Zaniah::UI::Label.new("Coverage trend", size: :md), Zaniah::UI::Sparkline.new(values, width: 640, height: 120)) unless values.empty?
      elsif report.tests&.failures&.any?
        Zaniah::UI::Card.new(Zaniah::UI::Label.new("Failed tests", size: :md),
          *report.tests.failures.first(8).map { |name| Zaniah::UI::Label.new(name, tone: :muted, size: :sm) })
      end
      slow = if report.tests&.slowest&.any?
        rows = report.tests.slowest.map { |name, seconds| {name: name, duration: format("%.3fs", seconds)} }
        Zaniah::UI::Table.new(rows, columns: [
          {key: :name, label: "Test", width: 560, sortable: false},
          {key: :duration, label: "Duration", width: 140, sortable: false}
        ], height: [rows.length * 32 + 40, 100].max, selection: :none)
      end
      root = Zaniah::Div.new.flex_col.p(48).gap(18).bg(theme.colors.background).child(header).child(metrics)
      root.child(trend) if trend
      root.child(Zaniah::UI::Card.new(Zaniah::UI::Label.new("Slowest tests", size: :md), slow)) if slow
      root
    end

    def metric(label, value, _theme)
      return unless value
      Zaniah::UI::Card.new(Zaniah::UI::Label.new(label, tone: :muted, size: :xs), Zaniah::UI::Label.new(value, size: :lg))
    end
  end

  class Renderer
    def initialize(theme: Zaniah::Theme.dark, width: 1200, height: 800)
      @theme, @width, @height = theme, width, height
      @font_db = Zaniah::TextSystem::FontDB.new(paths: [])
      @font = @font_db.find(family: theme.typography.font_sans)
      @text_system = Zaniah::TextSystem::Renderer.new(font: @font, font_db: @font_db)
    rescue StandardError
      @font_db = @font = @text_system = nil
    end

    def render(report)
      app = Zaniah::App.new
      window = app.open_window(backend: :headless, width: @width, height: @height)
      app.global(:theme, @theme)
      window.text_system = @text_system if @text_system
      window.draw { View.call(report, theme: @theme) }
      window.tick
      device = window.device
      Zaniah::PNG.encode(device.width.to_i, device.height.to_i, device.pixels)
    ensure
      window&.close
    end
  end

  module_function

  def theme(value)
    return value if value.respond_to?(:colors)
    return Auva.load(value) if defined?(Auva) && File.file?(value.to_s)
    return Auva.builtin(value) if defined?(Auva)
    Zaniah::Theme.public_send(value.to_s)
  rescue NoMethodError
    raise Error, "unknown theme: #{value}"
  end

  class CLI
    def self.run(argv, out: $stdout, err: $stderr)
      options = {junit: [], coverage: nil, bench: nil, history: nil, out: "card.png", summary: "summary.md", base: nil, now: Time.now.utc.iso8601, title: nil, theme: :dark, branch: nil, commit: nil, run_url: nil, fail_on: nil}
      OptionParser.new do |opts|
        opts.banner = "Usage: nashira build [options]"
        opts.on("--junit GLOB") { |v| options[:junit] << v }
        opts.on("--coverage PATH") { |v| options[:coverage] = v }
        opts.on("--bench PATH") { |v| options[:bench] = v }
        opts.on("--history PATH") { |v| options[:history] = v }
        opts.on("--base-coverage VALUE", Float) { |v| options[:base] = v }
        opts.on("--now TIME") { |v| options[:now] = v }
        opts.on("--out PATH") { |v| options[:out] = v }
        opts.on("--summary PATH") { |v| options[:summary] = v }
        opts.on("--title TITLE") { |v| options[:title] = v }
        opts.on("--theme NAME") { |v| options[:theme] = v }
        opts.on("--branch NAME") { |v| options[:branch] = v }
        opts.on("--commit SHA") { |v| options[:commit] = v }
        opts.on("--run-url URL") { |v| options[:run_url] = v }
        opts.on("--fail-on NAME") { |v| options[:fail_on] = v }
      end.parse!(argv.drop(argv.first == "build" ? 1 : 0))
      tests_result = JUnit.parse(options[:junit])
      coverage_result = CoverageParser.parse(options[:coverage], base: options[:base])
      benchmarks_result = Benchmarks.parse(options[:bench])
      tests = tests_result.value
      coverage = coverage_result.value
      benchmarks = benchmarks_result.value
      warnings = tests_result.warnings + coverage_result.warnings + benchmarks_result.warnings
      history = History.load(options[:history])
      point = options[:history] && HistoryPoint.new(commit: options[:commit], coverage: coverage&.percent,
        tests: tests&.total, at: options[:now])
      report = Report.build(tests: tests, coverage: coverage, benchmarks: benchmarks,
        history: point ? history + [point] : history,
        repository: options[:title], branch: options[:branch], commit: options[:commit], run_url: options[:run_url], finished_at: options[:now])
      FileUtils.mkdir_p(File.dirname(options[:out]))
      FileUtils.mkdir_p(File.dirname(options[:summary]))
      File.binwrite(options[:out], Renderer.new(theme: Nashira.theme(options[:theme])).render(report))
      File.write(options[:summary], Summary.markdown(report, image: options[:out]))
      History.append(options[:history], point) if point
      warnings.each { |warning| err.puts "nashira: warning: #{warning}" }
      (options[:fail_on] == "coverage-drop" && coverage&.delta.to_f.negative?) || (options[:fail_on] == "tests" && tests&.failed.to_i.positive?) ? 1 : 0
    rescue OptionParser::ParseError, KeyError, Error => error
      err.puts "nashira: #{error.message}"
      1
    end
  end
end
