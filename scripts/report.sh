#!/bin/bash
# Allure3 test report script for ROS2 Jazzy
# Usage:
#   ./report.sh                  # Run all tests, collect results, generate and open report
#   ./report.sh <package>        # Run tests for specific package
#   ./report.sh --collect-only   # Only collect existing results and generate report (skip testing)
#   ./report.sh --open-only      # Only open existing report
#   ./report.sh --generate-only  # Only generate report from existing allure-results (skip testing + collecting)
#   ./report.sh --publish        # Generate single-file report and publish to GitHub Pages
#   ./report.sh --publish-only   # Only publish existing allure-results to GitHub Pages (skip testing + collecting + generate)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALLURE_RESULTS_DIR="${SCRIPT_DIR}/allure-results"
ALLURE_REPORT_DIR="${SCRIPT_DIR}/allure-report"
PUBLISH_DIR="${SCRIPT_DIR}/allure3-public"
REPORT_NAME="ROS2 Jazzy Test Report"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

collect_results() {
  info "Collecting test results..."
  rm -rf "${ALLURE_RESULTS_DIR:?}"/*
  mkdir -p "${ALLURE_RESULTS_DIR}"

  # Find all gtest/xunit XML result directories
  local xml_dirs=()
  for dir in "${SCRIPT_DIR}"/build/*/test_results/*/; do
    if [ -d "$dir" ]; then
      xml_dirs+=("$dir")
    fi
  done

  if [ ${#xml_dirs[@]} -eq 0 ]; then
    warn "No test result directories found in build/*/test_results/"
    warn "Did you run 'colcon test' first?"
    return 1
  fi

  # Convert JUnit XML to Allure JSON format
  local total=0
  for dir in "${xml_dirs[@]}"; do
    local xml_count
    xml_count=$(find "$dir" -maxdepth 1 \( -name "*.gtest.xml" -o -name "*.xunit.xml" \) 2>/dev/null | wc -l)
    if [ "$xml_count" -gt 0 ]; then
      info "Converting: $dir ($xml_count files)"
      python3 "${SCRIPT_DIR}/junit2allure.py" "$dir" "${ALLURE_RESULTS_DIR}"
      total=$((total + xml_count))
    fi
  done

  if [ $total -eq 0 ]; then
    warn "No test result XML files found"
    return 1
  fi

  info "Converted ${total} XML files to Allure JSON format"
}

generate_report() {
  info "Generating Allure report..."
  rm -rf "${ALLURE_REPORT_DIR:?}"/*
  allure awesome "${ALLURE_RESULTS_DIR}" -o "${ALLURE_REPORT_DIR}" --report-name "${REPORT_NAME}"
  info "Report generated at ${ALLURE_REPORT_DIR}"
}

publish_report() {
  if [ ! -d "${PUBLISH_DIR}/.git" ]; then
    error "Publish directory ${PUBLISH_DIR} is not a git repository"
    error "Clone the GitHub Pages repo first"
    return 1
  fi

  # Check allure-results has content
  local result_count
  result_count=$(find "${ALLURE_RESULTS_DIR}" -name "*-result.json" 2>/dev/null | wc -l)
  if [ "$result_count" -eq 0 ]; then
    error "No Allure result files found in ${ALLURE_RESULTS_DIR}"
    error "Run with --collect-only or --publish first"
    return 1
  fi

  info "Generating single-file report for publishing..."
  local tmp_dir
  tmp_dir=$(mktemp -d)
  allure awesome "${ALLURE_RESULTS_DIR}" -o "${tmp_dir}" --single-file --report-name "${REPORT_NAME}"

  info "Copying report to publish directory..."
  cp "${tmp_dir}/index.html" "${PUBLISH_DIR}/index.html"
  cp "${tmp_dir}/summary.json" "${PUBLISH_DIR}/summary.json"
  rm -rf "${tmp_dir}"

  info "Committing and pushing to GitHub Pages..."
  git -C "${PUBLISH_DIR}" add index.html summary.json
  git -C "${PUBLISH_DIR}" commit -m "Update ${REPORT_NAME} - $(date '+%Y-%m-%d %H:%M')" || \
    warn "No changes to commit"
  git -C "${PUBLISH_DIR}" pull --rebase origin main
  git -C "${PUBLISH_DIR}" push origin main

  info "Report published to GitHub Pages!"
}

open_report() {
  info "Opening Allure report..."
  allure open --cwd "${SCRIPT_DIR}" ./allure-report
}

run_tests() {
  local package="${1:-}"

  info "Running tests..."
  source "${SCRIPT_DIR}/install/setup.bash" 2>/dev/null || true

  if [ -n "$package" ]; then
    colcon test --packages-select "$package" --allow-overriding "$package"
  else
    colcon test
  fi

  info "Tests completed"
}

# Parse arguments
MODE="full"
PACKAGE=""

for arg in "$@"; do
  case "$arg" in
    --collect-only)
      MODE="collect"
      ;;
    --open-only)
      MODE="open"
      ;;
    --generate-only)
      MODE="generate"
      ;;
    --publish)
      MODE="publish"
      ;;
    --publish-only)
      MODE="publish_only"
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS] [PACKAGE]"
      echo ""
      echo "Options:"
      echo "  --collect-only    Only collect existing results and generate report"
      echo "  --open-only       Only open existing report"
      echo "  --generate-only   Only generate report from existing allure-results"
      echo "  --publish         Run tests, collect, generate single-file report and publish to GitHub Pages"
      echo "  --publish-only    Only publish existing allure-results to GitHub Pages (skip testing)"
      echo "  --help            Show this help message"
      echo ""
      echo "Examples:"
      echo "  $0                     # Full: test + collect + report + open"
      echo "  $0 rclcpp              # Test only rclcpp package"
      echo "  $0 --collect-only      # Collect existing results + generate + open"
      echo "  $0 --publish           # Test + collect + publish to GitHub Pages"
      echo "  $0 --publish-only      # Publish existing allure-results to GitHub Pages"
      echo "  $0 --open-only         # Just open the existing report"
      exit 0
      ;;
    -*)
      error "Unknown option: $arg"
      exit 1
      ;;
    *)
      PACKAGE="$arg"
      ;;
  esac
done

case "$MODE" in
  full)
    run_tests "$PACKAGE"
    collect_results
    generate_report
    open_report
    ;;
  collect)
    collect_results
    generate_report
    open_report
    ;;
  generate)
    generate_report
    open_report
    ;;
  publish)
    run_tests "$PACKAGE"
    collect_results
    publish_report
    ;;
  publish_only)
    publish_report
    ;;
  open)
    open_report
    ;;
esac
