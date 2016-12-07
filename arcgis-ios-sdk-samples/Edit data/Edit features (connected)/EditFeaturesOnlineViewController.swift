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

class EditFeaturesOnlineViewController: UIViewController, AGSGeoViewTouchDelegate, AGSPopupsViewControllerDelegate, FeatureTemplatePickerDelegate {
    
    @IBOutlet private weak var mapView:AGSMapView!
    @IBOutlet private weak var sketchToolbar:UIToolbar!
    @IBOutlet private weak var doneBBI:UIBarButtonItem!
    
    private var map:AGSMap!
    private var sketchEditor:AGSSketchEditor!
    private var featureLayer:AGSFeatureLayer!
    private var popupsVC:AGSPopupsViewController!
    
    private var lastQuery:AGSCancelable!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //add the source code button item to the right of navigation bar
        (self.navigationItem.rightBarButtonItem as! SourceCodeBarButtonItem).filenames = ["EditFeaturesOnlineViewController","FeatureTemplatePickerViewController"]
        
        self.map = AGSMap(basemap: AGSBasemap.topographicBasemap())
        //set initial viewpoint
        self.map.initialViewpoint = AGSViewpoint(center: AGSPoint(x: -9184518.55, y: 3240636.90, spatialReference: AGSSpatialReference.webMercator()), scale: 7e5)
        self.mapView.map = self.map
        self.mapView.touchDelegate = self
        
        let featureTable = AGSServiceFeatureTable(URL: NSURL(string: "https://sampleserver6.arcgisonline.com/arcgis/rest/services/DamageAssessment/FeatureServer/0")!)
        self.featureLayer = AGSFeatureLayer(featureTable: featureTable)
        self.map.operationalLayers.addObject(featureLayer)
        
        //initialize sketch editor and assign to map view
        self.sketchEditor = AGSSketchEditor()
        self.mapView.sketchEditor = self.sketchEditor
                
        //hide the sketchToolbar initially
        self.sketchToolbar.hidden = true
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func dismissFeatureTemplatePickerVC() {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func applyEdits() {
        
        //show progress hud
        SVProgressHUD.showWithStatus("Applying edits", maskType: .Gradient)
        
        (self.featureLayer.featureTable as! AGSServiceFeatureTable).applyEditsWithCompletion { (result:[AGSFeatureEditResult]?, error:NSError?) -> Void in
            
            if let error = error {
                SVProgressHUD.showErrorWithStatus("Error while applying edits :: \(error.localizedDescription)")
            }
            else {
                SVProgressHUD.showSuccessWithStatus("Edits applied successfully!")
            }
        }
    }
    
    //MARK: - AGSGeoViewTouchDelegate
    
    func geoView(geoView: AGSGeoView, didTapAtScreenPoint screenPoint: CGPoint, mapPoint: AGSPoint) {
        if let lastQuery = self.lastQuery{
            lastQuery.cancel()
        }

        self.lastQuery = self.mapView.identifyLayer(self.featureLayer, screenPoint: screenPoint, tolerance: 5, returnPopupsOnly: false, maximumResults: 10) { [weak self] (identifyLayerResult: AGSIdentifyLayerResult) -> Void in
            if let error = identifyLayerResult.error {
                print(error)
            }
            else if let weakSelf = self {
                var popups = [AGSPopup]()
                let geoElements = identifyLayerResult.geoElements
                
                for geoElement in geoElements {

                    let popup = AGSPopup(geoElement: geoElement)
                    popups.append(popup)
                }
                
                if popups.count > 0 {
                    weakSelf.popupsVC = AGSPopupsViewController(popups: popups, containerStyle: .NavigationBar)
                    weakSelf.popupsVC.modalPresentationStyle = .FormSheet
                    weakSelf.presentViewController(weakSelf.popupsVC, animated: true, completion: nil)
                    weakSelf.popupsVC.delegate = weakSelf
                }
            }
        }
    }
    
    //MARK: -  AGSPopupsViewControllerDelegate methods
    
    func popupsViewController(popupsViewController: AGSPopupsViewController, sketchEditorForPopup popup: AGSPopup) -> AGSSketchEditor? {
        
        if let geometry = popup.geoElement.geometry {
            
            //start sketch editing
            self.mapView.sketchEditor?.startWithGeometry(geometry)
            
            //zoom to the existing feature's geometry
            self.mapView.setViewpointGeometry(geometry.extent, padding: 10, completion: nil)
        }
        
        return self.sketchEditor
    }
    
    func popupsViewController(popupsViewController: AGSPopupsViewController, readyToEditGeometryWithSketchEditor sketchEditor: AGSSketchEditor?, forPopup popup: AGSPopup) {
    
        //Dismiss the popup view controller
        self.dismissViewControllerAnimated(true, completion: nil)
        
        //Prepare the current view controller for sketch mode
        self.mapView.callout.hidden = true
        
        //hide the back button
        self.navigationItem.hidesBackButton = true
        
        //disable the code button
        self.navigationItem.rightBarButtonItem?.enabled = false
        
        //unhide the sketchToolbar
        self.sketchToolbar.hidden = false
        
        //disable the done button until any geometry changes
        self.doneBBI.enabled = false
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(EditFeaturesOnlineViewController.sketchChanged(_:)), name: AGSSketchEditorGeometryDidChangeNotification, object: nil)
    }
    
