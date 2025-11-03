#!/usr/bin/env python3
"""
Create Pub/Sub topics and subscriptions for local testing with the emulator.

Usage:
    export PUBSUB_EMULATOR_HOST="localhost:8085"
    export PUBSUB_PROJECT_ID="local-dev-project"
    python3 setup/create_topics.py
"""

import os
from google.cloud import pubsub_v1

def create_topic_and_subscription():
    """Create the payments topic and subscription in the Pub/Sub emulator."""

    # Check environment variables
    emulator_host = os.getenv("PUBSUB_EMULATOR_HOST")
    project_id = os.getenv("PUBSUB_PROJECT_ID", "local-dev-project")

    if not emulator_host:
        print("ERROR: PUBSUB_EMULATOR_HOST environment variable not set")
        print("Please set it to 'localhost:8085' for local testing")
        return False

    print(f"Using Pub/Sub emulator at: {emulator_host}")
    print(f"Project ID: {project_id}")

    # Create publisher client
    publisher = pubsub_v1.PublisherClient()

    # Topic and subscription details
    topic_id = "payments"
    subscription_id = "payments-sub"
    topic_path = publisher.topic_path(project_id, topic_id)

    # Create topic
    try:
        topic = publisher.create_topic(request={"name": topic_path})
        print(f"✓ Created topic: {topic.name}")
    except Exception as e:
        if "ALREADY_EXISTS" in str(e):
            print(f"✓ Topic already exists: {topic_path}")
        else:
            print(f"✗ Failed to create topic: {e}")
            return False

    # Create subscription
    subscriber = pubsub_v1.SubscriberClient()
    subscription_path = subscriber.subscription_path(project_id, subscription_id)

    try:
        subscription = subscriber.create_subscription(
            request={
                "name": subscription_path,
                "topic": topic_path,
                "ack_deadline_seconds": 60,
            }
        )
        print(f"✓ Created subscription: {subscription.name}")
    except Exception as e:
        if "ALREADY_EXISTS" in str(e):
            print(f"✓ Subscription already exists: {subscription_path}")
        else:
            print(f"✗ Failed to create subscription: {e}")
            return False

    print("\n✓ Setup complete!")
    print("\nTo receive messages:")
    print(f"  gcloud pubsub subscriptions pull {subscription_id} \\")
    print(f"    --auto-ack \\")
    print(f"    --project={project_id} \\")
    print(f"    --limit=10")

    return True

if __name__ == "__main__":
    success = create_topic_and_subscription()
    exit(0 if success else 1)
