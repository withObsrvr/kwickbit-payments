#!/usr/bin/env python3
"""
Test script to verify Pub/Sub emulator is working and can pull messages.
"""

import os
from google.cloud import pubsub_v1

# Ensure we're using the emulator
emulator_host = os.getenv("PUBSUB_EMULATOR_HOST", "localhost:8085")
project_id = os.getenv("PUBSUB_PROJECT_ID", "local-dev-project")

print(f"Using Pub/Sub emulator at: {emulator_host}")
print(f"Project ID: {project_id}")

# Create subscriber client
subscriber = pubsub_v1.SubscriberClient()
subscription_path = subscriber.subscription_path(project_id, "payments-sub")

print(f"\nSubscription path: {subscription_path}")

# Try to pull messages
try:
    response = subscriber.pull(
        request={
            "subscription": subscription_path,
            "max_messages": 10,
        },
        timeout=5.0,
    )

    if response.received_messages:
        print(f"\n✓ Pulled {len(response.received_messages)} messages:")
        for msg in response.received_messages:
            print(f"  - Message ID: {msg.message.message_id}")
            print(f"    Data: {msg.message.data.decode('utf-8')}")

        # Acknowledge the messages
        ack_ids = [msg.ack_id for msg in response.received_messages]
        subscriber.acknowledge(
            request={
                "subscription": subscription_path,
                "ack_ids": ack_ids,
            }
        )
        print(f"\n✓ Acknowledged {len(ack_ids)} messages")
    else:
        print("\n✓ Subscription is working, but no messages available yet")
        print("  (This is expected if you haven't run the indexer)")

except Exception as e:
    print(f"\n✗ Error: {e}")
    print("\nTroubleshooting:")
    print("  1. Ensure PUBSUB_EMULATOR_HOST is set: export PUBSUB_EMULATOR_HOST='localhost:8085'")
    print("  2. Check emulator is running: docker ps | grep pubsub")
    print("  3. Check subscription exists: python3 setup/create_topics.py")
