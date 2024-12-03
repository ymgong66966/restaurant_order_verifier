from flask import Flask, request, jsonify
from flask_cors import CORS
import base64
import speech_recognition as sr
import io
import wave
import nltk
from nltk.tokenize import word_tokenize
from nltk.tag import pos_tag
from openai import OpenAI
import os
from dotenv import load_dotenv
import json
from faster_whisper import WhisperModel

# Load environment variables
load_dotenv()

app = Flask(__name__)
CORS(app)

# Initialize OpenAI client
client = OpenAI(
    api_key=os.getenv("OPENAI_API_KEY"),
    base_url="https://api.openai.com/v1"
)

# Initialize Whisper model (do this once at startup)
model_size = "base"
model = WhisperModel(model_size, device="cpu", compute_type="int8")
print(f"Loaded faster-whisper model: {model_size}")

# Download required NLTK data
nltk.download('punkt')
nltk.download('averaged_perceptron_tagger')
nltk.download('maxent_ne_chunker')
nltk.download('words')

def extract_food_items(text):
    """Extract food items and quantities using GPT-4."""
    try:
        # Create a prompt for GPT-4
        prompt = f"""Extract food items and their quantities from the following text. 
        Return ONLY a JSON array where each item has 'name' and 'quantity' fields.
        Only include actual food items and beverages. The name should be in Title Case.
        Do not include any other text in your response, just the JSON array.
        
        Example output format:
        [
            {{"name": "Burger", "quantity": 2}},
            {{"name": "French Fries", "quantity": 1}}
        ]
        
        Text: {text}"""
        
        # Call GPT-4
        response = client.chat.completions.create(
            model="gpt-4",
            messages=[
                {"role": "system", "content": "You are a helpful assistant that extracts food items and quantities from text. Only respond with valid JSON arrays containing food items."},
                {"role": "user", "content": prompt}
            ],
            temperature=0  # Use deterministic output
        )
        
        # Parse the response
        response_text = response.choices[0].message.content.strip()
        result = json.loads(response_text)
        
        # Ensure the response is a list
        if not isinstance(result, list):
            result = result.get('items', [])  # Some models might wrap the array in an object
        
        print(f"GPT extracted items: {result}")  # Debug print
        return result
        
    except Exception as e:
        print(f"Error in GPT extraction: {str(e)}")
        # Fallback to empty list if there's an error
        return []

