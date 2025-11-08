"""
Custom API Load Test Scenario Template
Customize this file for your specific API endpoints
"""

from locust import HttpUser, task, between
import random


class CustomUser(HttpUser):
    """
    Template for custom API load testing
    Modify the tasks below to match your API endpoints
    """
    wait_time = between(1, 3)

    def on_start(self):
        """
        Called when a user starts
        Use this for login, authentication, or initialization
        """
        # Example: Login and store auth token
        # response = self.client.post("/api/login", json={"username": "test", "password": "test"})
        # self.auth_token = response.json().get("token")
        pass

    @task(5)
    def example_get_request(self):
        """
        Example GET request - customize for your API
        """
        # Example: Add authentication header
        # headers = {"Authorization": f"Bearer {self.auth_token}"}

        with self.client.get(
            "/api/endpoint",  # Replace with your endpoint
            # headers=headers,
            catch_response=True,
            name="/api/endpoint [GET]"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                # Add custom validations
                data = response.json()
                if "expected_field" in data:
                    response.success()
                else:
                    response.failure("Missing expected field in response")

    @task(2)
    def example_post_request(self):
        """
        Example POST request - customize for your API
        """
        payload = {
            "key": "value",
            "number": random.randint(1, 100)
        }

        with self.client.post(
            "/api/endpoint",  # Replace with your endpoint
            json=payload,
            catch_response=True,
            name="/api/endpoint [POST]"
        ) as response:
            if response.status_code not in [200, 201]:
                response.failure(f"Expected status 200/201, got {response.status_code}")
            else:
                response.success()

    @task(1)
    def example_complex_workflow(self):
        """
        Example multi-step workflow
        """
        # Step 1: Create resource
        create_response = self.client.post(
            "/api/resources",
            json={"name": f"resource_{random.randint(1000, 9999)}"}
        )

        if create_response.status_code == 201:
            resource_id = create_response.json().get("id")

            # Step 2: Fetch created resource
            self.client.get(f"/api/resources/{resource_id}", name="/api/resources/[id]")

            # Step 3: Update resource
            self.client.put(
                f"/api/resources/{resource_id}",
                json={"name": "updated_name"},
                name="/api/resources/[id] [PUT]"
            )

            # Step 4: Delete resource
            self.client.delete(
                f"/api/resources/{resource_id}",
                name="/api/resources/[id] [DELETE]"
            )

    def on_stop(self):
        """
        Called when a user stops
        Use this for cleanup, logout, etc.
        """
        # Example: Logout
        # self.client.post("/api/logout", headers={"Authorization": f"Bearer {self.auth_token}"})
        pass
