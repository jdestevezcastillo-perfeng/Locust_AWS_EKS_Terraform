"""
JSONPlaceholder API Load Test Scenario
Simulates typical REST API operations: GET, POST, PUT, DELETE
Target: https://jsonplaceholder.typicode.com
"""

from locust import HttpUser, task, between
import random


class JSONPlaceholderUser(HttpUser):
    """
    User behavior for JSONPlaceholder API testing
    Simulates a typical user browsing posts, comments, and creating content
    """
    wait_time = between(1, 3)  # Random wait between 1-3 seconds

    def on_start(self):
        """Called when a user starts (before any task)"""
        self.user_id = random.randint(1, 10)
        self.post_id = random.randint(1, 100)

    @task(5)
    def get_posts_list(self):
        """
        GET /posts - Fetch list of all posts
        Most common operation (weight: 5)
        """
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
        """
        GET /posts/{id} - Fetch single post details
        Common operation (weight: 3)
        """
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
        """
        GET /posts/{id}/comments - Fetch comments for a post
        Moderate frequency (weight: 2)
        """
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
        """
        POST /posts - Create new post
        Simulate write operations (weight: 1)
        """
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
        """
        PUT /posts/{id} - Update existing post
        Simulate update operations (weight: 1)
        """
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
        """
        GET /users - Fetch list of users
        Occasional operation (weight: 1)
        """
        with self.client.get("/users", catch_response=True, name="/users") as response:
            if response.status_code != 200:
                response.failure(f"Expected status 200, got {response.status_code}")
            else:
                users = response.json()
                if not isinstance(users, list) or len(users) < 10:
                    response.failure("Expected at least 10 users")
                else:
                    response.success()
