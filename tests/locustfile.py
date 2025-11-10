"""
Locust Load Test File with Multiple Scenario Support
Dynamically loads test scenarios based on LOCUST_SCENARIO environment variable
"""

import os
import sys
import time
import threading
from importlib import import_module

from locust import HttpUser, events
from prometheus_client import start_http_server, Counter, Histogram, Gauge

# Create Prometheus metrics
# Status metric: 0=stop, 1=hatching, 2=running
locust_running = Gauge('locust_running', 'Locust status: 0=stop, 1=hatching, 2=running')

# User and worker metrics
locust_users = Gauge('locust_users', 'Current number of users')
locust_workers_count = Gauge('locust_workers_count', 'Number of connected worker nodes')

# Request counters (renamed to match Locust exporter)
locust_requests_num_requests = Counter(
    'locust_requests_num_requests',
    'Total HTTP requests',
    ['method', 'name']
)
locust_requests_num_failures = Counter(
    'locust_requests_num_failures',
    'Total HTTP request failures',
    ['method', 'name']
)

# Request timing metrics
locust_requests_min_response_time = Gauge(
    'locust_requests_min_response_time',
    'Minimum response time (ms)',
    ['method', 'name']
)
locust_requests_max_response_time = Gauge(
    'locust_requests_max_response_time',
    'Maximum response time (ms)',
    ['method', 'name']
)
locust_requests_avg_response_time = Gauge(
    'locust_requests_avg_response_time',
    'Average response time (ms)',
    ['method', 'name']
)
locust_requests_median_response_time = Gauge(
    'locust_requests_median_response_time',
    'Median response time (ms)',
    ['method', 'name']
)

# Response time percentiles
locust_requests_current_response_time_percentile_50 = Gauge(
    'locust_requests_current_response_time_percentile_50',
    'P50 response time (ms)',
    ['method', 'name']
)
locust_requests_current_response_time_percentile_95 = Gauge(
    'locust_requests_current_response_time_percentile_95',
    'P95 response time (ms)',
    ['method', 'name']
)

# Content length and request rate metrics
locust_requests_avg_content_length = Gauge(
    'locust_requests_avg_content_length',
    'Average response content length (bytes)',
    ['method', 'name']
)
locust_requests_current_rps = Gauge(
    'locust_requests_current_rps',
    'Current requests per second',
    ['method', 'name']
)
locust_requests_current_fail_per_sec = Gauge(
    'locust_requests_current_fail_per_sec',
    'Current failures per second',
    ['method', 'name']
)
locust_requests_fail_ratio = Gauge(
    'locust_requests_fail_ratio',
    'Failure ratio (0-1)',
    ['method', 'name']
)

# Error tracking
locust_errors = Counter(
    'locust_errors',
    'Total errors by type',
    ['method', 'name', 'error']
)

# Start Prometheus metrics HTTP server on port 8090
# This exposes metrics at http://localhost:8090/metrics
try:
    start_http_server(8090)
except RuntimeError:
    # Port might already be in use (especially on master)
    pass

# Store for tracking stats in distributed mode
_last_stats = {}

def _calculate_percentile(response_times, percentile):
    """Calculate percentile from response times list"""
    if not response_times:
        return 0
    sorted_times = sorted(response_times)
    idx = int(len(sorted_times) * percentile / 100.0)
    return sorted_times[min(idx, len(sorted_times) - 1)]

