import UIKit
import Speech
import PhotosUI

class RecordingViewController: UIViewController {
    private let speechRecognizer = SpeechRecognitionService()
    private var detectedItems: [String] = []
    private var recordedText: String = ""
    private let orderProcessor = OrderProcessingService()
    var restaurantName: String?
    
    private lazy var recordButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Start Recording"
        configuration.baseBackgroundColor = .systemBlue
        configuration.baseForegroundColor = .white
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(recordButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Ready to record"
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()
    
    private lazy var addItemButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Add Item"
        configuration.baseBackgroundColor = .systemGreen
        configuration.baseForegroundColor = .white
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(addItemButtonTapped), for: .touchUpInside)
        return button
    }()
    
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        table.isHidden = true
        return table
    }()
    
    private lazy var verifyBillButton: UIButton = {
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Verify Bill"
        configuration.baseBackgroundColor = .systemOrange
        configuration.baseForegroundColor = .white
        
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: #selector(verifyBillTapped), for: .touchUpInside)
        button.isHidden = true
        return button
    }()
    
    private let restaurantLabel: UILabel = {
        let label = UILabel()
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 18, weight: .medium)
        label.numberOfLines = 0
        return label
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Record Order"
        
        // Add restaurant label
        view.addSubview(restaurantLabel)
        restaurantLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Add restaurant label constraints
        NSLayoutConstraint.activate([
            restaurantLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            restaurantLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            restaurantLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        
        // Set restaurant name
        if let restaurantName = restaurantName {
            restaurantLabel.text = "Restaurant: \(restaurantName)"
        }
        
        let stackView = UIStackView(arrangedSubviews: [recordButton, statusLabel, addItemButton, tableView, verifyBillButton])
        stackView.axis = .vertical
        stackView.spacing = 20
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(stackView)
        
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: restaurantLabel.bottomAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            tableView.heightAnchor.constraint(equalToConstant: 300)
        ])
    }
    
    @objc private func recordButtonTapped() {
        if recordButton.isSelected {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        recordButton.isSelected = true
        recordButton.configuration?.baseBackgroundColor = .systemRed
        statusLabel.text = "Recording..."
        tableView.isHidden = true
        verifyBillButton.isHidden = true
        detectedItems = []
        recordedText = ""
        
        speechRecognizer.startRecording(
            textUpdateHandler: { [weak self] text in
                DispatchQueue.main.async {
                    self?.recordedText = text
                    self?.statusLabel.text = text
                }
            },
            itemsCompletion: { [weak self] text in
                // Process the recognized text directly
                self?.processRecognizedText(text)
            },
            errorHandler: { [weak self] error in
                DispatchQueue.main.async {
                    self?.statusLabel.text = "Error: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                }
            }
        )
    }
    
    private func stopRecording() {
        recordButton.isSelected = false
        recordButton.configuration?.baseBackgroundColor = .systemBlue
        statusLabel.text = "Processing..."
        speechRecognizer.stopRecording()
    }
    
    private func processRecognizedText(_ text: String) {
        // Extract menu items from the recognized text
        let words = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        
        guard !words.isEmpty else { return }
        
        // For now, just add the entire text as one item
        detectedItems.append(text)
        
        tableView.reloadData()
        tableView.isHidden = false
        verifyBillButton.isHidden = false
    }
    
    @objc private func addItemButtonTapped() {
        let alert = UIAlertController(title: "Add Item", message: "Enter item details", preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Item name"
        }
        
        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let name = alert.textFields?.first?.text,
                  !name.isEmpty else {
                return
            }
            
            self?.detectedItems.append(name)
            self?.tableView.reloadData()
            self?.tableView.isHidden = false
            self?.verifyBillButton.isHidden = false
        })
        
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func verifyBillTapped() {
        guard !detectedItems.isEmpty else {
            statusLabel.text = "No items detected to verify"
            statusLabel.textColor = .systemRed
            return
        }
        
        statusLabel.text = "Verifying order..."
        statusLabel.textColor = .systemOrange
        
        // Process the verification using OrderProcessingService
        orderProcessor.verifyOrder(items: detectedItems) { [weak self] success in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                if success {
                    self.statusLabel.text = "Order verified successfully!"
                    self.statusLabel.textColor = .systemGreen
                } else {
                    self.statusLabel.text = "Please check your order items"
                    self.statusLabel.textColor = .systemRed
                }
            }
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension RecordingViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return detectedItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let item = detectedItems[indexPath.row]
        cell.textLabel?.text = item
        return cell
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            detectedItems.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            if detectedItems.isEmpty {
                verifyBillButton.isHidden = true
            }
        }
    }
}

// MARK: - PHPickerViewControllerDelegate
extension RecordingViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let provider = results.first?.itemProvider else { return }
        
        if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
                if let error = error {
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                
                // We're not using the image for now, so we can ignore it
                _ = object as? UIImage
            }
        }
    }
}