@app.route('/verify_bill', methods=['POST'])
def verify_bill():
    try:
        print("\n=== Starting Bill Verification Process ===")
        
        # Get data from request
        print("Getting request data...")
        data = request.json
        ordered_items = data.get('ordered_items', [])
        receipt_image_base64 = data.get('receipt_image', '')
        
        print(f"Received ordered items: {ordered_items}")
        print(f"Received base64 image length: {len(receipt_image_base64)} characters")
        
        # Validate required fields
        if not receipt_image_base64:
            print("Error: Receipt image is missing")
            return jsonify({"error": "Receipt image is required"}), 400
            
        if not ordered_items:
            print("Error: Ordered items are missing")
            return jsonify({"error": "Ordered items are required"}), 400
        
        # Decode base64 image
        try:
            print("Decoding base64 image...")
            receipt_image_data = base64.b64decode(receipt_image_base64)
            print(f"Successfully decoded image, size: {len(receipt_image_data)} bytes")
        except Exception as e:
            print(f"Error decoding base64 image: {str(e)}")
            return jsonify({"error": f"Invalid base64 image: {str(e)}"}), 400
        
        # Use GPT-4 Vision to analyze the receipt
        try:
            print("\nCalling GPT-4 Vision API to analyze receipt...")
            print("This may take a few moments...")
            
            response = client.chat.completions.create(
                model="gpt-4o-mini",
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text", 
                                "text": "This is a restaurant receipt. Please extract all food items and their quantities. Format your response as a JSON array with objects containing 'name' and 'quantity' fields. Names should be in Title Case. Example format: [{\"name\": \"Burger\", \"quantity\": 1}, {\"name\": \"Fries\", \"quantity\": 2}] Only include actual food items and beverages. Do not include any other text in your response, just the JSON array!!! Do not include words like 'json', 'array', or 'object' in your response. Only respond with valid JSON arrays containing food items. Example output format: [ {\"name\": \"Burger\", \"quantity\": 2}, {\"name\": \"French Fries\", \"quantity\": 1} ]"
                            },
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/jpeg;base64,{receipt_image_base64}"
                                }
                            }
                        ]
                    }
                ],
                temperature=0  # U
            )
            
            print("Received response from GPT-4 Vision")
            
            # Extract billed items from GPT-4 Vision response
            billed_items_text = response.choices[0].message.content.strip()
            print(f"\nGPT-4 Vision Response:\n{billed_items_text}")
            
            try:
                print("\nParsing GPT response as JSON...")
                # Attempt to parse the response as JSON
                billed_items = json.loads(billed_items_text)
                
                # Validate that we got a list of dictionaries with required fields
                if not isinstance(billed_items, list):
                    print("Error: GPT response is not a JSON array")
                    return jsonify({"error": "Invalid response format: expected JSON array"}), 500
                    
                for item in billed_items:
                    if not isinstance(item, dict) or 'name' not in item or 'quantity' not in item:
                        print(f"Error: Invalid item format in GPT response: {item}")
                        return jsonify({"error": "Invalid item format: missing required fields"}), 500
                
                print(f"Successfully parsed billed items: {billed_items}")
                
            except json.JSONDecodeError as e:
                print(f"Error parsing GPT response as JSON: {str(e)}")
                return jsonify({"error": f"Failed to parse GPT response as JSON: {str(e)}"}), 500
            
        except Exception as e:
            print(f"Error during GPT-4 Vision API call: {str(e)}")
            return jsonify({"error": f"Error analyzing receipt with GPT-4 Vision: {str(e)}"}), 500
        
        # Compare ordered vs billed items using GPT-4
        try:
            print("\nComparing ordered items with billed items...")
            comparison_prompt = f"""
            Compare these two lists of food items and identify any discrepancies:
            
            Ordered Items: {json.dumps(ordered_items, indent=2)}
            Billed Items: {json.dumps(billed_items, indent=2)}
            
            Return a JSON object with:
            1. "message": A summary of the comparison
            2. "discrepancies": Array of objects with fields:
               - "item": The item name
               - "orderedQuantity": Quantity ordered
               - "billedQuantity": Quantity billed
               - "question": A follow-up question if needed
            3. "isMatch": Boolean indicating if the orders match
            
            Focus on quantity mismatches and missing/extra items.
            Generate clear, specific questions for each discrepancy.
            Do not include any other text in your response, just the JSON array!!! Do not include any words other than the JSON array in python in your response. Only respond with valid python JSON arrays containing food items. 

            If there is discrepancy, return a JSON object with the following format: 
            "{{
  "message": "The ordered items and billed items do not match perfectly.",
  "discrepancies": [{{'item': 'Dumplings', 'orderedQuantity': 12, 'billedQuantity': 0, 'question': 'Did you order 12 Dumplings? They are not included in the bill.'}},{{'item': 'burgers', 'orderedQuantity': 0, 'billedQuantity': 2, 'question': 'Did you order 2 burgers? You are charged for 2 burgers in the bill.'}}],
  "isMatch": "false"
}}"
If there are no discrepancies, return an empty array for the "discrepancies" array. and "isMatch": "true"
            """
            
            print("Calling GPT-4 for order comparison...")
            comparison_response = client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are a helpful assistant comparing restaurant orders with bills."},
                    {"role": "user", "content": comparison_prompt}
                ],
                temperature=0
            )
            print("Received comparison response from GPT-4")
            print(comparison_response.choices[0].message.content)
            
            # Parse and return the comparison result
            result = json.loads(comparison_response.choices[0].message.content)
            print(f"\nFinal comparison result: {result}")
            print("\n=== Bill Verification Complete ===")
            return jsonify(result)
            
        except Exception as e:
            print(f"Error during order comparison: {str(e)}")
            return jsonify({"error": f"Error comparing orders: {str(e)}"}), 500
            
    except Exception as e:
        print(f"Unexpected error in bill verification: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/process_text', methods=['POST'])
def process_text():
    try:
        data = request.json
        if not data or 'text' not in data:
            return jsonify({'success': False, 'error': 'No text provided'})
        
        text = data['text']
        print(f"Input text: '{text}'")
        
        # Extract food items from text
        food_items = extract_food_items(text)
        print(f"Extracted food items: {food_items}")
        
        return jsonify({
            'success': True,
            'text': text,
            'food_items': food_items
        })

    except Exception as e:
        print(f"Error processing text: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        })

@app.route('/process_audio', methods=['POST'])
def process_audio():
    try:
        print("\n=== New Audio Processing Request ===")
        
        # Get base64 audio data from request
        data = request.json
        if not data or 'audio_data' not in data:
            print("Error: No audio data provided")
            return jsonify({'success': False, 'error': 'No audio data provided'})

        # Decode base64 audio
        print("Decoding base64 audio data...")
        audio_data = base64.b64decode(data['audio_data'])
        print(f"Received audio data size: {len(audio_data)} bytes")
        
        # Create a recognizer instance
        recognizer = sr.Recognizer()
        
        # Create an in-memory WAV file
        print("Processing audio file...")
        with io.BytesIO(audio_data) as wav_io:
            # Use speech recognition
            with sr.AudioFile(wav_io) as source:
                print("Reading audio file...")
                audio = recognizer.record(source)
                
                try:
                    print("Performing speech recognition...")
                    text = recognizer.recognize_google(audio)
                    print(f"Recognized text: '{text}'")
                    
                    # Extract food items
                    food_items = extract_food_items(text)
                    
                    return jsonify({
                        'success': True,
                        'text': text,
                        'food_items': food_items
                    })
                    
                except sr.UnknownValueError:
                    print("Speech recognition could not understand the audio")
                    return jsonify({
                        'success': False,
                        'error': 'Could not understand audio'
                    })
                except sr.RequestError as e:
                    print(f"Could not request results from speech recognition service: {str(e)}")
                    return jsonify({
                        'success': False,
                        'error': f'Speech recognition service error: {str(e)}'
                    })
                
    except Exception as e:
        print(f"Error processing audio: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        })

@app.route('/transcribe_audio_chunk', methods=['POST'])
def transcribe_audio_chunk():
    try:
        print("\n=== Processing Complete Audio Recording ===")
        
        # Get audio data from request
        data = request.json
        if not data or 'audio_data' not in data:
            print("Error: No audio data provided")
            return jsonify({'success': False, 'error': 'No audio data provided'})

        # Decode base64 audio
        print("Decoding base64 audio...")
        try:
            audio_data = base64.b64decode(data['audio_data'])
            print(f"Decoded audio size: {len(audio_data)} bytes")
            
            if len(audio_data) < 100:
                print("Warning: Audio data seems too small")
                return jsonify({'success': False, 'error': 'Audio data too small'})
        except Exception as e:
            print(f"Error decoding base64: {str(e)}")
            return jsonify({'success': False, 'error': f'Base64 decode error: {str(e)}'})
        
        # Save audio to temporary file
        temp_file = 'temp_recording.wav'
        try:
            with open(temp_file, 'wb') as f:
                f.write(audio_data)
            
            print(f"Saved complete recording: {temp_file}")
            print(f"File size: {os.path.getsize(temp_file)} bytes")
            
            # Transcribe using faster-whisper
            print("Transcribing complete audio...")
            segments, info = model.transcribe(temp_file, beam_size=5)
            
            # Combine all segments into one text
            transcription = " ".join([segment.text for segment in segments])
            print(f"Complete transcription: {transcription}")
            
            return jsonify({
                'success': True,
                'text': transcription
            })
            
        finally:
            if os.path.exists(temp_file):
                os.remove(temp_file)
                
    except Exception as e:
        print(f"Error in audio transcription: {str(e)}")
        return jsonify({
            'success': False,
            'error': str(e)
        })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=5000)
