import requests
import json
import base64
import os

BASE_URL = 'http://127.0.0.1:5001'

def test_process_text():
    print("\n=== Testing Process Text Endpoint ===")
    url = f"{BASE_URL}/process_text"
    
    # Test data
    data = {
        "text": "I would like to order two cheeseburgers and one large fries"
    }
    
    try:
        response = requests.post(url, json=data)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
    except Exception as e:
        print(f"Error: {str(e)}")

def test_verify_bill():
    print("\n=== Testing Verify Bill Endpoint ===")
    url = f"{BASE_URL}/verify_bill"
    
    # Test data
    data = {
        "ordered_items": [
            {"name": "Cheeseburger", "quantity": 2},
            {"name": "Large Fries", "quantity": 1}
        ],
        "receipt_image": base64.b64encode(b"test_image_data").decode('utf-8')
    }
    
    try:
        response = requests.post(url, json=data)
        print(f"Status Code: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
    except Exception as e:
        print(f"Error: {str(e)}")

# def test_process_audio():
#     print("\n=== Testing Process Audio Endpoint ===")
#     url = f"{BASE_URL}/process_audio"
    
#     # Create a small test audio file (you can replace this with a real audio file)
#     test_audio = b"test_audio_data"
#     audio_base64 = base64.b64encode(test_audio).decode('utf-8')
    
#     data = {
#         "audio_data": audio_base64
#     }
    
#     try:
#         response = requests.post(url, json=data)
#         print(f"Status Code: {response.status_code}")
#         print(f"Response: {json.dumps(response.json(), indent=2)}")
#     except Exception as e:
#         print(f"Error: {str(e)}")

def main():
    print("Starting server tests...")
    
    # Test server connection
    try:
        requests.get(f"{BASE_URL}")
        print("Server is running!")
    except requests.exceptions.ConnectionError:
        print("Error: Cannot connect to server. Make sure it's running on port 5001")
        return
    
    # Run tests
    test_process_text()
    # test_verify_bill()
    # test_process_audio()

if __name__ == "__main__":
    main()