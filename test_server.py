#!/usr/bin/env python3
"""
Test Apple On-Device OpenAI Compatible Server
Make sure the server is running at http://localhost:11535 before running this script
"""

import requests
import json
from openai import OpenAI

# Server addresses
BASE_URL = "http://127.0.0.1:11535"
API_BASE_URL = f"{BASE_URL}/v1"

def test_health_check():
    """Test health check endpoint"""
    print("🔍 Testing health check...")
    try:
        response = requests.get(f"{BASE_URL}/health")
        if response.status_code == 200:
            print("✅ Health check passed")
            return True
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Connection failed: {e}")
        return False

def test_status():
    """Test status endpoint"""
    print("\n🔍 Testing server status...")
    try:
        response = requests.get(f"{BASE_URL}/status")
        if response.status_code == 200:
            data = response.json()
            print("✅ Status check passed")
            print(f"   Model available: {data.get('model_available', False)}")
            print(f"   Reason: {data.get('reason', 'N/A')}")
            print(f"   Supported languages count: {len(data.get('supported_languages', []))}")
            return data.get('model_available', False)
        else:
            print(f"❌ Status check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Status check error: {e}")
        return False

def test_models_list():
    """Test models list endpoint using OpenAI SDK"""
    print("\n🔍 Testing models list (OpenAI SDK)...")
    try:
        client = OpenAI(
            base_url=API_BASE_URL,
            api_key="dummy-key"  # No real API key needed
        )
        
        models = client.models.list()
        print("✅ Models list retrieved successfully")
        print(f"   Available models count: {len(models.data)}")
        for model in models.data:
            print(f"   - {model.id}")
        return True
    except Exception as e:
        print(f"❌ Models list retrieval error: {e}")
        print(e) 
        return False

def test_chat_completion_openai_sdk():
    """Test multi-turn chat completion using OpenAI SDK"""
    print("\n🔍 Testing multi-turn chat completion (OpenAI SDK)...")
    try:
        client = OpenAI(
            base_url=API_BASE_URL,
            api_key="dummy-key"  # No real API key needed
        )
        
        response = client.chat.completions.create(
            model="apple-on-device",
            messages=[
                {"role": "user", "content": "What are the benefits of on-device AI?"},
                {"role": "assistant", "content": "On-device AI offers several key benefits including improved privacy, faster response times, reduced reliance on internet connectivity, and better data security since processing happens locally on your device."},
                {"role": "user", "content": "Can you elaborate on the privacy benefits?"},
            ],
            max_tokens=200
        )
        
        print("✅ Multi-turn OpenAI SDK call successful")
        print(f"   Response ID: {response.id}")
        print(f"   Model: {response.model}")
        print(f"   AI Response: {response.choices[0].message.content}")
        return True
    except Exception as e:
        print(f"❌ Multi-turn OpenAI SDK call failed: {e}")
        print(e) 
        return False

def test_chinese_conversation():
    """Test Chinese conversation using OpenAI SDK"""
    print("\n🔍 Testing Chinese conversation (OpenAI SDK)...")
    try:
        client = OpenAI(
            base_url=API_BASE_URL,
            api_key="dummy-key"  # No real API key needed
        )
        
        response = client.chat.completions.create(
            model="apple-on-device",
            messages=[
                {"role": "user", "content": "你好！请用中文解释一下什么是苹果智能。"}
            ],
            max_tokens=200
        )
        
        print("✅ Chinese conversation successful")
        print(f"   AI Response: {response.choices[0].message.content}")
        return True
    except Exception as e:
        print(f"❌ Chinese conversation error: {e}")
        return False

def test_streaming_chat_completion():
    """Test streaming chat completion using OpenAI SDK"""
    print("\n🔍 Testing streaming chat completion (OpenAI SDK)...")
    try:
        client = OpenAI(
            base_url=API_BASE_URL,
            api_key="dummy-key"  # No real API key needed
        )
        
        stream = client.chat.completions.create(
            model="apple-on-device",
            messages=[
                {"role": "user", "content": "Tell me a short story about AI helping humans."}
            ],
            max_tokens=150,
            stream=True
        )
        
        print("✅ Streaming chat completion started")
        collected_content = ""
        chunk_count = 0
        
        for chunk in stream:
            if chunk.choices[0].delta.content is not None:
                content = chunk.choices[0].delta.content
                collected_content += content
                chunk_count += 1
                print(f"   Chunk {chunk_count}: '{content}'")
        
        print(f"✅ Streaming completed with {chunk_count} chunks")
        print(f"   Full response: {collected_content}")
        return True
    except Exception as e:
        print(f"❌ Streaming chat completion failed: {e}")
        return False

