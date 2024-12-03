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
    let chargeAmount: String // New property for charge amount
}

class ViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    @IBOutlet weak var mapView: MKMapView!
    let locationManager = CLLocationManager()
    var toilets: [Toilet] = [] // Declare toilets as a class property

    override func viewDidLoad() {
        super.viewDidLoad()
        
        guard mapView != nil else {
            print("Error: Map view is not connected.")
            return
        }
        
        mapView.mapType = .standard
        mapView.delegate = self
        
        locationManager.delegate = self
        locationManager.distanceFilter = 100
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        mapView.showsUserLocation = true
        
        fetchJSONData { [weak self] toilets in
            guard let self = self else { return }
            self.toilets = toilets // Assign fetched toilets to the class property
            let babyChangeRequired = true
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
        let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        let region = MKCoordinateRegion(center: location.coordinate, span: span)
        mapView.setRegion(region, animated: true)
        
        fetchJSONData { [weak self] toilets in
            guard let self = self else { return }
            self.toilets = toilets // Assign fetched toilets to the class property
            let babyChangeRequired = true
            let filteredToilets = self.filterToilets(toilets: toilets, babyChangeRequired: babyChangeRequired)
            let nearestToilets = self.findNearestToilets(userLocation: location, toilets: filteredToilets, count: 10)
            DispatchQueue.main.async {
                self.displayToiletsOnMap(toilets: nearestToilets)
            }
        }
    }
    
    func fetchJSONData(completion: @escaping ([Toilet]) -> Void) {
        let urlString = "http://35.225.28.134:8080/api/csv/read?filePath=https://dataworks.calderdale.gov.uk/download/20qn9/3ge/public-conveniences.csv"
        guard let url = URL(string: urlString) else {
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                return
            }
            guard let data = data else {
                return
            }

            do {
                let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String]]
                guard let rows = jsonArray, rows.count > 1 else {
                    return
                }

                let header = rows[0]
                guard let locationIndex = header.firstIndex(of: "Location"),
                      let latitudeIndex = header.firstIndex(of: "Latitude"),
                      let longitudeIndex = header.firstIndex(of: "Longitude"),
                      let openingHoursIndex = header.firstIndex(of: "Opening hours"),
                      let accessibleIndex = header.firstIndex(of: "Accessible"),
                      let babyChangeIndex = header.firstIndex(of: "Baby change"),
                      let chargeAmountIndex = header.firstIndex(of: "Charge amount") else {
                    return
                }

                var toilets: [Toilet] = []

                for row in rows[1...] {
                    guard row.count > max(locationIndex, latitudeIndex, longitudeIndex, openingHoursIndex, accessibleIndex, babyChangeIndex, chargeAmountIndex),
                          row.contains(where: { !$0.isEmpty }) else {
                        continue
                    }
                    if let latitude = Double(row[latitudeIndex]),
                       let longitude = Double(row[longitudeIndex]) {
                        let toilet = Toilet(
                            name: row[locationIndex],
                            latitude: latitude,
                            longitude: longitude,
                            openingHours: row[openingHoursIndex],
                            disabledAccess: row[accessibleIndex],
                            babyChange: row[babyChangeIndex],
                            chargeAmount: row[chargeAmountIndex]
                        )
                        toilets.append(toilet)
                    }
                }
                completion(toilets)
            } catch {
            }
        }.resume()
    }

    func findNearestToilets(userLocation: CLLocation, toilets: [Toilet], count: Int = 10) -> [Toilet] {
        let sortedToilets = toilets.sorted {
            let location1 = CLLocation(latitude: $0.latitude, longitude: $0.longitude)
            let location2 = CLLocation(latitude: $1.latitude, longitude: $1.longitude)
            return location1.distance(from: userLocation) < location2.distance(from: userLocation)
        }
        return Array(sortedToilets.prefix(count))
    }

    func displayToiletsOnMap(toilets: [Toilet]) {
        mapView.removeAnnotations(mapView.annotations)
        toilets.forEach { toilet in
            let annotation = MKPointAnnotation()
            annotation.title = toilet.name
            annotation.coordinate = CLLocationCoordinate2D(latitude: toilet.latitude, longitude: toilet.longitude)
            mapView.addAnnotation(annotation)
        }
        
        if let firstToilet = toilets.first {
            let span = MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: firstToilet.latitude, longitude: firstToilet.longitude), span: span)
            mapView.setRegion(region, animated: true)
        }
    }

    func filterToilets(toilets: [Toilet], babyChangeRequired: Bool) -> [Toilet] {
        return toilets.filter { toilet in
            let matchesBabyChange = !babyChangeRequired || toilet.babyChange.lowercased() == "yes"
            return matchesBabyChange
        }
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        guard let annotation = view.annotation else { return }
        guard let title = annotation.title else { return }
        
        // Search for the selected toilet in your array
        if let selectedToilet = toilets.first(where: { $0.name == title }) {
            let toiletInfo = """
            Opening Hours: \(selectedToilet.openingHours)
            Disabled Access: \(selectedToilet.disabledAccess)
            Baby Change: \(selectedToilet.babyChange)
            Charge Amount: \(selectedToilet.chargeAmount)
            """
            
            let alert = UIAlertController(title: selectedToilet.name, message: toiletInfo, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Get Directions", style: .default, handler: { _ in
                self.showDirections(to: annotation.coordinate)
            }))
            present(alert, animated: true, completion: nil)
        }
    }

    func showDirections(to coordinate: CLLocationCoordinate2D) {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        destination.name = "Public Toilet"
        MKMapItem.openMaps(with: [destination], launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

