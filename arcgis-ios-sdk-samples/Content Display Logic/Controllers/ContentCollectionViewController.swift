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

private let reuseIdentifier = "CategoryCell"

class ContentCollectionViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, CustomSearchHeaderViewDelegate {

    @IBOutlet private var collectionView:UICollectionView!
    
    private var headerView:CustomSearchHeaderView!
    
    var nodesArray:[Node]!
    private var transitionSize:CGSize!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        //hide suggestions
        self.hideSuggestions()
        
        self.populateTree()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func populateTree() {
        
        let path = NSBundle.mainBundle().pathForResource("ContentPList", ofType: "plist")
        let content = NSArray(contentsOfFile: path!)
        self.nodesArray = self.populateNodesArray(content! as [AnyObject])
        self.collectionView?.reloadData()
    }
    
    func populateNodesArray(array:[AnyObject]) -> [Node] {
        var nodesArray = [Node]()
        for object in array {
            let node = self.populateNode(object as! [String:AnyObject])
            nodesArray.append(node)
        }
        return nodesArray
    }
    
    func populateNode(dict:[String:AnyObject]) -> Node {
        let node = Node()
        if let displayName = dict["displayName"] as? String {
            node.displayName = displayName
        }
        if let descriptionText = dict["descriptionText"] as? String {
            node.descriptionText = descriptionText
        }
        if let storyboardName = dict["storyboardName"] as? String {
            node.storyboardName = storyboardName
        }
        if let children = dict["children"] as? [AnyObject] {
            node.children = self.populateNodesArray(children)
        }
        return node
    }
    
    //MARK: - Suggestions related
    
    func showSuggestions() {
//        if !self.isSuggestionsTableVisible() {
            self.collectionView.performBatchUpdates({ [weak self] () -> Void in
                (self?.collectionView.collectionViewLayout as! UICollectionViewFlowLayout).headerReferenceSize = CGSize(width: self!.collectionView.bounds.width, height: self!.headerView.expandedViewHeight)
            }, completion: nil)
            
            //show suggestions
//        }
    }
    
    func hideSuggestions() {
//        if self.isSuggestionsTableVisible() {
            self.collectionView.performBatchUpdates({ [weak self] () -> Void in
                (self?.collectionView.collectionViewLayout as! UICollectionViewFlowLayout).headerReferenceSize = CGSize(width: self!.collectionView.bounds.width, height: self!.headerView.shrinkedViewHeight)
            }, completion: nil)
            
            //hide suggestions
//        }
    }

    //TODO: implement this
//    func isSuggestionsTableVisible() -> Bool {
//        return (self.headerView?.suggestionsTableHeightConstraint?.constant == 0 ? false : true) ?? false
//    }
    
    //MARK: - samples lookup by name
    
    func nodesByDisplayNames(names:[String]) -> [Node] {
        var nodes = [Node]()
        for node in self.nodesArray {
            let children = node.children
            let matchingNodes = children.filter({ return names.contains($0.displayName) })
            nodes.appendContentsOf(matchingNodes)
        }
        return nodes
    }

    // MARK: UICollectionViewDataSource

    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 1
    }


    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return self.nodesArray?.count ?? 0
    }

    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(reuseIdentifier, forIndexPath: indexPath) as! CategoryCell
        
        let node = self.nodesArray[indexPath.item]
        
        //mask to bounds
        cell.layer.masksToBounds = false
        
        //name
        cell.nameLabel.text = node.displayName.uppercaseString
        
        //icon
        let image = UIImage(named: "\(node.displayName)_icon")
        cell.iconImageView.image = image
        
        //background image
        let bgImage = UIImage(named: "\(node.displayName)_bg")
        cell.backgroundImageView.image = bgImage
        
        //cell shadow
        cell.layer.cornerRadius = 5
        cell.layer.masksToBounds = true
        
        return cell
    }

    //supplementary view as search bar
    func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        if self.headerView == nil {
            self.headerView = collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: "CollectionHeaderView", forIndexPath: indexPath) as! CustomSearchHeaderView
            self.headerView.delegate = self
        }
        return self.headerView
    }
    
    //size for item
    func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        if self.transitionSize != nil {
            return self.transitionSize
        }
        return self.itemSizeForCollectionViewSize(collectionView.frame.size)
    }
    
    //MARK: - UICollectionViewDelegate
    
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        //hide keyboard if visible
        self.view.endEditing(true)
        
        let node = self.nodesArray[indexPath.item]
        let controller = self.storyboard!.instantiateViewControllerWithIdentifier("ContentTableViewController") as! ContentTableViewController
        controller.nodesArray = node.children
        controller.title = node.displayName
        self.navigationController?.showViewController(controller, sender: self)
    }
    
    //MARK: - Transition
    
    //get the size of the new view to be transitioned to
    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        
        let newFlowLayout = UICollectionViewFlowLayout()
        newFlowLayout.itemSize = self.itemSizeForCollectionViewSize(size)
        newFlowLayout.sectionInset = UIEdgeInsets(top: 5, left: 10, bottom: 10, right: 10)
        newFlowLayout.headerReferenceSize = CGSize(width: size.width, height: (self.headerView.isShowingSuggestions ? self.headerView.expandedViewHeight : self.headerView.shrinkedViewHeight))
        
        self.transitionSize = newFlowLayout.itemSize
        self.collectionView?.setCollectionViewLayout(newFlowLayout, animated: false)
        self.transitionSize = nil
    }
    
    //item width based on the width of the collection view
    func itemSizeForCollectionViewSize(size:CGSize) -> CGSize {
        //first try for 3 items in a row
        var width = (size.width - 4*10)/3
        if width < 150 {    //if too small then go for 2 in a row
            width = (size.width - 3*10)/2
        }
        return CGSize(width: width, height: width)
    }

    //MARK: - CustomSearchHeaderViewDelegate
    
    func customSearchHeaderView(customSearchHeaderView: CustomSearchHeaderView, didFindSamples sampleNames: [String]?) {
        if let sampleNames = sampleNames {
            let resultNodes = self.nodesByDisplayNames(sampleNames)
            if resultNodes.count > 0 {
                //show the results
                let controller = self.storyboard!.instantiateViewControllerWithIdentifier("ContentTableViewController") as! ContentTableViewController
                controller.nodesArray = resultNodes
                controller.title = "Search results"
                controller.containsSearchResults = true
                self.navigationController?.showViewController(controller, sender: self)
                return
            }
        }
        
        SVProgressHUD.showErrorWithStatus("No match found", maskType: .Gradient)
    }
    
    func customSearchHeaderViewWillHideSuggestions(customSearchHeaderView: CustomSearchHeaderView) {
        self.hideSuggestions()
    }
    
    func customSearchHeaderViewWillShowSuggestions(customSearchHeaderView: CustomSearchHeaderView) {
        self.showSuggestions()
    }
}
