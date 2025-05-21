# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test Commands
- Install dependencies: `bundle install`
- Run all tests: `rake` (runs both test suite and RuboCop)
- Run only RSpec tests: `rake spec`
- Run only RuboCop: `rake rubocop`
- Run a single test: `bundle exec rspec path/to/spec_file:line_number`
- Install gem locally: `rake install`

## Code Style Guidelines
- Ruby version >= 3.0.0
- RuboCop enforces style guidelines
- Line length max: 200 characters
- Method length max: 100 lines
- Class length max: 200 lines
- No style enforcement for string literals (single/double quotes)
- Documentation not strictly required
- Snake case for methods/variables, CamelCase for classes/modules
- Custom exceptions defined in exceptions.rb
- Exception handling pattern: rescue specific exceptions, log error, exit with code 1
- Tests use RSpec with documentation formatter