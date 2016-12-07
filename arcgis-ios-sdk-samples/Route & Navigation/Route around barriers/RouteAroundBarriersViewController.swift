//
// Copyright 2016 Esri.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit
import ArcGIS

class RouteAroundBarriersViewController: UIViewController, AGSGeoViewTouchDelegate, UIAdaptivePresentationControllerDelegate, DirectionsListVCDelegate {
    
    @IBOutlet var mapView:AGSMapView!
    @IBOutlet var segmentedControl:UISegmentedControl!
    @IBOutlet var routeParametersBBI:UIBarButtonItem!
    @IBOutlet var routeBBI:UIBarButtonItem!
    @IBOutlet var directionsListBBI:UIBarButtonItem!
    @IBOutlet var directionsBottomConstraint:NSLayoutConstraint!
    
    private var stopGraphicsOverlay = AGSGraphicsOverlay()
    private var barrierGraphicsOverlay = AGSGraphicsOverlay()
    private var routeGraphicsOverlay = AGSGraphicsOverlay()
    private var directionsGraphicsOverlay = AGSGraphicsOverlay()
    
    private var routeTask:AGSRouteTask!
    private var routeParameters:AGSRouteParameters!
    private var isDirectionsListVisible = false
    private var directionsListViewController:DirectionsListViewController!
    
