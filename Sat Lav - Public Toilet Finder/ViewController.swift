import UIKit
import MapKit
import CoreLocation

struct Toilet {
    let name: String
    let latitude: Double
    let longitude: Double
    let openingHours: String
    let disabledAccess: String
    let babyChange: String
}

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    @IBOutlet weak var mapView: MKMapView!
    let locationManager = CLLocationManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Ensure the map view is not nil
        guard mapView != nil else {
            print("Error: Map view is not connected.")
            return
        }
        
        // Set the map type to standard
        mapView.mapType = .standard
        mapView.delegate = self
        
        // Set up location manager
        locationManager.delegate = self
        locationManager.distanceFilter = 100 // Update location every 100 meters
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        mapView.showsUserLocation = true
        
        fetchJSONData { [weak self] toilets in
            guard let self = self else { return }
            let babyChangeRequired = true  // Example: filtering for baby change
            let filteredToilets = self.filterToilets(toilets: toilets, babyChangeRequired: babyChangeRequired)
            if let userLocation = self.locationManager.location {
                let nearestToilets = self.findNearestToilets(userLocation: userLocation, toilets: filteredToilets, count: 10)
                DispatchQueue.main.async {
                    self.displayToiletsOnMap(toilets: nearestToilets)
                }
            }
        }
    }
    
    

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        print("User location updated: \(location.coordinate)")
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: true)
        
        fetchJSONData { [weak self] toilets in
            guard let self = self else { return }
            let babyChangeRequired = true  // Example: filtering for baby change
            let filteredToilets = self.filterToilets(toilets: toilets, babyChangeRequired: babyChangeRequired)
            let nearestToilets = self.findNearestToilets(userLocation: location, toilets: filteredToilets, count: 10)
            DispatchQueue.main.async {
                self.displayToiletsOnMap(toilets: nearestToilets)
            }
        }
    }
    
    // Method to fetch and parse JSON data
    func fetchJSONData(completion: @escaping ([Toilet]) -> Void) {
        let urlString = "http://34.71.219.20:8080/api/csv/read?filePath=https://dataworks.calderdale.gov.uk/download/20qn9/3ge/public-conveniences.csv"
        guard let url = URL(string: urlString) else {
            print("Error: Invalid URL.")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                return
            }
            guard let data = data else {
                print("Error: No data received.")
                return
            }

            do {
                // Parse JSON array
                let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String]]
                guard let rows = jsonArray, rows.count > 1 else {
                    print("Error: No data found.")
                    return
                }
                
                // Extract columns from header
                let header = rows[0]
                let locationIndex = header.firstIndex(of: "Location")
                let latitudeIndex = header.firstIndex(of: "Latitude")
                let longitudeIndex = header.firstIndex(of: "Longitude")
                let openingHoursIndex = header.firstIndex(of: "Opening hours")
                let disabledAccessIndex = header.firstIndex(of: "Accessible")
                let babyChangeIndex = header.firstIndex(of: "Baby change")
                
                var toilets: [Toilet] = []
                
                // Iterate through each row of data
                for row in rows[1...] {
                    // Skip empty or invalid rows
                    guard row.count > max(locationIndex ?? 0, latitudeIndex ?? 0, longitudeIndex ?? 0, openingHoursIndex ?? 0, disabledAccessIndex ?? 0, babyChangeIndex ?? 0),
                          row.contains(where: { !$0.isEmpty }) else {
                        continue
                    }
                    if let locationIndex = locationIndex,
                       let latitudeIndex = latitudeIndex,
                       let longitudeIndex = longitudeIndex,
                       let openingHoursIndex = openingHoursIndex,
                       let disabledAccessIndex = disabledAccessIndex,
                       let babyChangeIndex = babyChangeIndex,
                       let latitude = Double(row[latitudeIndex]),
                       let longitude = Double(row[longitudeIndex]) {
                        
                        let toilet = Toilet(
                            name: row[locationIndex],
                            latitude: latitude,
                            longitude: longitude,
                            openingHours: row[openingHoursIndex],
                            disabledAccess: row[disabledAccessIndex],
                            babyChange: row[babyChangeIndex]
                        )
                        toilets.append(toilet)
                    } else {
                        print("Error parsing row: \(row)")
                    }
                }
                print("Fetched and parsed \(toilets.count) toilets.")
                completion(toilets)
            } catch {
                print("Error parsing JSON: \(error)")
            }
        }.resume()
    }

    // Method to find nearest toilets
    func findNearestToilets(userLocation: CLLocation, toilets: [Toilet], count: Int = 10) -> [Toilet] {
        let sortedToilets = toilets.sorted {
            let location1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            let location2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
            return location1.distance(from: userLocation) < location2.distance(from: userLocation)
        }
        return Array(sortedToilets.prefix(count))
    }

    // Method to display toilets on the map
    func displayToiletsOnMap(toilets: [Toilet]) {
        mapView.removeAnnotations(mapView.annotations) // Clear existing annotations
        toilets.forEach { toilet in
            let annotation = MKPointAnnotation()
            annotation.title = toilet.name
            annotation.coordinate = CLLocationCoordinate2D(latitude: toilet.latitude, longitude: toilet.longitude)
            print("Adding annotation for \(toilet.name) at \(annotation.coordinate)")
            mapView.addAnnotation(annotation)
        }
        
        // Center the map around the annotations
        if let firstToilet = toilets.first {
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: firstToilet.latitude, longitude: firstToilet.longitude), span: span)
            mapView.setRegion(region, animated: true)
        }
    }

    // Filtering method
    func filterToilets(toilets: [Toilet], babyChangeRequired: Bool) -> [Toilet] {
        return toilets.filter { toilet in
            let matchesBabyChange = !babyChangeRequired || toilet.babyChange.lowercased() == "yes"
            return matchesBabyChange
        }
    }

    // MKMapViewDelegate method to handle annotation taps
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let coordinate = view.annotation?.coordinate else { return }
        
        // Show an alert with the option to get directions
        let alert = UIAlertController(title: "Get Directions", message: "Would you like to get directions to this location?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            self.showDirections(to: coordinate)
        }))
        self.present(alert, animated: true, completion: nil)
    }

    // Function to show directions
    func showDirections(to coordinate: CLLocationCoordinate2D) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = "Public Toilet"
        MKMapItem.openMaps(with: [destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
    
    
}