    func popupsViewController(popupsViewController: AGSPopupsViewController, didCancelEditingForPopup popup: AGSPopup) {
        
        //stop sketch editor
        self.disableSketchEditor()
    }
    
    func popupsViewController(popupsViewController: AGSPopupsViewController, didFinishEditingForPopup popup: AGSPopup) {
        
        //stop sketch editor
        self.disableSketchEditor()
        
        let feature = popup.geoElement as! AGSFeature
        
        // simplify the geometry, this will take care of self intersecting polygons and
        feature.geometry = AGSGeometryEngine.simplifyGeometry(feature.geometry!)
        
        //normalize the geometry, this will take care of geometries that extend beyone the dateline
        //(ifwraparound was enabled on the map)
        feature.geometry = AGSGeometryEngine.normalizeCentralMeridianOfGeometry(feature.geometry!)
        
        //apply edits
        self.applyEdits()
    }
    
    func popupsViewControllerDidFinishViewingPopups(popupsViewController: AGSPopupsViewController) {
        
        //dismiss the popups view controller
        self.dismissViewControllerAnimated(true, completion:nil)
        
        self.popupsVC = nil
    }
    
    func sketchChanged(notification:NSNotification) {
        //Check if the sketch geometry is valid to decide whether to enable
        //the sketchCompleteButton
        if let geometry = self.mapView.sketchEditor?.geometry where !geometry.empty {
            self.doneBBI.enabled = true
        }
    }
    
    @IBAction func sketchDoneAction() {
        //enable or unhide navigation bar button
        self.navigationItem.hidesBackButton = false
        self.navigationItem.rightBarButtonItem?.enabled = true
        
        //present the popups view controller again
        self.presentViewController(self.popupsVC, animated:true, completion:nil)
        
        //remove self as observer for notifications
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    private func disableSketchEditor() {
        //stop sketch editor
        self.mapView.sketchEditor?.stop()
        
        //hide sketch toolbar
        self.sketchToolbar.hidden = true
    }
    
    //MARK: - Navigation
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "FeatureTemplateSegue" {
            let controller = segue.destinationViewController as! FeatureTemplatePickerViewController
            controller.addTemplatesFromLayer(self.featureLayer)
            controller.delegate = self
        }
    }
    
    //MARK: - FeatureTemplatePickerDelegate
    
    func featureTemplatePickerViewController(controller: FeatureTemplatePickerViewController, didSelectFeatureTemplate template: AGSFeatureTemplate, forFeatureLayer featureLayer: AGSFeatureLayer) {
        
        let featureTable = self.featureLayer.featureTable as! AGSArcGISFeatureTable
        //create a new feature based on the template
        let newFeature = featureTable.createFeatureWithTemplate(template)!
        
        //set the geometry as the center of the screen
        if let visibleArea = self.mapView.visibleArea {
            newFeature.geometry = visibleArea.extent.center
        }
        else {
            newFeature.geometry = AGSPoint(x: 0, y: 0, spatialReference: self.map.spatialReference)
        }

        //initialize a popup definition using the feature layer
        let popupDefinition = AGSPopupDefinition(popupSource: self.featureLayer)
        //create a popup
        let popup = AGSPopup(geoElement: newFeature, popupDefinition: popupDefinition)
        
        //initialize popups view controller
        self.popupsVC = AGSPopupsViewController(popups: [popup], containerStyle: .NavigationBar)
        self.popupsVC.delegate = self
        
        //Only for iPad, set presentation style to Form sheet
        //We don't want it to cover the entire screen
        self.popupsVC.modalPresentationStyle = .FormSheet

        //First, dismiss the Feature Template Picker
        self.dismissViewControllerAnimated(false, completion:nil)

        //Next, Present the popup view controller
        self.presentViewController(self.popupsVC, animated: true) { [weak self] () -> Void in
            self?.popupsVC.startEditingCurrentPopup()
        }
    }
    
    func featureTemplatePickerViewControllerWantsToDismiss(controller: FeatureTemplatePickerViewController) {
        self.dismissFeatureTemplatePickerVC()
    }
    
}
