"""
Locust Load Test File with Multiple Scenario Support
Dynamically loads test scenarios based on LOCUST_SCENARIO environment variable
"""

import os
import sys

# Determine which scenario to load from environment variable
SCENARIO = os.getenv("LOCUST_SCENARIO", "jsonplaceholder")

print(f"Loading test scenario: {SCENARIO}")

try:
    if SCENARIO == "jsonplaceholder":
        from locust.scenarios.jsonplaceholder import JSONPlaceholderUser as TestUser
        print("Scenario: JSONPlaceholder API (https://jsonplaceholder.typicode.com)")
        print("Description: Tests typical REST API operations (GET, POST, PUT, DELETE)")

    elif SCENARIO == "httpbin":
        from locust.scenarios.httpbin import HTTPBinUser as TestUser
        print("Scenario: HTTPBin API (https://httpbin.org)")
        print("Description: Tests various HTTP methods, headers, auth, and status codes")

    elif SCENARIO == "custom":
        from locust.scenarios.custom import CustomUser as TestUser
        print("Scenario: Custom API")
        print("Description: Template for testing custom endpoints")

    else:
        print(f"ERROR: Unknown scenario '{SCENARIO}'", file=sys.stderr)
        print("Valid scenarios: jsonplaceholder, httpbin, custom", file=sys.stderr)
        sys.exit(1)

except ImportError as e:
    print(f"ERROR: Failed to import scenario '{SCENARIO}': {e}", file=sys.stderr)
    sys.exit(1)

# Export the selected user class for Locust to discover
User = TestUser

# Print loaded scenario info
print(f"Successfully loaded scenario: {SCENARIO}")
print(f"User class: {User.__name__}")
