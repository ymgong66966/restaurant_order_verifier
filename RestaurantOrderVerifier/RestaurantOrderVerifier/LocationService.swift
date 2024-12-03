//
//  LocationService.swift
//  RestaurantOrderVerifier
//
//  Created by Gong, Yiming on 12/3/24.
//

import CoreLocation
import GoogleMaps
import GooglePlaces

class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()
    private let locationManager = CLLocationManager()
    private var completion: ((Restaurant?) -> Void)?
    
    struct Restaurant {
        let name: String
        let placeId: String
        let coordinate: CLLocationCoordinate2D
    }
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func findNearbyRestaurant(completion: @escaping (Restaurant?) -> Void) {
        self.completion = completion
        
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        default:
            completion(nil)
        }
    }
    
    // CLLocationManagerDelegate methods
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            completion?(nil)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        locationManager.stopUpdatingLocation()
        
        let placesClient = GMSPlacesClient.shared()
        
        let placeFields: GMSPlaceField = [.name, .placeID, .coordinate]
        
        placesClient.findPlaceLikelihoodsFromCurrentLocation(withPlaceFields: placeFields) { [weak self] (placeLikelihoods, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("Error finding places: \(error.localizedDescription)")
                self.completion?(nil)
                return
            }
            
            // Find the nearest restaurant within 50 feet (≈ 15 meters)
            if let nearestPlace = placeLikelihoods?.first(where: { likelihood in
                let distance = location.distance(from: CLLocation(latitude: likelihood.place.coordinate.latitude,
                                                               longitude: likelihood.place.coordinate.longitude))
                return distance <= 15
            })?.place {
                let restaurant = Restaurant(name: nearestPlace.name ?? "",
                                         placeId: nearestPlace.placeID ?? "",
                                         coordinate: nearestPlace.coordinate)
                self.completion?(restaurant)
            } else {
                self.completion?(nil)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
        completion?(nil)
    }
}
