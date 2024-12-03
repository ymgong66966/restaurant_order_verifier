import UIKit
import GoogleMaps
import GooglePlaces

class RestaurantSelectionViewController: UIViewController, GMSMapViewDelegate {
    private let mapView: GMSMapView = {
        let camera = GMSCameraPosition.camera(withLatitude: 37.7749, longitude: -122.4194, zoom: 15)
        let mapView = GMSMapView(frame: .zero, camera: camera)
        return mapView
    }()
    
    private let searchBar: UISearchBar = {
        let searchBar = UISearchBar()
        searchBar.placeholder = "Search for a restaurant"
        searchBar.searchBarStyle = .minimal
        return searchBar
    }()
    
    private let resultsTableView: UITableView = {
        let tableView = UITableView()
        tableView.isHidden = true
        return tableView
    }()
    
    private var selectedRestaurant: LocationService.Restaurant?
    private var searchResults: [GMSAutocompletePrediction] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Select Restaurant"
        view.backgroundColor = .systemBackground
        
        // Setup map view
        mapView.delegate = self
        mapView.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup search bar
        searchBar.delegate = self
        searchBar.placeholder = "Search for a restaurant"
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        
        // Setup results table view
        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.isHidden = true
        resultsTableView.translatesAutoresizingMaskIntoConstraints = false
        resultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "RestaurantCell")
        
        // Add subviews
        view.addSubview(mapView)
        view.addSubview(searchBar)
        view.addSubview(resultsTableView)
        
        // Setup constraints
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            
            mapView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            resultsTableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            resultsTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resultsTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            resultsTableView.heightAnchor.constraint(equalToConstant: 200)
        ])
    }
    
    private func checkForNearbyRestaurant() {
        LocationService.shared.findNearbyRestaurant { [weak self] restaurant in
            guard let self = self else { return }
            
            if let restaurant = restaurant {
                // Found a nearby restaurant
                self.selectedRestaurant = restaurant
                self.proceedToRecording()
            } else {
                // No nearby restaurant found, let user search
                DispatchQueue.main.async {
                    self.searchBar.becomeFirstResponder()
                }
            }
        }
    }
    
    private func proceedToRecording() {
        guard let restaurant = selectedRestaurant else { return }
        
        DispatchQueue.main.async {
            let recordingVC = RecordingViewController()
            recordingVC.restaurantName = restaurant.name
            self.navigationController?.pushViewController(recordingVC, animated: true)
        }
    }
}

// MARK: - UISearchBarDelegate
extension RestaurantSelectionViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        guard !searchText.isEmpty else {
            searchResults = []
            resultsTableView.reloadData()
            resultsTableView.isHidden = true
            return
        }
        
        let filter = GMSAutocompleteFilter()
        filter.type = .establishment
        filter.types = ["restaurant"]
        filter.countries = ["US"]  // Restrict to US for better address formatting
        
        let sessionToken = GMSAutocompleteSessionToken()
        
        // For debugging
        print("Searching for: \(searchText)")
        
        GMSPlacesClient.shared().findAutocompletePredictions(
            fromQuery: searchText,
            filter: filter,
            sessionToken: sessionToken
        ) { [weak self] (results, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Error fetching autocomplete results: \(error.localizedDescription)")
                return
            }
            
            self.searchResults = results ?? []
            
            // For debugging - print full details of each prediction
            for prediction in self.searchResults {
                print("Full text: \(prediction.attributedFullText.string)")
                print("Primary: \(prediction.attributedPrimaryText.string)")
                print("Secondary: \(prediction.attributedSecondaryText?.string ?? "No secondary")")
                print("Place ID: \(prediction.placeID)")
                print("---")
            }
            
            DispatchQueue.main.async {
                self.resultsTableView.reloadData()
                self.resultsTableView.isHidden = self.searchResults.isEmpty
            }
        }
    }
}

// MARK: - UITableViewDelegate, UITableViewDataSource
extension RestaurantSelectionViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return searchResults.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        // Always create a new cell with subtitle style
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "RestaurantCell")
        
        let prediction = searchResults[indexPath.row]
        
        // Set the main text (restaurant name)
        cell.textLabel?.text = prediction.attributedPrimaryText.string
        
        // Set the subtitle (address) directly from secondaryText
        cell.detailTextLabel?.text = prediction.attributedSecondaryText?.string
        
        // Configure cell appearance
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        cell.detailTextLabel?.font = .systemFont(ofSize: 14)
        cell.textLabel?.numberOfLines = 1
        cell.detailTextLabel?.numberOfLines = 2  // Allow two lines for longer addresses
        cell.detailTextLabel?.textColor = .darkGray
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 75  // Slightly increased height for two address lines
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let prediction = searchResults[indexPath.row]
        
        let placesClient = GMSPlacesClient.shared()
        let sessionToken = GMSAutocompleteSessionToken()
        
        placesClient.fetchPlace(
            fromPlaceID: prediction.placeID,
            placeFields: [.name, .coordinate],
            sessionToken: sessionToken) { [weak self] (place, error) in
            guard let self = self,
                  let place = place else {
                print("Error fetching place details: \(error?.localizedDescription ?? "")")
                return
            }
            
            // Update map camera to show the selected location
            let camera = GMSCameraPosition.camera(
                withLatitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude,
                zoom: 15
            )
            
            DispatchQueue.main.async {
                // Move map camera to the selected location
                self.mapView.camera = camera
                
                // Add a marker for the selected restaurant
                let marker = GMSMarker(position: place.coordinate)
                marker.title = place.name
                marker.map = self.mapView
                
                // Hide search results
                self.resultsTableView.isHidden = true
                
                // Store selected restaurant
                self.selectedRestaurant = LocationService.Restaurant(
                    name: place.name ?? "",
                    placeId: place.placeID ?? "",
                    coordinate: place.coordinate
                )
                
                self.proceedToRecording()
            }
        }
    }
}
