import UIKit

class BillVerificationViewController: UIViewController {
    private let tableView = UITableView()
    private let orderedItems: [MenuItem]
    private var billItems: [MenuItem] = []
    
    init(orderedItems: [MenuItem]) {
        self.orderedItems = orderedItems
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        view.backgroundColor = .white
        title = "Verify Your Bill"
        
        // Add "Add Bill Item" button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addBillItemTapped)
        )
        
        // Configure table view
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.dataSource = self
        tableView.delegate = self
        
        view.addSubview(tableView)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    
    @objc private func addBillItemTapped() {
        let alert = UIAlertController(title: "Add Bill Item", message: nil, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "Item name"
        }
        alert.addTextField { textField in
            textField.placeholder = "Price"
            textField.keyboardType = .decimalPad
        }
        
        let addAction = UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let name = alert.textFields?[0].text,
                  let priceText = alert.textFields?[1].text,
                  let price = Double(priceText)
            else { return }
            
            let item = MenuItem(name: name, quantity: 1, price: price)
            self?.billItems.append(item)
            self?.tableView.reloadData()
            self?.verifyBill()
        }
        
        alert.addAction(addAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        present(alert, animated: true)
    }
    
    private func verifyBill() {
        var discrepancies: [String] = []
        
        // Check for missing items
        for orderedItem in orderedItems {
            let matchingBillItems = billItems.filter { $0.name.lowercased().contains(orderedItem.name.lowercased()) }
            if matchingBillItems.isEmpty {
                discrepancies.append("Missing item: \(orderedItem.name) (Quantity: \(orderedItem.quantity))")
            }
        }
        
        // Check for extra items
        for billItem in billItems {
            let matchingOrderItems = orderedItems.filter { $0.name.lowercased().contains(billItem.name.lowercased()) }
            if matchingOrderItems.isEmpty {
                discrepancies.append("Extra item on bill: \(billItem.name)")
            }
        }
        
        if !discrepancies.isEmpty {
            let alert = UIAlertController(title: "Bill Discrepancies Found",
                                        message: discrepancies.joined(separator: "\n"),
                                        preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
}

extension BillVerificationViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? orderedItems.count : billItems.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        
        let item = indexPath.section == 0 ? orderedItems[indexPath.row] : billItems[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = item.name
        
        if let price = item.price {
            content.secondaryText = "Quantity: \(item.quantity), Price: $\(String(format: "%.2f", price))"
        } else {
            content.secondaryText = "Quantity: \(item.quantity)"
        }
        
        cell.contentConfiguration = content
        return cell
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Ordered Items" : "Bill Items"
    }
}
