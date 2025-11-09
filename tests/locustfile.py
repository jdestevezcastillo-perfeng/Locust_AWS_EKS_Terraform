"""
Locust Load Test File with Multiple Scenario Support
Dynamically loads test scenarios based on LOCUST_SCENARIO environment variable
"""

import os
import sys
from locust import HttpUser, task, between
import random

# Determine which scenario to load from environment variable
SCENARIO = os.getenv("LOCUST_SCENARIO", "jsonplaceholder")

print(f"Loading test scenario: {SCENARIO}")

if SCENARIO == "jsonplaceholder":
    print("Scenario: JSONPlaceholder API (https://jsonplaceholder.typicode.com)")
    print("Description: Tests typical REST API operations (GET, POST, PUT, DELETE)")

    class User(HttpUser):
        """
        User behavior for JSONPlaceholder API testing
        Simulates a typical user browsing posts, comments, and creating content
        """
        wait_time = between(1, 3)

        def on_start(self):
            self.user_id = random.randint(1, 10)
            self.post_id = random.randint(1, 100)

        @task(5)
        def get_posts_list(self):
            with self.client.get("/posts", catch_response=True, name="/posts") as response:
                if response.status_code != 200:
                    response.failure(f"Expected status 200, got {response.status_code}")
                elif not response.json():
                    response.failure("Response is empty")
                elif len(response.json()) < 100:
                    response.failure(f"Expected 100 posts, got {len(response.json())}")
                else:
                    response.success()

        @task(3)
        def get_single_post(self):
            post_id = random.randint(1, 100)
            with self.client.get(
                f"/posts/{post_id}",
                catch_response=True,
                name="/posts/[id]"
            ) as response:
                if response.status_code != 200:
                    response.failure(f"Expected status 200, got {response.status_code}")
                else:
                    data = response.json()
                    if "userId" not in data or "title" not in data or "body" not in data:
                        response.failure("Missing required fields in response")
                    else:
                        response.success()

        @task(2)
        def get_post_comments(self):
            post_id = random.randint(1, 100)
            with self.client.get(
                f"/posts/{post_id}/comments",
                catch_response=True,
                name="/posts/[id]/comments"
            ) as response:
                if response.status_code != 200:
                    response.failure(f"Expected status 200, got {response.status_code}")
                else:
                    comments = response.json()
                    if not isinstance(comments, list):
                        response.failure("Expected array of comments")
                    else:
                        response.success()

        @task(1)
        def create_post(self):
            payload = {
                "title": f"Load Test Post {random.randint(1000, 9999)}",
                "body": "This is a test post created by Locust load testing framework",
                "userId": self.user_id
            }
            with self.client.post(
                "/posts",
                json=payload,
                catch_response=True,
                name="/posts [POST]"
            ) as response:
                if response.status_code not in [200, 201]:
                    response.failure(f"Expected status 200/201, got {response.status_code}")
                else:
                    data = response.json()
                    if "id" not in data:
                        response.failure("Created post missing ID")
                    else:
                        response.success()

        @task(1)
        def update_post(self):
            post_id = random.randint(1, 100)
            payload = {
                "id": post_id,
                "title": f"Updated Post {post_id}",
                "body": "This post has been updated by Locust",
                "userId": self.user_id
            }
            with self.client.put(
                f"/posts/{post_id}",
                json=payload,
                catch_response=True,
                name="/posts/[id] [PUT]"
            ) as response:
                if response.status_code != 200:
                    response.failure(f"Expected status 200, got {response.status_code}")
                else:
                    response.success()

        @task(1)
        def get_users(self):
            with self.client.get("/users", catch_response=True, name="/users") as response:
                if response.status_code != 200:
                    response.failure(f"Expected status 200, got {response.status_code}")
                else:
                    users = response.json()
                    if not isinstance(users, list) or len(users) < 10:
                        response.failure("Expected at least 10 users")
                    else:
                        response.success()

else:
    print(f"ERROR: Unknown scenario '{SCENARIO}'", file=sys.stderr)
    print("Valid scenarios: jsonplaceholder (default), httpbin, custom", file=sys.stderr)
    sys.exit(1)

print(f"Successfully loaded scenario: {SCENARIO}")
print(f"User class: {User.__name__}")
