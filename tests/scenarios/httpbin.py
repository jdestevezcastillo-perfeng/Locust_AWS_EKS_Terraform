"""
HTTPBin API Load Test Scenario
Tests various HTTP methods, status codes, and response types
Target: https://httpbin.org
"""

from locust import HttpUser, task, between
import random
import base64


class HTTPBinUser(HttpUser):
    """
    User behavior for HTTPBin API testing
    Tests various HTTP operations and edge cases
    """
    wait_time = between(0.5, 2)

    @task(5)
    def test_get_request(self):
        """
        GET /get - Test basic GET request with query parameters
        """
        params = {
            "param1": random.choice(["value1", "value2", "value3"]),
            "param2": random.randint(1, 100)
        }
        with self.client.get(
            "/get",
            params=params,
            catch_response=True,
            name="/get"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                data = response.json()
                if "args" not in data or data["args"] != {k: str(v) for k, v in params.items()}:
                    response.failure("Query parameters not echoed correctly")
                else:
                    response.success()

    @task(3)
    def test_post_json(self):
        """
        POST /post - Test POST request with JSON payload
        """
        payload = {
            "name": f"user_{random.randint(1000, 9999)}",
            "email": f"test{random.randint(1, 1000)}@example.com",
            "age": random.randint(18, 80)
        }
        with self.client.post(
            "/post",
            json=payload,
            catch_response=True,
            name="/post [JSON]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                response.success()

    @task(2)
    def test_post_form(self):
        """
        POST /post - Test POST request with form data
        """
        form_data = {
            "username": f"user_{random.randint(1, 1000)}",
            "password": "test123"
        }
        with self.client.post(
            "/post",
            data=form_data,
            catch_response=True,
            name="/post [FORM]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                response.success()

    @task(2)
    def test_headers(self):
        """
        GET /headers - Test custom headers
        """
        headers = {
            "X-Custom-Header": "LocustLoadTest",
            "X-Request-ID": f"req-{random.randint(10000, 99999)}"
        }
        with self.client.get(
            "/headers",
            headers=headers,
            catch_response=True,
            name="/headers"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                response.success()

    @task(1)
    def test_basic_auth(self):
        """
        GET /basic-auth/{user}/{passwd} - Test basic authentication
        """
        username = "testuser"
        password = "testpass"
        auth_string = f"{username}:{password}"
        encoded = base64.b64encode(auth_string.encode()).decode()

        with self.client.get(
            f"/basic-auth/{username}/{password}",
            headers={"Authorization": f"Basic {encoded}"},
            catch_response=True,
            name="/basic-auth/[user]/[pass]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                response.success()

    @task(1)
    def test_status_codes(self):
        """
        GET /status/{code} - Test various HTTP status codes
        """
        status_code = random.choice([200, 201, 204, 400, 404, 500, 503])
        with self.client.get(
            f"/status/{status_code}",
            catch_response=True,
            name="/status/[code]"
        ) as response:
            if response.status_code != status_code:
                response.failure(
                    f"Expected status {status_code}, got {response.status_code}"
                )
            else:
                # Mark as success even for error codes (we're testing the endpoint)
                response.success()

    @task(1)
    def test_delay(self):
        """
        GET /delay/{n} - Test endpoint with artificial delay
        """
        delay = random.choice([1, 2, 3])
        with self.client.get(
            f"/delay/{delay}",
            catch_response=True,
            name="/delay/[n]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            elif response.elapsed.total_seconds() < delay:
                response.failure(f"Delay was less than {delay} seconds")
            else:
                response.success()

    @task(1)
    def test_response_formats(self):
        """
        GET /json, /xml, /html - Test different response formats
        """
        endpoint = random.choice(["/json", "/xml", "/html"])
        with self.client.get(
            endpoint,
            catch_response=True,
            name="/[format]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                response.success()

    @task(1)
    def test_gzip(self):
        """
        GET /gzip - Test gzip compression
        """
        with self.client.get(
            "/gzip",
            catch_response=True,
            name="/gzip"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                data = response.json()
                if not data.get("gzipped", False):
                    response.failure("Response was not gzipped")
                else:
                    response.success()