WEATHER_TOOL = {
    "type": "function",
    "function": {
        "name": "get_weather",
        "description": "Get the current weather for a city.",
        "parameters": {
            "type": "object",
            "properties": {
                "city": {"type": "string", "description": "City name"},
                "unit": {"type": "string", "enum": ["celsius", "fahrenheit"]},
            },
            "required": ["city", "unit"],
        },
    },
}


def test_tool_calling_round_trip():
    """Test a tool call, the client-side execution, and the model's final answer"""
    print("\n🔍 Testing tool calling round trip (OpenAI SDK)...")
    try:
        client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
        messages = [{"role": "user", "content": "What is the weather in Berlin, in celsius?"}]

        first = client.chat.completions.create(
            model="apple-on-device", messages=messages, tools=[WEATHER_TOOL]
        )
        choice = first.choices[0]
        if choice.finish_reason != "tool_calls" or not choice.message.tool_calls:
            print(f"❌ Expected a tool call, got finish_reason={choice.finish_reason}")
            return False
        for call in choice.message.tool_calls:
            print(f"✅ Model requested {call.function.name}({call.function.arguments})")

        # The client runs the tool; the server never does.
        messages.append(choice.message.model_dump(exclude_none=True))
        for call in choice.message.tool_calls:
            json.loads(call.function.arguments)  # arguments must be a JSON document
            messages.append({
                "role": "tool",
                "tool_call_id": call.id,
                "content": json.dumps({"temp_c": 7, "condition": "drizzle"}),
            })

        second = client.chat.completions.create(
            model="apple-on-device", messages=messages, tools=[WEATHER_TOOL]
        )
        print(f"✅ Final answer: {second.choices[0].message.content}")
        return second.choices[0].finish_reason == "stop"
    except Exception as e:
        print(f"❌ Tool calling failed: {e}")
        return False


def test_structured_output():
    """Test response_format with a JSON Schema"""
    print("\n🔍 Testing structured output (response_format)...")
    try:
        client = OpenAI(base_url=API_BASE_URL, api_key="dummy-key")
        response = client.chat.completions.create(
            model="apple-on-device",
            messages=[{"role": "user", "content": "Extract: Anna Schmidt, 34, lives in Graz."}],
            response_format={
                "type": "json_schema",
                "json_schema": {
                    "name": "person",
                    "schema": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "age": {"type": "integer"},
                            "city": {"type": "string"},
                        },
                        "required": ["name", "age", "city"],
                    },
                },
            },
        )
        person = json.loads(response.choices[0].message.content)
        print(f"✅ Structured output: {person}")
        return set(person) == {"name", "age", "city"}
    except Exception as e:
        print(f"❌ Structured output failed: {e}")
        return False


def test_error_envelope():
    """Test that errors arrive in OpenAI's error envelope"""
    print("\n🔍 Testing error envelope...")
    try:
        response = requests.post(
            f"{API_BASE_URL}/chat/completions",
            json={"model": "no-such-model", "messages": [{"role": "user", "content": "hi"}]},
        )
        error = response.json().get("error", {})
        if response.status_code == 404 and error.get("code") == "model_not_found":
            print(f"✅ 404 {error['type']}: {error['message']}")
            return True
        print(f"❌ Unexpected error response: {response.status_code} {response.text}")
        return False
    except Exception as e:
        print(f"❌ Error envelope test failed: {e}")
        return False


def main():
    """Main test function"""
    print("🚀 Starting Apple On-Device OpenAI Compatible Server Tests")
    print("=" * 60)
    
    # Basic connection test
    if not test_health_check():
        print("\n❌ Server unreachable, please ensure the server is running")
        return
    
    # Status check
    model_available = test_status()
    
    # Models list (using OpenAI SDK)
    test_models_list()
    
    # If model is available, run chat tests (using OpenAI SDK)
    if model_available:
        print("\n" + "=" * 60)
        print("🤖 Model available, starting chat tests")
        print("=" * 60)
        
        test_chat_completion_openai_sdk()
        test_chinese_conversation()
        
        print("\n" + "=" * 60)
        print("🌊 Testing streaming functionality")
        print("=" * 60)
        
        test_streaming_chat_completion()

        print("\n" + "=" * 60)
        print("🛠  Testing tool calling, structured output and errors")
        print("=" * 60)

        test_tool_calling_round_trip()
        test_structured_output()
        test_error_envelope()

        print("\n" + "=" * 60)
        print("✅ All tests completed!")
        print("\n💡 You can now use any OpenAI-compatible client to connect to:")
        print(f"   Base URL: {API_BASE_URL}")
        print("   API Key: any value (no real API key needed)")
        print("   Model: apple-on-device")
    else:
        print("\n⚠️  Model unavailable, skipping chat tests")
        print("Please ensure:")
        print("1. Device supports Apple Intelligence")
        print("2. Apple Intelligence is enabled in Settings")
        print("3. Model download is complete")

if __name__ == "__main__":
    main() 