    var generatedRoute:AGSRoute! {
        didSet {
            let flag = generatedRoute != nil
            self.directionsListBBI.enabled = flag
            self.toggleRouteDetails(flag)
            self.directionsListViewController.route = generatedRoute
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //add the source code button item to the right of navigation bar
        (self.navigationItem.rightBarButtonItem as! SourceCodeBarButtonItem).filenames = ["RouteAroundBarriersViewController", "DirectionsListViewController", "RouteParametersViewController"]
        
        let map = AGSMap(basemap: AGSBasemap.topographicBasemap())
        
        self.mapView.map = map
        self.mapView.touchDelegate = self
        
        //add the graphics overlays to the map view
        self.mapView.graphicsOverlays.addObjectsFromArray([routeGraphicsOverlay, directionsGraphicsOverlay, barrierGraphicsOverlay, stopGraphicsOverlay])
        
        //zoom to viewpoint
        self.mapView.setViewpointCenter(AGSPoint(x: -13042254.715252, y: 3857970.236806, spatialReference: AGSSpatialReference(WKID: 3857)), scale: 1e5, completion: nil)
        
        //initialize route task
        self.routeTask = AGSRouteTask(URL: NSURL(string: "https://sampleserver6.arcgisonline.com/arcgis/rest/services/NetworkAnalysis/SanDiego/NAServer/Route")!)
        
        //get default parameters
        self.getDefaultParameters()
        
        //hide directions list
        self.toggleRouteDetails(false)
    }
    
    //MARK: - Route logic
    
    func getDefaultParameters() {
        self.routeTask.defaultRouteParametersWithCompletion({ [weak self] (params: AGSRouteParameters?, error: NSError?) -> Void in
            if let error = error {
                SVProgressHUD.showErrorWithStatus(error.localizedDescription)
            }
            else {
                self?.routeParameters = params
                //enable bar button item
                self?.routeParametersBBI.enabled = true
            }
        })
    }
    
    @IBAction func route() {
        //add check
        if self.routeParameters == nil || self.stopGraphicsOverlay.graphics.count < 2 {
            SVProgressHUD.showErrorWithStatus("Either parameters not loaded or not sufficient stops")
            return
        }
        
        SVProgressHUD.showWithStatus("Routing", maskType: SVProgressHUDMaskType.Gradient)
        
        //clear routes
        self.routeGraphicsOverlay.graphics.removeAllObjects()
        
        self.routeParameters.returnStops = true
        self.routeParameters.returnDirections = true
        
        //add stops
        var stops = [AGSStop]()
        for graphic in self.stopGraphicsOverlay.graphics as AnyObject as! [AGSGraphic] {
            let stop = AGSStop(point: graphic.geometry as! AGSPoint)
            stop.name = "\(self.stopGraphicsOverlay.graphics.indexOfObject(graphic)+1)"
            stops.append(stop)
        }
        self.routeParameters.clearStops()
        self.routeParameters.setStops(stops)
        
        //add barriers
        var barriers = [AGSPolygonBarrier]()
        for graphic in self.barrierGraphicsOverlay.graphics as AnyObject as! [AGSGraphic] {
            let polygon = graphic.geometry as! AGSPolygon
            let barrier = AGSPolygonBarrier(polygon: polygon)
            barriers.append(barrier)
        }
        self.routeParameters.clearPolygonBarriers()
        self.routeParameters.setPolygonBarriers(barriers)
        
        self.routeTask.solveRouteWithParameters(self.routeParameters) { [weak self] (routeResult:AGSRouteResult?, error:NSError?) -> Void in
            if let error = error {
                SVProgressHUD.showErrorWithStatus("\(error.localizedDescription) \(error.localizedFailureReason ?? "")")
            }
            else {
                SVProgressHUD.dismiss()
                let route = routeResult!.routes[0]
                let routeGraphic = AGSGraphic(geometry: route.routeGeometry, symbol: self!.routeSymbol(), attributes: nil)
                self?.routeGraphicsOverlay.graphics.addObject(routeGraphic)
                self?.generatedRoute = route
            }
        }
    }
    
    func routeSymbol() -> AGSSimpleLineSymbol {
        let symbol = AGSSimpleLineSymbol(style: .Solid, color: UIColor.yellowColor(), width: 5)
        return symbol
    }
    
    func directionSymbol() -> AGSSimpleLineSymbol {
        let symbol = AGSSimpleLineSymbol(style: .DashDot, color: UIColor.orangeColor(), width: 5)
        return symbol
    }
    
    private func symbolForStopGraphic(index: Int) -> AGSSymbol {
        let markerImage = UIImage(named: "BlueMarker")!
        let markerSymbol = AGSPictureMarkerSymbol(image: markerImage)
        markerSymbol.offsetY = markerImage.size.height/2
        
        let textSymbol = AGSTextSymbol(text: "\(index)", color: UIColor.whiteColor(), size: 20, horizontalAlignment: AGSHorizontalAlignment.Center, verticalAlignment: AGSVerticalAlignment.Middle)
        textSymbol.offsetY = markerSymbol.offsetY
        
        let compositeSymbol = AGSCompositeSymbol(symbols: [markerSymbol, textSymbol])
        
        return compositeSymbol
    }
    
    func barrierSymbol() -> AGSSimpleFillSymbol {
        return AGSSimpleFillSymbol(style: .DiagonalCross, color: UIColor.redColor(), outline: nil)
    }
    
    //MARK: - AGSGeoViewTouchDelegate
    
    func geoView(geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        //normalize geometry
        let normalizedPoint = AGSGeometryEngine.normalizeCentralMeridianOfGeometry(mapPoint)!
        
        if segmentedControl.selectedSegmentIndex == 0 {
            //create a graphic for stop and add to the graphics overlay
            let graphicsCount = self.stopGraphicsOverlay.graphics.count
            let symbol = self.symbolForStopGraphic(graphicsCount+1)
            let graphic = AGSGraphic(geometry: normalizedPoint, symbol: symbol, attributes: nil)
            self.stopGraphicsOverlay.graphics.addObject(graphic)
            
            //enable route button
            if graphicsCount > 0 {
                self.routeBBI.enabled = true
            }
        }
        else {
            let bufferedGeometry = AGSGeometryEngine.bufferGeometry(normalizedPoint, byDistance: 500)
            let symbol = self.barrierSymbol()
            let graphic = AGSGraphic(geometry: bufferedGeometry, symbol: symbol, attributes: nil)
            self.barrierGraphicsOverlay.graphics.addObject(graphic)
        }
    }
    
    //MARK: - Actions
    
    @IBAction func clearAction() {
        if segmentedControl.selectedSegmentIndex == 0 {
            self.stopGraphicsOverlay.graphics.removeAllObjects()
            self.routeBBI.enabled = false
        }
        else {
            self.barrierGraphicsOverlay.graphics.removeAllObjects()
        }
    }
    
    @IBAction func directionsListAction() {
        self.directionsBottomConstraint.constant = self.isDirectionsListVisible ? -115 : 0
        UIView.animateWithDuration(0.3, animations: { [weak self] () -> Void in
            self?.view.layoutIfNeeded()
            }) { [weak self] (finished) -> Void in
                self?.isDirectionsListVisible = !self!.isDirectionsListVisible
        }
    }
    
    func toggleRouteDetails(on:Bool) {
        self.directionsBottomConstraint.constant = on ? -115 : -150
        UIView.animateWithDuration(0.3, animations: { [weak self] () -> Void in
            self?.view.layoutIfNeeded()
            }) { [weak self] (finished) -> Void in
                if !on {
                    self?.isDirectionsListVisible = false
                }
        }
    }
    
    //MARK: - Navigation
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "RouteSettingsSegue" {
            let controller = segue.destinationViewController as! RouteParametersViewController
            controller.presentationController?.delegate = self
            controller.preferredContentSize = CGSize(width: 300, height: 125)
            controller.routeParameters = self.routeParameters
        }
        else if segue.identifier == "DirectionsListSegue" {
            self.directionsListViewController = segue.destinationViewController as! DirectionsListViewController
            self.directionsListViewController.delegate = self
        }
    }
    
    //MARk: - UIAdaptivePresentationControllerDelegate
    
    func adaptivePresentationStyleForPresentationController(controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
    
        return .None
    }
    
    //MARK: - DirectionsListVCDelegate
    
    func directionsListViewControllerDidDeleteRoute(directionsListViewController: DirectionsListViewController) {
        self.generatedRoute = nil;
        self.routeGraphicsOverlay.graphics.removeAllObjects()
        self.directionsGraphicsOverlay.graphics.removeAllObjects()
    }
    
    func directionsListViewController(directionsListViewController: DirectionsListViewController, didSelectDirectionManuever directionManeuver: AGSDirectionManeuver) {
        //remove previous directions
        self.directionsGraphicsOverlay.graphics.removeAllObjects()
        
        //show the maneuver geometry on the map view
        let directionGraphic = AGSGraphic(geometry: directionManeuver.geometry!, symbol: self.directionSymbol(), attributes: nil)
        self.directionsGraphicsOverlay.graphics.addObject(directionGraphic)
        
        //zoom to the direction
        self.mapView.setViewpointGeometry(directionManeuver.geometry!.extent, padding: 100, completion: nil)
    }
}