def _update_prometheus_metrics(environment):
    """
    Poll Locust's Stats object and update Prometheus metrics.
    Syncs with dashboard expectations from Grafana.
    """
    try:
        stats = environment.stats
        runner = environment.runner

        # Update status: 0=stop, 1=hatching, 2=running
        if hasattr(runner, 'state'):
            state_val = runner.state
            # state can be a string or an enum-like object
            if isinstance(state_val, str):
                state_str = state_val
            else:
                state_str = state_val.name if hasattr(state_val, 'name') else str(state_val)

            if state_str == 'running':
                locust_running.set(2)
            elif state_str == 'hatching':
                locust_running.set(1)
            else:
                locust_running.set(0)
        else:
            locust_running.set(0)

        # Update user count
        if hasattr(runner, 'user_count'):
            locust_users.set(runner.user_count)
        elif hasattr(runner, 'users_dispatcher') and hasattr(runner.users_dispatcher, 'user_count'):
            locust_users.set(runner.users_dispatcher.user_count)

        # Update worker count (for distributed mode)
        if hasattr(runner, 'workers'):
            try:
                locust_workers_count.set(len([w for w in runner.workers.values() if w]))
            except:
                pass
        elif hasattr(runner, 'clients'):
            try:
                locust_workers_count.set(len(runner.clients) if hasattr(runner.clients, '__len__') else 0)
            except:
                pass

        # Process each request type from stats
        for stat_entry in stats.entries.values():
            method = stat_entry.method  # e.g., "GET", "POST"
            name = stat_entry.name      # e.g., "/posts"

            # Get current counts
            num_requests = stat_entry.num_requests
            num_failures = stat_entry.num_failures
            success_count = num_requests - num_failures

            # Create unique key for tracking deltas
            key = f"{method}_{name}"
            if key not in _last_stats:
                _last_stats[key] = {
                    'requests': 0,
                    'failures': 0,
                    'last_request_time': time.time()
                }

            last = _last_stats[key]
            current_time = time.time()
            time_delta = current_time - last['last_request_time']

            # Calculate deltas
            request_delta = num_requests - last['requests']
            failure_delta = num_failures - last['failures']

            # Update request counters
            if request_delta > 0:
                locust_requests_num_requests.labels(method=method, name=name).inc(request_delta)
            if failure_delta > 0:
                locust_requests_num_failures.labels(method=method, name=name).inc(failure_delta)

            # Calculate and update rates (RPS, failures per second)
            if time_delta > 0:
                rps = request_delta / time_delta
                fail_per_sec = failure_delta / time_delta
                locust_requests_current_rps.labels(method=method, name=name).set(max(0, rps))
                locust_requests_current_fail_per_sec.labels(method=method, name=name).set(max(0, fail_per_sec))

            # Calculate failure ratio
            if num_requests > 0:
                fail_ratio = num_failures / num_requests
                locust_requests_fail_ratio.labels(method=method, name=name).set(fail_ratio)
            else:
                locust_requests_fail_ratio.labels(method=method, name=name).set(0)

            # Update response time metrics
            if hasattr(stat_entry, 'response_times') and stat_entry.response_times:
                response_times = list(stat_entry.response_times.values())
                if response_times:
                    min_rt = min(response_times) if response_times else 0
                    max_rt = max(response_times) if response_times else 0
                    avg_rt = sum(response_times) / len(response_times) if response_times else 0

                    # Calculate median and percentiles
                    sorted_times = sorted(response_times)
                    median_idx = len(sorted_times) // 2
                    median_rt = sorted_times[median_idx] if sorted_times else 0
                    p50 = _calculate_percentile(response_times, 50)
                    p95 = _calculate_percentile(response_times, 95)

                    locust_requests_min_response_time.labels(method=method, name=name).set(min_rt)
                    locust_requests_max_response_time.labels(method=method, name=name).set(max_rt)
                    locust_requests_avg_response_time.labels(method=method, name=name).set(avg_rt)
                    locust_requests_median_response_time.labels(method=method, name=name).set(median_rt)
                    locust_requests_current_response_time_percentile_50.labels(method=method, name=name).set(p50)
                    locust_requests_current_response_time_percentile_95.labels(method=method, name=name).set(p95)

            # Update content length if available
            if hasattr(stat_entry, 'content_length') and hasattr(stat_entry.content_length, '__iter__'):
                content_lengths = list(stat_entry.content_length.values())
                if content_lengths:
                    avg_content_length = sum(content_lengths) / len(content_lengths)
                    locust_requests_avg_content_length.labels(method=method, name=name).set(avg_content_length)

            # Track errors by type
            if hasattr(stat_entry, 'errors') and stat_entry.errors:
                for error_msg, count in stat_entry.errors.items():
                    locust_errors.labels(method=method, name=name, error=str(error_msg)[:100]).inc(count)

            # Update tracking
            _last_stats[key]['requests'] = num_requests
            _last_stats[key]['failures'] = num_failures
            _last_stats[key]['last_request_time'] = current_time

    except Exception as e:
        print(f"Error updating Prometheus metrics: {e}", file=sys.stderr)

def _stats_poller(environment):
    """Background thread that periodically updates metrics from Stats object"""
    while True:
        try:
            time.sleep(1)  # Poll every second
            _update_prometheus_metrics(environment)
        except Exception as e:
            print(f"Stats poller error: {e}", file=sys.stderr)
            time.sleep(1)

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Start the stats polling thread when test starts"""
    if environment.runner:
        # Only run stats poller on master
        if isinstance(environment.runner, type(environment.runner)) and \
           environment.runner.__class__.__name__ in ['MasterRunner', 'LocalRunner']:
            print("Starting Prometheus metrics polling thread...")
            poller_thread = threading.Thread(target=_stats_poller, args=(environment,), daemon=True)
            poller_thread.start()

@events.spawning_complete.add_listener
def on_spawning_complete(user_count, **kwargs):
    """Track active users"""
    locust_users.set(user_count)

@events.quitting.add_listener
def on_quitting(**kwargs):
    """Reset user count when test ends"""
    locust_users.set(0)

# Determine which scenario to load from environment variable
SCENARIO = os.getenv("LOCUST_SCENARIO", "jsonplaceholder").lower()

SCENARIO_MAP = {
    "jsonplaceholder": "tests.scenarios.jsonplaceholder:JSONPlaceholderUser",
    "httpbin": "tests.scenarios.httpbin:HTTPBinUser",
    "custom": "tests.scenarios.custom:CustomUser",
}


def load_user_class(scenario_key: str) -> HttpUser:
    """Resolve the scenario key into a Locust HttpUser subclass."""
    target = SCENARIO_MAP.get(scenario_key)
    if not target:
        raise KeyError(f"Scenario '{scenario_key}' not found")

    module_name, class_name = target.split(":")
    module = import_module(module_name)
    user_cls = getattr(module, class_name, None)

    if user_cls is None:
        raise AttributeError(f"Class '{class_name}' missing in module {module_name}")

    if not issubclass(user_cls, HttpUser):
        raise TypeError(f"{class_name} is not a Locust HttpUser")

    return user_cls


print(f"Loading test scenario: {SCENARIO}")

try:
    User = load_user_class(SCENARIO)
except Exception as exc:
    print(f"ERROR: {exc}", file=sys.stderr)
    print(f"Valid scenarios: {', '.join(SCENARIO_MAP.keys())}", file=sys.stderr)
    sys.exit(1)

print(f"Successfully loaded scenario: {SCENARIO}")
print(f"User class: {User.__name__}")
