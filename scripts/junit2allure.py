#!/usr/bin/env python3
"""Convert gtest JUnit XML results to Allure3 JSON format.

Usage:
    python3 junit2allure.py <input_dir> <output_dir>

Reads *.gtest.xml files from input_dir and writes Allure3 result JSON files
({uuid}-result.json) to output_dir.
"""

import json
import os
import sys
import uuid
from datetime import datetime, timezone

from junitparser import JUnitXml


def parse_timestamp(ts_str):
    """Parse ISO timestamp string to epoch milliseconds."""
    if not ts_str:
        return 0
    try:
        # Handle formats like "2026-05-09T00:44:24.754"
        dt = datetime.fromisoformat(ts_str)
        return int(dt.timestamp() * 1000)
    except (ValueError, TypeError):
        return 0


def convert_xml_to_allure(xml_path, output_dir):
    """Convert a single JUnit XML file to Allure result JSON files."""
    try:
        xml = JUnitXml.fromfile(xml_path)
    except Exception as e:
        print(f"  Warning: Failed to parse {xml_path}: {e}", file=sys.stderr)
        return 0

    count = 0
    suite_name = os.path.splitext(os.path.basename(xml_path))[0]

    for suite in xml:
        suite_name_full = suite.name or suite_name

        for case in suite:
            start_ms = parse_timestamp(case.timestamp) if hasattr(case, 'timestamp') and case.timestamp else 0
            duration_ms = int((case.time or 0) * 1000)
            stop_ms = start_ms + duration_ms if start_ms > 0 else 0

            result = {
                "uuid": str(uuid.uuid4()),
                "name": case.name or "unknown",
                "fullName": f"{suite_name_full}.{case.name}" if case.name else suite_name_full,
                "historyId": f"{suite_name_full}.{case.name}" if case.name else suite_name_full,
                "start": start_ms,
                "stop": stop_ms,
                "stage": "finished",
                "status": "passed",
                "labels": [
                    {"name": "suite", "value": suite_name_full},
                    {"name": "package", "value": suite_name_full},
                    {"name": "testClass", "value": suite_name_full},
                    {"name": "testMethod", "value": case.name or "unknown"},
                    {"name": "resultFormat", "value": "allure2"},
                ],
            }

            # Handle test status
            if case.result:
                for r in case.result:
                    rtype = type(r).__name__
                    if rtype == "Failure":
                        result["status"] = "failed"
                        result["statusDetails"] = {
                            "message": r.message or "Test failed",
                            "trace": r.text or "",
                        }
                    elif rtype == "Error":
                        result["status"] = "broken"
                        result["statusDetails"] = {
                            "message": r.message or "Test error",
                            "trace": r.text or "",
                        }
                    elif rtype == "Skipped":
                        result["status"] = "skipped"
                        result["statusDetails"] = {
                            "message": r.message or "Test skipped",
                        }

            # Write result file
            out_path = os.path.join(output_dir, f"{result['uuid']}-result.json")
            with open(out_path, "w") as f:
                json.dump(result, f, indent=2)
            count += 1

    return count


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input_dir> <output_dir>", file=sys.stderr)
        sys.exit(1)

    input_dir = sys.argv[1]
    output_dir = sys.argv[2]

    os.makedirs(output_dir, exist_ok=True)

    total = 0
    for fname in sorted(os.listdir(input_dir)):
        if fname.endswith(".gtest.xml") or fname.endswith(".xunit.xml"):
            xml_path = os.path.join(input_dir, fname)
            count = convert_xml_to_allure(xml_path, output_dir)
            print(f"  {fname}: {count} test cases")
            total += count

    print(f"\nTotal: {total} test cases converted")


if __name__ == "__main__":
    main()
