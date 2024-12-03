import Foundation
import AVFoundation

public struct MenuItem: Codable {
    public let name: String
    public let quantity: Int
    public let price: Double?
    
    public init(name: String, quantity: Int, price: Double? = nil) {
        self.name = name
        self.quantity = quantity
        self.price = price
    }
}

public struct BillVerificationResult: Codable {
    public let message: String
    public let discrepancies: [Discrepancy]
    public let isMatch: Bool
    
    public init(message: String, discrepancies: [Discrepancy], isMatch: Bool) {
        self.message = message
        self.discrepancies = discrepancies
        self.isMatch = isMatch
    }
}

public struct Discrepancy: Codable {
    public let item: String
    public let orderedQuantity: Int
    public let billedQuantity: Int
    public let question: String
    
    public init(item: String, orderedQuantity: Int, billedQuantity: Int, question: String) {
        self.item = item
        self.orderedQuantity = orderedQuantity
        self.billedQuantity = billedQuantity
        self.question = question
    }
}

public class OrderProcessingService {
    private let baseURL = "http://127.0.0.1:5000"
    private let serverURL = "http://127.0.0.1:5000/process_audio"
    
    public func processAudioData(_ audioData: Data, completion: @escaping (Result<[MenuItem], Error>) -> Void) {
        // Convert audio data to base64
        let base64Audio = audioData.base64EncodedString()
        print("Sending audio data to Python server...")
        
        // Create request
        guard let url = URL(string: serverURL) else {
            print("Invalid URL")
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        
        // Create request body
        let body: [String: Any] = ["audio_data": base64Audio]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("Error creating request body: \(error)")
            completion(.failure(error))
            return
        }
        
        // Make request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Network error: \(error)")
                completion(.failure(error))
                return
            }
            
            // Print response headers for debugging
            if let httpResponse = response as? HTTPURLResponse {
                print("Response status code: \(httpResponse.statusCode)")
                print("Response headers: \(httpResponse.allHeaderFields)")
            }
            
            guard let data = data else {
                print("No data received from server")
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Print raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Raw server response: \(responseString)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("Parsed JSON: \(json)")
                    
                    if let success = json["success"] as? Bool,
                       success,
                       let foodItems = json["food_items"] as? [[String: Any]] {
                        
                        print("Found food items: \(foodItems)")
                        
                        // Convert food items to MenuItem objects
                        let menuItems = foodItems.compactMap { item -> MenuItem? in
                            guard let name = item["name"] as? String,
                                  let quantity = item["quantity"] as? Int else {
                                print("Invalid item format: \(item)")
                                return nil
                            }
                            return MenuItem(name: name, quantity: quantity, price: nil)
                        }
                        
                        print("Converted to menu items: \(menuItems)")
                        
                        DispatchQueue.main.async {
                            completion(.success(menuItems))
                        }
                    } else {
                        print("Invalid response format - missing success or food_items")
                        print("JSON contents: \(json)")
                        DispatchQueue.main.async {
                            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                        }
                    }
                } else {
                    print("Could not parse response as JSON dictionary")
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])))
                    }
                }
            } catch {
                print("JSON parsing error: \(error)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        
        task.resume()
    }
    
    public func processText(_ text: String, completion: @escaping (Result<[MenuItem], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/process_text") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let parameters = ["text": text]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let items = try JSONDecoder().decode([MenuItem].self, from: data)
                completion(.success(items))
            } catch {
                completion(.failure(error))
            }
        }
        
        task.resume()
    }
    
    public func verifyBill(orderedItems: [MenuItem], receiptImage: String, completion: @escaping (Result<BillVerificationResult, Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/verify_bill") else {
            completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        let parameters: [String: Any] = [
            "ordered_items": orderedItems.map { ["name": $0.name, "quantity": $0.quantity] },
            "receipt_image": receiptImage
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let data = data else {
                completion(.failure(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            do {
                let result = try JSONDecoder().decode(BillVerificationResult.self, from: data)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    public typealias VerificationCompletion = (Bool) -> Void
    
    public func verifyOrder(items: [String], completion: @escaping VerificationCompletion) {
        // TODO: Implement actual verification logic
        // For now, just simulate verification
        DispatchQueue.global().async {
            // Simulate network delay
            Thread.sleep(forTimeInterval: 1.0)
            
            // Simple verification: consider it successful if there are items
            let success = !items.isEmpty
            
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }
}
